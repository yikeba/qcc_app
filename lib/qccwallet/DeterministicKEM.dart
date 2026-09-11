import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:liboqs/liboqs.dart' as d5;
import 'package:pointycastle/export.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

// 1. 定义 C 函数签名 (确保与 liboqs 源码完全一致)
typedef _RandBytesFuncC = Void Function(Pointer<Uint8> randomArray, Uint64 bytesToRead);
// NativeCallable 需要的 Dart 签名
typedef _RandBytesFuncDart = void Function(Pointer<Uint8> randomArray, int bytesToRead);

typedef _InitCustomRandC = Void Function(Pointer<NativeFunction<_RandBytesFuncC>>);
typedef _SwitchAlgoC = Void Function(Pointer<Utf8> algoName);

class DeterministicKEM {
  static Uint8List? _seedBuffer;
  static int _seedOffset = 0;

  // 这里的回调必须是静态方法或顶级函数
  static void _customRandBytes(Pointer<Uint8> buf, int length) {
    if (_seedBuffer == null) return;
    for (int i = 0; i < length; i++) {
      buf[i] = _seedBuffer![_offset % _seedBuffer!.length];
      _offset++;
    }
  }
  static int get _offset => _seedOffset;
  static set _offset(int val) => _seedOffset = val;

  /// 修复后的确定性密钥生成
  static d5.SignatureKeyPair generateMLDSA87FromSeed(Uint8List seed) {
    DynamicLibrary lib;
    if(Platform.isMacOS){
      lib=openmacLib();
      LogObj.log("mac 是否完成d5-c语言库的返回:${lib.runtimeType.toString()}");
    }else{
       lib = DynamicLibrary.open(_getLibPath());
    }
    // 2. 修复 lookupFunction 的红线
    final initCustomRand = lib.lookupFunction<_InitCustomRandC, void Function(Pointer<NativeFunction<_RandBytesFuncC>>)>('OQS_randombytes_custom_algorithm');
    final switchAlgo = lib.lookupFunction<_SwitchAlgoC, void Function(Pointer<Utf8>)>('OQS_randombytes_switch_algorithm');

    // 3. 准备种子扩展
    _seedBuffer = _expandSeed(seed, 2048);
    _seedOffset = 0;

    // 4. 【修复红线】使用 isolateLocal 创建回调
    // 对于 void 返回类型的回调，exceptionalReturn 必须省略或设为 null
    final callback = NativeCallable<_RandBytesFuncC>.isolateLocal(
      _customRandBytes,
      // void 函数不需要指定 exceptionalReturn，如果报错请直接删除该参数
    );

    // 5. 切换到自定义随机数
    initCustomRand(callback.nativeFunction);

    // 6. 【修复红线】使用 liboqs 1.2.0 正确的类名
    // 注意：liboqs 1.2.0 中 Signature.generateKeyPair() 返回的是 KeyPair 类型
    d5.SignatureKeyPair? keyPair;
    final sig = d5.Signature.create('ML-DSA-87');

    try {
      if (sig == null) throw Exception("不支持 ML-DSA-87");
      keyPair = sig.generateKeyPair(); // 此时生成受种子控制
    } finally {
      sig.dispose();

      // 7. 【修复红线】恢复系统随机数
      // 必须传入 "system" 的指针
      final systemStr = 'system'.toNativeUtf8();
      switchAlgo(systemStr);
      malloc.free(systemStr);

      callback.close();
      _seedBuffer = null;
    }

    return keyPair;
  }

  static Uint8List _expandSeed(Uint8List seed, int targetLength) {
    final digest = SHA512Digest();
    final result = <int>[];
    var current = seed;
    while (result.length < targetLength) {
      current = digest.process(current);
      result.addAll(current);
    }
    return Uint8List.fromList(result.sublist(0, targetLength));
  }

  static String _getLibPath() {
    if (Platform.isAndroid) return 'liboqs.so';
    if (Platform.isIOS) return 'liboqs.framework/liboqs';
    return 'liboqs.so';
  }



  static DynamicLibrary openmacLib() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('This loader is macOS only');
    }

    Object? lastError;

    final execDir = File(Platform.resolvedExecutable).parent.path;

    final candidates = <DynamicLibrary Function()>[
      // 1. 如果 liboqs 被静态链接或符号已进入主进程
          () => DynamicLibrary.process(),
          () => DynamicLibrary.executable(),

      // 2. Flutter/macOS 更推荐 framework 方式
          () => DynamicLibrary.open('liboqs.framework/liboqs'),
          () => DynamicLibrary.open('Frameworks/liboqs.framework/liboqs'),
          () => DynamicLibrary.open('$execDir/../Frameworks/liboqs.framework/liboqs'),

      // 3. 你如果当前仍然是 dylib，再尝试 bundle 内真实路径
          () => DynamicLibrary.open('$execDir/../Frameworks/liboqs.dylib'),
          () => DynamicLibrary.open('$execDir/liboqs.dylib'),
    ];

    for (final open in candidates) {
      try {
        final lib = open();

        const symbols = <String>[
          'OQS_init',
          'OQS_randombytes_custom_algorithm',
          'OQS_randombytes_switch_algorithm',
          'OQS_SIG_new',
          'OQS_SIG_keypair',
          'OQS_SIG_free',
        ];
        final ok = symbols.every(lib.providesSymbol);
        if (ok) {
          return lib;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('无法加载 liboqs。最后错误: $lastError');
  }
}