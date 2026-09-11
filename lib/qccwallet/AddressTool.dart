import 'dart:typed_data';
import 'package:bs58/bs58.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/digests/sha3.dart';

import 'MultiSigAddrTool.dart';

/// ════════════════════════════════════════════════════════
/// QCC 单签地址生成 — 天然 34 字符定长方案 (第二次协议变更)
///
/// 与上一版 (version=0x10, "Q"+34位body=35字符) 的区别：
///   这一版直接让 Base58 编码结果本身以 'Q' 开头，不再手动
///   拼接前缀字符串——地址整体恒定 34 字符。
///
/// 精确验证（大整数运算，非对数估算）：
///   25字节数值区间 [0x3A×256^24, 0x3B×256^24) 内，
///   任意 hash20+checksum 取值，Base58 编码结果：
///     - 长度恒为 34
///     - 首字符恒为 'Q'
///   （用 Python 大整数对边界值 lo/hi 精确编码验证，
///    因编码函数单调递增，边界一致即整个区间一致）
///
/// 碰撞抗性说明：version byte 变化不影响安全性——它本身贡献
/// 0 bit 熵，真正的碰撞抗性完全由 hash20 (160 bit, SHA3-256
/// 截断) 决定，34 位方案和之前 35 位方案的碰撞概率完全相同，
/// 34 位唯一的优势是少存 1 个字符，千万级地址规模下有真实的
/// 内存收益。
///
/// ⚠️ 协议级变更：Java 端 MULTI_VERSION_BYTE 对应的单签逻辑
/// 也必须同步改为 0x3A，且用旧 0x10 生成的地址会全部作废。
/// ════════════════════════════════════════════════════════

class AddressTool {
  /// 唯一权威 version byte 来源
  static const int QCC_VERSION_BYTE = 0x3A;

  /// 对齐 Java 版 creatAddress(String publicKeyHex)
  /// 返回值恒定 34 字符，天然以 'Q' 开头，不再手动拼接前缀
  static String createAddress(String publicKeyHex) {
    if (publicKeyHex.isEmpty) return "";

    try {
      // 0. Hex 解码 (得到 2592 字节原始公钥)
      String cleanHex = publicKeyHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      Uint8List pubKeyBytes = Uint8List.fromList(hex.decode(cleanHex));

      // 1. 第一次 SHA3-256
      Uint8List hash = SHA3Digest(256).process(pubKeyBytes);

      // 取前 20 字节作为地址核心
      Uint8List hash20 = hash.sublist(0, 20);

      // 2. 构建 Versioned Payload (1 byte version + 20 bytes hash)
      Uint8List versionedPayload = Uint8List(21);
      versionedPayload[0] = QCC_VERSION_BYTE;
      versionedPayload.setRange(1, 21, hash20);

      // 3. 计算 Checksum (Double SHA3-256)
      Uint8List firstSHA = SHA3Digest(256).process(versionedPayload);
      Uint8List secondSHA = SHA3Digest(256).process(firstSHA);
      Uint8List checksum = secondSHA.sublist(0, 4);

      // 4. 拼接二进制地址 [Version + Hash20 + Checksum] (共 25 bytes)
      Uint8List binaryAddress = Uint8List(25);
      binaryAddress.setRange(0, 21, versionedPayload);
      binaryAddress.setRange(21, 25, checksum);

      // 5. 直接返回 Base58 编码结果 —— 不再手动拼 "Q" 前缀，
      //    'Q' 本身就是编码结果的天然首字符
      return base58.encode(binaryAddress);
    } catch (e) {
      print("[AddressTool] Error: $e");
      return "";
    }
  }

  /// 校验地址格式合法性（含 checksum 校验）
  static bool isValidAddress(String? address) {
    if (address == null || address.length != 34) {
      return false;
    }
    try {
      final Uint8List binaryAddress = Uint8List.fromList(base58.decode(address));

      if (binaryAddress.length != 25) {
        return false;
      }

      final version = binaryAddress[0];
      if (version != QCC_VERSION_BYTE) {
        return false;
      }

      final versionedPayload = binaryAddress.sublist(0, 21);
      final checksum = binaryAddress.sublist(21, 25);

      final firstSHA = SHA3Digest(256).process(versionedPayload);
      final secondSHA = SHA3Digest(256).process(firstSHA);

      for (int i = 0; i < 4; i++) {
        if (checksum[i] != secondSHA[i]) {
          return false;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 轻量级格式检查（不做 checksum 校验）
  /// 修复后地址长度恒定 34 字符，天然以 'Q' 开头
  static bool isValidAddressFormat(String? address) {
    if (address == null) return false;
    final reg = RegExp(r'^Q[1-9A-HJ-NP-Za-km-z]{33}$');
    return reg.hasMatch(address);
  }

  /// 【新增】转账收款地址校验：单签(Q)地址和多签(M)地址都是合法的收款
  /// 地址——多签地址本身就是一个可以正常收款、查余额的链上账户，和普通
  /// 单签地址在"能不能作为转账目标"这件事上没有区别。之前如果转账页面
  /// 只单独调 isValidAddress()（只认 Q 开头），会把合法的多签 M 地址当成
  /// 格式非法拒绝掉，导致没法转账给一个多签账户。
  ///
  /// 这里做完整校验（含 checksum），提交转账前应该用这个，而不是继续单独
  /// 调 isValidAddress()。
  static bool isValidTransferAddress(String? address) {
    return isValidAddress(address) || MultiSigAddrTool.isValidMultiSigAddress(address);
  }

  /// 同上，轻量版（不解码 Base58、不校验 checksum，只看格式）——用于
  /// 输入框实时校验等高频调用、不需要每次都做完整解码开销的场景。
  static bool isValidTransferAddressFormat(String? address) {
    return isValidAddressFormat(address) || MultiSigAddrTool.isValidMultiSigAddressFormat(address);
  }
}