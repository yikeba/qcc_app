import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

/// QCC 规则大类定义
enum QccRuleType {
  UserRule,
  AsseIdRule,
  GovernanceRule,
  SystemRule,
}

/// 规则基础属性 (对应 Java 的 RuleBaseObj)
abstract class QccRuleBaseObj {
  String ruleType = "UserRule";
  bool governance = true;
  bool gasPolicy = true;
  String ruleContinuousType = "Replace";
  String ruleGovernanceType = "Address";
  String? handlerClass;
  String ruleName = "";
  String version = "1.0.0";

  Map<String, dynamic> toBaseJson() {
    return {
      'ruleType': ruleType,
      'governance': governance,
      'gasPolicy': gasPolicy,
      'ruleContinuousType': ruleContinuousType,
      'ruleGovernanceType': ruleGovernanceType,
      'handlerClass': handlerClass,
      'ruleName': ruleName,
      'version': version,
    };
  }
}

/// 1. 开发者奖励规则 (DeveloperRule)
class QccDeveloperRule extends QccRuleBaseObj {
  String address;
  String? credentialHash;
  double rewardRate = 0.3;

  QccDeveloperRule({
    required this.address,
    this.credentialHash,
    this.rewardRate = 0.3,
  }) {
    ruleName = "DeveloperRule";
    handlerClass = "qcc.rule.userRule.DeveloperHandler";
  }

  Map<String, dynamic> toJson() {
    final map = toBaseJson();
    map.addAll({
      'address': address,
      'credentialHash': credentialHash,
      'rewardRate': rewardRate,
    });
    return map;
  }
}

/// 2. 商户到付规则 (MerchantRule)
class QccMerchantRule extends QccRuleBaseObj {
  String address;
  String? credentialHash;
  bool gasDelegation = true;

  QccMerchantRule({
    required this.address,
    this.credentialHash,
    this.gasDelegation = true,
  }) {
    ruleName = "MerchantRule";
    handlerClass = "qcc.rule.userRule.MerchantHandler";
  }

  Map<String, dynamic> toJson() {
    final map = toBaseJson();
    map.addAll({
      'address': address,
      'credentialHash': credentialHash,
      'gasDelegation': gasDelegation,
    });
    return map;
  }
}

/// 3. 支付回调规则 (PayCallRule)
class QccPayCallRule extends QccRuleBaseObj {
  String address;
  String callUrl;
  String? credentialHash;

  QccPayCallRule({
    required this.address,
    required this.callUrl,
    this.credentialHash,
  }) {
    ruleName = "PayCallRule";
    handlerClass = "qcc.rule.userRule.PayCallHandler";
  }

  Map<String, dynamic> toJson() {
    final map = toBaseJson();
    map.addAll({
      'address': address,
      'callUrl': callUrl,
      'credentialHash': credentialHash,
    });
    return map;
  }
}

/// QCC 规则交易容器 (对应 Java 的 RuleData)
class QccRuleData {
  String? id;
  String from;
  String? fromMulti;
  String assetId;
  String ruleType;
  String ruleName;
  String ruleJson;
  int timestamp;

  QccRuleData({
    required this.from,
    this.fromMulti,
    this.assetId = "QCCRule", // 默认 QCCRule
    required this.ruleType,
    required this.ruleName,
    required this.ruleJson,
    required this.timestamp,
  });

  /// 对应 Java 端的 finalizeId()
  /// 计算规则内容的 SHA3-256 哈希作为 TxID
  void finalizeId() {
    // 按照 Java 序列化顺序拼接关键字段
    String content = "$from$ruleType$ruleName$ruleJson$timestamp$assetId";
    if (fromMulti != null) content += fromMulti!;

    var bytes = utf8.encode(content);
    // ✅ 修复：使用真正的 SHA3-256，与 Java CryptoUtil.sha3256Hex() 一致
    id = sha3256Hex(bytes);
  }

  /// SHA3-256 实现方法
  String sha3256Hex(List<int> input) {
    final digest = SHA3Digest(256); // 256位 = SHA3-256
    final inputBytes = Uint8List.fromList(input);
    digest.update(inputBytes, 0, inputBytes.length);
    final output = Uint8List(32);
    digest.doFinal(output, 0);
    return hex.encode(output);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'fromMulti': fromMulti,
    'assetId': assetId,
    'ruleType': ruleType,
    'ruleName': ruleName,
    'ruleJson': ruleJson,
    'timestamp': timestamp,
  };
}