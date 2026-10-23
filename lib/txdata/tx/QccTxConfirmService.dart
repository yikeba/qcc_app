import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/qccnodemap/QccNodeManager.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

/// 交易上链确认的三种结果：
/// - confirmed：某个节点 /v1/hash 返回 status=SUCCESS
/// - failed   ：某个节点返回了明确的失败状态（见 _failStatuses）
/// - pending  ：超时仍未查到——交易已被节点接收，只是还没确认，不代表失败
enum QccTxConfirmState { confirmed, failed, pending }

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return <String, dynamic>{};
}

int? _asIntOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// /v1/hash/{txHash} 的解析结果。
/// 返回结构（data、data.tx 都是被再次 JSON 编码过的字符串）：
/// {"ok":true,"kind":"TX","status":"SUCCESS",
///  "data":"{\"tx\":\"{...交易...}\",\"containerId\":...,\"tailHash\":...,
///           \"confirmTimestamp\":...,\"height\":646,\"confirmDateUTC\":...}",
///  "timestamp":...}
class QccTxConfirmation {
  final QccTxConfirmState state;
  final String txHash;
  final String? rawStatus; // 节点原始 status，例如 "SUCCESS"
  final String? msg;
  final String? source; // 哪个节点给出的结果（baseUrl）
  final Map<String, dynamic> tx; // 链上交易本体；pending 时为空
  final int? height;
  final String? containerId;
  final String? tailHash;
  final int? confirmTimestamp;
  final String? confirmDateUTC;

  const QccTxConfirmation({
    required this.state,
    required this.txHash,
    this.rawStatus,
    this.msg,
    this.source,
    this.tx = const {},
    this.height,
    this.containerId,
    this.tailHash,
    this.confirmTimestamp,
    this.confirmDateUTC,
  });

  factory QccTxConfirmation.pending(String txHash) =>
      QccTxConfirmation(state: QccTxConfirmState.pending, txHash: txHash);

  bool get isConfirmed => state == QccTxConfirmState.confirmed;
  bool get isFailed => state == QccTxConfirmState.failed;
  bool get isPending => state == QccTxConfirmState.pending;

  /// 假设：除 SUCCESS 外，下面这些 status 视为终态失败；其它任何情况
  /// （ok!=true、404、PENDING、查不到）都视为"还没上链"，继续轮询。
  /// 服务端实际的失败 status 取值需要你核对。
  static const _failStatuses = {'FAIL', 'FAILED', 'ERROR', 'REJECTED', 'INVALID'};

  /// 解析单个节点的 /v1/hash 响应。返回 null 表示"这个节点还没查到/不确定"。
  static QccTxConfirmation? parse(String body, String txHash, String source) {
    final root = _asMap(body);
    if (root['ok'] != true) return null;

    final status = (root['status'] is String)
        ? (root['status'] as String).toUpperCase()
        : null;
    final QccTxConfirmState state;
    if (status == 'SUCCESS') {
      state = QccTxConfirmState.confirmed;
    } else if (status != null && _failStatuses.contains(status)) {
      state = QccTxConfirmState.failed;
    } else {
      return null;
    }

    final data = _asMap(root['data']);
    final tx = _asMap(data['tx']);

    // 防串：返回里带的交易 hash 和要查的不一致，就当没查到
    final inTx = tx['txHash'] ?? tx['id'];
    if (inTx is String && inTx.isNotEmpty && inTx != txHash) {
      LogObj.log("qcc上链确认 $source 返回的交易 hash 不匹配: $inTx != $txHash，忽略");
      return null;
    }

    return QccTxConfirmation(
      state: state,
      txHash: txHash,
      rawStatus: status,
      msg: (root['msg'] ?? data['msg']) as String?,
      source: source,
      tx: tx,
      height: _asIntOrNull(data['height']),
      containerId: data['containerId'] as String?,
      tailHash: data['tailHash'] as String?,
      confirmTimestamp: _asIntOrNull(data['confirmTimestamp']),
      confirmDateUTC: data['confirmDateUTC'] as String?,
    );
  }
}

/// 统一的"等待交易上链确认"。
///
/// 新机制下 /v1/txm 等交易接口只返回"已接收"（交易进了节点缓存），真正
/// 上链要另外查 /v1/hash/{txHash}。查询不绑定提交节点：每轮取当前高度
/// 最高的几个节点并发查，任何一个返回 SUCCESS 即确认。
///
/// 所有交易接口（txm/rule/data/mtxrule/mutxbaseData）提交后都走这里。
class QccTxConfirmService {
  static const Duration defaultTimeout = Duration(seconds: 180);
  static const Duration pollInterval = Duration(seconds: 1);
  static const Duration _queryTimeout = Duration(seconds: 3);
  static const int _nodesPerRound = 3;

  /// [extraBaseUrls]：额外加入每轮查询的节点（比如提交节点），可选。
  /// [onAttempt]：每轮查询前回调一次轮次，用于 UI 显示"第 N 次确认"之类。
  ///
  /// 超时返回 pending 而不是抛异常——交易已经被接收，超时只说明还没确认，
  /// 调用方应该展示"已提交、等待确认"，而不是"失败"。
  static Future<QccTxConfirmation> waitForConfirmation(
      String txHash, {
        Duration timeout = defaultTimeout,
        List<String> extraBaseUrls = const [],
        void Function(int attempt)? onAttempt,
      }) async {
    final sw = Stopwatch()..start();
    var attempt = 0;
    while (sw.elapsed < timeout) {
      attempt++;
      onAttempt?.call(attempt);
      final bases = <String>{
        ...QccNodeManager.instance.highestHeightBaseUrls(limit: _nodesPerRound),
        ...extraBaseUrls,
      }.toList();

      final r = await _queryRound(bases, txHash);
      if (r != null) {
        LogObj.log("qcc上链确认 $txHash → ${r.rawStatus} 高度 ${r.height} "
            "来源 ${r.source}，第 $attempt 轮，耗时 ${sw.elapsedMilliseconds}ms");
        return r;
      }
      await Future.delayed(pollInterval);
    }
    LogObj.log("qcc上链确认 $txHash 超时(${timeout.inSeconds}s)，共 $attempt 轮，仍未查到");
    return QccTxConfirmation.pending(txHash);
  }

  /// 单次查询（不轮询），供结果页"继续查询"或其它场景直接用。
  static Future<QccTxConfirmation> queryOnce(String txHash,
      {List<String> extraBaseUrls = const []}) async {
    final bases = <String>{
      ...QccNodeManager.instance.highestHeightBaseUrls(limit: _nodesPerRound),
      ...extraBaseUrls,
    }.toList();
    return await _queryRound(bases, txHash) ?? QccTxConfirmation.pending(txHash);
  }

  /// 一轮并发查询：任一节点 SUCCESS 立即返回；没有 SUCCESS 但有节点给出
  /// 明确失败，等本轮全部返回后再报失败（避免某个节点数据异常抢先报错）；
  /// 都没查到返回 null。
  static Future<QccTxConfirmation?> _queryRound(
      List<String> bases, String txHash) {
    if (bases.isEmpty) return Future.value(null);
    final completer = Completer<QccTxConfirmation?>();
    var remaining = bases.length;
    QccTxConfirmation? failure;

    for (final base in bases) {
      _queryOne(base, txHash).then((r) {
        if (r == null || completer.isCompleted) return;
        if (r.isConfirmed) {
          completer.complete(r);
        } else if (r.isFailed) {
          failure ??= r;
        }
      }).whenComplete(() {
        remaining--;
        if (remaining == 0 && !completer.isCompleted) completer.complete(failure);
      });
    }
    return completer.future;
  }

  static Future<QccTxConfirmation?> _queryOne(String base, String txHash) async {
    try {
      final resp = await http
          .get(Uri.parse("$base/v1/hash/$txHash"))
          .timeout(_queryTimeout);
      if (resp.statusCode != 200) return null;
      return QccTxConfirmation.parse(resp.body, txHash, base);
    } catch (_) {
      return null;
    }
  }
}