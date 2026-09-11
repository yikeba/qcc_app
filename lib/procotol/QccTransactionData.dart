// transaction_data.dart
//
// 对应 Java: qcc.core.qccData.TransactionData
// 前端不做 toBytes()/fromBytes()，只走 toJson()/fromJson()；
// 签名/验签走 toSign()（value-only 拼接），与 JSON 序列化完全解耦。
//
// 依赖: pointycastle（Dart 的 crypto 包没有 SHA3-256，需要额外引入）
//   pubspec.yaml:
//     dependencies:
//       pointycastle: ^3.9.1
//
// ⚠️ 本文件基于以下假设，未核对到你的实际源码，需要你确认或发我对应文件：
// 1. QccBaseData 的基础字段为 chain/type/id/assetId/from/timestamp（来自你项目 memory 记录的
//    fastjson2 @JSONField ordinal 顺序推断），signatureHash 不参与 JSON 序列化。
// 2. MatchLogic 字段沿用你之前发过的：pairAssetId(String) / rate(double) /
//    maxParticipants(int) / rule(String) / remainingAmount(long)。QccMatchLogic.dart
//    是独立文件，本次没有拿到最新内容，下方 validateNoReservedChar() 假设它里面已经/需要有
//    对应的方法——如果实际字段或类结构不同，请把 QccMatchLogic.dart 发我核对。
// 3. 【未修复，原样保留】Java 端 getPayloadForHash() 依然是无分隔符拼接
//    （chain+from+to+amount+timestamp+memo+assetId+fromdev+matcHash），
//    本文件的 getPayloadForHash() 为了保证 id 跨端一致，故意原样复刻这个"有歧义"的实现。
// 4. txType 依然没有参与 getPayloadForHash() 和 toSign()，未校验（是否要签还没定）。
// 5. finalizeId() 里 `timestamp = DateTime.now()...` 这行是你这版新加的，Java 端没有——
//    这行为差异还没确认是否有意为之，见对话说明，先原样保留没有擅自删除。

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/digests/sha3.dart';

import 'QccMatchLogic.dart';


class QccTransactionData {
  // ---- 基础字段（对应 QccBaseData）----
  String? chain;
  String? id;
  String? assetId;
  String? from;
  int? timestamp; // Java long -> Dart int
  // signatureHash 不参与 JSON 序列化，此处不建模，由你现有签名流程单独持有

  // ---- 业务字段 ----
  String? to;
  int? amount; // Java long -> Dart int，⚠️ Flutter Web 下 int 只有 53 位精度，见底部说明
  String? memo;
  String? txType;
  QccMatchLogic? matchLogic;
  String? matcHash;
  String? fromdev;

  static const String type = 'transaction';

  QccTransactionData(){
    fromdev="QQxDj4tZrVA77PA3U1wW91kcmMigkcj5HN";
  }

  QccTransactionData.from({
    this.chain,
    this.id,
    this.assetId,
    this.from,
    required this.timestamp,
    this.to,
    required this.amount,
    this.memo,
    this.txType,
    this.matchLogic,
    this.matcHash,
    this.fromdev,
  });

  // ==================== JSON（传输/存储用，和签名彻底解耦，字段顺序无所谓）====================

  factory QccTransactionData.fromJson(Map<String, dynamic> json) {
    return QccTransactionData.from(
      chain: json['chain'] as String?,
      id: json['id'] as String?,
      assetId: json['assetId'] as String?,
      from: json['from'] as String?,
      timestamp: json['timestamp'] as int,
      to: json['to'] as String?,
      amount: json['amount'] as int,
      memo: json['memo'] as String?,
      txType: json['txType'] as String?,
      matchLogic: json['matchLogic'] == null
          ? null
          : QccMatchLogic.fromJson(json['matchLogic'] as Map<String, dynamic>),
      matcHash: json['matcHash'] as String?,
      fromdev: json['fromdev'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'chain': chain,
    'id': id,
    'assetId': assetId,
    'from': from,
    'timestamp': timestamp,
    'to': to,
    'amount': amount,
    'memo': memo,
    'txType': txType,
    'matchLogic': matchLogic?.toJson(),
    'matcHash': matcHash,
    'fromdev': fromdev,
  };

  String toJsonString() => jsonEncode(toJson());

  static QccTransactionData fromJsonString(String s) =>
      QccTransactionData.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ==================== id 计算（对应 Java getPayloadForHash() + finalizeId()）====================

  static String _nz(String? s) => s ?? '';

  /// ⚠️ 原样复刻 Java 端未修复的无分隔符拼接，两端必须保持一致（见文件头说明）
  String getPayloadForHash() {
    // 校验放在这里而不是 finalizeId()：和 Java 端保持同样的位置选择，
    // 覆盖 finalizeId() 和任何直接调用 getPayloadForHash() 的路径。
    validateNoReservedChar();
    final mHash = (matcHash == null || matcHash!.isEmpty) ? '' : matcHash!;
    return '${_nz(chain)}${_nz(from)}${_nz(to)}$amount$timestamp${_nz(memo)}${_nz(assetId)}${_nz(fromdev)}$mHash';
  }

  /// 校验所有参与签名/id计算的字符串字段，禁止包含系统保留字符（与 signSep 同一个字符）。
  /// 覆盖范围必须和 getPayloadForHash() + toSign() 用到的字段集合严格一致，
  /// 与 Java validateNoReservedChar() 对称。txType 目前不参与签名，未校验。
  void validateNoReservedChar() {
    checkField('assetId', assetId);
    checkField('chain', chain);
    checkField('from', from);
    checkField('fromdev', fromdev);
    checkField('to', to);
    checkField('memo', memo);
    checkField('matcHash', matcHash);
    matchLogic?.validateNoReservedChar(signSep);
  }

  static void checkField(String fieldName, String? value) {
    if (value != null && value.contains(signSep)) {
      throw ArgumentError('字段 [$fieldName] 包含系统保留字符 "$signSep"，交易被拒绝');
    }
  }

  /// 对应 Java finalizeId()：SHA3-256(getPayloadForHash()) 的十六进制小写字符串
  String finalizeId() {
    fromdev="QQxDj4tZrVA77PA3U1wW91kcmMigkcj5HN";
    timestamp = DateTime.now().millisecondsSinceEpoch;
    memo ??= "";
    final bytes = utf8.encode(getPayloadForHash());
    final digest = SHA3Digest(256);
    final out = digest.process(Uint8List.fromList(bytes));
    id = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return id!;
  }

  String getTxHash() {
    if (id == null || id!.isEmpty) {
      finalizeId();
    }
    return id!;
  }

  // ==================== 签名字符串（对应 Java toSign()，与 JSON 完全解耦）====================

  /// 系统保留字符：不可出现在任何参与签名/id计算的字符串字段中，
  /// 同时用作 toSign() 的拼接分隔符——两个用途共用同一个常量，不要拆成两个变量维护
  static const String signSep = '`';


  /// ⚠️ 数值格式化必须和 Java String.valueOf(double) 逐字节一致才能保证 toSign() 跨端相同，
  /// 见文件底部说明——这不是"实现细节"，是这套方案能不能用的关键前提，需要你决策。
  static String formatDoubleForSign(double v) {
    // 临时策略：整数值去掉小数点（1.0 -> "1.0"，与 Java Double.toString 行为对齐的常见 case）
    // 非整数值原样输出。这不保证覆盖所有边界情况（科学计数法、精度舍入），见说明。
    return v.toString();
  }

  /// 必须先调用 finalizeId()，id 已生成，才能调用本方法——与 Java 端前置条件一致
  String toSign() {
    if (id == null || id!.isEmpty) {
      throw StateError('必须先调用 finalizeId() 生成 id，才能构造签名内容');
    }
    final matchLogicStr = matchLogic?.toSignSegment() ?? '';
    return [
      _nz(assetId),
      _nz(chain),
      _nz(from),
      _nz(fromdev),
      _nz(to),
      amount.toString(),
      timestamp.toString(),
      _nz(memo),
      matchLogicStr,
      _nz(matcHash),
      id!,
    ].join(signSep);
  }

  /// 拿到（比如从服务端/其他节点收到的）交易后，重新派生签名字符串做比对，
  /// 和 Java verifySignString() 语义一致
  bool verifySignString(String received) => toSign() == received;

  /// 供调试用：按分隔符切分，核对字段数量是否符合协议（无 matchLogic 时 11 段，有则 15 段）
  static List<String> parseSignFields(String signStr) {
    final parts = signStr.split(signSep);
    if (parts.length != 11 && parts.length != 15) {
      throw FormatException('字段数量不符合协议，收到 ${parts.length} 个字段');
    }
    return parts;
  }
}



