import 'dart:convert';
import 'dart:developer' as LogObj;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Dart 版本的资产冻结/解冻规则类
/// 严格对应 Java qcc.rule.assetRule.AssetFreezeRule
class AssetFreezeRule {
  String assetId;       // 目标资产ID (如: USDQ)
  String targetAddress; // 要冻结/解冻的目标地址
  bool freeze;          // true 为冻结操作，false 为解冻操作
  int expiry;           // 冻结有效期时间戳 (0 为永久冻结，Java long 对应 Dart int64)

  AssetFreezeRule({
    required this.assetId,
    required this.targetAddress,
    required this.freeze,
    required this.expiry,
  });

  // --- 序列化逻辑 (Map 模式，防止 Double Serialization) ---

  /// 标准 toJson 返回 Map，供嵌套使用
  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'targetAddress': targetAddress,
    'freeze': freeze,
    'expiry': expiry,
  };

  /// 专门提供给 RuleData.ruleJson 赋值的原始 JSON 字符串方法
  String toRawJson() => jsonEncode(toJson());

  /// 从 Map 结构构建对象
  factory AssetFreezeRule.fromStructure(Map<String, dynamic> json) {
    return AssetFreezeRule(
      assetId: json['assetId'] ?? '',
      targetAddress: json['targetAddress'] ?? '',
      freeze: json['freeze'] ?? true,
      expiry: json['expiry'] != null ? json['expiry'].toInt() : 0,
    );
  }
}




class FreezeRecord {
  final String assetId;
  final String targetAddress;
  final bool isFrozen; // true 为冻结, false 为解冻
  final int timestamp;
  final String txHash;

  FreezeRecord({
    required this.assetId,
    required this.targetAddress,
    required this.isFrozen,
    required this.timestamp,
    required this.txHash,
  });

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'targetAddress': targetAddress,
    'isFrozen': isFrozen,
    'timestamp': timestamp,
    'txHash': txHash,
  };

  factory FreezeRecord.fromJson(Map<String, dynamic> json) => FreezeRecord(
    assetId: json['assetId'],
    targetAddress: json['targetAddress'],
    isFrozen: json['isFrozen'],
    timestamp: json['timestamp'],
    txHash: json['txHash'],
  );
}

class AssetFreezeStorage {
  static const String _fileName = "asset_freeze_records.json";

  // 保存一条记录
  static Future<void> saveRecord(FreezeRecord record) async {
    try {
      final List<FreezeRecord> records = await getAllRecords();
      // 如果是对同一个地址的操作，可以考虑更新或直接追加
      records.insert(0, record); // 最新操作放在最前面

      final file = await _getLocalStorageFile();
      await file.writeAsString(jsonEncode(records.map((e) => e.toJson()).toList()));
    } catch (e) {
      LogObj.log("保存冻结记录失败: $e");
    }
  }

  // 获取所有记录
  static Future<List<FreezeRecord>> getAllRecords() async {
    try {
      final file = await _getLocalStorageFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => FreezeRecord.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<File> _getLocalStorageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}