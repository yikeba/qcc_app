import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import 'QccNodeManager.dart';
import 'QccNodeMapWidget.dart' show shortNodeId;
import 'QccMinerReward.dart';
import 'qcc_geo_service.dart';

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// /v1/producer 返回的单个状态机条目（全部质押 ≥1 万 QCC 节点的总排序）
class QccProducerRank {
  final int rank;
  final String nodeId;
  final String status; // PRODUCER / CANDIDATE / 其它原样保留
  final int heat; // 积分（热度），可为负
  final int regTime;
  final int cycleProduced; // 本周期已出容器数
  final int toMilestone; // 距本周期 1 万容器里程碑还差多少
  final int cyclePurchased; // 本周期购买的积分
  final int totalProduced;
  final int missed; // 轮到却由他人出块的次数（扣分依据）
  final int pledge; // 质押量，最小单位
  final int unlockAt; // 解押时间（ms）

  QccProducerRank.fromJson(Map<String, dynamic> j)
      : rank = _i(j['rank']),
        nodeId = (j['nodeId'] ?? '').toString(),
        status = (j['status'] ?? '').toString(),
        heat = _i(j['heat']),
        regTime = _i(j['regTime']),
        cycleProduced = _i(j['cycleProduced']),
        toMilestone = _i(j['toMilestone']),
        cyclePurchased = _i(j['cyclePurchased']),
        totalProduced = _i(j['totalProduced']),
        missed = _i(j['missed']),
        pledge = _i(j['pledge']),
        unlockAt = _i(j['unlockAt']);

  bool get isProducer => status == 'PRODUCER';
  bool get isCandidate => status == 'CANDIDATE';

  /// 里程碑总量：用 cycleProduced + toMilestone 现算，不在客户端写死 10000，
  /// 服务端常量表调参后这里自动跟随。
  int get milestone => cycleProduced + toMilestone;
}

class QccProducerCluster {
  final int height;
  final int term;
  final int clusterSize; // 集群容量
  final List<String> producers; // 当前在生产组里的 nodeId
  final int members; // 状态机名单人数
  final List<QccProducerRank> ranking;
  final String source; // 由哪个节点返回（baseUrl），便于排查

  QccProducerCluster.fromJson(Map<String, dynamic> j, this.source)
      : height = _i(j['height']),
        term = _i(j['term']),
        clusterSize = _i(j['clusterSize']),
        producers = ((j['producers'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        members = _i(j['members']),
        ranking = ((j['ranking'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => QccProducerRank.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
}

/// /v1/producer 的拉取与缓存。节点列表页也要按 nodeId 显示积分，
/// 所以把结果缓存在这里，两个页面共用一份。
class QccProducerService {
  static QccProducerCluster? last;
  static Future<QccProducerCluster>? _inFlight;

  static Future<QccProducerCluster> fetch() {
    return _inFlight ??= _doFetch().whenComplete(() => _inFlight = null);
  }

  static Future<QccProducerCluster> _doFetch() async {
    await QccNodeManager.instance.init();
    final resp = await QccNodeManager.instance.get('/v1/producer');
    if (resp == null) throw Exception("所有节点均不可达");
    final j = jsonDecode(resp.body);
    if (j is! Map || j['status'] != 'ok') {
      throw Exception("返回异常: ${resp.body}");
    }
    final data = QccProducerCluster.fromJson(
        Map<String, dynamic>.from(j), resp.request?.url.origin ?? '');
    last = data;
    return data;
  }

  static QccProducerRank? rankOf(String nodeId) {
    if (nodeId.isEmpty) return null;
    for (final r in last?.ranking ?? const <QccProducerRank>[]) {
      if (r.nodeId == nodeId) return r;
    }
    return null;
  }
}

/// 积分构成（从数据反推，非服务端定义）：
/// 样例 611 = 10 + 701 − 100×1，612 = 10 + 602，74 = 10 + 64，
/// 即 初始10 + 本周期出块 − 100×漏块 + 本周期购买。
/// 只在算式与 heat 完全吻合时才显示拆解，对不上就不显示，避免给出错误解释。
String? heatBreakdown(QccProducerRank r) {
  const init = 10, missPenalty = 100;
  final calc =
      init + r.cycleProduced - missPenalty * r.missed + r.cyclePurchased;
  if (calc != r.heat) return null;
  final parts = <String>["初始$init", "出块${r.cycleProduced}"];
  if (r.missed > 0) parts.add("漏块−${missPenalty * r.missed}");
  if (r.cyclePurchased > 0) parts.add("购买${r.cyclePurchased}");
  return parts.join(" + ").replaceAll("+ 漏块−", "− 漏块");
}

/// 生产者集群状态 & 积分。
/// 数据来自任意节点的 GET /v1/producer，走 QccNodeManager.get() 自动选点和故障转移。
/// nodeId 与节点列表里的 nodeId 关联，补上 IP / 地区 / 本机能否直连。
class QccProducerClusterWidget extends StatefulWidget {
  const QccProducerClusterWidget({super.key});

  @override
  State<QccProducerClusterWidget> createState() =>
      _QccProducerClusterWidgetState();
}

class _QccProducerClusterWidgetState extends State<QccProducerClusterWidget>
    with AutomaticKeepAliveClientMixin {
  QccProducerCluster? _data;
  String? _error;
  bool _loading = false;
  DateTime? _updatedAt;
  final Map<String, GeoInfo?> _geo = {};
  Set<String> _myAddrs = {};

  @override
  bool get wantKeepAlive => true; // 切 tab 不重新拉

  @override
  void initState() {
    super.initState();
    _myAddrs = QccObj.readWallets().map((e) => e.address).toSet();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 收益汇总与集群状态并行拉；收益失败不影响集群状态显示
      final rewardsF = QccMinerRewardService.fetchSummary().catchError((e) {
        LogObj.log("qcc生产者收益 汇总查询失败: $e");
      });
      final data = await QccProducerService.fetch();
      await rewardsF;
      await _lookupGeo(data);
      if (!mounted) return;
      setState(() {
        _data = data;
        _updatedAt = DateTime.now();
      });
    } catch (e) {
      LogObj.log("qcc生产集群 查询失败: $e");
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  QccNode? _nodeOf(String nodeId) {
    for (final n in QccNodeManager.instance.nodes) {
      if (n.nodeId == nodeId) return n;
    }
    return null;
  }

  Future<void> _lookupGeo(QccProducerCluster d) async {
    await Future.wait(d.ranking.map((r) async {
      final n = _nodeOf(r.nodeId);
      if (n == null) return;
      final key = IpUtils.stripBrackets(n.ip);
      if (_geo[key] != null) return;
      _geo[key] = await GeoService.lookup(n.ip);
    }));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("已复制：$text"), duration: const Duration(seconds: 1)));
  }

  String _fmtDate(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return "${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}";
  }

  String _fmtQcc(int raw) {
    final v = QccAssetService().getHumanAmountNum('QCC', raw);
    var s = v.toStringAsFixed(4);
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_data != null) _buildSummary(_data!),
          if (_error != null) _buildError(),
          if (_data == null && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_data != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text("积分排名 · ${_data!.ranking.length} 个质押节点",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
            ),
            ..._data!.ranking.map(_buildRankCard),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10)),
      child: Text("查询失败：$_error\n下拉重试",
          style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
    );
  }

  Widget _buildSummary(QccProducerCluster d) {
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color ?? Colors.black87)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              stat("高度", "${d.height}"),
              stat("轮次", "${d.term}"),
              stat("生产组", "${d.producers.length}/${d.clusterSize}",
                  color: Colors.indigo),
              stat("质押节点", "${d.members}"),
            ],
          ),
          if (d.ranking.isNotEmpty) ...[
            const Divider(height: 22, thickness: 0.5),
            _buildHeatBoard(d),
          ],
          if (QccMinerRewardService.byNode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                "全网已发放生产者收益 ${QccMinerRewardService.fmt(QccMinerRewardService.byNode.values.fold<int>(0, (a, s) => a + s.total))} QCC"
                " · ${QccMinerRewardService.byNode.length} 个生产者",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade700),
              ),
            ),
            if (QccMinerRewardService.looksStale(QccMinerRewardService.indexMaxHeight))
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  "⚠ 收益数据来源节点最高高度 ${QccMinerRewardService.indexMaxHeight} 高于网络高度，"
                  "可能残留重置前的旧链记录",
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            "数据来自 ${d.source.isEmpty ? '—' : d.source}"
            "${_updatedAt == null ? '' : ' · ${_fmtDate(_updatedAt!.millisecondsSinceEpoch).substring(11)} 更新'}",
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  /// 积分榜：集群参数的核心，放在汇总卡片里一眼可见。
  /// 每行：名次 · nodeId · 出块中/我的 · 积分条（按最高分归一，负分红色）· 积分
  Widget _buildHeatBoard(QccProducerCluster d) {
    final net = QccNodeManager.instance.network;
    final maxHeat = d.ranking
        .map((r) => r.heat)
        .fold<int>(1, (a, b) => b > a ? b : a);
    final total = d.ranking
        .where((r) => r.isProducer)
        .fold<int>(0, (a, r) => a + (r.heat > 0 ? r.heat : 0));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("积分榜",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800)),
              const Spacer(),
              Text("生产组合计 $total",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          ...d.ranking.map((r) {
            final isNow = net.nowProducerId == r.nodeId;
            final isMine = _myAddrs.contains(r.nodeId);
            final ratio = r.heat <= 0 ? 0.0 : (r.heat / maxHeat).clamp(0.0, 1.0);
            final barColor = r.heat < 0
                ? Colors.red.shade400
                : (r.isProducer ? Colors.indigo : Colors.blueGrey);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text("#${r.rank}",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade700)),
                  ),
                  SizedBox(
                    width: 104,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(shortNodeId(r.nodeId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: isMine
                                      ? FontWeight.w800
                                      : FontWeight.w500)),
                        ),
                        if (isNow)
                          Icon(Icons.bolt,
                              size: 13, color: Colors.amber.shade800),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: r.heat < 0 ? 1.0 : ratio,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        color: r.heat < 0
                            ? Colors.red.shade100
                            : barColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text("${r.heat}",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: r.heat < 0 ? Colors.red.shade600 : barColor)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 2),
          Text(
            "积分决定生产排序：出块加分，轮到却由他人出块（漏块）扣分；⚡ 当前出块",
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color c, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
            color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null)
            Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(icon, size: 11, color: c)),
          Text(text,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: c)),
        ]),
      );

  Widget _statusChip(QccProducerRank r) {
    if (r.isProducer) return _chip("生产组", Colors.indigo);
    if (r.isCandidate) return _chip("候选", Colors.blueGrey);
    return _chip(r.status.isEmpty ? "未知" : r.status, Colors.grey);
  }

  Widget _buildRankCard(QccProducerRank r) {
    final net = QccNodeManager.instance.network;
    final isNow = net.nowProducerId == r.nodeId;
    final isMine = _myAddrs.contains(r.nodeId);
    final node = _nodeOf(r.nodeId);
    final geo = node == null ? null : _geo[IpUtils.stripBrackets(node.ip)];
    final heatColor = r.heat < 0
        ? Colors.red.shade600
        : (r.isProducer ? Colors.indigo : Colors.black87);
    final progress =
        r.milestone <= 0 ? 0.0 : (r.cycleProduced / r.milestone).clamp(0.0, 1.0);

    // 节点位置：节点列表里有就显示 IP/地区和本机连通情况，没有就说明未发现
    String where;
    if (node == null) {
      where = "节点列表中未发现";
    } else {
      final reach = node.isDirect
          ? "${node.latencyMs}ms"
          : (node.isOnline
              ? QccNodeManager.instance.unreachableReason(node)
              : "离线");
      where =
          "${geo?.displayName ?? IpUtils.displayIp(node.ip)} · $reach";
    }

    final reward = QccMinerRewardService.byNode[r.nodeId];

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNow ? Colors.amber.shade600 : Colors.grey.shade200,
          width: isNow ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：名次 · 状态 · nodeId · 积分
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text("#${r.rank}",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700)),
              ),
              _statusChip(r),
              if (isNow) _chip("出块中", Colors.amber.shade800, icon: Icons.bolt),
              if (isMine) _chip("我的", Colors.teal),
              Expanded(
                child: GestureDetector(
                  onLongPress: () => _copy(r.nodeId),
                  child: Text(shortNodeId(r.nodeId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("${r.heat}",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: heatColor)),
                  Text("积分",
                      style:
                          TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
          if (heatBreakdown(r) != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text("积分 = ${heatBreakdown(r)}",
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: heatColor.withOpacity(0.85))),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text("${geo?.flag ?? ''} $where".trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
          const SizedBox(height: 8),
          // 本周期里程碑进度
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    color: r.isProducer ? Colors.indigo : Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "本周期 ${r.cycleProduced}/${r.milestone} · 距里程碑 ${r.toMilestone}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    children: [
                      TextSpan(text: "累计出块 ${r.totalProduced} · "),
                      TextSpan(
                        text: "漏块 ${r.missed}",
                        style: r.missed > 0
                            ? TextStyle(
                                color: Colors.red.shade600,
                                fontWeight: FontWeight.w600)
                            : null,
                      ),
                      TextSpan(text: " · 购买积分 ${r.cyclePurchased}"),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "质押 ${_fmtQcc(r.pledge)} QCC · 注册 ${_fmtDate(r.regTime)}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  "解锁 ${_fmtDate(r.unlockAt)}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                // 生产者收益（/v1/miner）：累计 gas 分成 + 里程碑奖励，点卡片看明细
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.payments_outlined,
                        size: 13, color: Colors.indigo.shade400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        reward == null
                            ? "累计收益 —（暂无出块收益记录）"
                            : "累计收益 ${QccMinerRewardService.fmt(reward.total)} QCC"
                                " · ${reward.containers} 个容器",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: reward == null
                                ? Colors.grey.shade500
                                : Colors.indigo.shade700),
                      ),
                    ),
                    Text("明细",
                        style: TextStyle(fontSize: 11, color: Colors.indigo.shade400)),
                    Icon(Icons.chevron_right, size: 16, color: Colors.indigo.shade300),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QccMinerRewardPage(nodeId: r.nodeId)),
      ),
      child: card,
    );
  }
}
