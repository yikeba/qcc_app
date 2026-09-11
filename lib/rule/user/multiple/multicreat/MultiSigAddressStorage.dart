import 'dart:convert';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../../utile/QccStorage.dart';
import '../QccMultiSig.dart';
import 'QccMultiSigService.dart';
class MultiSigAddressStorage {
  // 建议将 key 统一管理，防止拼写错误
  static const String _vaultKey = "qcc_multi_address_vault";

  static Future<void> saveConfirmedAccount(MultiSigAccount account) async {
    try {
      List<MultiSigAccount> all = await getAllAccounts();
      // 检查 M 地址是否已存在
      if (!all.any((e) => e.multiAddress == account.multiAddress)) {
        all.add(account);
        // 对象转 Map 再转 JSON
        String jsonStr = jsonEncode(all.map((e) => e.toMap()).toList());
        // 使用 QccStorage 存储
        await QccStorage.setString(_vaultKey, jsonStr);
        LogObj.log("QCC DEBUG_: 存储成功 -> $jsonStr");
      }
    } catch (e) {
      LogObj.log("QCC DEBUG_: 存储过程异常 -> $e");
    }
  }


  // 在 QccMultiSigCenterPage 的列表渲染或刷新逻辑中
  static void checkAndSaveAccount(MultiSigTaskWrapper task) {
    // 1. 提取多签地址
    String? mAddr;
    if (task.data['ruleJson'] != null) {
      try {
        var rule = jsonDecode(task.data['ruleJson'].toString());
        mAddr = rule['multiaddress'] ?? rule['multiAddress'];
      } catch(_) {}
    }

    // 2. 如果地址出现了，且是 Confirmed 状态，就存为正式资产
    if (mAddr != null && mAddr.startsWith('M') && task.isConfirmed) {
      MultiSigAddressStorage.saveConfirmedAccount(MultiSigAccount(
        multiAddress: mAddr,
        owners: task.signedOwners, // 这里的 5 个地址序列直接存，保留审计存证
        threshold: task.data['threshold'] ?? 3,
        txHash: task.txHash, createTime: null,
      ));
    }
  }

  static Future<void> deleteAccount(String multiAddress) async {
    List<MultiSigAccount> all = await getAllAccounts();
    all.removeWhere((e) => e.multiAddress == multiAddress);
    String jsonStr = jsonEncode(all.map((e) => e.toMap()).toList());
    await QccStorage.setString(_vaultKey, jsonStr); // 重新覆盖存储
  }

  static Future<MultiSigAccount?> getMultiAccount(String multiAddress) async {
    List<MultiSigAccount> all = await getAllAccounts();
    for(MultiSigAccount item in all){
      if(item.multiAddress== multiAddress) return item;
    }
    return null;
  }

  static Future<List<MultiSigAccount>> getAllAccounts() async {
    try {
      // 核心修正：确保 QccStorage 的 prefs 已经初始化
      // 如果你的 QccStorage 有 init 方法，请确保在 App 入口调用过
      await QccStorage.init();
      String? data = QccStorage.getString(_vaultKey);
      LogObj.log("QCC DEBUG_: 从 QccStorage 读取原始字符串: $data");
      if (data == null || data.isEmpty || data == "[]") return [];
      List<dynamic> list = jsonDecode(data);
      return list.map((e) => MultiSigAccount.fromMap(e)).toList();
    } catch (e) {
      LogObj.log("QCC DEBUG_: 读取并解析本地账户异常 -> $e");
      return [];
    }
  }
}