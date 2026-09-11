
import 'dart:convert';

import 'package:qcc_flutter/utile/LogObj.dart';

class QccMultiSigData {
  final String txHash;
  final String from;
  final UserRule ruleJson;
  final Map<String, MultiSigAppend> ruleAppendJson;
  final String ruleName;

  QccMultiSigData({
    required this.txHash,
    required this.from,
    required this.ruleJson,
    required this.ruleAppendJson,
    required this.ruleName,
  });

  factory QccMultiSigData.fromJson(Map<String, dynamic> json) {
    // 解析 ruleJson
    LogObj.log("加载多签明细:$json");
    var ruleJsonRaw = json['ruleJson'];
    UserRule ruleDetails = ruleJsonRaw is String
        ? UserRule.fromJson(jsonDecode(ruleJsonRaw))
        : UserRule.fromJson(ruleJsonRaw);

    // 解析 ruleAppendJson (这是一个 Map 结构)
    Map<String, dynamic> appendRaw = jsonDecode(json['ruleAppendJson'] ?? '{}');
    Map<String, MultiSigAppend> appends = appendRaw.map(
            (key, value) => MapEntry(key, MultiSigAppend.fromJson(value))
    );

    return QccMultiSigData(
      txHash: json['txHash'],
      from: json['from'],
      ruleJson: ruleDetails,
      ruleAppendJson: appends,
      ruleName: json['ruleName'],
    );
  }
}

class UserRule {
  final List<String> owners;
  final int threshold;
  final String multiaddress;
  final bool governance;
  final String processHash;

  UserRule({
    required this.owners,
    required this.threshold,
    required this.multiaddress,
    required this.governance,
    required this.processHash,
  });

  factory UserRule.fromJson(Map<String, dynamic> json) {
    // 1. 获取原始列表
    List<dynamic> rawOwners = json['owners'] ?? [];

    // 2. 使用 Set 去重，并转换为 List<String>
    // toSet() 会自动移除重复地址，toList() 恢复为列表格式
    List<String> distinctOwners = rawOwners
        .map((e) => e.toString())
        .toSet()
        .toList();

    return UserRule(
      owners: distinctOwners,
      threshold: json['threshold'] ?? 0,
      multiaddress: json['multiaddress'] ?? '',
      governance: json['governance'] ?? false,
      processHash: json['processHash'] ?? '',
    );
  }
}

class MultiSigAppend {
  final String from;
  final String signatureHash;
  final String timestamp;

  MultiSigAppend({
    required this.from,
    required this.signatureHash,
    required this.timestamp,
  });

  factory MultiSigAppend.fromJson(Map<String, dynamic> json) {
    return MultiSigAppend(
      from: json['from'],
      signatureHash: json['signatureHash'],
      timestamp: json['timestamp'].toString(),
    );
  }
}