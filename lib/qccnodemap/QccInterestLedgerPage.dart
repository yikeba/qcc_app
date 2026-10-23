import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/qccnodemap/QccNodeManager.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// 周期聚合信息（/cycle/{id}，或明细记录内嵌的 cycle 字段）
class QccInterestCycle {
  final String cycleId;
  final int containerTime;
  final int poolBalanceBefore;
  final int totalToDistribute;
  final int totalDistributed;
  final int totalStakedBasis;
  final int beneficiaryCount;
  final String prevHash;
  final String cycleHash;

  QccInterestCycle.fromJson(Map<String, dynamic> j, {String? cycleId, int? time})
      : cycleId = (j['cycleId'] ?? cycleId ?? '').toString(),
        containerTime = j.containsKey('containerTime') ? _i(j['containerTime']) : (time ?? 0),
        poolBalanceBefore = _i(j['poolBalanceBefore']),
        totalToDistribute = _i(j['totalToDistribute']),
        totalDistributed = _i(j['totalDistributed']),
        totalStakedBasis = _i(j['totalStakedBasis']),
        beneficiaryCount = _i(j['beneficiaryCount']),
        prevHash = (j['prevHash'] ?? '').toString(),
        cycleHash = (j['cycleHash'] ?? '').toString();
}

/// 单条利息明细（某地址在某周期实得的利息）
class QccInterestRecord {
  final String cycleId;
  final int containerTime;
  final int stakedBasis; // 计息本金
  final int amount; // 本期实得利息
  QccInterestCycle? cycle; // 新版服务端内嵌；旧版为空，点开时再查

  QccInterestRecord.fromJson(Map<String, dynamic> j)
      : cycleId = (j['cycleId'] ?? '').toString(),
        containerTime = _i(j['containerTime']),
        stakedBasis = _i(j['stakedBasis']),
        amount = _i(j['amount']),
        cycle = j['cycle'] is Map
            ? QccInterestCycle.fromJson(Map<String, dynamic>.from(j['cycle']),
            cycleId: (j['cycleId'] ?? '').toString(), time: _i(j['containerTime']))
            : null;

  /// 本期本金占比（0~1）；没有周期信息时为 null
  double? get shareRatio {
    final c = cycle;
    if (c == null || c.totalStakedBasis <= 0) return null;
    return stakedBasis / c.totalStakedBasis;
  }
}

/// 统一解包。兼容两种格式：
/// - 新：{"ok":true,"data":{...}}
/// - 旧：{"ok":true,"kind":"interest","data":"{\"ok\":true,\"data\":{...}}"}
Map<String, dynamic> qccInterestUnwrap(String body) {
  dynamic j = jsonDecode(body);
  for (var depth = 0; depth < 3; depth++) {
    if (j is! Map) break;
    final d = j['data'];
    if (d is String) {
      try {
        j = {...j, 'data': jsonDecode(d)};
        continue;
      } catch (_) {
        break;
      }
    }
    if (d is Map && d.containsKey('ok')) {
      j = d;
      continue;
    }
    break;
  }
  if (j is Map && j['ok'] == true && j['data'] is Map) {
    return Map<String, dynamic>.from(j['data']);
  }
  final err = j is Map ? (j['error'] ?? j['data']) : body;
  throw Exception(err?.toString() ?? '未知错误');
}

/// 一页利息明细
class QccInterestHistory {
  final int totalReceived;
  final List<QccInterestRecord> records;
  final bool hasMore;
  QccInterestHistory(this.totalReceived, this.records, this.hasMore);

  bool get isEmpty => totalReceived <= 0 && records.isEmpty;
}

/// 供其它页面（如地址详情）拉一页利息明细；不固定节点，走 QccNodeManager 故障转移
class QccInterestService {
  static Future<QccInterestHistory> fetchHistory(String address,
      {int offset = 0, int limit = 20}) async {
    await QccNodeManager.instance.init();
    final r = await QccNodeManager.instance.get(
        "/v1/InterestLedgerApi/$address/history?offset=$offset&limit=$limit");
    if (r == null) throw Exception("所有节点均不可达");
    final data = qccInterestUnwrap(r.body);
    final list = (data['records'] is List ? data['records'] as List : const [])
        .whereType<Map>()
        .map((e) => QccInterestRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final hasMore = data.containsKey('hasMore')
        ? data['hasMore'] == true
        : list.length >= limit;
    return QccInterestHistory(_i(data['totalReceived']), list, hasMore);
  }
}

/// 信托类质押利息收益明细。
/// 数据：GET /v1/InterestLedgerApi/{address}/history?offset=&limit=
///
/// 注意：利息罗盘是执行层本地文件、不参与共识，从快照接入的节点可能没有
/// 早期历史，不同节点给出的明细可能不同。所以：
/// - 同一次浏览固定在一个节点上翻页（不同节点之间 offset 不一定对齐）；
/// - 顶部显示数据来源节点和罗盘链头 hash，用于跨节点比对。
class QccInterestLedgerPage extends StatefulWidget {
  final String address;
  final String assetId; // 利息池按 QCC 分配
  const QccInterestLedgerPage({super.key, required this.address, this.assetId = 'QCC'});

  @override
  State<QccInterestLedgerPage> createState() => _QccInterestLedgerPageState();
}

class _QccInterestLedgerPageState extends State<QccInterestLedgerPage> {
  static const int _pageSize = 20;

  final List<QccInterestRecord> _records = [];
  int _totalReceived = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;
  String? _base; // 本次浏览固定使用的节点
  String? _headCycleId;
  String? _headHash;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Map<String, dynamic> _unwrap(String body) => qccInterestUnwrap(body);

  /// 优先请求固定节点；失败时走 QccNodeManager 故障转移，并把成功的节点固定下来
  Future<Map<String, dynamic>> _fetch(String path) async {
    await QccNodeManager.instance.init();
    if (_base != null) {
      try {
        final r = await http
            .get(Uri.parse("$_base$path"))
            .timeout(const Duration(seconds: 5));
        if (r.statusCode == 200) return _unwrap(r.body);
      } catch (e) {
        LogObj.log("qcc利息 固定节点 $_base 请求失败，切换: $e");
      }
    }
    final r = await QccNodeManager.instance.get(path);
    if (r == null) throw Exception("所有节点均不可达");
    final origin = r.request?.url.origin;
    if (origin != null && origin != _base) {
      // 换了节点：之前的分页 offset 未必对得上，由调用方决定是否从头加载
      _base = origin;
    }
    return _unwrap(r.body);
  }

  Future<void> _reload() async {
    setState(() {
      _records.clear();
      _hasMore = false;
      _error = null;
    });
    await _loadPage();
    _loadHead();
  }

  Future<void> _loadPage() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final baseBefore = _base;
      final data = await _fetch(
          "/v1/InterestLedgerApi/${widget.address}/history?offset=${_records.length}&limit=$_pageSize");
      if (baseBefore != null && baseBefore != _base && _records.isNotEmpty) {
        // 翻页途中节点切换：不同节点罗盘可能不一致，从新节点重新加载第一页
        _records.clear();
        final fresh = await _fetch(
            "/v1/InterestLedgerApi/${widget.address}/history?offset=0&limit=$_pageSize");
        _apply(fresh);
      } else {
        _apply(data);
      }
    } catch (e) {
      LogObj.log("qcc利息 明细查询失败: $e");
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(Map<String, dynamic> data) {
    final list = (data['records'] is List ? data['records'] as List : const [])
        .whereType<Map>()
        .map((e) => QccInterestRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (!mounted) return;
    setState(() {
      _totalReceived = _i(data['totalReceived']);
      _records.addAll(list);
      // 旧版服务端没有 hasMore：按"本页取满"推断
      _hasMore = data.containsKey('hasMore')
          ? data['hasMore'] == true
          : list.length >= _pageSize;
    });
  }

  Future<void> _loadHead() async {
    try {
      final h = await _fetch("/v1/InterestLedgerApi/head");
      if (!mounted) return;
      setState(() {
        _headCycleId = h['lastCycleId']?.toString();
        _headHash = h['lastCycleHash']?.toString();
      });
    } catch (_) {
      // 旧版服务端没有 head 接口，不影响明细
    }
  }

  Future<QccInterestCycle?> _ensureCycle(QccInterestRecord r) async {
    if (r.cycle != null) return r.cycle;
    try {
      final d = await _fetch("/v1/InterestLedgerApi/cycle/${Uri.encodeComponent(r.cycleId)}");
      r.cycle = QccInterestCycle.fromJson(d, cycleId: r.cycleId, time: r.containerTime);
      if (mounted) setState(() {});
      return r.cycle;
    } catch (e) {
      LogObj.log("qcc利息 周期 ${r.cycleId} 查询失败: $e");
      return null;
    }
  }

  // ───────────────────────── 格式化 ─────────────────────────

  String _amt(int raw) {
    final v = QccAssetService().getHumanAmountNum(widget.assetId, raw);
    var s = v.toStringAsFixed(6);
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  String _date(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return "${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}";
  }

  String _short(String s, [int head = 8, int tail = 6]) =>
      s.length > head + tail + 1 ? "${s.substring(0, head)}…${s.substring(s.length - tail)}" : s;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已复制：${_short(text, 12, 8)}"), duration: const Duration(seconds: 1)));
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("利息收益明细"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _buildSummary(),
            const SizedBox(height: 14),
            if (_error != null) _buildError(),
            if (_records.isEmpty && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text("暂无利息分配记录",
                      style: TextStyle(color: Colors.grey.shade600)),
                ),
              ),
            ..._records.map(_buildRecord),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton(
                  onPressed: _loadPage,
                  child: const Text("加载更多"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.teal.shade700, Colors.teal.shade400]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("累计利息收益",
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_amt(_totalReceived),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Text(widget.assetId,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onLongPress: () => _copy(widget.address),
            child: Text(widget.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 4),
          Text(
            "已加载 ${_records.length} 期${_hasMore ? '，还有更多' : ''}"
                " · 来源 ${_base ?? '—'}",
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          if (_headHash != null)
            GestureDetector(
              onLongPress: () => _copy(_headHash!),
              child: Text(
                "罗盘链头 ${_headCycleId ?? '—'} · ${_short(_headHash!)}",
                style: const TextStyle(
                    color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
      child: Text("查询失败：$_error",
          style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
    );
  }

  Widget _buildRecord(QccInterestRecord r) {
    final ratio = r.shareRatio;
    return InkWell(
      onTap: () => _showCycleSheet(r),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(r.cycleId,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(_date(r.containerTime),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "计息本金 ${_amt(r.stakedBasis)}"
                        "${ratio == null ? '' : ' · 占本期 ${(ratio * 100).toStringAsFixed(2)}%'}",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  if (r.cycle != null)
                    Text(
                      "本期共分配 ${_amt(r.cycle!.totalDistributed)} · ${r.cycle!.beneficiaryCount} 个地址",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
            Text("+${_amt(r.amount)}",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.teal.shade700)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Future<void> _showCycleSheet(QccInterestRecord r) async {
    final c = await _ensureCycle(r);
    if (!mounted) return;
    Widget row(String k, String v, {String? copy}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 96,
              child: Text(k, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(
            child: GestureDetector(
              onLongPress: copy == null ? null : () => _copy(copy),
              child: Text(v,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: copy == null ? null : 'monospace')),
            ),
          ),
        ],
      ),
    );

    final ratio = r.shareRatio;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("周期 ${r.cycleId}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              row("本期实得", "+${_amt(r.amount)} ${widget.assetId}"),
              row("计息本金", _amt(r.stakedBasis)),
              if (ratio != null) row("本金占比", "${(ratio * 100).toStringAsFixed(4)}%"),
              row("分配时间", _date(r.containerTime)),
              const Divider(height: 20),
              if (c == null)
                Text("未能获取周期聚合信息（该节点罗盘可能缺少此周期）",
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800))
              else ...[
                row("利息池余额", _amt(c.poolBalanceBefore)),
                row("计划分配", "${_amt(c.totalToDistribute)}（余额 / 12）"),
                row("实际分配", _amt(c.totalDistributed)),
                row("计息本金总和", _amt(c.totalStakedBasis)),
                row("受益地址数", "${c.beneficiaryCount}"),
                row("周期 hash", _short(c.cycleHash, 12, 8), copy: c.cycleHash),
                row("上一周期 hash", _short(c.prevHash, 12, 8), copy: c.prevHash),
              ],
              const SizedBox(height: 6),
              Text("hash 长按复制；周期 hash 串成链，可跨节点比对罗盘是否被篡改",
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}