import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个节点的状态
class QccNode {
  final String ip;
  final String nodeId;
  int height;
  int lastSeen;
  bool active; // 节点自己上报的状态（来自 /v1/qccnode 返回）
  bool reachable; // 客户端实际探测结果
  int failCount; // 连续失败次数（用于熔断）
  int latencyMs; // 最近一次探测延迟，用于排序选优
  bool hidden; // 本地"删除"标记：用户手动隐藏后不在列表里展示；
  // 只影响 UI 展示，后台仍然继续拉取/探测这个节点——
  // 一旦探测到它重新可达，会在 _doProbeAll 里自动清掉这个标记，
  // 让它重新出现，不需要用户手动恢复（见 QccNodeManager.hideNode）。

  QccNode({
    required this.ip,
    required this.nodeId,
    this.height = 0,
    this.lastSeen = 0,
    this.active = true,
    this.reachable = true,
    this.failCount = 0,
    this.latencyMs = 9999,
    this.hidden = false,
  });

  // 假设：只有 https://test.qccio.com 配了证书，其余节点只能走明文 HTTP + 固定 9080 端口
  //
  // IPv6 注意：URL 里的 IPv6 地址必须用方括号包起来，例如
  // "http://[2001:db8::1]:9080"，否则地址里的冒号会跟端口分隔符混在一起，
  // Uri.parse 要么解析出错误的 host，要么直接抛异常——探测请求发出去就是错的，
  // 表现为该节点一直被判定为离线（即使节点本身完全可达）。
  // 这里用 ip 里是否含 ':' 简单判断是不是 IPv6（IPv4/域名都不含冒号），
  // 已经带方括号的 ip（万一上游数据就是这么给的）不再重复加。
  String get baseUrl {
    final isIPv6 = ip.contains(':') && !ip.startsWith('[');
    final host = isIPv6 ? '[$ip]' : ip;
    return "http://$host:9080";
  }

  factory QccNode.fromJson(Map<String, dynamic> j) => QccNode(
    ip: j['ip'] as String,
    nodeId: (j['nodeId'] ?? '') as String,
    height: (j['height'] ?? 0) as int,
    lastSeen: (j['lastSeen'] ?? 0) as int,
    active: (j['active'] ?? true) as bool,
    failCount: (j['failCount'] ?? 0) as int,
    // 注意：hidden 只从本地缓存（_loadFromCache）读回来才有意义；
    // 服务端返回的节点数据里不会有这个字段，走这个分支时自然是 null → false，
    // 不会出现"服务端数据把本地隐藏状态覆盖掉"的问题。
    hidden: (j['hidden'] ?? false) as bool,
  );

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'nodeId': nodeId,
    'height': height,
    'lastSeen': lastSeen,
    'active': active,
    'failCount': failCount,
    'hidden': hidden,
  };
}

/// _rankNodesByHeightConsensus() 的返回值：领先组 / 落后组，分开暴露
/// 好让调用方（currentBaseUrl()/get()）能把 SSL 入口插在两组中间。
class _HeightRankedNodes {
  final List<QccNode> leading;
  final List<QccNode> lagging;
  const _HeightRankedNodes(this.leading, this.lagging);
}

/// 节点管理单例：负责拉取/缓存节点列表、健康探测、故障转移
class QccNodeManager {
  QccNodeManager._();
  static final QccNodeManager instance = QccNodeManager._();

  static const String sslBaseUrl = "https://test.qccio.com";

  // 种子节点：写死在客户端，避免 sslBaseUrl 单点故障时连节点列表都拿不到。
  // 需要你确认这几个 IP 是长期稳定的种子节点而非临时测试节点，
  // 建议至少配置在远程配置/APP 更新里可下发，而不是纯硬编码。
  static final List<String> _seedIps = [
    "104.128.190.31",
    "45.92.158.123",
    "23.238.114.9",
    "192.131.142.226",
    "192.129.133.168",
  ];

  static const String _prefsKey = "qcc_node_list_v1";
  static const int _maxFailBeforeDeactivate = 3;
  static const Duration _probeTimeout = Duration(seconds: 3);
  static const Duration _refreshInterval = Duration(minutes: 10);

  List<QccNode> _nodes = [];
  bool _initialized = false;
  DateTime? _lastRefresh;
  int _sslFailCount = 0;

  // 用 in-flight Future 做重入保护：防止 refreshNodes 被并发调用两次
  // （比如 init() 里 unawaited(refreshNodes()) 和 widget 显式调用的那次撞一起）。
  // 重入时不是简单丢弃，而是直接返回正在跑的那个 Future，让调用方老老实实等它
  // 跑完拿到最新数据，避免"跳过刷新但调用方以为已经刷新完了"这种坑。
  Future<void>? _inFlightRefresh;
  bool _crossValidating = false;

  /// 只读节点快照（含本地隐藏的节点），供需要全量数据的场景使用
  List<QccNode> get nodes => List.unmodifiable(_nodes);

  /// 供列表 UI 展示用：排除掉本地手动隐藏的节点。
  List<QccNode> get visibleNodes =>
      List.unmodifiable(_nodes.where((n) => !n.hidden));

  /// 已被本地隐藏的节点，供"隐藏节点管理"入口展示、支持手动恢复。
  List<QccNode> get hiddenNodes =>
      List.unmodifiable(_nodes.where((n) => n.hidden));

  /// 供 UI 主动触发一次探测（比如下拉刷新）
  Future<void> probeAll() => _probeAll();

  /// 本地隐藏一个节点：不再出现在列表里，但后台仍然继续拉取/探测它——
  /// 一旦探测到它重新可达，_doProbeAll 会自动清掉隐藏标记，让它重新出现，
  /// 不需要用户手动恢复；用户也可以随时在"已隐藏节点"里手动恢复。
  Future<void> hideNode(String ip) async {
    for (final n in _nodes) {
      if (n.ip == ip) {
        n.hidden = true;
        break;
      }
    }
    await _saveToCache();
  }

  /// 手动恢复一个已隐藏的节点。
  Future<void> unhideNode(String ip) async {
    for (final n in _nodes) {
      if (n.ip == ip) {
        n.hidden = false;
        break;
      }
    }
    await _saveToCache();
  }

  Future<void> init() async {
    if (_initialized) return;
    await _loadFromCache();
    if (_nodes.isEmpty) {
      _nodes = _seedIps.map((ip) => QccNode(ip: ip, nodeId: '')).toList();
    }
    _initialized = true;
    unawaited(refreshNodes()); // 启动时异步刷新一次，不阻塞业务
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final List list = jsonDecode(raw);
        _nodes = list
            .map((e) => QccNode.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print("加载本地节点缓存失败: $e");
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_nodes.map((n) => n.toJson()).toList()),
      );
    } catch (e) {
      print("保存节点缓存失败: $e");
    }
  }

  /// 拉取最新节点列表：优先走 SSL 入口，失败则用当前已知健康节点兜底
  Future<void> refreshNodes({bool force = false}) {
    if (!force &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _refreshInterval) {
      return Future.value();
    }
    // 已经有一次刷新在跑：不再并发发起第二次，而是把同一个 Future 返回给
    // 调用方，等它跑完——保证调用方 await 完之后拿到的一定是最新数据。
    if (_inFlightRefresh != null) return _inFlightRefresh!;
    final fut = _doRefreshNodes();
    _inFlightRefresh = fut;
    fut.whenComplete(() => _inFlightRefresh = null);
    return fut;
  }

  Future<void> _doRefreshNodes() async {
    Map<String, dynamic>? data = await _fetchNodeList(sslBaseUrl);

    if (data == null) {
      // 拿主列表时同样优先问"领先组"节点：它手上的节点表本身更可能是
      // 最新、最完整的（落后节点缓存的节点表可能是它掉队之前的旧快照）。
      for (final n in _healthyNodesSortedByPreference()) {
        data = await _fetchNodeList(n.baseUrl);
        if (data != null) break;
      }
    }

    if (data == null) {
      print("节点列表刷新失败：所有已知入口均不可达，沿用本地缓存");
      return;
    }

    try {
      final List remoteNodes = (data['nodes'] ?? []) as List;
      final Map<String, QccNode> merged = {for (final n in _nodes) n.ip: n};
      for (final r in remoteNodes) {
        final incoming = QccNode.fromJson(r as Map<String, dynamic>);
        final old = merged[incoming.ip];
        if (old != null) {
          old.height = incoming.height;
          old.lastSeen = incoming.lastSeen;
          old.active = incoming.active;
        } else {
          merged[incoming.ip] = incoming;
        }
      }
      _nodes = merged.values.toList();
      _lastRefresh = DateTime.now();
      await _saveToCache();

      // 主列表拿到手之后，再做一轮交叉验证：
      // 像 test.qccio.com 自报 height=0、但被其他节点看到是 62 这种情况，
      // 单信一个源是发现不了的，必须让别的节点也说一遍。
      // 这一步也顺带发现主列表里没有的新节点（比如新加入网络、还没被
      // test.qccio.com 收录的节点），发现到就直接补进 _nodes 并落盘。
      await crossValidateNodes();

      // 【修复】这里原来是 unawaited(_probeAll())——刷新方法自己不等探测
      // 结果就返回了。这本身不算错，但 _probeAll() 内部有一个"正在探测就
      // 直接跳过"的重入保护（见下面 _probing 那段）。而 QccNodeListWidget
      // 的 _refresh() 在 await 完 refreshNodes() 之后，会紧接着自己再
      // await 一次 probeAll()——这次调用几乎总是撞上刚刚这里 unawaited
      // 出去、还没跑完的那一轮探测，于是被重入保护直接短路、瞬间返回，
      // 根本没有真的等到探测结果落地。结果就是：界面上的"加载中"提前结束、
      // 用 setState 渲染出去的其实是探测完成前的旧数据（新发现的节点默认
      // reachable=true、旧节点保留上一轮的 reachable/latencyMs），而真正
      // 的探测结果在几秒后才悄悄写回 _nodes，却没有任何 setState 通知 UI
      // 重新渲染——多刷新几次之后，"X/Y 在线"的统计数字和列表里实际显示
      // 的在线节点就对不上了。改成这里老老实实 await，保证 refreshNodes()
      // 返回时数据是真正探测过的最新结果。
      await _probeAll();
    } catch (e) {
      print("解析 /v1/qccnode 返回失败: $e");
    }
  }

  /// 抽样问几个节点各自的 /v1/qccnode 视图，用多方一致的数据校正单一来源的异常值
  /// （比如某节点自报 height=0，但其余节点看到的都是 62，这种情况取非零值里的最大值）。
  ///
  /// 注意这只能防"某个节点自身状态上报 bug / 探测超时给了脏数据"这类无意的不一致，
  /// 防不了"多个节点合谋撒谎"这种恶意场景——如果你们后面要做到拜占庭容错级别的
  /// 高度校验，这里的多数表决逻辑需要重新设计（比如要求超过 2/3 节点一致才采信）。
  ///
  /// sampleSize 控制抽样节点数而不是问全部节点：节点数一旦涨到几十上百，
  /// 每次都全量互相问一遍会是 O(n²) 的流量开销，这里先按小样本做。
  Future<void> crossValidateNodes({int sampleSize = 3}) async {
    if (_crossValidating) return; // 避免和另一次刷新触发的交叉验证并发踩踏
    _crossValidating = true;
    try {
      final pool = _healthyNodesSortedByLatency();
      final sample = pool.length <= sampleSize
          ? pool
          : (List<QccNode>.from(pool)..shuffle()).take(sampleSize).toList();

      final responses = <Map<String, dynamic>>[];
      await Future.wait([
        _fetchNodeList(sslBaseUrl).then((d) {
          if (d != null) responses.add(d);
        }),
        ...sample.map((n) => _fetchNodeList(n.baseUrl).then((d) {
          if (d != null) responses.add(d);
        })),
      ]);

      if (responses.length < 2) return; // 样本不够，交叉验证没意义

      // 汇总每个 IP 在各个源里的 height 上报，同时收集从未见过的新节点信息
      final Map<String, List<int>> heightReports = {};
      final Map<String, Map<String, dynamic>> firstSeenRaw = {};
      //LogObj.log("qcc超级节点 返回数据:$responses");
      for (final resp in responses) {
        final List remoteNodes = (resp['nodes'] ?? []) as List;
        for (final r in remoteNodes) {
          final map = r as Map<String, dynamic>;
          final ip = map['ip'] as String?;
          if (ip == null) continue;
          final h = (map['height'] ?? 0) as int;
          heightReports.putIfAbsent(ip, () => []).add(h);
          firstSeenRaw.putIfAbsent(ip, () => map);
        }
      }

      // 已知节点：用非零上报里的最大值校正 height
      for (final n in _nodes) {
        final reports = heightReports[n.ip];
        if (reports == null || reports.isEmpty) continue;

        final nonZero = reports.where((h) => h > 0).toList();
        if (nonZero.isEmpty) continue; // 大家都报 0，可能是真的还没同步，不覆盖

        final consensusHeight = nonZero.reduce((a, b) => a > b ? a : b);
        if (reports.toSet().length > 1) {
          LogObj.log("qcc超级节点 ${n.ip} 各源上报高度不一致: $reports，采用交叉验证值 $consensusHeight");
        }
        n.height = consensusHeight;
      }

      // 动态发现：交叉验证顺带问到的节点里，有本地 _nodes 里完全没有的 IP，
      // 说明网络里出现了本地列表还不知道的新节点，直接加进来并落盘缓存。
      final knownIps = _nodes.map((n) => n.ip).toSet();
      final newIps = heightReports.keys.where((ip) => !knownIps.contains(ip));
      for (final ip in newIps) {
        final newNode = QccNode.fromJson(firstSeenRaw[ip]!);
        _nodes.add(newNode);
        print("发现新节点并加入本地列表: $ip");
      }

      await _saveToCache();
    } finally {
      _crossValidating = false;
    }
  }

  Future<Map<String, dynamic>?> _fetchNodeList(String base) async {
    try {
      final resp =
      await http.get(Uri.parse("$base/v1/qccnode")).timeout(_probeTimeout);
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['status'] == 'ok') {
          return decoded as Map<String, dynamic>;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 并发探测所有节点的可达性/延迟。
  /// 注意：这里复用 /v1/qccnode 当健康检查端点，图省事。
  /// 如果你们有专门的轻量 /health 或 /ping 接口，换成那个更合适，
  /// 否则每次探测都拉全量节点列表，浪费带宽。
  bool _probing = false;
  Future<void> _probeAll() async {
    if (_probing) return;
    _probing = true;
    try {
      await _doProbeAll();
    } finally {
      _probing = false;
    }
  }

  Future<void> _doProbeAll() async {
    await Future.wait(_nodes.map((n) async {
      final sw = Stopwatch()..start();
      try {
        final resp = await http
            .get(Uri.parse("${n.baseUrl}/v1/qccnode"))
            .timeout(_probeTimeout);
        sw.stop();
        n.reachable = resp.statusCode == 200;
        n.latencyMs = sw.elapsedMilliseconds;
        if (n.reachable) {
          n.failCount = 0;
          // 节点是被本地隐藏的，但这次探测又通了：自动取消隐藏，让它
          // 动态重新出现在列表里，不需要用户自己去"已隐藏节点"里手动恢复。
          if (n.hidden) {
            n.hidden = false;
            print("节点 ${n.ip} 重新可达，自动取消本地隐藏");
          }
        }
      } catch (_) {
        sw.stop();
        n.reachable = false;
        n.latencyMs = 99999;
      }
    }));
    await _saveToCache();
  }

  List<QccNode> _healthyNodesSortedByLatency() {
    final list = _nodes
        .where((n) =>
    n.active && n.reachable && n.failCount < _maxFailBeforeDeactivate)
        .toList();
    list.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return list;
  }

  /// ═══════════════════════════════════════════════════════════════
  /// "当前优化访问节点"的真正选择逻辑
  /// ═══════════════════════════════════════════════════════════════
  /// 区块链节点间高度不一致是常态（有节点会落后），最新数据必然在高度
  /// 最高的节点上——但"最高"不能只信单个节点自报的一个数字：一个节点
  /// 完全可能因为状态异常/探测误差/甚至被篡改，自报一个虚高的孤立值，
  /// 单纯按 height 降序选节点会被这类孤证带偏。
  ///
  /// 这里改用"多数节点共同确认"作为验证方式：把全网 active 节点按 height
  /// 分组，节点数最多的那一组高度，才是被多方独立数据点验证过的网络当前
  /// 高度（比如样例数据里 5 个节点同时停在 342434，明显是已同步到位的
  /// 领先组，而不是某个节点声称自己在 999999 却没有第二个节点佐证）。
  /// 节点数相同时取高度更高的分组——落后组不该反而胜出。
  ///
  /// 分组统计用全部 active 节点（不要求 reachable），避免"恰好这次探测
  /// 顺利的节点"污染了"谁的数据最新"这个判断；但最终能返回的候选，
  /// 仍然只能从 active && reachable && 未熔断 的可路由节点里选——
  /// 探测不通的节点再新也没法拿来发请求。
  ///
  /// 返回顺序：领先组内部按延迟升序排在最前（优先选最快的一个）；
  /// 领先组节点这次恰好都连不上时，自然回退到候选列表里第二梯队——
  /// 按高度降序、同高度再按延迟升序排列的"次优"节点。
  ///
  /// 【拆分原因】以前这里直接把 leading/lagging 拼成一条扁平列表返回，
  /// currentBaseUrl()/get() 就没法把 SSL 入口插在"领先组之后、落后组
  /// 之前"这个位置——所以拆成 _HeightRankedNodes，把两组分开暴露。
  _HeightRankedNodes _rankNodesByHeightConsensus() {
    final routable = _nodes
        .where((n) =>
    n.active && n.reachable && n.failCount < _maxFailBeforeDeactivate)
        .toList();
    if (routable.isEmpty) {
      return _HeightRankedNodes(const [], const []);
    }

    final activeWithHeight =
    _nodes.where((n) => n.active && n.height > 0).toList();
    if (activeWithHeight.isEmpty) {
      // 还没有任何高度数据（刚启动、探测/交叉验证还没跑完一轮），
      // 没法按高度分组，先退化为纯延迟排序，下一轮数据到位后自然切回来。
      final byLatency = List<QccNode>.from(routable)
        ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
      return _HeightRankedNodes(byLatency, const []);
    }

    final Map<int, int> countByHeight = {};
    for (final n in activeWithHeight) {
      countByHeight[n.height] = (countByHeight[n.height] ?? 0) + 1;
    }
    final rankedHeights = countByHeight.keys.toList()
      ..sort((a, b) {
        final byCount = countByHeight[b]!.compareTo(countByHeight[a]!);
        if (byCount != 0) return byCount;
        return b.compareTo(a); // 节点数相同，高度更高的分组优先
      });
    final leadingHeight = rankedHeights.first;

    final leading = routable.where((n) => n.height == leadingHeight).toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    final lagging = routable.where((n) => n.height != leadingHeight).toList()
      ..sort((a, b) {
        final byHeight = b.height.compareTo(a.height);
        if (byHeight != 0) return byHeight;
        return a.latencyMs.compareTo(b.latencyMs);
      });

    if (leading.isEmpty) {
      LogObj.log(
          "qcc节点优选: 领先高度 $leadingHeight 对应节点当前均不可路由，退化为可路由节点里高度最高的一组");
    } else if (leading.length > 1) {
      LogObj.log(
          "qcc节点优选: 高度 $leadingHeight 有 ${leading.length} 个活跃节点共同确认(领先组)，"
              "从可路由节点中优先按延迟选取；落后节点 ${lagging.length} 个作为兜底候选");
    }
    return _HeightRankedNodes(leading, lagging);
  }

  /// 拍平版本，供 _doRefreshNodes() 兜底拉取节点表等"只要一条排好序的
  /// 候选列表，不关心 leading/lagging 分界"的场景使用。
  List<QccNode> _healthyNodesSortedByPreference() {
    final r = _rankNodesByHeightConsensus();
    return [...r.leading, ...r.lagging];
  }

  String currentBaseUrl() {
    final ranked = _rankNodesByHeightConsensus();
    if (ranked.leading.isNotEmpty) return ranked.leading.first.baseUrl;
    if (ranked.lagging.isNotEmpty) return ranked.lagging.first.baseUrl;
    return sslBaseUrl;
  }

  QccNode? _findNode(String baseUrl) {
    for (final n in _nodes) {
      if (n.baseUrl == baseUrl) return n;
    }
    return null;
  }

  void reportSuccess(String baseUrl) {
    if (baseUrl == sslBaseUrl) {
      _sslFailCount = 0;
    } else {
      _findNode(baseUrl)?.failCount = 0;
    }
  }

  void reportFailure(String baseUrl) {
    if (baseUrl == sslBaseUrl) {
      _sslFailCount++;
    } else {
      final n = _findNode(baseUrl);
      if (n != null) {
        n.failCount++;
        if (n.failCount >= _maxFailBeforeDeactivate) n.reachable = false;
      }
    }
  }

  /// 带自动故障转移的 GET：业务层直接调用，不用关心具体连的是哪个节点。
  /// 每次尝试都会换一个候选 baseUrl，避免反复打同一个已失败节点。
  ///
  /// 【修复】候选顺序原来是 currentBaseUrl()（本质就是无条件的 SSL）→
  /// sslBaseUrl（去重后等于没有）→ 高度优选节点列表；默认 maxAttempts=3
  /// 时，只要 SSL 这一次 HTTP 请求"成功"（哪怕数据是明显落后节点给的），
  /// 下面这个 for 循环第一轮命中 2xx 就直接 return 了，高度优选列表压根
  /// 没机会被尝试到——这就是"高度一致性优选"在真实业务请求里被彻底
  /// 架空的地方。现在改成：领先组（按延迟）→ SSL → 落后组（按高度/延迟），
  /// SSL 不再排第一位，也不再重复占位。
  Future<http.Response?> get(String path, {int maxAttempts = 3}) async {
    if (!_initialized) await init();
    final ranked = _rankNodesByHeightConsensus();
    final candidates = <String>{
      ...ranked.leading.map((n) => n.baseUrl),
      sslBaseUrl,
      ...ranked.lagging.map((n) => n.baseUrl),
    }.toList();

    for (int i = 0; i < maxAttempts && i < candidates.length; i++) {
      final base = candidates[i];
      try {
        final resp =
        await http.get(Uri.parse("$base$path")).timeout(_probeTimeout);
        // 关键修复：http 包不会因为 4xx/5xx 状态码抛异常，只有网络层错误
        // （超时、连接被拒、DNS 失败等）才会走到 catch。像 521（Cloudflare
        // 判定源站不可用）这种"连上了但内容是错误页"的情况，之前会被
        // reportSuccess 误判为成功，导致 _sslFailCount 永远不增长，
        // currentBaseUrl() 就永远死认这个已经不可用的入口，压根不会切到
        // 别的健康节点。这里显式区分：
        // - 2xx：真正成功
        // - 5xx：服务端/网关错误，等同节点故障，计入失败并换下一个候选
        // - 其余（如 4xx）：节点本身是通的，只是这次请求的业务结果如此
        //   （比如地址不存在），不应触发切换，直接把响应交回业务层处理
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          reportSuccess(base);
          return resp;
        } else if (resp.statusCode >= 500) {
          print("请求 $base$path 返回 ${resp.statusCode}（服务端/网关错误），切换节点重试");
          reportFailure(base);
        } else {
          reportSuccess(base);
          return resp;
        }
      } catch (e) {
        print("请求 $base$path 失败: $e，切换节点重试");
        reportFailure(base);
      }
    }
    return null;
  }
}