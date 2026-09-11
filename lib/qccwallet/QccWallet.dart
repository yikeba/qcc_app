/// QCC 助记词钱包 — Dart/Flutter 完整实现
/// 字节格式与 Java BouncyCastle 版本完全对齐（实测校验）
///
/// 实测数据：
///   privateKey.serialize() = 4864 字节（Dilithium5 标准私钥）
///   publicKey.serialize()  = 2592 字节（rho(32) + t1(2560)）
///   Java rawPrivKey        = 4864 + 2592 = 7456 字节 ✅
///   Java rawPrivKey 构成   = stdPriv(4864) + fullPubKey(2592)
///                           即：rho+K+tr+s1+s2+t0  +  rho+t1
///
/// pubspec.yaml 依赖：
///   bip39: ^1.0.6
///   dilithium_crypto: ^1.0.2
///   pointycastle: ^3.9.1
///   convert: ^3.1.1

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import 'package:liboqs/liboqs.dart';
import 'package:pointycastle/export.dart' hide Signature;
import 'AddressTool.dart';
import 'MLDSA87Sizes.dart';
// ════════════════════════════════════════════════════════
// 数据模型
// ════════════════════════════════════════════════════════

class QccWallet {
  final String address;
  String? mnemonic;
  String? privateKey;
  String? pubkey;
  bool isHidden=true; // 是否手动永久隐藏
  DateTime? muteUntil; // 屏蔽截止时间，允许为 null

  QccWallet({
    required this.address,
    this.mnemonic,
    this.isHidden = false, // 默认不隐藏
    this.muteUntil,        // 默认为空，即不屏蔽
  });

  QccWallet.fromStr({
    required this.address,
    this.privateKey,
    this.pubkey,
    this.mnemonic
  });

  // 观察者模式工厂方法
  factory QccWallet.watchOnly(String address) {
    return QccWallet(address: address);
  }

  // 计算属性：判断当前是否应该在列表中显示
  bool get isVisible {
    // 1. 如果被永久隐藏，直接不显示
    if (isHidden) return false;
    // 2. 如果设置了屏蔽时间，且时间还没到，则不显示
    if (muteUntil != null && muteUntil!.isAfter(DateTime.now())) {
      return false;
    }
    return true;
  }

  Uint8List get privateKeyBytes => Uint8List.fromList(hex.decode(privateKey!));
  Uint8List get publicKeyBytes  => Uint8List.fromList(hex.decode(pubkey!));

  @override
  String toString() => 'QccWallet(\n'
      '  address   : $address\n'
      '  pubKeyLen : ${pubkey!.length ~/ 2} 字节（期望 ${_D5.pubKeyLen}）\n'
      '  privKeyLen: ${privateKey!.length ~/ 2} 字节（期望 ${_D5.rawPrivLen}）\n'
      '  mnemonic  : ${mnemonic!.split(' ').take(4).join(' ')} ...\n'
      ')';
}


/// 1. 种子派生器 (你提供的 PBKDF2 实现)
class SeedDeriver {
  static Uint8List deriveSeed({
    required String mnemonic,
    required String paymentPassword,
    int seedLength = 32, // Dilithium5 需要 32 字节种子
    int iterations = 210000,
  }) {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw ArgumentError('无效的助记词');
    }
    final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic.trim()));
    // 盐中使用 ML-DSA-87 标识，确保即使密码相同，不同算法生成的种子也不同
    final salt = Uint8List.fromList(
        utf8.encode('ML-DSA-87:qcc-wallet:$paymentPassword')
    );

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128));
    pbkdf2.init(Pbkdf2Parameters(salt, iterations, seedLength));

    return pbkdf2.process(mnemonicBytes);
  }
}


// 注意：这里需要依赖你之前那个能根据 Seed 生成 Dilithium5 密钥组件的库
// 假设该库的调用方式仍为 Dilithium.generateKeyPair

class QccMnemonicWallet {
  // liboqs 1.2.0 对应的 FIPS 204 标准名称
  static const String _algoName = 'ML-DSA-87';

  /// 2. 验证助记词合法性
  static bool validateMnemonic(String mnemonic) {
    return bip39.validateMnemonic(mnemonic);
  }

  /// 利用 liboqs 的量子安全随机源生成 24 个助记词
  static String generateRandomMnemonic() {
    // 1. 直接获取 liboqs 产生的 32 字节安全随机数
    final Uint8List entropy = OQSRandom.generateBytes(32);
    // 2. 将这 32 字节熵转换为 24 个助记词
    // bip39.entropyToMnemonic 接受 256bit 熵并生成 24 个单词
    return bip39.entropyToMnemonic(hex.encode(entropy));
  }

  /// 随机创建新钱包 (完全通过 liboqs)
  static QccWallet createRandom() {
    // 1. 生成助记词
    final mnemonic = generateRandomMnemonic();
    // 2. 初始化 liboqs 签名器
    final sig = Signature.create(_algoName);
    try {
      // 3. 直接生成标准密钥对 (4896字节私钥, 2592字节公钥)
      final keyPair = sig.generateKeyPair();
      final pubHex = hex.encode(keyPair.publicKey);
      final privHex = hex.encode(keyPair.secretKey);
      // 4. 生成 Q 地址
      final address = AddressTool.createAddress(pubHex);
      return QccWallet.fromStr(
        address: address!,
        privateKey: privHex,
        pubkey: pubHex,
        mnemonic: mnemonic,
      );
    } finally {
      sig.dispose();
    }
  }
  /// 3. 【核心逻辑】从助记词恢复钱包
  static Future<QccWallet> fromMnemonic(String mnemonic, {required String paymentPassword}) async {
    // Step A: 派生确定性种子
    final seed = _deriveSeed(mnemonic, paymentPassword);
    if(Platform.isMacOS){
      LogObj.log("在mac 上派生种子数据长度${seed.length}");
    }
    return await _generateWalletInternal(mnemonic, seed);

  }


  /// 内部异步生成逻辑
  static Future<QccWallet> _generateWalletInternal(String mnemonic, Uint8List seed) async {
    // 调用你新提供的兼容类
    try {
      final keyPair = await DeterministicMLDSA87.generateFromSeed(seed);
      // 获取标准字节流
      final publicKey = keyPair.publicKey; // 2592 字节
      final secretKey = keyPair.secretKey; // 4896 字节 (FIPS 204 标准)

      final pubHex = hex.encode(publicKey);
      final privHex = hex.encode(secretKey);


      // Step C: 生成地址
      final address = AddressTool.createAddress(pubHex);
      LogObj.log("生成的地址: $address");
      if (address == null) throw Exception("地址生成失败，请检查公钥格式");
      return QccWallet.fromStr(
        address: address,
        privateKey: privHex,
        pubkey: pubHex,
        mnemonic: mnemonic,
      );
    }catch(e){
      LogObj.log("QCC DEBUG_:生成密钥错误$e");
       throw Exception("地址生成失败，请检查公钥格式");
    }

  }

  /// 5. 内部种子派生函数 (PBKDF2-SHA512)
  static Uint8List _deriveSeed(String mnemonic, String password) {
    final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic.trim()));
    final salt = Uint8List.fromList(
        utf8.encode('ML-DSA-87:qcc-wallet:$password'));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128));
    pbkdf2.init(Pbkdf2Parameters(salt, 210000, 32));
    return pbkdf2.process(mnemonicBytes);
  }

}
class _Base58 {
  static const _chars =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static String encode(Uint8List input) {
    int zeros = 0;
    for (final b in input) {
      if (b == 0) zeros++;
      else break;
    }
    BigInt value = BigInt.zero;
    for (final b in input) {
      value = value * BigInt.from(256) + BigInt.from(b);
    }
    final buf = <String>[];
    final base = BigInt.from(58);
    while (value > BigInt.zero) {
      buf.add(_chars[(value % base).toInt()]);
      value ~/= base;
    }
    for (int i = 0; i < zeros; i++) buf.add(_chars[0]);
    return buf.reversed.join();
  }
}

class _D5 {
  static const int stdPrivLen = 4864; // privateKey.serialize() 实测值
  static const int pubKeyLen  = 2592; // publicKey.serialize()  实测值
  // Java getRawPrivateKeyBytes = stdPriv + fullPubKey = 4864 + 2592 = 7456
  static const int rawPrivLen = stdPrivLen + pubKeyLen; // 7456
}