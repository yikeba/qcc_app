/// 统一签名工具类：所有交易类型（普通转账 QccTransactionData、多签规则 RuleData，
/// 以及以后可能出现的其他交易模型）都应该走这一个入口，而不是各个页面各写一遍
/// "compute + QccLibOqsSigner.sign + QccDataProtocol.encodeTransaction + 覆盖 signature"。
///
/// 单例：SignUtil.instance
///
/// ============================ 【已确认的关键事实】 ============================
/// 看过 QccDataProtocol.dart 源码后确认：encodeTransaction() 内部的签名逻辑是被
/// **注释掉**的（第 27-33 行），它现在只是简单地构造一个 `signature: ""` 的空签名
/// QccPacket，什么都没签！也就是说：
///
///   如果调用方只是 `await QccDataProtocol.encodeTransaction(...)` 拿到 packet 就直接
///   拿去广播，这个 packet 的签名字段永远是空字符串。
///
/// 这正是之前 QccCreateMultiSigPage.dart / QccFollowMultiSigPage.dart 的
/// `_signTransactionTask` 在做的事——两个页面都只调了 encodeTransaction，
/// 从来没有单独调用 QccLibOqsSigner.sign() 再覆盖 packet.signature。
/// 也就是说，目前多签创建/追随签署提交上去的交易，签名字段大概率是空的。
/// 这不是"可能有问题"，是看了 encodeTransaction 源码后可以确认的 bug。
///
/// 这个 SignUtil 已经按"必须自己签名再覆盖"的正确方式实现（对应你贴的普通交易代码
/// 里 `qp.signature = signature;` 那一步），多签的两个页面需要改成调用这里的
/// signAndEncode()，而不是继续直接调 QccDataProtocol.encodeTransaction。
/// ==============================================================================
///
/// ============================ 【仍然需要你确认的一点】 ============================
/// "from 发起交易成功过，再次提交无需发送公钥"：
/// QccPacket.publicKey 是 `required String`（非空类型），QccDataProtocol.encodeTransaction
/// 也只是把 publicKeyHex 原样塞进 QccPacket，没有做任何校验/特殊处理——所以在
/// **Dart 客户端这一侧**，传空字符串 '' 不会报错、不会崩溃，语法上是安全的。
/// 但服务端/链上那边是不是真的支持"公钥字段为空 = 使用该地址已登记过的公钥"这个
/// 语义，我没法从这几个 Dart 文件里确认，这是纯粹的后端行为问题，需要你（或者
/// 后端同学）确认。所以 [enablePublicKeySkip] 默认关闭：关闭时行为和现在完全一样
/// （每次都带公钥），你确认后端确实支持了，再打开。
/// ==============================================================================
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:convert/convert.dart' show hex;

import 'package:qcc_flutter/procotol/QccDataProtocol.dart';
import 'package:qcc_flutter/procotol/QccPacket.dart';
import 'package:qcc_flutter/qccwallet/QccLibOqsSigner.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';

class SignUtil {
  SignUtil._internal();

  static final SignUtil instance = SignUtil._internal();

  /// 【开关，默认关闭】见文件头"仍然需要你确认的一点"。在你确认服务端/链上
  /// 真的支持"空公钥 = 复用已登记公钥"之前，不要打开。
  bool enablePublicKeySkip = false;

  static const String _storageKey = "sign_util_known_pubkey_addresses";

  Set<String> _knownAddresses = {};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await QccStorage.getRawData(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _knownAddresses = list.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      LogObj.log("SignUtil: 加载已提交地址索引失败: $e");
    }
    _loaded = true;
  }

  /// 某个地址是否已经成功提交过交易（也就是链上/服务端应该已经登记过它的公钥）。
  Future<bool> hasSubmittedBefore(String address) async {
    await _ensureLoaded();
    return _knownAddresses.contains(address);
  }

  /// 在一笔交易被服务端确认接受（比如 resData['status'] == 'ACCEPTED'）之后调用，
  /// 标记这个地址"以后可以不用再带公钥"。
  ///
  /// 【待确认】"服务端 ACCEPTED" 是否等于"公钥已登记"，如果实际需要等链上确认，
  /// 这个调用时机要往后挪到你查询交易回执确认之后。
  Future<void> markSubmitted(String address) async {
    if (address.isEmpty) return;
    await _ensureLoaded();
    if (_knownAddresses.add(address)) {
      try {
        await QccStorage.saveRawData(_storageKey, jsonEncode(_knownAddresses.toList()));
      } catch (e) {
        LogObj.log("SignUtil: 保存已提交地址索引失败: $e");
      }
    }
  }

  /// 钱包被删除 / 重新导入时应该调用，防止残留状态导致"新设备第一次用这个地址"
  /// 却被误判成"已经登记过公钥"。
  Future<void> forgetAddress(String address) async {
    await _ensureLoaded();
    if (_knownAddresses.remove(address)) {
      await QccStorage.saveRawData(_storageKey, jsonEncode(_knownAddresses.toList()));
    }
  }

  /// 统一签名入口，替代各页面里各自写的：
  ///   compute(_signTransactionTask, {...}) -> QccDataProtocol.encodeTransaction(...)
  /// （那种写法拿到的 packet.signature 恒为空字符串，见文件头说明）
  ///
  /// 参数不要求调用方的交易对象实现某个公共接口，只要能拿出这三样东西即可，
  /// 普通转账 QccTransactionData 和多签 RuleData 都能直接喂进来：
  /// - [from]：发起地址，用来查/记录"是否已提交过"。
  /// - [toSignString]：对应各交易模型的 toSign()（QccTransactionData.toSign() /
  ///   RuleData.toSign()，注意调用前两者都要求已经 finalizeId() 过）。
  /// - [payloadJson]：对应各交易模型 toJson() 之后 jsonEncode 的结果。
  /// - [privateKeyHex] / [publicKeyHex]：钱包私钥/公钥（hex）。
  ///
  /// 内部用 compute() 丢到子线程执行 Dilithium5 签名，避免卡 UI。
  Future<QccPacket> signAndEncode({
    required String from,
    required String toSignString,
    required String payloadJson,
    required String privateKeyHex,
    required String publicKeyHex,
  }) async {
    bool skipPubKey = false;
    if (enablePublicKeySkip) {
      skipPubKey = await hasSubmittedBefore(from);
    }

    LogObj.log("SignUtil: 发起签名 from=$from skipPubKey=$skipPubKey toSign=$toSignString");

    final QccPacket packet = await compute(_signInBackground, {
      'toSign': toSignString,
      'payloadJson': payloadJson,
      'privHex': privateKeyHex,
      // 【待确认，见文件头】空字符串代表"不下发公钥"，需要后端确认支持。
      'pubHex': skipPubKey ? '' : publicKeyHex,
    });

    return packet;
  }

  /// 静态子线程任务：对应你贴的普通交易签名逻辑——
  /// 1) 单独用 QccLibOqsSigner.sign() 对 toSign() 原文签名
  /// 2) 调用 QccDataProtocol.encodeTransaction 编码出 packet（它内部不会真的签名）
  /// 3) 用第 1 步算出来的签名覆盖 packet.signature
  /// 这一步（尤其是第 3 步）是必须的，不是可选的容错——不做这一步 packet.signature
  /// 就是空字符串。
  static Future<QccPacket> _signInBackground(Map<String, String> data) async {
    final String toSignStr = data['toSign']!;
    final String payloadJson = data['payloadJson']!;
    final String privHex = data['privHex']!;
    final String pubHex = data['pubHex'] ?? '';

    if (payloadJson.isEmpty) {
      throw Exception("交易构建失败：payloadJson 为空");
    }

    // 1. 用 C FFI (QccLibOqsSigner) 直接对 toSign() 原文做 Dilithium5 签名
    final Uint8List signatureBytes = QccLibOqsSigner.sign(privHex, toSignStr);
    final String signature = hex.encode(signatureBytes);
    LogObj.log("🛡️ 签名原始字节长度: ${signatureBytes.length}");
    LogObj.log("🛡️ 签名 Hex 字符串长度: ${signature.length}");

    // 2. 走协议层编码出 QccPacket（内部签名逻辑已被注释掉，signature 目前是 ""）
    final QccPacket packet = await QccDataProtocol.encodeTransaction(
      payloadJson: payloadJson,
      privateKeyHex: privHex,
      publicKeyHex: pubHex,
    );

    // 3. 【关键，不能省略】用第 1 步单独算出来的签名覆盖 packet.signature
    packet.signature = signature;
    return packet;
  }
}