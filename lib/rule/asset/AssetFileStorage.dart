import 'dart:convert';
import '../../utile/QccStorage.dart';
import '../../utile/LogObj.dart';

class AssetFileStorage {
  static const String _storageKey = "qcc_assets_registry";

  /// 保存已发行的资产记录
  static Future<void> saveAsset(Map<String, dynamic> responseData) async {
    try {
      final List<dynamic> assets = await getAllAssets();

      // 1. 提取资产元数据
      Map<String, dynamic>? assetEntry;
      if (responseData['data'] != null) {
        var innerData = jsonDecode(responseData['data']);
        var ruleJson = jsonDecode(innerData['ruleJson'] ?? "{}");

        // 适配 AssetMintRule -> assetMeta 结构
        var meta = ruleJson['assetMeta'] ?? ruleJson;

        assetEntry = {
          'assetId': meta['assetId'],
          'owner': meta['owner'],
          'precision': meta['precision'],
          'initialSupply': meta['initialSupply'],
          'mintable': meta['mintable'],
          'freezable': meta['freezable'],
          'txHash': responseData['txHash'] ?? innerData['id'],
          'timestamp': responseData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          'status': responseData['status'],
        };
      }

      if (assetEntry != null && assetEntry['assetId'] != null) {
        // 2. 查重：如果 assetId 已存在则更新，不存在则添加
        int index = assets.indexWhere((e) => e['assetId'] == assetEntry!['assetId']);
        if (index != -1) {
          assets[index] = assetEntry;
        } else {
          assets.add(assetEntry);
        }

        // 3. 写入本地存储
        await QccStorage.saveRawData(_storageKey, jsonEncode(assets));
        LogObj.log("✅ 资产 [${assetEntry['assetId']}] 已注册到本地状态中心");
      }
    } catch (e) {
      LogObj.log("保存资产记录异常: $e");
    }
  }

  /// 获取所有已发行资产
  static Future<List<dynamic>> getAllAssets() async {
    String? raw = await QccStorage.getRawkeyuData(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return jsonDecode(raw);
    } catch (e) {
      return [];
    }
  }
}