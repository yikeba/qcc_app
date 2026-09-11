import 'dart:typed_data';
import 'package:bs58/bs58.dart';
import 'package:pointycastle/digests/sha3.dart';

/// ════════════════════════════════════════════════════════
/// QCC 多签地址格式校验 —— 对齐服务端 qcc.service.MultiSigAddrTool
///
/// 服务端多签地址方案：version=0x33，让 Base58 编码结果本身天然以
/// 'M' 开头，整体恒定 34 字符（和单签 AddressTool 的 0x3A/'Q' 方案是
/// 同一批协议变更、同一套编码结构，只是 version byte 和首字符不同，
/// 两边的 checksum 算法完全一致：payload = version(1 byte) + hash20，
/// checksum = 前 4 字节 SHA3-256(SHA3-256(payload))）。
///
/// 客户端目前只需要"校验一个字符串是不是合法的多签地址格式"这一个
/// 能力——多签地址是服务端在多签规则签署完成时算出来、随响应下发给
/// 客户端的，客户端不需要自己从公钥推导，所以这里只对齐服务端
/// isValidMultiSigAddress()，不实现 deriveMultiAddrFromPubKeys()。
/// ════════════════════════════════════════════════════════
class MultiSigAddrTool {
  /// 多签地址版本号（payload[0]）—— 唯一权威来源，必须和服务端
  /// MultiSigAddrTool 里的 MULTI_VERSION_BYTE 保持一致，不要在别处
  /// 再各自声明一份。
  static const int MULTI_VERSION_BYTE = 0x33;

  /// 校验多签地址格式 + checksum（完整校验，对齐服务端
  /// MultiSigAddrTool.isValidMultiSigAddress()）。
  /// 地址长度恒定 34 字符，天然以 'M' 开头。
  static bool isValidMultiSigAddress(String? address) {
    if (address == null || address.length != 34) {
      return false;
    }
    try {
      final Uint8List binaryAddress = Uint8List.fromList(base58.decode(address));
      if (binaryAddress.length != 25) {
        return false;
      }
      if (binaryAddress[0] != MULTI_VERSION_BYTE) {
        return false;
      }

      final payload = binaryAddress.sublist(0, 21);
      final checksum = binaryAddress.sublist(21, 25);

      final firstSHA = SHA3Digest(256).process(payload);
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

  /// 轻量级格式检查（不解码 Base58、不校验 checksum，只看首字符 +
  /// 长度 + 合法 Base58 字符集）—— 对齐 AddressTool.dart 里
  /// isValidAddressFormat() 的写法，用于输入框实时校验等不需要真正
  /// 解码的场景（比如每次按键都要判断一次，避免频繁做 Base58 解码 +
  /// 双重 SHA3 的开销）。真正提交前仍应该用上面的 isValidMultiSigAddress()
  /// 做完整校验。
  static bool isValidMultiSigAddressFormat(String? address) {
    if (address == null) return false;
    final reg = RegExp(r'^M[1-9A-HJ-NP-Za-km-z]{33}$');
    return reg.hasMatch(address);
  }
}
