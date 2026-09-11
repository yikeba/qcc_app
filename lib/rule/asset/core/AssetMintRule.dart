import 'dart:convert';

/// Dart 版本的资产铸造/增发规则类
/// 严格对应 Java qcc.rule.assetRule.AssetMintRule
class AssetMintRule {
  String assetId;    // 目标资产ID (如: USDQ)
  int amount;        // 本次铸造/增发数量 (Java long 对应 Dart int64)
  String receiver;   // 接收增发资产的地址 (通常是多签地址本身)
  String? proof;     // 铸造证明（可选，解释铸造来源、审计凭证等）

  AssetMintRule({
    required this.assetId,
    required this.amount,
    required this.receiver,
    this.proof,
  });

  // --- 对应 Java 的 JSON 序列化 ---

// 1. 标准 toJson 返回 Map，而不是 String
  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'amount': amount,
    'receiver': receiver,
    'proof': proof,
  };

  String toRawJson() => jsonEncode(toJson());

  /// 从 JSON 字符串反序列化
  factory AssetMintRule.fromJson(String jsonStr) {
    Map<String, dynamic> json = jsonDecode(jsonStr);
    return AssetMintRule.fromStructure(json);
  }

  /// 从 Map 结构构建对象
  factory AssetMintRule.fromStructure(Map<String, dynamic> json) {
    return AssetMintRule(
      assetId: json['assetId'] ?? '',
      // 注意：从 JSON 解析时，如果数字很大，FastJSON2 传出的可能是 BigInt 或 double
      // 这里确保它被解析为 Dart 的 int64
      amount: json['amount'] != null ? json['amount'].toInt() : 0,
      receiver: json['receiver'] ?? '',
      proof: json['proof'],
    );
  }
}