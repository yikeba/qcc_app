import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import 'QccNodeManager.dart';
import 'QccNodeMapWidget.dart' show shortNodeId;

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// GET /v1/miner 里的一行：某个生产者的累计收益
class QccMinerRewardSummary {
  final String nodeId;
  final int containers;
  final int total; // gasShare + milestone，最小单位
  final int lastHeight;
  final int lastTime;

  QccMinerRewardSummary.fromJson(Map<String, dynamic> j)
      : nodeId = (j['nodeId'] ?? '').toString(),
        containers = _i(j['containers']),
        total = _i(j['total']),
        lastHeight = _i(j['lastHeight']),
        lastTime = _i(j['lastTime']);
}

/// GET /v1/miner/{nodeId} 的 recent 条目：一个容器的生产者收益
class QccMinerRewardRecord {
  final int height;
  final int time;
  final int gasShare;
  final int milestone;
  final int total;
  final int txCount;
  final String containerHash;

  QccMinerRewardRecord.fromJson(Map<String, dynamic> j)
      : height = _i(j['height']),
        time = _i(j['time']),
        gasShare = _i(j['gasShare']),
        milestone = _i(j['milestone']),
        total = _i(j['total']),
        txCount = _i(j['txCount']),
        containerHash = (j['containerHash'] ?? '').toString();
}

/// GET /v1/miner/{nodeId}?limit=
class QccMinerRewardDetail {
  final String nodeId;
  final int containers;
  final int txCount;
  final int gasShare;
  final int milestone;
  final int total;
  final int firstHeight;
  final int lastHeight;
  final int indexMaxHeight;
  final List<QccMinerRewardRecord> recent;
  final String source;

  QccMinerRewardDetail.fromJson(Map<String, dynamic> j, this.source)
      : nodeId = (j['nodeId'] ?? '').toString(),
        containers = _i(j['containers']),
        txCount = _i(j['txCount']),
        gasShare = _i(j['gasShare']),
        milestone = _i(j['milestone']),
        total = _i(j['total']),
        firstHeight = _i(j['firstHeight']),
        lastHeight = _i(j['lastHeight']),
        indexMaxHeight = _i(j['indexMaxHeight']),
        recent = ((j['recent'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => QccMinerRewardRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList();
}

/// 生产者收益查询。
/// 注意：收益明细是 index 层本地文件（minerreward/rewards.dat），由本机执行层
/// 推送生成，不参与共识。从快照接入的节点没有接入前的明细；链重置时如果没清
/// 这个目录，旧链高于新链高度的记录会一直留在累计里。客户端用
/// indexMaxHeight 与网络高度比对，发现明显偏高就提示"收益数据可能含旧链"。
class QccMinerRewardService {
  static final Map<String, QccMinerRewardSummary> byNode = {};
  static int indexMaxHeight = -1;
  static String source = '';

  static Map<String, dynamic> _decode(String body) {
    final j = jsonDecode(body);
    if (j is Map && j['status'] == 'ok') return Map<String, dynamic>.from(j);
    throw Exception("返回异常: $body");
  }

  static Future<void> fetchSummary() async {
    await QccNodeManager.instance.init();
    final r = await QccNodeManager.instance.get('/v1/miner');
    if (r == null) throw Exception("所有节点均不可达");
    final j = _decode(r.body);
    final list = ((j['producers'] ?? const []) as List)
        .whereType<Map>()
        .map((e) => QccMinerRewardSummary.fromJson(Map<String, dynamic>.from(e)));
    byNode
      ..clear()
      ..addEntries(list.map((s) => MapEntry(s.nodeId, s)));
    indexMaxHeight = _i(j['indexMaxHeight']);
    source = r.request?.url.origin ?? '';
  }

  static Future<QccMinerRewardDetail> fetchDetail(String nodeId, int limit) async {
    await QccNodeManager.instance.init();
    final r = await QccNodeManager.instance
        .get('/v1/miner/${Uri.encodeComponent(nodeId)}?limit=$limit');
    if (r == null) throw Exception("所有节点均不可达");
    return QccMinerRewardDetail.fromJson(_decode(r.body), r.request?.url.origin ?? '');
  }

  /// 收益数据的最高高度明显高于网络高度：该节点的收益库很可能残留旧链记录
  static bool looksStale(int indexMax) {
    final tip = QccNodeManager.instance.tipHeight;
    return tip > 0 && indexMax > tip + 10;
  }

  static String fmt(int raw, {int digits = 4}) {
    final v = QccAssetService().getHumanAmountNum('QCC', raw);
    var s = v.toStringAsFixed(digits);
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }
}

/// 单个生产者的收益明细页
class QccMinerRewardPage extends StatefulWidget {
  final String nodeId;
  const QccMinerRewardPage({super.key, required this.nodeId});

  @override
  State<QccMinerRewardPage> createState() => _QccMinerRewardPageState();
}

class _QccMinerRewardPageState extends State<QccMinerRewardPage> {
  // 服务端没有 offset，只保留每个生产者最近 1000 条：加载更多 = 加大 limit 重拉
  static const int _step = 50, _max = 1000;
  int _limit = _step;
  QccMinerRewardDetail? _d;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await QccMinerRewardService.fetchDetail(widget.nodeId, _limit);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      LogObj.log("qcc生产者收益 查询失败: $e");
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return "${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}";
  }

  void _copy(String s) {
    Clipboard.setData(ClipboardData(text: s));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已复制：$s"), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    // 本次拿到的条数达到 limit，且 limit 还没到上限、累计容器数比已加载的多 → 还能加载更多
    final canMore = d != null &&
        d.recent.length >= _limit &&
        _limit < _max &&
        d.containers > d.recent.length;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("生产者收益"),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            if (d != null) _buildHeader(d),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text("查询失败：$_error",
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
            if (d != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text("最近出块收益（新的在前，服务端最多保留 $_max 条）",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
              ),
              if (d.recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text("暂无收益记录",
                          style: TextStyle(color: Colors.grey.shade600))),
                ),
              ...d.recent.map(_buildRow),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (canMore)
              OutlinedButton(
                onPressed: () {
                  _limit = (_limit + _step).clamp(_step, _max);
                  _load();
                },
                child: const Text("加载更多"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(QccMinerRewardDetail d) {
    final stale = QccMinerRewardService.looksStale(d.indexMaxHeight);
    Widget kv(String k, String v) => Expanded(
          child: Column(children: [
            Text(v,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(k, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade700, Colors.indigo.shade400]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _copy(d.nodeId),
            child: Text(shortNodeId(d.nodeId),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(QccMinerRewardService.fmt(d.total, digits: 6),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              const Text("QCC 累计收益",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            kv("Gas 分成", QccMinerRewardService.fmt(d.gasShare)),
            kv("里程碑奖励", QccMinerRewardService.fmt(d.milestone)),
            kv("出块数", "${d.containers}"),
            kv("打包交易", "${d.txCount}"),
          ]),
          const SizedBox(height: 10),
          Text(
            "高度 ${d.firstHeight} → ${d.lastHeight} · 来源 ${d.source.isEmpty ? '—' : d.source}",
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "⚠ 该节点收益库最高高度 ${d.indexMaxHeight} 高于网络高度 "
                "${QccNodeManager.instance.tipHeight}，可能残留重置前的旧链记录",
                style: TextStyle(color: Colors.amber.shade200, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(QccMinerRewardRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text("#${r.height}",
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(_date(r.time),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Text("${r.txCount} 笔",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
                const SizedBox(height: 3),
                Text(
                  "Gas ${QccMinerRewardService.fmt(r.gasShare, digits: 6)}"
                  "${r.milestone > 0 ? ' · 里程碑 ${QccMinerRewardService.fmt(r.milestone)}' : ''}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                GestureDetector(
                  onLongPress: () => _copy(r.containerHash),
                  child: Text(
                    r.containerHash.length > 20
                        ? "${r.containerHash.substring(0, 10)}…${r.containerHash.substring(r.containerHash.length - 8)}"
                        : r.containerHash,
                    style: TextStyle(
                        fontSize: 10, fontFamily: 'monospace', color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
          Text("+${QccMinerRewardService.fmt(r.total, digits: 6)}",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: r.milestone > 0 ? Colors.amber.shade800 : Colors.indigo)),
        ],
      ),
    );
  }
}
