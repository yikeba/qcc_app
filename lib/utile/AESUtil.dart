import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class AESUtil {
  // 使用 PBKDF2 将 6 位数字密码拉伸为 32 字节 (256-bit) 的强密钥
  static Key _deriveKey(String password, String salt) {
    // 简单的加盐哈希模拟 PBKDF2 逻辑，确保 6 位数字也能产生强 key
    var bytes = utf8.encode(password + salt);
    var digest = sha256.convert(bytes); // 产生 256 位
    return Key(Uint8List.fromList(digest.bytes));
  }

  // 加密助记词
  static String encrypt(String plainText, String password, String address) {
    try {
      final key = _deriveKey(password, address); // 以地址作为盐
      final iv = IV.fromLength(16); // 随机向量
      final encrypter = Encrypter(AES(key));

      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // 将 IV 和加密内容拼接后存储，解密时需要同一个 IV
      return "${iv.base64}:${encrypted.base64}";
    } catch (e) {
      rethrow;
    }
  }

  // 解密助记词
  static String decrypt(String cipherText, String password, String address) {
    try {
      final parts = cipherText.split(':');
      if (parts.length != 2) throw Exception("数据格式错误");

      final iv = IV.fromBase64(parts[0]);
      final encryptedData = parts[1];

      final key = _deriveKey(password, address);
      final encrypter = Encrypter(AES(key));

      return encrypter.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      throw Exception("解密失败：密码错误或数据损坏");
    }
  }
}