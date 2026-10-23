import 'dart:convert';
import 'package:qcc_flutter/utile/JsonUtil.dart';

import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/txdata/tx/QccTxConfirmService.dart';
import '../../views/myasset/QccAssetService.dart';

class QccTransaction {
  final String status;
  final String? msg;
  final String txHash;
  final String assetId;
  final String from;
  final String to;
  final double amount; // 人类可读金额（已按资产精度换算）
  final String type; // 对应 txType (如 pay, win, open 等)
  final int timestamp;

  // ---- 上链确认信息（来自 /v1/hash）；不是走确认流程构建的对象时都为 null ----
  final QccTxConfirmState? confirmState;
  final int? height;
  final String? containerId;
  final String? tailHash;
  final int? confirmTimestamp;
  final String? confirmDateUTC;

  QccTransaction({
    required this.status,
    this.msg,
    required this.txHash,
    required this.assetId,
    required this.from,
    required this.to,
    required this.amount,
    required this.type,
    required this.timestamp,
    this.confirmState,
    this.height,
    this.containerId,
    this.tailHash,
    this.confirmTimestamp,
    this.confirmDateUTC,
  });

  bool get isConfirmed => confirmState == QccTxConfirmState.confirmed;
  bool get isFailed => confirmState == QccTxConfirmState.failed;
  bool get isPending => confirmState == QccTxConfirmState.pending;

  /// 旧入口：解析交易接口直接返回的 JSON（外层 + data 字符串）。
  /// 新机制下 /v1/txm 只返回 {"status":"accepted","txHash":...}，里面没有
  /// 交易本体，用这个解析出来的金额必然是 0——提交后的展示请改用
  /// fromConfirmation()。保留这个入口是给其它仍然直接返回交易本体的场景用。
  factory QccTransaction.fromJson(String jsonstr) {
    Map json = JsonUtil.strtoMap(jsonstr);
    final status = json['status'] as String? ?? '';
    final msg = json['msg'] as String?;

    Map detail = {};
    try {
      if (json['data'] != null && json['data'] is String) {
        detail = jsonDecode(json['data']);
      } else {
        detail = json;
      }
    } catch (e) {
      print("QccTransaction Data Decode Error: $e");
    }

    return _fromDetail(
      detail,
      status: status,
      msg: msg,
      txHash: json['txHash'] as String?,
      timestamp: json['timestamp'] as int?,
    );
  }

  /// 新入口：由上链确认结果构建。
  /// - confirmed/failed 且节点返回了交易本体：用链上数据（金额、双方地址以链上为准）
  /// - pending（超时未查到）或返回里没有交易本体：用本地提交的交易 [localTx]
  ///   兜底展示（QccTransactionData.toJson() 的结果），金额照样正确
  factory QccTransaction.fromConfirmation(QccTxConfirmation c,
      {Map<String, dynamic>? localTx}) {
    final detail = c.tx.isNotEmpty ? c.tx : (localTx ?? const <String, dynamic>{});
    return _fromDetail(
      detail,
      status: c.rawStatus ?? c.state.name,
      msg: c.msg,
      txHash: c.txHash,
      confirmation: c,
    );
  }

  /// 已有对象 + 新的确认结果（结果页"继续查询"用）：链上返回了交易本体就
  /// 重新解析，否则保留原有金额/地址，只更新确认信息。
  QccTransaction withConfirmation(QccTxConfirmation c) {
    if (c.tx.isNotEmpty) return QccTransaction.fromConfirmation(c);
    return QccTransaction(
      status: c.rawStatus ?? c.state.name,
      msg: c.msg ?? msg,
      txHash: txHash,
      assetId: assetId,
      from: from,
      to: to,
      amount: amount,
      type: type,
      timestamp: timestamp,
      confirmState: c.state,
      height: c.height,
      containerId: c.containerId,
      tailHash: c.tailHash,
      confirmTimestamp: c.confirmTimestamp,
      confirmDateUTC: c.confirmDateUTC,
    );
  }

  /// 统一的交易本体解析：优先 QccTransactionData.fromJson（规范解析器），
  /// 失败则手动取值兜底；金额全程 原始整数 -> 人类可读 double，不经过 int 截断。
  static QccTransaction _fromDetail(
      Map detail, {
        required String status,
        String? msg,
        String? txHash,
        int? timestamp,
        QccTxConfirmation? confirmation,
      }) {
    QccTransactionData? txData;
    if (detail.isNotEmpty) {
      try {
        txData = QccTransactionData.fromJson(Map<String, dynamic>.from(detail));
      } catch (e) {
        print("QccTransaction: QccTransactionData.fromJson 解析失败，退回手动解析: $e");
      }
    }

    final String assetId =
        txData?.assetId ?? (detail['assetId'] as String?) ?? 'QCC';
    final int rawAmount =
        txData?.amount ?? ((detail['amount'] as num?)?.toInt() ?? 0);
    final double humanAmount =
    QccAssetService().getHumanAmountNum(assetId, rawAmount);

    return QccTransaction(
      status: status,
      msg: msg,
      txHash: (txHash != null && txHash.isNotEmpty)
          ? txHash
          : (txData?.id ?? (detail['txHash'] as String?) ?? ''),
      assetId: assetId,
      from: txData?.from ?? (detail['from'] as String?) ?? '',
      to: txData?.to ?? (detail['to'] as String?) ?? '',
      amount: humanAmount,
      type: txData?.txType ??
          (detail['txType'] as String?) ??
          (detail['type'] as String?) ??
          'unknown',
      timestamp: timestamp ??
          txData?.timestamp ??
          ((detail['timestamp'] as num?)?.toInt()) ??
          0,
      confirmState: confirmation?.state,
      height: confirmation?.height,
      containerId: confirmation?.containerId,
      tailHash: confirmation?.tailHash,
      confirmTimestamp: confirmation?.confirmTimestamp,
      confirmDateUTC: confirmation?.confirmDateUTC,
    );
  }
}