import 'dart:convert';
import 'dart:typed_data';
import 'package:liboqs/liboqs.dart';
import 'package:convert/convert.dart';
import 'package:qcc_flutter/utile/LogObj.dart'; // 用于 hex 处理

class QccLibOqsSigner {
  static const String algoName = 'Dilithium5';

  /// 使用 Java 端生成的 7456 字节私钥进行签名
  /// [privateKeyHex] 是你在 Java 端打印的那个 14912 长度的 Hex 字符串
  /// 这里的算法必须指定为 ML-DSA-87 以匹配 Java 的 Dilithium5
  static Uint8List sign(String privateKeyHex,String message) {
    // 1. 创建签名对象 (对应 Java 的 Dilithium5)
    final sig = Signature.create('ML-DSA-87');
    try {
      final msgBytes = Uint8List.fromList(utf8.encode(message));
      final skBytes = Uint8List.fromList(hex.decode(privateKeyHex));
      LogObj.log("测试签名内容byte长度:${msgBytes.length}  测试签名私钥长度${skBytes.length}");
      // 2. 直接调用签名方法
      // liboqs 会处理底层的 C 语言实现，确保与 FIPS 204 标准一致
      final signature = sig.sign(msgBytes, skBytes);
      //LogObj.log("测试签名byte长度:${signature.length}");
      return signature;
    } finally {
      // 3. 按照 1.2.0 规范使用 dispose() 或 free()
      sig.dispose();
    }
  }


  static Uint8List signUint8List(String privateKeyHex,Uint8List msgBytes) {
    // 1. 创建签名对象 (对应 Java 的 Dilithium5)
    final sig = Signature.create('ML-DSA-87');
    try {
      final skBytes = Uint8List.fromList(hex.decode(privateKeyHex));
      LogObj.log("测试签名内容byte长度:${msgBytes.length}  测试签名私钥长度${skBytes.length}");
      // 2. 直接调用签名方法
      // liboqs 会处理底层的 C 语言实现，确保与 FIPS 204 标准一致
      final signature = sig.sign(msgBytes, skBytes);
      //LogObj.log("测试签名byte长度:${signature.length}");
      return signature;
    } finally {
      // 3. 按照 1.2.0 规范使用 dispose() 或 free()
      sig.dispose();
    }
  }


  static Uint8List signByte(Uint8List privateKey,String message) {
    // 1. 创建签名对象 (对应 Java 的 Dilithium5)
    final sig = Signature.create('ML-DSA-87');
    try {
      final msgBytes = Uint8List.fromList(utf8.encode(message));
      final skBytes = privateKey;
      LogObj.log("测试签名内容byte长度:${msgBytes.length}  测试签名私钥长度${skBytes.length}");
      // 2. 直接调用签名方法
      // liboqs 会处理底层的 C 语言实现，确保与 FIPS 204 标准一致
      final signature = sig.sign(msgBytes, skBytes);
      //LogObj.log("测试签名byte长度:${signature.length}");
      return signature;
    } finally {
      // 3. 按照 1.2.0 规范使用 dispose() 或 free()
      sig.dispose();
    }
  }

  /// 验证签名
  static bool verifySignature(String message, Uint8List signature, String publicKeyHex) {
    Uint8List pkBytes = Uint8List.fromList(hex.decode(publicKeyHex));
    final verifier = Signature.create('ML-DSA-87');
    try {
      return verifier.verify(
          Uint8List.fromList(message.codeUnits),
          signature,
          pkBytes
      );
    } finally {
      verifier.dispose();
    }
  }

}