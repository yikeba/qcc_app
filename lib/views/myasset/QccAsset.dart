import 'dart:convert';
import 'dart:math';

class QccAsset  {
  final String assetId;
  final String address;
  final String type;
  final int precision;
  final String? credentialHash;
  final int initialSupply;
  bool isFollowing; // 本地状态

  QccAsset({
    required this.assetId,
    required this.type,
    required this.address,
    required this.precision,
    this.initialSupply = 0,
    this.credentialHash,
    this.isFollowing = false,
  });

  factory QccAsset.fromJson(Map<String, dynamic> json) {
    return QccAsset(
      assetId: json['assetId'] ?? '',
      type: json['type'] ?? 'COIN',
      address: json["owner"] ?? "",
      precision: json['precision'] ?? 9,
      initialSupply: json['initialSupply'] ?? 0,
      credentialHash: json['credentialHash'],
    );
  }

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'type': type,
    'precision': precision,
    'credentialHash': credentialHash,
  };



  /// ✅ 核心转换方法：将 QCC 状态机识别的 int (原始金额) 转换为人类可读金额
  /// [assetId] 资产代码（用于查找精度）
  /// [rawAmount] 原始金额（Java long / Dart int）
  /// [showFull] 是否显示全量不限制小数位的字符串，默认 false（会进行格式化）
  String getHumanAmount(dynamic rawAmount, {bool showFull = false}) {
    // 1. 获取资产对象以确定精度
    // 逻辑参考你提供的 getAmountRaw 逻辑
    if (rawAmount == null) return "0";
    // 2. 转换输入值为 BigInt 或 double 处理
    num amountValue = 0;
    if (rawAmount is String) {
      amountValue = num.tryParse(rawAmount) ?? 0;
    } else if (rawAmount is num) {
      amountValue = rawAmount;
    }
    // 3. 计算除数 (10 ^ precision)
    // 注意：你之前的 multiplier 逻辑是 pow(10, precision)，这里保持一致
    num divider = pow(10, precision);
    // 4. 执行除法
    double result = amountValue / divider;
    return result.toStringAsFixed(precision).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");

  }

}