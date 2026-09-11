import 'dart:convert';

/// Dart 版本的资产销毁规则类
/// 严格对应 Java qcc.rule.assetRule.AssetBurnRule（字段取自
/// TxRuleITIAAssetFullFlow.java 里两处实际用法：
///   burnOther.assetId / .targetAddress / .amount / .legalBasis  （销毁第三方地址）
///   burnSelf.assetId  / .targetAddress / .amount / .memo         （自烧）
/// ）。
///
/// 【协议要点，务必保留】销毁在协议层是一笔 RuleData（ruleType=AsseIdRule，
/// ruleName=AssetBurnRule），走 /v1/rule 由发行方签名提交，不是普通转账
/// （TransactionData/v1/txm）。这一点很关键：如果做成"转账到黑洞地址"，
/// 发起方就只能转自己账户里的余额——因为普通转账需要用余额持有人自己的
/// 私钥签名，发行方并不持有第三方地址的私钥。而协议允许发行方对"已冻结
/// 满12个自然月"的第三方地址发起销毁，正是因为这笔操作由链上
/// AssetRegistry.executeBurn() 校验并执行（校验 freezable 开关 + 冻结时长），
/// 不需要目标地址本人签名——所以必须用 AssetBurnRule 这个模型，不能用转账。
class AssetBurnRule {
  String assetId;         // 目标资产ID
  String targetAddress;   // 被销毁余额的地址：可以是发行方自己（自烧），
                           // 也可以是已冻结满12个月的第三方地址（合规销毁）
  int amount;             // 本次销毁数量 (Java long 对应 Dart int64)
  String? legalBasis;      // 合规依据/法律依据——销毁第三方地址时使用
  String? memo;            // 备注——自烧时使用

  AssetBurnRule({
    required this.assetId,
    required this.targetAddress,
    required this.amount,
    this.legalBasis,
    this.memo,
  });

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'targetAddress': targetAddress,
    'amount': amount,
    'legalBasis': legalBasis,
    'memo': memo,
  };

  String toRawJson() => jsonEncode(toJson());

  factory AssetBurnRule.fromJson(String jsonStr) {
    Map<String, dynamic> json = jsonDecode(jsonStr);
    return AssetBurnRule.fromStructure(json);
  }

  factory AssetBurnRule.fromStructure(Map<String, dynamic> json) {
    return AssetBurnRule(
      assetId: json['assetId'] ?? '',
      targetAddress: json['targetAddress'] ?? '',
      amount: json['amount'] != null ? json['amount'].toInt() : 0,
      legalBasis: json['legalBasis'],
      memo: json['memo'],
    );
  }
}
