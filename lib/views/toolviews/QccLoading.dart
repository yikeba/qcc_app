// 在 lib/utile/QccDialogs.dart 中定义
import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

enum TxStep { building, password, restoring, signing, submitting }

final Map<TxStep, String> _stepMsgs = {
  TxStep.building: "正在构建交易数据...",
  TxStep.restoring: "🔐 正在从安全加固区还原钱包...",
  TxStep.signing: "✍️ 正在进行抗量子签名 (格数学计算)...",
  TxStep.submitting: "🚀 签名成功！正在同步至量子链节点...",
};

class QccLoading {
  static void show(BuildContext context, ValueNotifier<TxStep> notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false, // 禁止返回键关闭
          child: ValueListenableBuilder<TxStep>(
            valueListenable: notifier,
            builder: (context, step, _) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                title: const Text("🛡️ 抗量子安全传输", style: TextStyle(fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 25),
                    Trans(
                      _stepMsgs[step] ?? "请稍候...",
                      //textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const SizedBox(height: 15),
                    Trans(
                      "安全提示：由于格数学计算极其复杂，签名约需60秒(部分android设备需要数分钟)，请保持屏幕开启，不要切换后台。",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}