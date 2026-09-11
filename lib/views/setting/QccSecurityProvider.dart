import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class QccSecurityProvider {
  static const _storage = FlutterSecureStorage();
  static const String _pwdHashKey = "qcc_pay_pwd_hash";

  // 1. 保存支付密码（存哈希值）
  static Future<void> savePayPassword(String password) async {
    var bytes = utf8.encode(password);
    var hash = sha256.convert(bytes).toString();
    await _storage.write(key: _pwdHashKey, value: hash);
  }

  // 2. 验证支付密码是否正确
  static Future<bool> verifyPassword(String input) async {
    String? storedHash = await _storage.read(key: _pwdHashKey);
    if (storedHash == null) return false;

    var inputBytes = utf8.encode(input);
    var inputHash = sha256.convert(inputBytes).toString();
    return storedHash == inputHash;
  }

  // 3. 判断是否已经设置过密码
  static Future<bool> hasSetPassword() async {
    String? storedHash = await _storage.read(key: _pwdHashKey);
    return storedHash != null && storedHash.isNotEmpty;
  }
}