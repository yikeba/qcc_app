import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'AddressTool.dart';

/// ════════════════════════════════════════════════════════
/// QCC 地址长度定长性验证脚本
///
/// 用法：
///   1. 把本文件和 AddressTool.dart 放进你项目的 test/ 目录
///      （或任意有 pubspec 依赖的目录）
///   2. pubspec.yaml 确保有依赖：bs58, convert, pointycastle
///   3. dart run address_length_test.dart
///
/// 用随机字节模拟公钥输入 —— AddressTool.createAddress 只对
/// 输入做 SHA3 哈希，不关心公钥是否为合法 ML-DSA-87 公钥，
/// 所以随机 2592 字节足以驱动 hash20 + checksum 的均匀分布，
/// 对"地址位数是否恒定"这个统计问题是有效的压力测试。
/// ════════════════════════════════════════════════════════

const int sampleCount = 100000;
const int pubKeyByteLen = 2592; // ML-DSA-87 公钥长度

void main() {
  final rng = Random.secure();

  print('=== QCC 地址长度定长性验证 (修复版, version byte = 0x${AddressTool.QCC_VERSION_BYTE.toRadixString(16).padLeft(2, '0')}) ===');
  _runFixedVersionTest(rng);

  print('');
  print('=== 对照组：旧版 version byte = 0x00（复现原 bug，用于对比） ===');
  _runLegacyBuggyVersionTest(rng);
}

void _runFixedVersionTest(Random rng) {
  final lengthHistogram = <int, int>{};
  int checksumFailures = 0;
  final sw = Stopwatch()..start();

  for (int i = 0; i < sampleCount; i++) {
    final pubKeyHex = _randomHex(rng, pubKeyByteLen);
    final address = AddressTool.createAddress(pubKeyHex);
    print("生成地址长度:${address.length}   地址内容：$address");
    lengthHistogram[address.length] = (lengthHistogram[address.length] ?? 0) + 1;

    if (!AddressTool.isValidAddress(address)) {
      checksumFailures++;
    }
  }

  sw.stop();
  _report(lengthHistogram, checksumFailures, sw.elapsedMilliseconds, expectedLen: 35);
}

/// 复现修复前的逻辑（version byte = 0x00），仅用于对比统计，
/// 证明"34/35 波动"确实源于 version byte 选取，而非其他因素。
void _runLegacyBuggyVersionTest(Random rng) {
  final lengthHistogram = <int, int>{};
  final sw = Stopwatch()..start();

  for (int i = 0; i < sampleCount; i++) {
    final pubKeyHex = _randomHex(rng, pubKeyByteLen);
    final address = _legacyCreateAddress(pubKeyHex);
    lengthHistogram[address.length] = (lengthHistogram[address.length] ?? 0) + 1;
  }

  sw.stop();
  _report(lengthHistogram, null, sw.elapsedMilliseconds, expectedLen: null);
}

String _legacyCreateAddress(String publicKeyHex) {
  String address= AddressTool.createAddress(publicKeyHex);
  print("生成地址长度:${address.length}   地址内容：$address");
  return address;
}

String _randomHex(Random rng, int byteLen) {
  final bytes = Uint8List(byteLen);
  for (int i = 0; i < byteLen; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return hex.encode(bytes);
}

void _report(
    Map<int, int> histogram,
    int? checksumFailures,
    int elapsedMs, {
      required int? expectedLen,
    }) {
  print('样本数: $sampleCount   耗时: ${elapsedMs}ms');
  final sortedKeys = histogram.keys.toList()..sort();
  for (final len in sortedKeys) {
    final count = histogram[len]!;
    final pct = (count / sampleCount * 100).toStringAsFixed(4);
    print('  长度 $len 字符: $count 次 ($pct%)');
  }

  if (expectedLen != null) {
    final onlyExpected = histogram.length == 1 && histogram.containsKey(expectedLen);
    print(onlyExpected
        ? '✅ 结论：全部 $sampleCount 个地址长度恒为 $expectedLen 字符，定长性验证通过'
        : '❌ 结论：出现非 $expectedLen 字符的地址，定长性验证失败，请检查 version byte');
  } else {
    print(histogram.length > 1
        ? '⚠️  对照组（旧 0x00）确认存在长度波动，复现了原问题'
        : '（对照组未复现波动，属于小概率巧合，可增大样本数复核）');
  }

  if (checksumFailures != null) {
    print(checksumFailures == 0
        ? '✅ checksum/isValidAddress 校验全部通过'
        : '❌ 有 $checksumFailures 个地址未通过 isValidAddress 校验');
  }
}