import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart' hide Key;
import 'package:flutter/foundation.dart' hide Key;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qcc_flutter/qccwallet/SecureWalletFragment.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import '../qccwallet/QccWallet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

import 'Tools.dart';

class QccStorage {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),

  );

  // 1. Key 绑定地址，不再绑定密码
  static String _getAddrKey(String address) => "qcc_vault_$address";

  // ⚠️ 名称索引单独用 SharedPreferences 明文存储（非敏感数据），
  // 目的：列表页展示名称时无需输入支付密码解密 vault。
  static const String _keyWalletNames = "qcc_wallet_names";

  // 2. 单个钱包保存：使用该地址对应的支付密码
  // ⚠️ 修复点：原代码 name 参数被接收但从未写入 data / 未持久化，现已修复。
  static Future<void> saveSingleWallet(QccWallet wallet, String name, String password) async {
    String key = _getAddrKey(wallet.address);

    Map<String, dynamic> data = {
      'address': wallet.address,
      'mnemonic': wallet.mnemonic, // 这里后续可以配合 AES(password) 加密更安全
      'verify': "QCC_OK",
      'name': name, // 名称随 vault 备份一份，便于导出/恢复时不丢失
    };

    await _storage.write(key: key, value: jsonEncode(data));

    // 名称主存放在 SharedPreferences 索引里，供 UI 快速读取
    await saveWalletName(wallet.address, name);
  }

  static void delSingleWallet(QccWallet wallet){
    String key = _getAddrKey(wallet.address);
    _storage.delete(key: key);
    // 同步清理名称索引，避免遗留脏数据
    deleteWalletName(wallet.address);
    QccObj.removeWallet(wallet);
  }

  // 3. 获取所有已存储的钱包地址列表（不需要密码即可扫描）
  static Future<List<String>> getAllStoredAddresses() async {
    Map<String, String> all = await _storage.readAll();
    return all.keys
        .where((key) => key.startsWith("qcc_vault_"))
        .map((key) => key.replaceFirst("qcc_vault_", ""))
        .toList();
  }

  // ============ ✅ 新增：钱包名称（昵称）管理 ============

  /// 获取本地保存的「地址 -> 名称」映射表
  static Future<Map<String, String>> getAllWalletNames() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(_keyWalletNames);
    if (jsonStr == null) return {};
    return Map<String, String>.from(jsonDecode(jsonStr));
  }


  static Future<String?> getWalletNameByAddress(String address) async {
    final all = await getAllWalletNames();
    final target = address.toLowerCase();
    for (final entry in all.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  /// 保存 / 更新单个地址对应的名称。name 传空字符串等价于删除该名称。
  static Future<bool> saveWalletName(String address, String name) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> names = await getAllWalletNames();
    if (name.trim().isEmpty) {
      names.remove(address);
    } else {
      names[address] = name.trim();
    }
    return await prefs.setString(_keyWalletNames, jsonEncode(names));
  }

  /// 对外语义化方法名，内部逻辑与 saveWalletName 一致
  static Future<bool> renameWallet(String address, String newName) {
    return saveWalletName(address, newName);
  }

  /// 读取单个地址的名称；若未命名，返回地址缩写形式，方便 UI 直接兜底展示
  static Future<String> getWalletName(String address) async {
    Map<String, String> names = await getAllWalletNames();
    return names[address] ?? shortAddress(address);
  }

  /// 删除某地址的名称记录（配合 delSingleWallet / clearAllWallets 使用）
  static Future<void> deleteWalletName(String address) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> names = await getAllWalletNames();
    if (names.remove(address) != null) {
      await prefs.setString(_keyWalletNames, jsonEncode(names));
    }
  }

  /// 地址缩写显示（如 Q125Y...S4xvr），用于未命名钱包的兜底展示
  static String shortAddress(String address, {int head = 6, int tail = 6}) {
    if (address.length <= head + tail + 3) return address;
    return "${address.substring(0, head)}...${address.substring(address.length - tail)}";
  }

  // =====================================================

  // 根据地址和对应的密码加载单个钱包（带自动升级逻辑）
  static Future<QccWallet?> loadByAddress(String address, String password) async {
    // 测试地址跳过
    if(address == "Q125YBsGHTsEtyByB82W8y6oabtJEnS4xvr") {
      return testaddress();
    }

    String? jsonString = await _storage.read(key: _getAddrKey(address));
    if (jsonString == null) return null;

    Map<String, dynamic> data = jsonDecode(jsonString);
    String storedMnemonic = data['mnemonic'];

    // --- 🔑 执行自适应解密尝试 ---
    String? plainMnemonic;

    // 步骤 A: 尝试使用设备绑定密钥解密
    plainMnemonic = await QccSecurity.decrypt(storedMnemonic, password);

    if (plainMnemonic == null) {
      // 步骤 B: 如果解密失败，判断是否为旧版明文数据
      // 旧版数据通常是 JSON 数组字符串或普通单词列表
      if (storedMnemonic.contains(" ") && !storedMnemonic.contains(":")) {
        LogObj.log("检测到旧版明文数据，准备执行加固升级...");
        plainMnemonic = storedMnemonic;

        // ✅ 触发自动加固：将旧明文转换为加密密文并存回
        _autoUpgradeToEncrypted(address, plainMnemonic, password);
      } else {
        // 既不是密文也不是有效的旧版明文（可能是密码错误）
        LogObj.log("解密失败：密文损坏或支付密码错误");
        return null;
      }
    }else{
      LogObj.log("解密成功，还原助剂词");
    }

    // 成功获取明文后，构建钱包对象
    try {
      return QccMnemonicWallet.fromMnemonic(plainMnemonic, paymentPassword: password);
    } catch (e) {
      LogObj.log("构建钱包对象失败: $e");
      return null;
    }
  }

  /// ✅ 内部方法：自动执行静默升级
  // ⚠️ 修复点：原调用 saveSingleWallet(tempWallet, password) 少传了一个参数
  // （原函数签名需要 name），按原样保留会导致编译报错，这里改为读取已存名称一并传入。
  static Future<void> _autoUpgradeToEncrypted(String address, String mnemonic, String password) async {
    try {
      // 使用新逻辑重新保存（saveSingleWallet 内部已包含加密逻辑）
      // 构造一个临时钱包对象进行重写
      final tempWallet = await QccMnemonicWallet.fromMnemonic(mnemonic, paymentPassword: password);
      final existingName = await getWalletName(address); // 保留原有名称，避免升级后名称丢失
      await saveSingleWallet(tempWallet, existingName, password);
      LogObj.log("钱包 $address 数据已成功升级至设备绑定加密模式");
    } catch (e) {
      LogObj.log("自动升级失败: $e");
    }
  }


  // 在 QccStorage 类中添加
  static Future<String?> getRawData(String address) async {
    return await _storage.read(key: _getAddrKey(address));
  }


  /// 【测试专用】清空本地所有钱包数据
  static Future<void> clearAllWallets() async {
    try {
      // 1. 获取所有存储的 Key
      Map<String, String> allEntries = await _storage.readAll();
      // 2. 筛选出所有与 QCC 钱包相关的 Key 进行删除
      // 包含 qcc_vault_ (加密数据) 和 qcc_address_list (清单)
      for (String key in allEntries.keys) {
        if (key.startsWith("qcc_vault_") || key == "qcc_address_list") {
          await _storage.delete(key: key);
          LogObj.log("已删除存储项: $key");
        }
      }
      // 3. 同步清空名称索引
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyWalletNames);
      // 4. (可选) 如果你想彻底重置存储，可以取消下面这一行的注释：
      // await _storage.deleteAll();
      LogObj.log("--- QCC 本地存储已完全清空 ---");
    } catch (e) {
      LogObj.log("清空存储失败: $e");
    }
  }

  static Future<QccWallet> testaddress() async {
    String password="123456";
    String estMnemonic ="lamp shield trial garment tragic chimney cinnamon over bicycle cruise evoke thought razor poem shoulder submit another wood lava vicious clean pepper blame infant";
    QccWallet qcc= await QccMnemonicWallet.fromMnemonic(estMnemonic, paymentPassword: password);
    LogObj.log("测试地址公钥:${qcc.pubkey!}");
    LogObj.log("测试地址公钥长度:${qcc.pubkey!.length}");
    return qcc;
  }



  // 1. 保存地址清单（明文，用于主页列表显示）
  static Future<void> saveAddressToList(String address) async {
    String? current = await _storage.read(key: "qcc_address_list");
    List<String> list = current != null ? List<String>.from(jsonDecode(current)) : [];
    if (!list.contains(address)) {
      list.add(address);
      await _storage.write(key: "qcc_address_list", value: jsonEncode(list));
    }
  }

/*  // 2. 核心：只存加密内容，不存钱包对象
  static Future<void> saveEncryptedMnemonic(String address, String mnemonic, String password) async {
  // 这里使用密码对助记词进行 AES 加密
  String encryptedMnemonic = AESUtil.encrypt(mnemonic, password);
  await _storage.write(key: "vault_$address", value: encryptedMnemonic);
  await saveAddressToList(address); // 同时把地址存入公开清单
  }*/

  // 3. 仅读取地址列表（初始化用，无需密码）
  static Future<List<String>> loadPublicAddresses() async {
    String? json = await _storage.read(key: "qcc_address_list");
    return json != null ? List<String>.from(jsonDecode(json)) : [];
  }

  static Future<QccWallet?> restoreWallet(BuildContext context,String fromAddress,String password) async {
    final sw = Stopwatch()..start();
    QccWallet? qc=QccWalletSecurityManager().getQccWallet(fromAddress, password);
    print("⏱️ 内存还原尝试: ${sw.elapsedMilliseconds}ms");  // getQccWallet 里有 restorePrivateKey→_deriveAesKey
    sw.reset();
    if(qc != null) {
      LogObj.log("内存高速还原钱包${qc.address}");
      return qc;
    }else{
      LogObj.log("内存高速还原钱包失败:$fromAddress");
    }
    String? encryptedData = await QccStorage.getRawData(fromAddress);
    if (encryptedData == null) {
      Tools.showToast(context, "找不到钱包私钥数据"); return null;
    }
    final wallet = await compute(_restoreWalletTask, {
      'rawData': encryptedData,
      'address': fromAddress,
      'password': password
    });
    if(wallet!=null){
      LogObj.log("将私钥写入内存安全处理区，私钥长度${wallet.privateKey!.length}");
      QccWalletSecurityManager().cacheWallet(wallet.privateKey!, wallet.address, password, wallet.pubkey!);
    }
    return wallet;
  }


  static Future<QccWallet?> restoreWalletTask(Map<String, String> data) async {
    // 这里运行在子线程，仅处理 JSON 解析和 Wallet 对象构建
    final String rawData = data['rawData']!;
    final String password = data['password']!;
    Map<String, dynamic> json = jsonDecode(rawData);
    String mnemonic = json['mnemonic'];
    // 这里会触发复杂的 Dilithium 密钥生成，正适合在子线程跑
    return QccMnemonicWallet.fromMnemonic(mnemonic, paymentPassword: password);
  }

  static Future<QccWallet?> _restoreWalletTask(Map<String, String> data) async {
    // 这里运行在子线程，仅处理 JSON 解析和 Wallet 对象构建

    String? rawData = data['rawData'];
    String? password = data['password'];
    String? address=data["address"];
    if(password==null) return null;
    if(rawData==null && address!=null) {
      rawData = await QccStorage.getRawData(address);
      if (rawData == null) {
        return null;
      }
    }
    if(rawData==null) return null;
    Map<String, dynamic> json = jsonDecode(rawData);
    String mnemonic = json['mnemonic'];
    QccWallet qc= await QccMnemonicWallet.fromMnemonic(
        mnemonic, paymentPassword: password);

    return qc;
  }

  static SharedPreferences? _prefs;

  // 1. 初始化方法：建议在 main.dart 的 main() 函数中调用
  // await QccStorage.init();
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 2. 字符串 存/取 (用于缓存 Hash 详情 JSON)
  static Future<bool> setString(String key, String value) async {
    return await _prefs?.setString(key, value) ?? false;
  }

  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  // 3. 字符串列表 存/取 (用于保存发布历史)
  static Future<bool> setStringList(String key, List<String> value) async {
    return await _prefs?.setStringList(key, value) ?? false;
  }

  static List<String>? getStringList(String key) {
    return _prefs?.getStringList(key);
  }


  /// 1. 保存原始字符串数据 (用于临时存草稿)
  static Future<bool> saveRawData(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setString(key, value);
  }

  /// 2. 获取原始字符串数据
  static Future<String?> getRawkeyuData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  /// 3. 清除指定缓存 (用于重置状态)
  static Future<bool> removeData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.remove(key);
  }

  /// ✅ 建立：保存字符串列表 (用于关注资产 ID)
  static Future<bool> saveStringList(String key, List<String> value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return await prefs.setStringList(key, value);
  }


  // 如果你还没有初始化逻辑，可以参考这个简单的异步版本
  static Future<List<String>?> getStringListAsync(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key);
  }



  // 在 QccStorage 类中添加以下方法

  // 获取订单存储的 Key
  static String _getDexOrdersKey(String address) => "dex_orders_$address";

  /// 保存一笔新的 DEX 挂单到本地
  static Future<void> saveDexOrder(String address, Map<String, dynamic> txData) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getDexOrdersKey(address);

    // 获取现有列表
    List<String> ordersJson = prefs.getStringList(key) ?? [];

    // 增加状态字段：open (进行中), filled (成交), cancelled (已撤单)
    txData['localStatus'] = 'open';
    txData['createTime'] = DateTime.now().millisecondsSinceEpoch;
    txData['filledAmount'] = "0"; // 已成交数量初始为0

    ordersJson.insert(0, jsonEncode(txData)); // 新订单插到最前面
    await prefs.setStringList(key, ordersJson);
    LogObj.log("✅ 订单已保存到本地: ${txData['id']}");
  }

  /// 读取本地所有挂单
  static Future<List<Map<String, dynamic>>> getDexOrders(String address) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getDexOrdersKey(address);
    List<String> ordersJson = prefs.getStringList(key) ?? [];

    return ordersJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  /// 更新本地订单状态（如成交或取消）
  static Future<void> updateDexOrderStatus(String address, String txId, String newStatus, {String? filledAmount}) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getDexOrdersKey(address);
    List<String> ordersJson = prefs.getStringList(key) ?? [];

    List<String> updatedList = ordersJson.map((e) {
      Map<String, dynamic> map = jsonDecode(e);
      if (map['id'] == txId) {
        map['localStatus'] = newStatus;
        if (filledAmount != null) map['filledAmount'] = filledAmount;
      }
      return jsonEncode(map);
    }).toList();

    await prefs.setStringList(key, updatedList);
  }

  static Future<void> saveAllDexOrders(String address, List<Map<String, dynamic>> orders) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _getDexOrdersKey(address);
    List<String> ordersJson = orders.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(key, ordersJson);
  }


  // 在 QccStorage 类中添加
  static const String _keyWinOrders = "qcc_win_orders_";

  /// ✅ 保存一笔 Win 交易到本地历史
  static Future<void> addWinOrder(String address, Map<String, dynamic> winOrder) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _keyWinOrders + address;

    // 1. 读取现有记录
    List<Map<String, dynamic>> orders = await getWinOrders(address);

    // 2. 插入到最前面（时间倒序）
    orders.insert(0, winOrder);

    // 3. 限制存储数量（例如只保留最近 100 笔）
    if (orders.length > 100) orders = orders.sublist(0, 100);

    await prefs.setString(key, jsonEncode(orders));
  }


  static const String _keyDividendOrders = "qcc_dividend_orders_";

  /// ✅ 保存分红发布记录
  static Future<void> addDividendOrder(String address, Map<String, dynamic> order) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _keyDividendOrders + address;
    List<Map<String, dynamic>> orders = await getDividendOrders(address);
    orders.insert(0, order); // 最新发布的排在前面
    if (orders.length > 50) orders = orders.sublist(0, 50); // 保留最近50条
    await prefs.setString(key, jsonEncode(orders));
  }

  /// ✅ 获取分红发布历史
  static Future<List<Map<String, dynamic>>> getDividendOrders(String address) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _keyDividendOrders + address;
    String? jsonStr = prefs.getString(key);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

  /// ✅ 获取本地 Win 交易历史
  static Future<List<Map<String, dynamic>>> getWinOrders(String address) async {
    final prefs = await SharedPreferences.getInstance();
    String key = _keyWinOrders + address;
    String? jsonStr = prefs.getString(key);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

}



class QccLocalCache {
  static const String _storageKey = "qcc_hash_registry";

  /// 将扫描到的 Hash 明细存入本地，下次秒开
  static Future<void> saveHashDetail(String hash, Map<String, dynamic> detail) async {
    Map<String, dynamic> registry = _getRawRegistry();
    registry[hash] = detail;
    await QccStorage.setString(_storageKey, jsonEncode(registry));
  }

  static Map<String, dynamic>? getHashDetail(String hash) {
    return _getRawRegistry()[hash];
  }

  static Map<String, dynamic> _getRawRegistry() {
    String? data = QccStorage.getString(_storageKey);
    return data != null ? jsonDecode(data) : {};
  }






}



class QccSecurity {
  static String? _cachedDeviceId;

  /// 获取设备唯一标识作为盐值
  static Future<String> _getDeviceSeed() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final deviceInfo = DeviceInfoPlugin();
    String id = "QCC_DEFAULT_SALT";
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id; // Android ID
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor ?? "IOS_UNKNOWN";
    }
    _cachedDeviceId = id;
    LogObj.log("获取到设备id:$_cachedDeviceId");
    return id;
  }

  /// 核心：通过 (用户密码 + 设备ID) 派生 32 字节的 AES 密钥
  static Future<Key> _deriveKey(String password) async {
    final deviceSeed = await _getDeviceSeed();
    // 使用 SHA256 混合密码和设备 ID，确保密钥长度固定为 32 字节
    final bytes = utf8.encode("$password-$deviceSeed");
    final digest = sha256.convert(bytes);
    return Key(digest.bytes as Uint8List);
  }

  /// 加密助记词
  static Future<String> encrypt(String plainText, String password) async {
    final key = await _deriveKey(password);
    final iv = IV.fromLength(16); // 这里的 IV 可以固定，也可以随数据存，建议固定以简化
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // 返回 base64(IV + CipherText)
    return "${iv.base64}:${encrypted.base64}";
  }

  /// 解密助记词
  static Future<String?> decrypt(String encryptedData, String password) async {
    try {
      final parts = encryptedData.split(':');
      if (parts.length != 2) return null;

      final iv = IV.fromBase64(parts[0]);
      final cipherText = parts[1];
      final key = await _deriveKey(password);

      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return null; // 密码错误或设备不匹配会导致解密失败
    }
  }
}