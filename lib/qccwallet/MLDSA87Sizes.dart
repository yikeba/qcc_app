import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:liboqs/liboqs.dart' as oqs;
import 'package:pointycastle/export.dart';

/// ML-DSA-87 标准尺寸
class MLDSA87Sizes {
  static const int publicKeyBytes = 2592;
  static const int secretKeyBytes = 4896;
  static const int signatureBytes = 4627;
  static const int seedBytes = 32;
}

/// liboqs rand.h:
/// void OQS_randombytes_custom_algorithm(void (*algorithm_ptr)(uint8_t*, size_t));
typedef _RandBytesFuncC = Void Function(Pointer<Uint8> randomArray, Size bytesToRead);
typedef _RandBytesFuncDart = void Function(Pointer<Uint8> randomArray, int bytesToRead);

typedef _InitCustomRandC = Void Function(Pointer<NativeFunction<_RandBytesFuncC>>);
typedef _InitCustomRandDart = void Function(Pointer<NativeFunction<_RandBytesFuncC>>);

/// liboqs rand.h:
/// OQS_STATUS OQS_randombytes_switch_algorithm(const char *algorithm);
typedef _SwitchAlgoC = Int32 Function(Pointer<Utf8>);
typedef _SwitchAlgoDart = int Function(Pointer<Utf8>);

/// 开源样板 / Demo 版：
/// 用 seed 驱动 liboqs 全局 randombytes，得到“可复现”的 ML-DSA-87 keypair。
///
/// 注意：
/// 1. 这是 demo 方案，适合开源样板、恢复实验、跨端一致性验证。
/// 2. 不建议把“全局切换 RNG”作为正式生产方案。
class DeterministicMLDSA87 {
  static Uint8List? _seedBuffer;
  static int _seedOffset = 0;

  /// 串行执行，避免并发污染 liboqs 全局 RNG
  static Future<void> _serial = Future.value();

  /// 供 NativeCallable 回调使用
  static void _customRandBytes(Pointer<Uint8> buf, int length) {
    final source = _seedBuffer;
    if (source == null || source.isEmpty) {
      throw StateError('Seed buffer is not initialized.');
    }

    for (int i = 0; i < length; i++) {
      buf[i] = source[_seedOffset % source.length];
      _seedOffset++;
    }
  }

  /// 对外：由 32 字节 seed 生成可复现的 ML-DSA-87 密钥对
  static Future<oqs.SignatureKeyPair> generateFromSeed(Uint8List seed) {
    if (seed.length != MLDSA87Sizes.seedBytes) {
      throw ArgumentError(
        'Seed length must be ${MLDSA87Sizes.seedBytes} bytes, got ${seed.length}',
      );
    }
    return _runExclusive(() async {
      final lib = _openLiboqs();

      final initCustomRand = lib.lookupFunction<_InitCustomRandC, _InitCustomRandDart>(
        'OQS_randombytes_custom_algorithm',
      );

      final switchAlgo = lib.lookupFunction<_SwitchAlgoC, _SwitchAlgoDart>(
        'OQS_randombytes_switch_algorithm',
      );

      // 这里扩展出足够长的伪随机流，供 liboqs 内部建钥过程读取
      _seedBuffer = _expandSeed(seed, 4096);
      _seedOffset = 0;

      final callback = NativeCallable<_RandBytesFuncC>.isolateLocal(_customRandBytes);

      oqs.Signature? sig;
      oqs.SignatureKeyPair? keyPair;

      try {
        // 切到自定义 RNG
        initCustomRand(callback.nativeFunction);

        sig = oqs.Signature.create('ML-DSA-87');

        keyPair = sig.generateKeyPair();

        _validateKeyPair(keyPair);

        return keyPair;
      } finally {
        try {
          sig?.dispose();
        } catch (_) {}

        // 恢复系统 RNG
        final systemPtr = 'system'.toNativeUtf8();
        try {
          final rc = switchAlgo(systemPtr);
          if (rc != 0) {
            throw StateError('Failed to restore liboqs RNG to system mode, rc=$rc');
          }
        } finally {
          malloc.free(systemPtr);
        }

        callback.close();
        _seedBuffer = null;
        _seedOffset = 0;
      }
    });
  }

  /// 返回十六进制结果，方便钱包保存/调试
  static Future<DeterministicMLDSA87HexPair> generateHexFromSeed(Uint8List seed) async {
    final kp = await generateFromSeed(seed);
    return DeterministicMLDSA87HexPair(
      publicKeyHex: _bytesToHex(kp.publicKey),
      secretKeyHex: _bytesToHex(kp.secretKey),
    );
  }

  /// 使用私钥签名
  static Future<Uint8List> sign(Uint8List secretKey, Uint8List message) async {
    final sig = oqs.Signature.create('ML-DSA-87');

    try {
      final signature = sig.sign(message, secretKey);
      if (signature.length != MLDSA87Sizes.signatureBytes) {
        throw StateError(
          'Unexpected ML-DSA-87 signature length: ${signature.length}',
        );
      }
      return signature;
    } finally {
      sig.dispose();
    }
  }

  /// 使用公钥验签
  static Future<bool> verify(
      Uint8List publicKey,
      Uint8List message,
      Uint8List signature,
      ) async {
    if (publicKey.length != MLDSA87Sizes.publicKeyBytes) {
      throw ArgumentError(
        'Invalid ML-DSA-87 public key length: ${publicKey.length}',
      );
    }
    if (signature.length != MLDSA87Sizes.signatureBytes) {
      return false;
    }

    final sig = oqs.Signature.create('ML-DSA-87');

    try {
      return sig.verify(message, signature, publicKey);
    } finally {
      sig.dispose();
    }
  }

  /// ===== 内部工具 =====

  static Future<T> _runExclusive<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    _serial = _serial.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  static DynamicLibrary _openLiboqs() {
    if (Platform.isIOS || Platform.isMacOS) {
      // iOS 常见做法：framework 已经装入进程
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('liboqs.so');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('liboqs.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('oqs.dll');
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static void _validateKeyPair(oqs.SignatureKeyPair keyPair) {
    if (keyPair.publicKey.length != MLDSA87Sizes.publicKeyBytes) {
      throw StateError(
        'Unexpected ML-DSA-87 public key length: ${keyPair.publicKey.length}',
      );
    }
    if (keyPair.secretKey.length != MLDSA87Sizes.secretKeyBytes) {
      throw StateError(
        'Unexpected ML-DSA-87 secret key length: ${keyPair.secretKey.length}',
      );
    }
  }

  /// 用 SHAKE256 从 32 字节 seed 扩展出足够长的伪随机流
  static Uint8List _expandSeed(Uint8List seed, int targetLength) {
    final shake = SHAKEDigest(256);
    shake.update(seed, 0, seed.length);
    final out = Uint8List(targetLength);
    shake.doOutput(out, 0, targetLength);
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length.isOdd) {
      throw FormatException('Hex length must be even.');
    }
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      out[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return out;
  }
}

class DeterministicMLDSA87HexPair {
  final String publicKeyHex;
  final String secretKeyHex;

  DeterministicMLDSA87HexPair({
    required this.publicKeyHex,
    required this.secretKeyHex,
  });
}