import 'dart:convert';
import 'dart:developer' as LogObj;
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:qcc_flutter/qccwallet/QccLibOqsSigner.dart';

import 'QccPacket.dart';
import 'EntityData.dart';
import 'package:convert/convert.dart';

class QccDataProtocol {
  static final Random _random = Random.secure();

  // 模拟客户端编码：TransactionData -> QccPacket
  static Future<QccPacket> encodeTransaction({
    required String payloadJson,
    required String privateKeyHex, // 后量子私钥
    required String publicKeyHex,  // 后量子公钥
  }) async {
    // 2. 执行本地 Dilithium5 签名 (这里调用你已有的签名库)
    // 签名对象是 payloadJson 字符串
    if (payloadJson.isEmpty) {
      throw Exception("无法从服务端获取交易对象");
    }
    // Step 2: 签名 (关键点：直接对 payloadJson 字符串进行签名)
    // 对应 Java: WalletSigner.sign(payloadJson, privKey)
    /*  Uint8List signatureBytes = QccLibOqsSigner.sign(
        privateKeyHex,
        payloadJson
    );
    String signature = hex.encode(signatureBytes);
    LogObj.log("🛡️ 签名原始字节长度: ${signatureBytes.length}"); // 理论上应为 4595
    LogObj.log("🛡️ 签名 Hex 字符串长度: ${signature.length}"); // 理论上应为 9190*/
    // 3. 构造 Packet
    return QccPacket(
      publicKey: publicKeyHex,
      signature: "",
      payloadJson: payloadJson,
      clientTime: DateTime.now().millisecondsSinceEpoch,
      nonce: _random.nextInt(100000000),
    );
  }


  // 模拟客户端编码：TransactionData -> QccPacket
  static Future<QccPacket> encodeByteTransaction({
    required Uint8List mesbyte,
    required String privateKeyHex, // 后量子私钥
    required String publicKeyHex,  // 后量子公钥
  }) async {
    // Step 2: 签名 (关键点：直接对 payloadJson 字符串进行签名)
    // 对应 Java: WalletSigner.sign(payloadJson, privKey)
    Uint8List signatureBytes = QccLibOqsSigner.signUint8List(
        privateKeyHex,
        mesbyte
    );
    String signature = hex.encode(signatureBytes);
    LogObj.log("🛡️ 签名原始字节长度: ${signatureBytes.length}"); // 理论上应为 4595
    LogObj.log("🛡️ 签名 Hex 字符串长度: ${signature.length}"); // 理论上应为 9190
    // 3. 构造 Packet
    return QccPacket(
      publicKey: publicKeyHex,
      signature: signature,
      payloadJson:  base64UrlEncode(signatureBytes.toList()),
      clientTime: DateTime.now().millisecondsSinceEpoch,
      nonce: _random.nextInt(100000000),
    );
  }

  // ================================================================
  //  存证数据(EntityData) 客户端编码：EntityData -> QccPacket
  //  逐字对应 Java QccDataProtocol.encodeEntityData()：
  //    1. 签名对象是 data.getPayloadForHash()（一段"|"拼接的短字符串），
  //       不是 toBytes() 的二进制、也不是 JSON。
  //    2. packet.payloadJson 字段名带 Json，但实际塞的是
  //       base64UrlEncode(data.toBytes())——纯二进制透传，Java 源码里连
  //       QccDataBaseFactory.toJson(data) 那一行都注释掉了，特意改成这样。
  //    3. nonce 对应 Java SecureRandom.nextLong()——一个可正可负的完整
  //       64位有符号整数，不是 0~1e8 的小范围随机数（那是上面两个旧方法
  //       历史遗留的近似值，这里不沿用）。
  // ================================================================
  static Future<QccPacket> encodeEntityData({
    required EntityData data,
    required String privateKeyHex, // 后量子私钥
    required String publicKeyHex,  // 后量子公钥
  }) async {
    // 【放进 compute() 里跑】dataDigest 需要对最大 1MB 的 payload 做一次
    // SHA3-256（ensureLocalFields()/getPayloadForHash()/toBytes() 内部都
    // 依赖它），"测试十万次"这种量级下不该占用 UI isolate——这一步原来是
    // 由调用方(QccDataBroadcastPage.dart)自己包 compute()，现在收进协议层
    // 统一处理，调用方不用再关心"要不要开子线程"这件事。
    return compute(_encodeEntityDataIsolate, {
      'assetId': data.assetId,
      'from': data.from,
      'fromdev': data.fromdev,
      'timestamp': data.timestamp,
      'chain': data.chain,
      'payload': data.payload,
      'privateKeyHex': privateKeyHex,
      'publicKeyHex': publicKeyHex,
    });
  }

  /// 在子 isolate 里执行的实际编码逻辑。参数只用 Map/基础类型/Uint8List，
  /// 保证能安全跨 isolate 传递(和原来 QccDataBroadcastPage.dart 里
  /// _signEntityTask 的做法一致，这里只是把它挪到协议层集中管理)。
  static QccPacket _encodeEntityDataIsolate(Map<String, dynamic> args) {
    final entity = EntityData();
    entity.assetId = args['assetId'] as String?;
    entity.from = args['from'] as String?;
    entity.fromdev = args['fromdev'] as String?;
    entity.timestamp = args['timestamp'] as int;
    entity.chain = args['chain'] as String;
    entity.payload = args['payload'] as Uint8List?;

    // 先 finalizeId()（内部含 validateNoReservedChar() 校验 + 计算 id），
    // 再取 getPayloadForHash() 去签——和 Java getTxHash()/encodeEntityData()
    // 的调用顺序一致。
    entity.finalizeId();
    final String signData = entity.getPayloadForHash();

    final Uint8List signatureBytes = QccLibOqsSigner.sign(
      args['privateKeyHex'] as String,
      signData,
    );
    final String signature = hex.encode(signatureBytes);

    return QccPacket(
      publicKey: args['publicKeyHex'] as String,
      signature: signature,
      payloadJson: base64UrlEncode(entity.toBytes()),
      clientTime: DateTime.now().millisecondsSinceEpoch,
      nonce: _randomInt64(),
    );
  }

  /// 模拟 Java SecureRandom.nextLong()：产生一个可正可负的完整64位
  /// 有符号整数(逐字节拼，自然落在 Dart 64位 int 的完整取值范围内，
  /// 包含负数)，不是之前两个旧方法里 0~1e8 那种小范围近似值。
  static int _randomInt64() {
    int value = 0;
    for (int i = 0; i < 8; i++) {
      value = (value << 8) | _random.nextInt(256);
    }
    return value;
  }
}