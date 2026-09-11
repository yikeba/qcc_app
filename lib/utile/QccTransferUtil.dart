import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/digests/sha3.dart';
import 'package:pointycastle/export.dart'; // 用于 SHA3Digest

class QccTransferUtil {
  static const String _PREFIX = "QCC_SECURE_V2:";
  static const String _SALT_STR = "QCC_V1_RECOVERY_SALT";

  /// ✅ 统一的密钥派生方法 (确保编解码一致)
  static Uint8List _deriveKey(String password, String exportCode) {
    final salt = utf8.encode(_SALT_STR);
    final combinedInput = "$password-$exportCode";

    Uint8List seed = Uint8List.fromList(utf8.encode(combinedInput));

    for (int i = 0; i < 1000; i++) {
      // 在 Dart 中 Uint8List 拼接需要通过 Builder 或 List
      final List<int> combined = List.from(seed)..addAll(salt);
      seed = sha3256(combined);
    }
    return seed;
  }

  /// ✅ 导出逻辑
  static Future<String> encodeToQrData({
    required String mnemonic,
    required String paymentPassword,
    required String exportCode,
  }) async {
    // 1. 派生密钥
    final keySeed = _deriveKey(paymentPassword, exportCode);
    final key = encrypt.Key(keySeed);

    // 2. 准备 IV (16字节)
    final iv = encrypt.IV.fromLength(16);

    // 3. AES 加密 (CBC 模式)
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(mnemonic, iv: iv);

    // 4. 组合数据并压缩
    final payload = "${iv.base64}:${encrypted.base64}";
    final compressed = GZipEncoder().encode(utf8.encode(payload))!;

    return "$_PREFIX${base64Encode(Uint8List.fromList(compressed))}";
  }

  /// ✅ 恢复逻辑 (已修复)
  static Future<String?> decodeFromQrData(
      String qrString,
      String paymentPassword,
      String exportCode,
      ) async {
    try {
      // 1. 校验前缀 (必须是 V2)
      if (!qrString.startsWith(_PREFIX)) return null;

      // 2. Base64 解码数据
      final base64Part = qrString.replaceFirst(_PREFIX, "");
      final compressed = base64Decode(base64Part);

      // 3. GZip 解压
      final decompressed = GZipDecoder().decodeBytes(compressed);
      final payload = utf8.decode(decompressed);

      // 4. 拆分 IV 和 CipherText
      final parts = payload.split(':');
      if (parts.length != 2) return null;

      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipherText = parts[1];

      // 5. 使用统一逻辑派生相同的 Key
      final keySeed = _deriveKey(paymentPassword, exportCode);
      final key = encrypt.Key(keySeed);

      // 6. AES 解密
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      // 如果密码或验证码错误，这里会抛出异常
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      // 解密失败（Padding 错误等）均返回 null
      return null;
    }
  }

  /// ✅ SHA3-256 实现
  static Uint8List sha3256(List<int> input) {
    final digest = SHA3Digest(256);
    final inputBytes = Uint8List.fromList(input);
    final output = Uint8List(32);
    digest.update(inputBytes, 0, inputBytes.length);
    digest.doFinal(output, 0);
    return output;
  }
}