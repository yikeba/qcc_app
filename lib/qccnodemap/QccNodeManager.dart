import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 节点类型：
/// - producer：出现在某个视图 `nodes` 数组里的节点（生产者集群成员，含当前出块者）
/// - sync    ：只出现在某个视图 `syncNodes.nodes` 里的节点（挂在某个生产者下的同步节点）
/// - unknown ：本轮没有任何视图提到它（比如写死的种子 IP 已经下线/换了 IP）
///
/// 同一个 IP 本轮只要在任一视图的 `nodes` 里出现过，就按 producer 算——
/// 同步节点晋升进生产者集群后，下一轮刷新自然切换类型，不需要特殊处理。
enum QccNodeKind { producer, sync, unknown }

int _asInt(dynamic v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

/// 单个节点的状态
class QccNode {
  final String ip;
  String nodeId; // 种子节点一开始没有 nodeId，从视图里拿到后回填
  int height;
  int lastSeen; // 客户端时钟下最近一次"被网络看到是新鲜的"时间（ms），= now - agoMs
  bool active; // 网络侧判断：本轮有视图看到它心跳新鲜，或它自己响应了探测
  bool reachable; // 客户端实际探测结果
  int failCount; // 连续失败次数（用于熔断）
  int latencyMs; // 最近一次探测延迟，用于排序选优
  bool hidden; // 本地"删除"标记：只影响 UI 展示，恢复可达后自动清除

  QccNodeKind kind;
  String? role; // 生产者视图里的 role 原值，例如 "NOW_PRODUCER"
  bool isNowProducer; // 当前出块者（按各视图 consistency.nowProducerIp 多数票）
  int lag; // 相对网络高度（_computeTip）落后的容器数；-1 表示未知/未同步
  String? voucherState; // 生产者凭证与多数 hash 的比对结果，例如 "match"
  Set<String> upstreamIps; // 同步节点：挂在哪个生产者下（来自该生产者视图的 syncNodes）

  // ---- IPv6 适配（同步节点视图新增字段）----
  // ip       ：节点凭证里自报的地址（ipSource=="credential"），可能是 IPv6；
  // remoteIp ：生产者看到的这条连接的实际来源地址。家庭节点的 remoteIp 是
  // NAT 出口，入站不可达，所以只作展示，不用于连接。
  String? remoteIp;
  String? ipSource;

  QccNode({
    required this.ip,
    this.nodeId = '',
    this.height = 0,
    this.lastSeen = 0,
    this.active = true,
    this.reachable = true,
    this.failCount = 0,
    this.latencyMs = 9999,
    this.hidden = false,
    this.kind = QccNodeKind.unknown,
    this.role,
    this.isNowProducer = false,
    this.lag = -1,
    this.voucherState,
    Set<String>? upstreamIps,
    this.remoteIp,
    this.ipSource,
  }) : upstreamIps = upstreamIps ?? <String>{};

  /// 出口地址与自报地址不同（典型：IPv6 家庭节点的 NAT 出口），仅展示用
  bool get hasAltRemote =>
      remoteIp != null && remoteIp!.isNotEmpty && remoteIp != ip;

  bool get isIPv6 => ip.contains(':');

  /// 其他链：该节点自己的视图比当前出块者高出太多 / 认的是另一个出块者
  /// （链重置后未升级的旧链节点、分叉、测试链）。每轮重新判定，不缓存。
  /// 不参与网络高度、读请求路由和上链确认。
  bool foreign = false;

  bool get isProducer => kind == QccNodeKind.producer;
  bool get isSync => kind == QccNodeKind.sync;

  /// 存活 = 网络判定（有视图看到新鲜心跳 / 自己响应了探测），与本机能否连上无关。
  /// 在金边连不上 IPv6 节点，不代表这个节点离线。
  bool get isOnline => active;

  /// 本机能否直连——只用于路由选点和延迟展示，不参与存活判断。
  bool get isDirect => reachable;

  // 假设：只有 https://test.qccio.com 配了证书，其余节点只能走明文 HTTP + 固定 9080 端口
  // IPv6 地址在 URL 里必须加方括号，已带方括号的不重复加。
  String get baseUrl {
    final isV6 = ip.contains(':') && !ip.startsWith('[');
    final host = isV6 ? '[$ip]' : ip;
    return "http://$host:9080";
  }

  /// 只用于本地缓存格式（_loadFromCache）。服务端视图走 _ingestViews 解析，
  /// 不再复用这个工厂——新的 /v1/qccnode 结构已经和缓存结构不是一回事了。
  factory QccNode.fromJson(Map<String, dynamic> j) => QccNode(
    ip: j['ip'] as String,
    nodeId: (j['nodeId'] ?? '') as String,
    height: _asInt(j['height']),
    lastSeen: _asInt(j['lastSeen']),
    active: (j['active'] ?? true) as bool,
    failCount: _asInt(j['failCount']),
    hidden: (j['hidden'] ?? false) as bool,
    kind: QccNodeKind.values.firstWhere(
          (k) => k.name == j['kind'],
      orElse: () => QccNodeKind.unknown,
    ),
    role: j['role'] as String?,
    upstreamIps:
    ((j['upstreamIps'] ?? const []) as List).whereType<String>().toSet(),
    remoteIp: j['remoteIp'] as String?,
    ipSource: j['ipSource'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'nodeId': nodeId,
    'height': height,
    'lastSeen': lastSeen,
    'active': active,
    'failCount': failCount,
    'hidden': hidden,
    'kind': kind.name,
    'role': role,
    'upstreamIps': upstreamIps.toList(),
    'remoteIp': remoteIp,
    'ipSource': ipSource,
  };
}

/// 由本轮收集到的各节点视图汇总出的网络状态，供 UI 顶部摘要展示。
class QccNetworkStatus {
  final int tipHeight; // 经互证的网络高度（见 _computeTip），0 = 未知
  final String? nowProducerIp;
  final String? nowProducerId;
  final bool consistent; // 所有视图的 consistency.consistent 均为 true
  final bool producerAgreed; // 所有视图 producerAgreed 且 nowProducerIp 一致
  final bool contentConsistent;
  final int viewCount; // 本轮汇总了几个节点的视图；0 = 还没校验过
  final DateTime? updatedAt;

  const QccNetworkStatus({
    this.tipHeight = 0,
    this.nowProducerIp,
    this.nowProducerId,
    this.consistent = false,
    this.producerAgreed = false,
    this.contentConsistent = false,
    this.viewCount = 0,
    this.updatedAt,
  });

  static const empty = QccNetworkStatus();

  bool get healthy =>
      viewCount > 0 && consistent && producerAgreed && contentConsistent;
}

/// 本机（客户端）的 IPv6 出站能力，由每轮探测结果推断，不枚举网卡、不引依赖：
/// - yes    ：本轮至少一个 IPv6 节点探测成功
/// - no     ：所有 IPv6 节点都不通，但有 IPv4 节点通
/// - unknown：还没探测过 / 网络里没有 IPv6 节点 / 本机整体断网
enum QccClientV6 { unknown, yes, no }

/// 单个视图的身份摘要：谁返回的（link=="self"）、它自己多高、它认谁是出块者。
/// _ingestViews 第一遍用它判定主链/其他链。
class _ViewMeta {
  final String? selfIp;
  final int? selfHeight;
  final String? vote;
  final Map<String, int> _heights; // 该视图 nodes[] 里对各节点报告的高度

  _ViewMeta(this.selfIp, this.selfHeight, this.vote, this._heights);

  int? heightOf(String ip) => _heights[ip];

  static _ViewMeta of(Map<String, dynamic> v) {
    String? selfIp;
    int? selfHeight;
    final hs = <String, int>{};
    final nodes = v['nodes'];
    if (nodes is List) {
      for (final raw in nodes) {
        if (raw is! Map) continue;
        final ip = raw['ip'];
        if (ip is! String || ip.isEmpty) continue;
        final h = _asInt(raw['height']);
        hs[ip] = h;
        if (raw['link'] == 'self') {
          selfIp = ip;
          selfHeight = h;
        }
      }
    }
    String? vote;
    final c = v['consistency'];
    if (c is Map) {
      final np = c['nowProducerIp'];
      if (np is String && np.isNotEmpty) vote = np;
    }
    return _ViewMeta(selfIp, selfHeight, vote, hs);
  }
}

/// _rankForReads() 的返回值：新鲜组 / 落后组，分开暴露
/// 好让 currentBaseUrl()/get() 能把 SSL 入口插在两组中间。
class _RankedNodes {
  final List<QccNode> leading;
  final List<QccNode> lagging;
  const _RankedNodes(this.leading, this.lagging);
}

/// 节点管理单例：负责拉取/缓存节点列表、健康探测、故障转移
class QccNodeManager {
  QccNodeManager._();
  static final QccNodeManager instance = QccNodeManager._();

  static const String sslBaseUrl = "https://test.qccio.com";

  // 种子节点：写死在客户端，避免 sslBaseUrl 单点故障时连节点列表都拿不到。
  // 注意：对照 2026-10-21 的视图，23.238.114.9、192.129.133.168 已不在网络里
  // （同步列表里出现的是 23.238.114.155），种子表需要你核对更新。
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

  /// 假设：心跳/lastSeen 超过 15 秒视为不新鲜。样例里心跳间隔在 0.2–2 秒，
  /// 15 秒足够宽容；如果服务端有明确的心跳超时常量，改成跟它一致。
  static const int _staleAfterMs = 15000;

  /// 读请求可接受的落后容器数。同步节点相对当前生产者常态落后 1 个容器
  /// （样例里 6 个同步节点全是 lag=1），所以不能要求 lag=0。
  static const int _maxReadLag = 2;

  /// 判定"其他链"的高度差：沿用"落后 >10 退出生产者集群"的边界。
  /// 主链节点不可能高出当前出块者，正常落后也在 10 以内；重置前的旧链
  /// 高度差通常是成千上万，不会误判。
  static const int _foreignGap = 10;

  /// 读请求优先走同步节点、生产者兜底——生产者集群的设计目标之一是隐藏/
  /// 保护生产者，客户端读流量不应该默认打到当前出块者身上。
  /// 如果某类读接口必须拿到最新一个容器（lag=0），对那类请求单独走生产者。
  static const bool _preferSyncForReads = true;

  List<QccNode> _nodes = [];
  bool _initialized = false;
  DateTime? _lastRefresh;
  int _sslFailCount = 0;
  QccNetworkStatus _network = QccNetworkStatus.empty;
  QccClientV6 _clientV6 = QccClientV6.unknown;
  bool _clientOffline = false;

  // 刷新、探测都用 in-flight Future 做重入保护：重入时返回正在跑的那个
  // Future，而不是直接 return——保证调用方 await 完拿到的是真结果。
  Future<void>? _inFlightRefresh;
  Future<void>? _inFlightProbe;
  bool _crossValidating = false;

  /// 只读节点快照（含本地隐藏的节点）
  List<QccNode> get nodes => List.unmodifiable(_nodes);

  /// 供列表 UI 展示用：排除掉本地手动隐藏的节点。
  List<QccNode> get visibleNodes =>
      List.unmodifiable(_nodes.where((n) => !n.hidden));

  /// 已被本地隐藏的节点
  List<QccNode> get hiddenNodes =>
      List.unmodifiable(_nodes.where((n) => n.hidden));

  /// 最近一轮汇总出的网络状态（当前出块者、一致性标记等）
  QccNetworkStatus get network => _network;

  /// 网络高度：最近一轮汇总结果（以当前出块者为准）；还没汇总过时从缓存高度互证推算
  int get tipHeight =>
      _network.tipHeight > 0 ? _network.tipHeight : _computeTip();

  /// 可路由：网络在线、本机可直连、未熔断、且在主链上
  bool _routable(QccNode n) =>
      n.active &&
          n.reachable &&
          !n.foreign &&
          n.failCount < _maxFailBeforeDeactivate;

  /// 本机 IPv6 出站能力（见 QccClientV6）
  QccClientV6 get clientV6 => _clientV6;

  /// 最近一轮探测所有节点都不通：本机网络有问题，此时不改动任何节点的存活判断
  bool get clientOffline => _clientOffline;

  /// UI 用：节点网络在线但本机连不上的原因
  String unreachableReason(QccNode n) {
    if (_clientOffline) return "本机网络异常";
    if (n.isIPv6 && _clientV6 == QccClientV6.no) return "本机无IPv6";
    return "本机不可达";
  }

  /// 供 UI 主动触发一次探测（比如下拉刷新）
  Future<void> probeAll() => _probeAll();

  Future<void> hideNode(String ip) async {
    for (final n in _nodes) {
      if (n.ip == ip) {
        n.hidden = true;
        break;
      }
    }
    await _saveToCache();
  }

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
      _nodes = _seedIps.map((ip) => QccNode(ip: ip)).toList();
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

  Future<void> refreshNodes({bool force = false}) {
    if (!force &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _refreshInterval) {
      return Future.value();
    }
    if (_inFlightRefresh != null) return _inFlightRefresh!;
    final fut = _doRefreshNodes();
    _inFlightRefresh = fut;
    fut.whenComplete(() => _inFlightRefresh = null);
    return fut;
  }

  /// 刷新流程：
  /// 1. 先拿一个"主视图"（SSL 入口，失败则按优选顺序问已知节点），
  ///    非整轮合并——只用来尽早发现新节点，让它们能被第 2 步探测到；
  /// 2. 对全部已知节点做一轮探测。每个节点的 /v1/qccnode 响应本身就是该节点
  ///    的一份完整视图，所以探测这一步顺带拿到了"全网所有可达节点的视图"，
  ///    在这里做整轮合并：生产/同步类型、当前出块者、高度、新鲜度全部一次定下。
  ///
  /// 以前的 crossValidateNodes()（抽样 3 个节点再拉一遍）被第 2 步完全覆盖，
  /// 刷新流程里不再调用，避免对同一批节点重复拉取。
  Future<void> _doRefreshNodes() async {
    Map<String, dynamic>? primary = await _fetchNodeList(sslBaseUrl);
    if (primary == null) {
      for (final n in _healthyNodesSortedByPreference()) {
        primary = await _fetchNodeList(n.baseUrl);
        if (primary != null) break;
      }
    }

    if (primary != null) {
      try {
        _ingestViews([primary], fullRound: false);
        _lastRefresh = DateTime.now();
      } catch (e) {
        print("解析 /v1/qccnode 返回失败: $e");
      }
    } else {
      // 和以前不同：主入口全挂时不再直接 return，照样探测已知节点——
      // 探测响应本身就是视图，节点间互相还能看到的话，列表照样能更新。
      print("节点列表主入口均不可达，改为直接探测已知节点");
    }

    await _probeAll();
  }

  /// 保留对外签名，供业务层需要时手动触发一次抽样校验；刷新流程不再调用。
  Future<void> crossValidateNodes({int sampleSize = 3}) async {
    if (_crossValidating) return;
    _crossValidating = true;
    try {
      final pool = _healthyNodesSortedByLatency();
      final sample = pool.length <= sampleSize
          ? pool
          : (List<QccNode>.from(pool)..shuffle()).take(sampleSize).toList();

      final views = <Map<String, dynamic>>[];
      await Future.wait([
        _fetchNodeList(sslBaseUrl).then((d) {
          if (d != null) views.add(d);
        }),
        ...sample.map((n) => _fetchNodeList(n.baseUrl).then((d) {
          if (d != null) views.add(d);
        })),
      ]);
      if (views.isEmpty) return;
      _ingestViews(views, fullRound: false);
      await _saveToCache();
    } finally {
      _crossValidating = false;
    }
  }

  Map<String, dynamic>? _decodeView(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['status'] == 'ok') {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchNodeList(String base) async {
    try {
      final resp =
      await http.get(Uri.parse("$base/v1/qccnode")).timeout(_probeTimeout);
      if (resp.statusCode == 200) return _decodeView(resp.body);
    } catch (_) {}
    return null;
  }

  /// ═══════════════════════════════════════════════════════════════
  /// 把若干节点视图合并进本地节点表
  /// ═══════════════════════════════════════════════════════════════
  /// 视图结构（/v1/qccnode）：
  /// - nodes[]          ：该节点看到的生产者（含 link=="self" 的自己、role、voucher）
  /// - syncNodes.nodes[]：挂在该节点（生产者）下的同步节点
  /// - consistency      ：该节点对生产者集群的一致性判断（nowProducerIp 等）
  ///
  /// fullRound=true 表示这批视图是"本轮对全部已知节点探测"的完整结果：
  /// 本轮任何视图都没看到新鲜心跳、自己也没响应探测的节点，判为 active=false。
  /// fullRound=false（单个主视图/抽样）只做增量：只会点亮，不会熄灭。
  ///
  /// 高度取值规则（链重置后发现的问题，取代原来的"各视图最大值"）：
  /// 1. 节点自己视图里 link=="self" 的高度是权威值；
  ///    其它视图对它的观察，取最新鲜（ago 最小）的一条，不再取最大值。
  /// 2. syncNodes.offline 条目的高度是"最后一次看到时"的陈旧值（重置前的
  ///    8052 就是这样来的），只用于发现节点和记录上游关系，不参与高度。
  /// 3. 当前出块者是唯一真相源，任何节点都不可能高出它：自身高度比出块者
  ///    高出 _foreignGap 以上，或者投票的出块者与多数不同、且高度相差
  ///    _foreignGap 以上的视图，判为"其他链"（重置前未升级 / 分叉 / 测试链）。
  ///    其他链视图整体丢弃，不污染主链节点的高度，节点本身标 foreign，
  ///    不参与路由和网络高度计算。
  void _ingestViews(List<Map<String, dynamic>> views,
      {required bool fullRound, Set<String> respondedIps = const {}}) {
    if (views.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ---- 第一遍：每个视图的自身 ip / 自身高度 / 投票的出块者 ----
    final metas = views.map(_ViewMeta.of).toList();
    final nowProducerVotes = <String, int>{};
    for (final m in metas) {
      if (m.vote != null) {
        nowProducerVotes[m.vote!] = (nowProducerVotes[m.vote!] ?? 0) + 1;
      }
    }
    String? nowProducerIp;
    if (nowProducerVotes.isNotEmpty) {
      nowProducerIp = nowProducerVotes.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    // 出块者高度：优先它自己的视图；拿不到就取投它票的视图里对它的观察最大值
    int? producerHeight;
    if (nowProducerIp != null) {
      for (final m in metas) {
        if (m.selfIp == nowProducerIp && m.selfHeight != null) {
          producerHeight = m.selfHeight;
        }
      }
      producerHeight ??= metas
          .where((m) => m.vote == nowProducerIp)
          .map((m) => m.heightOf(nowProducerIp!))
          .whereType<int>()
          .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    }

    bool isForeign(_ViewMeta m) {
      if (producerHeight == null || m.selfHeight == null) return false;
      final diff = m.selfHeight! - producerHeight!;
      if (diff > _foreignGap) return true; // 不可能高出当前出块者
      if (m.vote != null && m.vote != nowProducerIp && diff.abs() > _foreignGap) {
        return true; // 认的是另一个出块者，且高度对不上
      }
      return false;
    }

    final foreignHeights = <String, int>{};
    final mainViews = <Map<String, dynamic>>[];
    for (var i = 0; i < views.length; i++) {
      final m = metas[i];
      if (isForeign(m)) {
        if (m.selfIp != null) foreignHeights[m.selfIp!] = m.selfHeight ?? 0;
      } else {
        mainViews.add(views[i]);
      }
    }
    if (foreignHeights.isNotEmpty) {
      LogObj.log("qcc节点 排除其他链视图: $foreignHeights（当前出块者 $nowProducerIp 高度 $producerHeight）");
    }

    // ---- 第二遍：只处理主链视图 ----
    final seenIps = <String>{};
    final selfHeights = <String, int>{};
    final obsHeight = <String, int>{};
    final obsAgo = <String, int>{};
    final nodeIds = <String, String>{};
    final roles = <String, String>{};
    final voucherStates = <String, String>{};
    final freshAt = <String, int>{};
    final upstream = <String, Set<String>>{};
    final remoteIps = <String, String>{};
    final ipSources = <String, String>{};
    var consistent = true, producerAgreed = nowProducerVotes.length <= 1;
    var contentConsistent = true;

    void seenAddr(String ip, Map raw) {
      final r = raw['remoteIp'];
      if (r is String && r.isNotEmpty) remoteIps[ip] = r;
      final s = raw['ipSource'];
      if (s is String && s.isNotEmpty) ipSources[ip] = s;
    }

    /// agoMs < 0：新鲜度未知（offline 条目），只记录存在，不参与高度/新鲜度
    void seen(String ip, dynamic id, int h, int agoMs, {bool self = false}) {
      seenIps.add(ip);
      if (id is String && id.isNotEmpty) nodeIds[ip] = id;
      if (self) {
        selfHeights[ip] = h;
      } else if (agoMs >= 0) {
        final cur = obsAgo[ip];
        if (cur == null || agoMs < cur || (agoMs == cur && h > obsHeight[ip]!)) {
          obsAgo[ip] = agoMs;
          obsHeight[ip] = h;
        }
      }
      if (agoMs >= 0 && agoMs <= _staleAfterMs) {
        final at = nowMs - agoMs;
        if ((freshAt[ip] ?? 0) < at) freshAt[ip] = at;
      }
    }

    for (final v in mainViews) {
      final c = v['consistency'];
      if (c is Map) {
        consistent = consistent && c['consistent'] == true;
        producerAgreed = producerAgreed && c['producerAgreed'] == true;
        contentConsistent = contentConsistent && c['contentConsistent'] == true;
      } else {
        consistent = producerAgreed = contentConsistent = false;
      }

      String? selfIp;
      final producers = v['nodes'];
      if (producers is List) {
        for (final raw in producers) {
          if (raw is! Map) continue;
          final ip = raw['ip'];
          if (ip is! String || ip.isEmpty) continue;
          final isSelf = raw['link'] == 'self';
          if (isSelf) selfIp = ip;
          final role = raw['role'];
          if (role is String) roles[ip] = role;
          final voucher = raw['voucher'];
          if (voucher is Map && voucher['state'] is String) {
            voucherStates[ip] = voucher['state'] as String;
          }
          seenAddr(ip, raw);
          seen(ip, raw['nodeId'], _asInt(raw['height']),
              isSelf ? 0 : _asInt(raw['lastSeenAgoMs'], -1),
              self: isSelf);
        }
      }

      // 同步节点：上游 = 本视图里 link=="self" 的那个节点
      final sync = v['syncNodes'];
      if (sync is Map) {
        for (final listKey in const ['nodes', 'offline']) {
          final list = sync[listKey];
          if (list is! List) continue;
          final isOffline = listKey == 'offline';
          for (final raw in list) {
            if (raw is! Map) continue;
            final ip = raw['ip'];
            if (ip is! String || ip.isEmpty) continue;
            if (selfIp != null) {
              upstream.putIfAbsent(ip, () => <String>{}).add(selfIp);
            }
            seenAddr(ip, raw);
            seen(ip, raw['nodeId'], _asInt(raw['height']),
                isOffline ? -1 : _asInt(raw['lastHeartbeatAgoMs'], -1));
          }
        }
      }
    }

    final heights = <String, int>{...obsHeight, ...selfHeights};

    // 动态发现新节点
    final known = {for (final n in _nodes) n.ip};
    for (final ip in seenIps) {
      if (known.add(ip)) {
        _nodes.add(QccNode(ip: ip, nodeId: nodeIds[ip] ?? ''));
        LogObj.log("qcc节点 发现新节点并加入本地列表: $ip");
      }
    }

    // 同一 nodeId 换了地址（例如由 IPv4 改报 IPv6）：nodeId 才是身份，
    // 保留本轮视图里的地址，删掉旧地址条目，隐藏标记带过去。
    // 本轮同一 nodeId 出现多个地址时，优先 ipSource=="credential" 的那个。
    final ipByNodeId = <String, String>{};
    nodeIds.forEach((ip, id) {
      final cur = ipByNodeId[id];
      if (cur == null || ipSources[ip] == 'credential') ipByNodeId[id] = ip;
    });
    final stale = _nodes.where((n) {
      if (n.nodeId.isEmpty) return false;
      final cur = ipByNodeId[n.nodeId];
      return cur != null && cur != n.ip;
    }).toList();
    for (final old in stale) {
      final keep = _nodes.firstWhere((x) => x.ip == ipByNodeId[old.nodeId]);
      keep.hidden = keep.hidden || old.hidden;
      _nodes.remove(old);
      // 正常情况下只在清理本地缓存里的旧地址时出现一次；
      // 如果每轮刷新都出现，说明有视图在持续报出不同地址，需要查服务端。
      LogObj.log("qcc节点 ${old.nodeId} 旧地址 ${old.ip} 并入 ${keep.ip}（以本轮视图为准）");
    }

    for (final n in _nodes) {
      // 其他链节点：显示它自报的高度，类型归入"未识别/其他链"，
      // 存活看它是否响应了本轮探测（它确实活着，只是不在主链上）
      final fh = foreignHeights[n.ip];
      if (fh != null) {
        n.foreign = true;
        n.height = fh;
        n.kind = QccNodeKind.unknown;
        n.isNowProducer = false;
        n.upstreamIps = <String>{};
        if (respondedIps.contains(n.ip)) {
          n.active = true;
          n.lastSeen = nowMs;
        } else if (fullRound) {
          n.active = false;
        }
        continue;
      }
      if (seenIps.contains(n.ip) || fullRound) n.foreign = false;

      final h = heights[n.ip];
      if (h != null) n.height = h;
      final id = nodeIds[n.ip];
      if (id != null) n.nodeId = id;
      if (remoteIps.containsKey(n.ip)) n.remoteIp = remoteIps[n.ip];
      if (ipSources.containsKey(n.ip)) n.ipSource = ipSources[n.ip];

      // 类型判定：任何时刻只有一个生产者（当前出块者），其余节点都在同步。
      // 不再按"出现在视图 nodes 还是 syncNodes 里"判断——实测同步节点在
      // 自己的视图里会把自己列进 nodes，按位置判断会把全网都判成生产者。
      final seenThisRound = seenIps.contains(n.ip);
      if (nowProducerIp != null) {
        n.isNowProducer = n.ip == nowProducerIp;
        if (n.isNowProducer) {
          n.kind = QccNodeKind.producer;
        } else if (seenThisRound || n.kind == QccNodeKind.producer) {
          n.kind = QccNodeKind.sync;
        }
      }
      n.role = roles[n.ip] ?? n.role;
      n.voucherState = voucherStates[n.ip] ?? n.voucherState;
      if (n.isProducer) {
        n.upstreamIps = <String>{};
      } else if (seenThisRound) {
        n.upstreamIps = fullRound
            ? (upstream[n.ip] ?? <String>{})
            : {...n.upstreamIps, ...?upstream[n.ip]};
      }

      final at = freshAt[n.ip];
      if (at != null || respondedIps.contains(n.ip)) {
        n.active = true;
        n.lastSeen = at ?? nowMs;
      } else if (fullRound) {
        n.active = false;
      }
    }

    // 网络高度：拿得到当前出块者高度就以它为准（唯一真相源），否则走互证算法
    final tip = producerHeight ?? _computeTip();

    // 链重置检测：本轮没有任何主链视图给出高度、本地缓存的高度却比网络高度
    // 高出 _foreignGap 以上——这是重置前留下的旧值，清掉（显示"未同步"），
    // 等它下次被观察到再填。不清的话离线节点会一直显示重置前的高度，
    // 并且 lag 被夹到 0，看起来像"已同步"。
    if (tip > 0) {
      var cleared = 0;
      for (final n in _nodes) {
        if (n.foreign || heights.containsKey(n.ip)) continue;
        if (n.height > tip + _foreignGap) {
          n.height = -1;
          cleared++;
        }
      }
      if (cleared > 0) {
        LogObj.log("qcc节点 网络高度 $tip，清除 $cleared 个节点高于网络的陈旧缓存高度（链重置？）");
      }
    }

    for (final n in _nodes) {
      if (tip <= 0 || n.height < 0) {
        n.lag = -1;
      } else {
        final d = tip - n.height;
        n.lag = d < 0 ? 0 : d;
      }
    }

    _network = QccNetworkStatus(
      tipHeight: tip,
      nowProducerIp: nowProducerIp,
      nowProducerId: nowProducerIp == null ? null : nodeIds[nowProducerIp],
      consistent: consistent,
      producerAgreed: producerAgreed,
      contentConsistent: contentConsistent,
      viewCount: views.length,
      updatedAt: DateTime.now(),
    );

    // 高度差 1–2 个容器在高频出块下是常态，不记日志；
    // 只有各视图对"谁是当前出块者"说法不一才值得关注。
    if (nowProducerVotes.length > 1) {
      LogObj.log("qcc节点 各视图当前出块者不一致: $nowProducerVotes");
    }
  }

  /// 网络高度（互证版）：
  /// 旧逻辑是"节点数最多的高度组"——在生产者/同步分层后这个规则是错的：
  /// 样例里 1 个生产者在 393、6 个同步节点在 392，众数会选中 392，把真正
  /// 最新的生产者判成落后。
  ///
  /// 现在改为：从高到低找第一个"至少还有另一个节点在它下方 _maxReadLag 以内"
  /// 的高度。既不被同步节点常态落后 1 拉低，又保留了旧逻辑想要的防孤证——
  /// 某个节点单独自报 999999、没有任何节点在附近佐证，会被跳过。
  /// 只统计 active 节点；全都不 active 时退化为全部节点。
  int _computeTip() {
    List<int> collect(bool activeOnly) => _nodes
        .where((n) => n.height > 0 && !n.foreign && (!activeOnly || n.active))
        .map((n) => n.height)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    var hs = collect(true);
    if (hs.isEmpty) hs = collect(false);
    if (hs.isEmpty) return 0;
    if (hs.length == 1) return hs.first;
    for (var i = 0; i + 1 < hs.length; i++) {
      if (hs[i] - hs[i + 1] <= _maxReadLag) return hs[i];
    }
    // 所有高度两两相差都超过 _maxReadLag（网络严重分裂），没有任何互证；
    // 取第二高——至少有两个节点达到或超过它。
    return hs[1];
  }

  /// 并发探测所有节点的可达性/延迟，同时收集每个节点的视图做整轮合并。
  /// 注意：这里复用 /v1/qccnode 当健康检查端点——好处是探测即拿全网视图；
  /// 代价是节点数上千后每轮流量不小，到时候建议服务端出一个精简视图参数。
  Future<void> _probeAll() {
    if (_inFlightProbe != null) return _inFlightProbe!;
    final fut = _doProbeAll();
    _inFlightProbe = fut;
    fut.whenComplete(() => _inFlightProbe = null);
    return fut;
  }

  /// 探测单个节点：只连自报地址 ip，不再回退 remoteIp（家庭节点的 remoteIp
  /// 是 NAT 出口，入站必然不通，回退只会白等一次超时）。返回是否连通。
  Future<bool> _probeOne(QccNode n, List<Map<String, dynamic>> views,
      Set<String> responded) async {
    final sw = Stopwatch()..start();
    try {
      final resp = await http
          .get(Uri.parse("${n.baseUrl}/v1/qccnode"))
          .timeout(_probeTimeout);
      sw.stop();
      n.latencyMs = sw.elapsedMilliseconds;
      n.reachable = resp.statusCode == 200;
      if (!n.reachable) return false;
      n.failCount = 0;
      if (n.hidden) {
        n.hidden = false;
        print("节点 ${n.ip} 重新可达，自动取消本地隐藏");
      }
      final view = _decodeView(resp.body);
      if (view != null) {
        views.add(view);
        responded.add(n.ip);
      }
      return true;
    } catch (_) {
      sw.stop();
      n.reachable = false;
      n.latencyMs = 99999;
      return false;
    }
  }

  void _markSkipped(QccNode n) {
    n.reachable = false;
    n.latencyMs = 99999;
  }

  /// 一轮探测 + 本机 IPv6 能力推断：
  /// - 已判定本机无 IPv6 时，IPv6 节点只抽一个做"金丝雀"探测，其余不发请求
  ///   （每个都等 3 秒超时没有意义）；金丝雀通了说明本机恢复了 IPv6
  ///   （比如 Wi-Fi 切到 4G），同一轮里立即补探其余 IPv6 节点。
  /// - 结论：有 IPv6 节点通 → yes；IPv6 全不通但 IPv4 有通 → no；
  ///   全部不通 → 本机断网，_clientOffline=true，且不做视图合并、
  ///   不改动任何节点的存活状态（观察者自己的问题不能算到节点头上）。
  Future<void> _doProbeAll() async {
    final views = <Map<String, dynamic>>[];
    final responded = <String>{};
    final targets = List<QccNode>.from(_nodes);
    final v4 = targets.where((n) => !n.isIPv6).toList();
    final v6 = targets.where((n) => n.isIPv6).toList();

    List<QccNode> v6First;
    List<QccNode> v6Deferred;
    if (_clientV6 == QccClientV6.no && v6.isNotEmpty) {
      // 金丝雀优先挑网络侧在线的，避免挑到一个本来就下线的节点误判
      final canary = v6.firstWhere((n) => n.active, orElse: () => v6.first);
      v6First = [canary];
      v6Deferred = v6.where((n) => !identical(n, canary)).toList();
    } else {
      v6First = v6;
      v6Deferred = const [];
    }

    final v4Results =
    Future.wait(v4.map((n) => _probeOne(n, views, responded)));
    final v6Results =
    Future.wait(v6First.map((n) => _probeOne(n, views, responded)));
    final v4Ok = (await v4Results).any((ok) => ok);
    var v6Ok = (await v6Results).any((ok) => ok);

    if (v6Deferred.isNotEmpty) {
      if (v6Ok) {
        LogObj.log("qcc节点 本机 IPv6 已恢复，补探其余 ${v6Deferred.length} 个 IPv6 节点");
        await Future.wait(v6Deferred.map((n) => _probeOne(n, views, responded)));
      } else {
        for (final n in v6Deferred) {
          _markSkipped(n);
        }
      }
    }

    if (!v4Ok && !v6Ok && targets.isNotEmpty) {
      _clientOffline = true;
      LogObj.log("qcc节点 本轮所有节点均不可达，判定本机网络异常，保留节点原有存活状态");
      await _saveToCache();
      return;
    }
    _clientOffline = false;
    final prevV6 = _clientV6;
    if (v6Ok) {
      _clientV6 = QccClientV6.yes;
    } else if (v6.isNotEmpty) {
      _clientV6 = QccClientV6.no;
    }
    if (prevV6 != _clientV6) {
      LogObj.log("qcc节点 本机 IPv6 能力: $prevV6 → $_clientV6");
    }

    if (views.isNotEmpty) {
      try {
        _ingestViews(views, fullRound: true, respondedIps: responded);
      } catch (e) {
        print("合并节点视图失败: $e");
      }
    }
    await _saveToCache();
  }

  List<QccNode> _healthyNodesSortedByLatency() {
    final list = _nodes.where(_routable).toList();
    list.sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    return list;
  }

  /// ═══════════════════════════════════════════════════════════════
  /// 读请求的节点优选
  /// ═══════════════════════════════════════════════════════════════
  /// 新鲜组：height >= tip - _maxReadLag 的可路由节点；
  ///   _preferSyncForReads=true 时 同步节点(按延迟) → 生产者(按延迟)。
  /// 落后组：其余可路由节点，按高度降序、同高度按延迟升序。
  _RankedNodes _rankForReads() {
    final routable = _nodes.where(_routable).toList();
    if (routable.isEmpty) return const _RankedNodes([], []);

    int byLatency(QccNode a, QccNode b) => a.latencyMs.compareTo(b.latencyMs);

    final tip = tipHeight;
    if (tip <= 0) {
      // 还没有任何高度数据，先退化为纯延迟排序
      return _RankedNodes(routable..sort(byLatency), const []);
    }

    final fresh = <QccNode>[];
    final stale = <QccNode>[];
    for (final n in routable) {
      (n.height >= tip - _maxReadLag ? fresh : stale).add(n);
    }
    final freshSync = fresh.where((n) => !n.isProducer).toList()
      ..sort(byLatency);
    final freshProd = fresh.where((n) => n.isProducer).toList()
      ..sort(byLatency);
    stale.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      return byLatency(a, b);
    });

    if (fresh.isEmpty) {
      LogObj.log("qcc节点优选: 网络高度 $tip 附近没有可路由节点，退化为落后节点");
    }
    final leading = _preferSyncForReads
        ? [...freshSync, ...freshProd]
        : [...freshProd, ...freshSync];
    return _RankedNodes(leading, stale);
  }

  /// 供"查询交易是否已上链"使用：按高度降序（同高度按延迟）返回可路由节点。
  /// 交易进入容器后，最先拿到该容器的是高度最高的节点，所以这里不走
  /// _rankForReads() 的"同步节点优先"，而是直接按高度挑。
  /// 没有任何可路由节点时退回 SSL 入口。
  List<String> highestHeightBaseUrls({int limit = 3}) {
    final routable = _nodes.where(_routable).toList()
      ..sort((a, b) {
        final byHeight = b.height.compareTo(a.height);
        if (byHeight != 0) return byHeight;
        return a.latencyMs.compareTo(b.latencyMs);
      });
    if (routable.isEmpty) return [sslBaseUrl];
    return routable.take(limit).map((n) => n.baseUrl).toList();
  }

  List<QccNode> _healthyNodesSortedByPreference() {
    final r = _rankForReads();
    return [...r.leading, ...r.lagging];
  }

  String currentBaseUrl() {
    final ranked = _rankForReads();
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

  /// 带自动故障转移的 GET（读请求）。候选顺序：新鲜组 → SSL → 落后组。
  /// 2xx 成功；5xx 视为节点故障换下一个；其余（4xx）是业务结果，直接返回。
  Future<http.Response?> get(String path, {int maxAttempts = 3}) async {
    if (!_initialized) await init();
    final ranked = _rankForReads();
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