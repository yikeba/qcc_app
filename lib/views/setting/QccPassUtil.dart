import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

class QccPassUtil {
  final String address;
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // 构造函数：用地址实例化，确保密码管理与地址绑定
  QccPassUtil(this.address);

  // 存储 Key 的前缀，每个地址拥有独立的存储位
  String get _pwdHashKey => "qcc_hash_$address";
  String get _walletDataKey => "qcc_data_$address";

  // --- 1. 判断该地址是否设置过支付密码 ---
  Future<bool> hasSetPassword() async {
    String? hash = await _storage.read(key: _pwdHashKey);
    return hash != null && hash.isNotEmpty;
  }

  // --- 2. 创建新的支付密码 ---
  // 同时保存密码哈希和加密后的钱包数据（由密码派生 key）
  Future<void> createPassword(String newPassword, String mnemonic) async {
    // A. 保存密码哈希（用于日常校验）
    try {
      String hash = _generateHash(newPassword);
      await _storage.write(key: _pwdHashKey, value: hash);
      // B. 使用密码作为密钥，加密保存助记词
      // 注意：这里体现了“支付密码-密钥对匹配”，密码改了，Key就变了
      String encryptedData = _encryptMnemonic(mnemonic, newPassword);
      await _storage.write(key: _walletDataKey, value: encryptedData);
    }catch(e){
      LogObj.log("创建密码密钥加密的本地存储错误$e");
    }
  }

  // --- 3. 验证支付密码 ---
  Future<bool> verifyPassword(String input) async {
    String? storedHash = await _storage.read(key: _pwdHashKey);
    if (storedHash == null) return false;
    return _generateHash(input) == storedHash;
  }

  // --- 4. 更改支付密码 (关键：涉及数据迁移) ---
  // 必须先输入旧密码，解密出私钥，再用新密码重新加密存储
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    // A. 验证旧密码
    if (!await verifyPassword(oldPassword)) return false;

    // B. 尝试解密旧数据获取助记词
    String? encryptedData = await _storage.read(key: _walletDataKey);
    if (encryptedData == null) return false;

    try {
      String mnemonic = _decryptMnemonic(encryptedData, oldPassword);

      // C. 用新密码重新覆盖存储
      await createPassword(newPassword, mnemonic);
      return true;
    } catch (e) {
      // 如果解密失败（说明密码/密钥对匹配损坏），更改失败
      return false;
    }
  }

  // --- 辅助加密方法 (简易版方案，实际可使用 AES 库) ---
  String _generateHash(String input) {
    return sha256.convert(utf8.encode(input + "qcc_salt")).toString();
  }

  String _encryptMnemonic(String data, String password) {
    // 实际生产建议引入 encrypt 库进行 AES 加密
    // 这里演示逻辑：将助记词与密码哈希进行 Base64 混合存储
    return base64Encode(utf8.encode(data + "|" + _generateHash(password)));
  }

  String _decryptMnemonic(String encrypted, String password) {
    String decoded = utf8.decode(base64Decode(encrypted));
    List<String> parts = decoded.split("|");
    if (parts.last == _generateHash(password)) {
      return parts.first;
    }
    throw Exception("解密失败：密码与密钥对不匹配");
  }
}