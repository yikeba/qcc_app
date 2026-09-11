import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../procotol/QccPacket.dart';
import '../qccwallet/QccWallet.dart';
import '../qccwallet/SignUtil.dart';
import '../utile/QccStorage.dart';
import '../views/setting/QccPassDialog.dart';
import '../views/toolviews/QccLoading.dart';
/// 一次规则/交易提交的"待签名载荷"——只要求调用方给出 toSign() 的签名原文
/// 和 toJson() 的 payload 字符串，不关心背后到底是 RuleData 还是
/// TransactionData 还是 MultiTransactionData，这几种模型字段完全不同，
/// 不该被这个类替调用方决定。
class QccSignPayload {
  final String toSign;
  final String payloadJson;
  const QccSignPayload({required this.toSign, required this.payloadJson});
}

/// 统一提交流程的结果。三种终态互斥：
/// - cancelled：用户在（可选的风险确认框 / ）密码框上点了取消，调用方通常
///   什么都不用做，直接 return。
/// - success：拿到 data（服务端返回的完整 JSON）和用来签名的 wallet。
/// - 否则就是失败，error 里是给用户看的原因——可能是本地异常（钱包恢复
///   失败/密码错误），也可能是链上原样返回的拒绝原因（比如 Invalid
///   Signature、或者销毁时"未满12个月冻结"）。
class QccTxFlowResult {
  final bool cancelled;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  final QccWallet? wallet;

  const QccTxFlowResult._({
    required this.cancelled,
    required this.success,
    this.data,
    this.error,
    this.wallet,
  });

  factory QccTxFlowResult.cancelled() =>
      const QccTxFlowResult._(cancelled: true, success: false);

  factory QccTxFlowResult.ok(Map<String, dynamic> data, QccWallet wallet) =>
      QccTxFlowResult._(cancelled: false, success: true, data: data, wallet: wallet);

  factory QccTxFlowResult.fail(String error) =>
      QccTxFlowResult._(cancelled: false, success: false, error: error);
}

/// 统一的"密码 -> 显示loading -> 还原钱包 -> 构建载荷 -> 签名 -> 提交 ->
/// 解析返回 -> 关loading"流程。
///
/// 【抽取原因】这套流程在单签/多签发行、增发、跟签、销毁等一系列 Widget 里
/// 逐字重复了七八遍，人工复制导致好几个真实出现过的 bug：多签发行提案
/// 完全没有弹 loading；早期版本签名走了内部被注释掉的
/// QccDataProtocol.encodeTransaction，signature 恒为空；好几处漏了
/// ruleAppendJson=""；有的页面异常发生在中途，loading 永久卡死。这类问题
/// 只要抽到一处，改一次就全部调用方同时修好，不会再出现"这次改了 A 页面，
/// 忘了同步改 B 页面"的情况。
///
/// 调用方仍然完全掌控、这个类故意不替你做主的部分：
///   1. 提交前的业务权限校验（比如"当前地址是不是这个多签账户的成员"）——
///      这类校验和地址选择逻辑强绑定，留在各 Widget 自己的地方做。
///   2. 构建待签名对象（RuleData / TransactionData / MultiTransactionData
///      字段完全不同，必须由调用方在 buildPayload 回调里自己拼，拼完后如果
///      还需要 rule.id 之类的信息用于后续跳转，调用方可以在回调内部把它
///      存到外层闭包变量里）。
///   3. 成功之后写哪个本地存储（AssetFileStorage / MultiSigFileStorage 等）
///      以及跳转到哪个结果页——业务差异真实存在，交给调用方处理返回值。
///   4. 失败提示的具体文案——这个类只把 error 原样带出来，调用方决定怎么
///      展示（比如销毁页面想追加"请检查是否已冻结满12个月"这类场景化提示）。
class QccTxFlow {
  QccTxFlow._();

  /// [context] 用于弹密码框、loading、还原钱包。
  /// [address] 用哪个地址还原私钥——调用方在此之前应已校验过这个地址非空、
  ///   且确实有权限操作，这个类不做业务权限校验。
  /// [buildPayload] 拿到已还原的 wallet 之后，构建 (toSign, payloadJson)。
  ///   之所以要在"还原钱包成功之后"才调用，是因为不少规则的 from/owner
  ///   字段就是 wallet.address 本身，必须等钱包确实还原出来才能定稿。
  ///   支持 async，方便有的场景需要一次额外查询才能拼完 payload。
  /// [submitUrl] 最终 POST 的完整地址（/v1/rule、/v1/mtxrule、/v1/txm...
  ///   由调用方按场景传入，这个类不关心具体走哪个接口）。
  /// [showConfirmFirst] 可选：需要在密码框之前再弹一次风险确认框的场景
  ///   （比如销毁前的二次确认），返回 false 则整个流程当作"用户取消"处理，
  ///   不会弹密码框、也不会显示 loading。
  static Future<QccTxFlowResult> run({
    required BuildContext context,
    required String address,
    required Future<QccSignPayload> Function(QccWallet wallet) buildPayload,
    required String submitUrl,
    Future<bool> Function()? showConfirmFirst,
  }) async {
    if (showConfirmFirst != null) {
      final confirmed = await showConfirmFirst();
      if (!confirmed) return QccTxFlowResult.cancelled();
    }

    if (!context.mounted) return QccTxFlowResult.cancelled();
    String? password = await QccPassDialog.show(context);
    if (password == null) return QccTxFlowResult.cancelled();

    // 【关键顺序，之前反复出过问题的点】必须先拿到密码、确认要继续了，
    // 才显示 loading——弹在密码框之前会导致"取消密码框=loading永久卡死"。
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    if (!context.mounted) return QccTxFlowResult.cancelled();
    QccLoading.show(context, statusNotifier);

    try {
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, address, password);
      if (wallet == null || wallet.address != address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      statusNotifier.value = TxStep.building;
      final payload = await buildPayload(wallet);

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: payload.toSign,
        payloadJson: payload.payloadJson,
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse(submitUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      _closeLoading(context);

      if (response.statusCode != 200) {
        LogObj.log("提交qcc错误返回返回:${response.body}");
        return QccTxFlowResult.fail("网络通讯异常: ${response.statusCode}");
      }

      final resData = jsonDecode(response.body);

      if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
        // 标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
        await SignUtil.instance.markSubmitted(wallet.address);
        return QccTxFlowResult.ok(resData, wallet);
      } else {
        return QccTxFlowResult.fail(resData['msg']?.toString() ?? "公链拒绝了该请求");
      }
    } catch (e) {
      _closeLoading(context);
      return QccTxFlowResult.fail(e.toString());
    }
  }

  static void _closeLoading(BuildContext context) {
    if (context.mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}
