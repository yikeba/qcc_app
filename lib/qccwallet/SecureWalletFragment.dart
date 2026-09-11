import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:developer' as LogObj;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/digests/sha3.dart';

import 'QccWallet.dart';

/// 安全碎片类：在内存中存储加密后的私钥片段
class SecureWalletFragment {
  final String address;
  final String publicKey;
  final List<String> encryptedShards; // 加密后的私钥碎片
  final String ivBase64;              // ✅ 修复：必须存储加密时使用的 IV

  SecureWalletFragment({
    required this.address,
    required this.publicKey,
    required this.encryptedShards,
    required this.ivBase64,
  });
}

/// 钱包安全管理类：单例模式
class QccWalletSecurityManager {
  // 私有构造函数
  QccWalletSecurityManager._internal();
  static final QccWalletSecurityManager _instance = QccWalletSecurityManager._internal();
  factory QccWalletSecurityManager() => _instance;

  // 内存缓存容器
  final Map<String, SecureWalletFragment> _cache = {};

  // ✅ 性能优化：复用 SHA3 实例，避免在循环中重复创建
  final SHA3Digest _sha3digest = SHA3Digest(256);

  /// 1. 初始化并存入缓存
  /// [privateKey] 原始私钥字符串 (Hex 或 Base64)
  /// [address] 钱包地址
  /// [password] 支付密码 (用于派生 AES Key)
  /// [publicKey] 公钥明码
  void cacheWallet(String privateKey, String address, String password, String publicKey) {
    try {
      // A. 生成 AES 密钥：基于 SHA3-256(address + password) 迭代
      final key = _deriveAesKey(address, password);

      // B. 生成随机 IV 并转换为 Base64 存储
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      // C. 私钥随机切片
      List<String> shards = _splitStringRandomly(privateKey, 10);

      // D. 对每一份进行加密
      List<String> encryptedShards = shards.map((s) {
        return encrypter.encrypt(s, iv: iv).base64;
      }).toList();

      // E. 存入内存 Map
      _cache[address] = SecureWalletFragment(
        address: address,
        publicKey: publicKey,
        encryptedShards: encryptedShards,
        ivBase64: iv.base64, // ✅ 关键：保存这个 IV 以供还原
      );

      LogObj.log("💾 [SecurityManager] 钱包分片加密成功并存入内存: $address (私钥长度: ${privateKey.length})");
    } catch (e) {
      LogObj.log("❌ [SecurityManager] 缓存钱包失败: $e");
    }
  }

  /// 2. 获取完整的 QccWallet 对象
  QccWallet? getQccWallet(String address, String password) {
    final fragment = _cache[address];
    if (fragment == null) {
      LogObj.log("⚠️ [SecurityManager] 内存中不存在该地址的缓存: $address");
      return null;
    }

    String? priKey = restorePrivateKey(address, password);
    if (priKey == null) {
      LogObj.log("❌ [SecurityManager] 私钥还原失败，检查密码是否正确: $address");
      return null;
    }

    return QccWallet.fromStr(
      address: address,
      privateKey: priKey,
      pubkey: fragment.publicKey,
      mnemonic: "", // 内存中不建议常驻助记词，仅保留私钥用于签名
    );
  }

  /// 3. 还原私钥字符串
  String? restorePrivateKey(String address, String password) {
    final fragment = _cache[address];
    if (fragment == null) return null;

    try {
      final key = _deriveAesKey(address, password);
      // ✅ 修复：使用缓存中存储的同一个 IV 进行解密
      final iv = encrypt.IV.fromBase64(fragment.ivBase64);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      // 逐个解密碎片并拼接
      StringBuffer sb = StringBuffer();
      for (var encryptedData in fragment.encryptedShards) {
        final decrypted = encrypter.decrypt64(encryptedData, iv: iv);
        sb.write(decrypted);
      }

      String result = sb.toString();
      // LogObj.log("✅ [SecurityManager] 私钥解密还原成功，长度: ${result.length}");
      return result;
    } catch (e) {
      LogObj.log("❌ [SecurityManager] 解密异常 (IV或Key不匹配): $e");
      return null;
    }
  }

  /// 4. 工具方法：派生 AES 密钥 (SHA3-256 迭代)
  encrypt.Key _deriveAesKey(String address, String password) {
    final sw = Stopwatch()..start();
    Uint8List bytes = Uint8List.fromList(utf8.encode(address + password));

    // 执行 1000 次哈希增加暴力破解成本
    for (int i = 0; i < 1000; i++) {
      _sha3digest.reset();
      _sha3digest.update(bytes, 0, bytes.length);
      final output = Uint8List(32);
      _sha3digest.doFinal(output, 0);
      bytes = output;
    }
    print("⏱️ _deriveAesKey 1000次SHA3: ${sw.elapsedMilliseconds}ms");
    return encrypt.Key(bytes);
  }

  /// 5. 工具方法：将私钥字符串随机切分为 N 份
  List<String> _splitStringRandomly(String str, int n) {
    List<String> result = [];
    int len = str.length;
    if (len < n) return [str]; // 长度太短则不分片

    List<int> points = [0, len];
    Random rand = Random();

    while (points.length < n + 1) {
      int p = rand.nextInt(len);
      if (!points.contains(p) && p != 0) points.add(p);
    }
    points.sort();

    for (int i = 0; i < points.length - 1; i++) {
      result.add(str.substring(points[i], points[i + 1]));
    }
    return result;
  }

  /// 清除内存（如用户登出、App 进入后台过久）
  void clear() {
    _cache.clear();
    LogObj.log("🧹 [SecurityManager] 内存钱包缓存已清空");
  }
}