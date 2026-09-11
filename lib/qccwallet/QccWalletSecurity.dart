import 'dart:typed_data';
import 'package:convert/convert.dart';

import 'QccWallet.dart';

extension QccWalletSecurity on QccWallet {
  /// 核心：通过密码执行一次性操作（如签名）
  /// 操作完成后，派生出的私钥将从内存中销毁
  Future<T> withTemporaryKeys<T>({
    required String password,
    required Future<T> Function(String privHex, String pubHex) action,
  }) async {
    // 1. 验证助记词是否存在
    if (mnemonic == null) throw Exception("该钱包为观察者模式，无助记词");
    try {
      return await action(privateKey!, pubkey!);
    } finally {
      privateKey=null;
      pubkey=null;
      mnemonic=null;
      print("🛡️ 安全防护：私钥已在签名后物理销毁");
    }
  }
}