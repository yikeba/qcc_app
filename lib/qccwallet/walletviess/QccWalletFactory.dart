import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../qccwallet/QccWallet.dart';
import '../../utile/QccStorage.dart';
import '../../views/setting/AppTranslator.dart';
import '../../views/setting/QccPassDialog.dart';
import '../../views/setting/QccPassUtil.dart';


class QccWalletFactory {
  // 1. 随机生成：随机熵 + 支付密码
  static Future<QccWallet?> createByRandom(BuildContext context) async {
    // 生成 24 词助记词
    String mnemonic = bip39.generateMnemonic(strength: 256);
    return await finalizeWalletCreation(context, mnemonic, "随机生成");
  }

  // 2. 助记词导入：已有助记词 + 支付密码
  static Future<QccWallet?> createByImport(BuildContext context, String mnemonic) async {
    return await finalizeWalletCreation(context, mnemonic, "导入钱包");
  }

  // 3. 手工生产：手工输入的 24 词 + 支付密码
  static Future<QccWallet?> createByManual(BuildContext context, String mnemonic) async {
    return await finalizeWalletCreation(context, mnemonic, "人工生产");
  }


  // ⚠️ 说明：我没有你这个文件的完整上下文（import、_Palette、QccPassDialog、
// _showProcessingDialog、_showError、_heavyCalculationTask 的具体实现），
// 下面按你贴出的代码原样保留调用方式，只新增/修改了必要部分。
// 如果你项目里已有统一的 _Palette 配色，把下面 Color(0xFF3D6BFF) 等硬编码
// 替换成 _Palette.primary / _Palette.primarySoft 即可保持视觉统一。

  /// 弹出昵称输入框：
  /// - 有输入 -> 返回用户输入（trim 后）
  /// - 未输入直接点"确定" -> 返回 defaultName
  /// - 点"暂不命名" -> 返回 defaultName
  /// 始终返回非空字符串，调用方无需再判空。
  static Future<String> showWalletNameDialog(
      BuildContext context, {
        required String defaultName,
      }) async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.badge_outlined, color: Color(0xFF3D6BFF), size: 26),
                ),
                const SizedBox(height: 16),
                Trans(
                  "给钱包起个名字",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1D29)),
                ),
                const SizedBox(height: 6),
                Trans(
                  "方便区分多个地址，例如「妹妹的地址」「节点地址」",
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 20,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? defaultName : v.trim()),
                  decoration: InputDecoration(
                    hintText: defaultName,
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    counterText: "",
                    filled: true,
                    fillColor: const Color(0xFFF5F6FA),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, defaultName), // 跳过 = 使用默认名称
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color(0xFFF5F6FA),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          "暂不命名",
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final input = controller.text.trim();
                          Navigator.pop(ctx, input.isEmpty ? defaultName : input);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color(0xFF3D6BFF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          "确定",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? defaultName;
  }

  /// ===== 修改后的 finalizeWalletCreation =====
  ///
  /// 改动点：
  /// 1. wallet 生成成功后，先关闭 Loading 框，再弹命名框（顺序很重要：
  ///    命名框需要 wallet.address 做默认名兜底，且不能和 Loading 叠在一起弹）。
  /// 2. 新增 loadingClosed 标记，避免 catch 里对已经关闭的 Loading 再次 pop
  ///    （原代码若在这之后出错，会误 pop 到命名框或者上一级页面）。
  /// 3. 原来的 `QccStorage.saveSingleWallet(wallet, password);` 少传了 name
  ///    参数（和 QccStorage.dart 里 _autoUpgradeToEncrypted 的问题一样），
  ///    这里已经补上 walletName。
  static Future<QccWallet?> finalizeWalletCreation(
      BuildContext context,
      String mnemonic,
      String typeLabel
      ) async {
    // A. 强制要求输入支付密码
    String? password = await QccPassDialog.show(context, isSetMode: true);
    if (password == null) return null;

    // B. 显示增强版 Loading 框
    _showProcessingDialog(context);
    bool loadingClosed = false;

    try {
      // 给 UI 线程留出渲染时间，确保 Loading 框先弹出来
      await Future.delayed(const Duration(milliseconds: 300));

      // C. 【核心优化】使用 compute 在子线程执行计算密集型任务
      final wallet = await compute(_heavyCalculationTask, {
        'mnemonic': mnemonic,
        'password': password,
      });

      // D. 关闭 Loading，弹出命名框（此时地址已生成，可用作默认名兜底）
      Navigator.pop(context);
      loadingClosed = true;

      final defaultName = "$typeLabel·${QccStorage.shortAddress(wallet.address)}";
      final walletName = await showWalletNameDialog(context, defaultName: defaultName);

      // E. 存储逻辑（涉及 I/O 很快，可以在主线程）
      QccPassUtil passUtil = QccPassUtil(wallet.address);
      await passUtil.createPassword(password, mnemonic);
      LogObj.log("新生成钱包信息:${wallet.address}，昵称:$walletName");
      await QccStorage.saveSingleWallet(wallet, walletName, password);

      return wallet;
    } catch (e) {
      if (!loadingClosed) Navigator.pop(context); // 关闭 Loading（仅在尚未关闭时）
      _showError(context, "创建失败: $e");
      return null;
    }
  }

  // 必须是静态方法或顶级函数，供 compute 调用
  static Future<QccWallet> _heavyCalculationTask(Map<String, String> data) async {
    // 这个方法运行在子线程，不会卡死 UI
    return await QccMnemonicWallet.fromMnemonic(
        data['mnemonic']!,
        paymentPassword: data['password']!
    );
  }

  // 修改 Loading 框，增加安全教育引导
  static void _showProcessingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const CircularProgressIndicator(strokeWidth: 4),
                const SizedBox(height: 25),
                const Trans("后量子安全加固中...",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.blue)),
                const SizedBox(height: 15),
                const Trans(
                  "ML-DSA-87 算法生成 4896字节高强度密钥对",
                  //textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
                ),
                const Trans(
                  "iPhone30秒(中，低端Android 10分钟)，请耐心等待，切勿关闭手机。",
                  //textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.5),
                ),
                const SizedBox(height: 10),
                const Trans("🔐 QCC：为您的资产提供抗量子保护",
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }
  static void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Trans("操作失败"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Trans("确定"),
          ),
        ],
      ),
    );
  }




}