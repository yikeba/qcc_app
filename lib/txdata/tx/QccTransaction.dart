import 'dart:convert';
import 'package:qcc_flutter/utile/JsonUtil.dart';

import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import '../../views/myasset/QccAssetService.dart';

class QccTransaction {
  final String status;
  final String? msg;
  final String txHash;
  final String assetId;
  final String from;
  final String to;
  final double amount;
  final String type; // 对应 txType (如 pay, win, open 等)
  final int timestamp;

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
  });

  /// 【本次重写，对应你"干脆合并"的要求，同时修复"0.01及以下金额显示成0"】
  ///
  /// 原来的真正 bug 在这一行：
  ///   int desamount = QccAssetService().getAmountString(assetId, souamount);
  /// 不管 getAmountString 内部具体怎么实现，desamount 被声明成 int 这件事
  /// 本身就是错的——原始金额 souamount=10000000，QCC 精度9，换算成人类可读
  /// 金额应该是 10000000/10^9=0.01，这是个纯小数；只要中间结果被塞进 int，
  /// 任何换算结果 <1 的金额都会被直接截断成 0（日志里打印出来的
  /// "转账金额数据:0.0" 就是这么来的）。方法名 getAmountString 本身听着也
  /// 像是回传字符串用的，和后面接 int 变量对不上号，大概率是调错了方法/
  /// 顺手写错了类型。
  ///
  /// 现在改成两步，都是本 session 其它页面（DexMatchWidget.dart /
  /// QccWinTransactionPage.dart / MyDexOrdersWidget.dart 等）已经在用、
  /// 验证过的写法：
  /// 1. 不再在这里手写一遍"解析 detail 里的每个字段"——直接复用
  ///    QccTransactionData.fromJson()，这是你项目里已经和 Java
  ///    TransactionData 字段对齐过的规范解析器，amount 字段本来就该是
  ///    "最小单位的原始整数"（QccTransactionData.dart 里 `int? amount;`）。
  ///    两处以后也不用各自维护一份解析逻辑、慢慢长出不一致的 bug。
  /// 2. 人类可读金额单独用 QccAssetService().getHumanAmountNum(assetId,
  ///    rawAmount) 换算，这个方向是"原始整数 -> 人类可读 double"，返回值
  ///    从头到尾都是 double，不会像原来那样中途被 int 截断。
  factory QccTransaction.fromJson(String jsonstr) {
    // 1. 解析外层
    Map json = JsonUtil.strtoMap(jsonstr);
    final status = json['status'] as String? ?? '';
    final msg = json['msg'] as String?;

    // 2. 解析嵌套的 data 字符串
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

    // 3. 优先走 QccTransactionData 的规范解析；万一 detail 字段不全导致
    //    解析失败，退回到原来手写的 Map 取值方式兜底，不让整个页面崩掉。
    QccTransactionData? txData;
    try {
      txData = QccTransactionData.fromJson(Map<String, dynamic>.from(detail));
    } catch (e) {
      print("QccTransaction: QccTransactionData.fromJson 解析失败，退回手动解析: $e");
    }

    final String assetId = txData?.assetId ?? (detail['assetId'] as String?) ?? 'QCC';
    final int rawAmount = txData?.amount ?? ((detail['amount'] as num?)?.toInt() ?? 0);
    print("QccTransaction 原始金额(最小单位): $rawAmount, 资产: $assetId");

    // 换算方向：原始整数 -> 人类可读 double，全程不经过 int，避免 <1 的金额被截断成 0
    final double humanAmount = QccAssetService().getHumanAmountNum(assetId, rawAmount);

    return QccTransaction(
      status: status,
      msg: msg,
      txHash: (json['txHash'] as String?) ?? txData?.id ?? (detail['txHash'] as String?) ?? '',
      assetId: assetId,
      from: txData?.from ?? (detail['from'] as String?) ?? '',
      to: txData?.to ?? (detail['to'] as String?) ?? '',
      amount: humanAmount,
      type: txData?.txType ?? (detail['txType'] as String?) ?? (detail['type'] as String?) ?? 'unknown',
      timestamp: (json['timestamp'] as int?) ?? txData?.timestamp ?? (detail['timestamp'] as int?) ?? 0,
    );
  }
}