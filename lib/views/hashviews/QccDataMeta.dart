/// 数据类型枚举
//enum QccEntryType { transaction, data, rule}

enum QccEntryType { transaction, data, gas,rule }

class QccDataMeta {
  final String title;
  final String metaHash;     // 对应交易的 txId 或数据 Hash
  final List<String> hashes;
  final int timestamp;
  final QccEntryType entryType;
  final int totalSize;

  // --- 新增字段，用于兼容交易和 Gas 明细 ---
  final String? from;        // 支付方/发起方 (payer)
  final String? to;          // 接收方
  final double? amount;      // 交易金额
  final int? gasUsed;        // 手续费消耗 (totalGas)
  final String? assetId;     // 资产标识 (如 QCC)

  final Map<String, dynamic>? extra;

  QccDataMeta({
    required this.title,
    required this.metaHash,
    required this.hashes,
    required this.timestamp,
    required this.entryType,
    this.totalSize = 0,
    this.from,
    this.to,
    this.amount,
    this.gasUsed,
    this.assetId,
    this.extra,
  });

  // 1. 标准解析（用于原来的详情接口）
  factory QccDataMeta.fromJson(Map<String, dynamic> json) {
    return QccDataMeta(
      title: json['title'] ?? (json['type'] ?? "未知类型"),
      metaHash: json['metaHash'] ?? json['hash'] ?? "",
      hashes: List<String>.from(json['hashes'] ?? []),
      timestamp: json['timestamp'] ?? 0,
      entryType: QccEntryType.values[json['entryType'] ?? 0],
      totalSize: json['totalSize'] ?? 0,
      extra: json['extra'],
    );
  }

  // 2. 专门解析 Gas 接口返回的数组对象
  // 对应你提供的：[{"amount":128...0, "assetId":"QCC", "totalGas":1000000, "txId":"..."}]
  factory QccDataMeta.fromGasJson(Map<String, dynamic> json) {
    return QccDataMeta(
      title: "手续费支出",
      metaHash: json['txId'] ?? json['hash'] ?? "",
      hashes: [],
      timestamp: json['timestamp'] ?? 0,
      entryType: QccEntryType.gas, // 强制标记为 gas 类型
      from: json['payer'],
      to: json['to'],
      amount: (json['amount'] is num) ? json['amount'].toDouble() : 0.0,
      gasUsed: json['totalGas'] ?? 0,
      assetId: json['assetId'] ?? "QCC",
      extra: json, // 保留原始数据以备不时之需
    );
  }

  // 格式化后的时间
  String get timeStr {
    if (timestamp == 0) return "--";
    var dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
  }

  // 格式化后的 Gas 金额（假设 9 位精度）
  String get gasAmountFormatted {
    if (gasUsed == null) return "0.00";
    return (gasUsed! / 1000000000).toStringAsFixed(9);
  }
}