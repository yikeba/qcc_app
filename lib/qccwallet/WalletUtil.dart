import 'dart:convert';
import 'dart:developer' as LogObj;
import 'dart:io';

import 'package:file_picker/file_picker.dart'; // 【复用】与资产导出页一致，用于选择本地备份文件
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:qcc_flutter/qccwallet/walletviess/QccWalletFactory.dart';

import '../home/QccScanner.dart';
import '../utile/QccStorage.dart';
import '../utile/QccTransferUtil.dart';
import '../utile/Tools.dart';
import '../views/myasset/AssetUtil.dart';
import '../views/setting/QccPassDialog.dart';

class Walletutil {

  // 1. 触发方法：扫码 -> 逻辑处理
  static Future<bool> handleScanRestore(BuildContext context) async {
    // A. 调用扫码界面，拿到编码字符串
    String? qrResult = await QccScanner.scan(context);
    if (qrResult == null) return false;
    // B~E 的解密/密码/落库逻辑与文件恢复完全一致，统一走 _restoreFromEncodedData
    return _restoreFromEncodedData(context, qrResult, sourceLabel: "扫码");
  }

  // 2. 触发方法：选择本地备份文件 -> 逻辑处理
  // 文件内容本质上和扫码拿到的是同一份编码字符串(QCC_SECURE_V2:... )，
  // 只是获取方式不同：扫码用摄像头识别，这里用文件选择器读字节再还原成字符串。
  static Future<bool> handleFileRestore(BuildContext context) async {
    final picked = await _pickAndReadBackupFile(context);
    if (picked == null) return false; // 用户取消，或文件无法读取（已在内部提示）
    return _restoreFromEncodedData(
      context,
      picked.qrData,
      sourceLabel: "文件",
      // ✅ 文件恢复：把文件名（去掉后缀）作为钱包命名弹窗的默认值，
      // 用户可以直接确认，也可以在弹窗里改成别的名字
      presetWalletName: picked.suggestedName,
    );
  }

  // 选择文件并还原为编码字符串 + 文件名建议昵称。
  // 【假设】资产管理页导出备份文件时是用 utf8.encode(qrdata) 写入二进制内容的，
  // 这里对称地用 utf8.decode(bytes) 换回同一份字符串；如果导出格式后续改成了
  // base64Decode(qrdata) 写入，这里要同步改成 base64Encode(bytes) 反解。
  static Future<_PickedBackupFile?> _pickAndReadBackupFile(BuildContext context) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择钱包备份文件',
        type: FileType.any, // 若导出文件统一固定 .qccbak 后缀，可改为 FileType.custom, allowedExtensions: ['qccbak']
        withData: true, // 保证桌面端/移动端/Web 都能拿到 bytes，不强依赖 path
      );
    } catch (e) {
      LogObj.log("选择备份文件失败: $e");
      Tools.showToast(context, "选择文件失败: $e");
      return null;
    }

    if (result == null || result.files.isEmpty) {
      // 用户取消了选择
      return null;
    }

    try {
      final picked = result.files.single;
      final List<int>? bytes =
          picked.bytes ?? (picked.path != null ? await File(picked.path!).readAsBytes() : null);
      if (bytes == null) {
        Tools.showToast(context, "无法读取所选文件");
        return null;
      }
      final String qrData = utf8.decode(bytes);
      // 用文件名（去掉后缀）作为钱包昵称建议值，例如 "老王的钱包.qccbak" -> "老王的钱包"
      final String suggestedName = _stripExtension(picked.name);
      return _PickedBackupFile(qrData, suggestedName);
    } catch (e) {
      LogObj.log("读取/解析备份文件失败: $e");
      Tools.showToast(context, "文件格式无法识别，请确认选择的是正确的备份文件: $e");
      return null;
    }
  }

  static String _stripExtension(String fileName) {
    final int dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName; // 没有后缀，或以 "." 开头，原样返回
    return fileName.substring(0, dotIndex);
  }

  // 3. 共用的核心还原逻辑：拿到 QCC_SECURE_V2:... 编码字符串之后，
  // 无论来源是扫码还是文件，走的都是同一套 格式校验 -> 密码输入 -> 解密 -> 落库 流程。
  static Future<bool> _restoreFromEncodedData(
      BuildContext context,
      String qrResult, {
        required String sourceLabel,
        String? presetWalletName,
      }) async {
    // B. 基础校验
    if (!qrResult.startsWith("QCC_SECURE_V2:")) {
      Tools.showToast(context, "无效的 QCC 备份格式");
      return false;
    }
    // C. 支付密码输入 (用于派生 AES 密钥)
    String? payPass = await QccPassDialog.show(context);
    if (payPass == null) return false;

    // D. 恢复验证码输入 (用户导出时自己设置的那个)
    String? customVerifyCode = await Assetutil.showTextInputDialog(
        context,
        "请输入6位以上QR密码",
        "导入密码",
        "导入密码是您迁徙冷钱包时设置的QR密码"
    );
    if (customVerifyCode == null) return false;
    if (payPass == customVerifyCode) {
      Tools.showLoading(context, "导入密码和支付密码不能一致，违反安全规范，无法导入");
      return false;
    }

    try {
      Tools.showLoading(context, "需要数分钟解密资产，...");
      // E. 调用你写的工具类进行解密
      // 注意：解密需要 1000 次 SHA3 迭代，是计算密集型，建议异步执行
      String? mnemonic = await QccTransferUtil.decodeFromQrData(
          qrResult,
          payPass,
          customVerifyCode
      );
      if (mnemonic != null && mnemonic.isNotEmpty) {
        final wallet = await compute(QccStorage.restoreWalletTask, {
          'rawData': mnemonic,
          'password': payPass,
        });
        if(wallet!=null) {
          mnemonic="";
          //final defaultName = "$typeLabel·${QccStorage.shortAddress(wallet.address)}";

          // ✅ 文件恢复时，把从文件名识别出的钱包名称预填进命名输入框，并提醒用户这是自动加载的，
          // 用户可以直接确认，也可以自己改成别的名字；扫码恢复没有文件名这个信息来源，维持原样手动输入
          if (presetWalletName != null && presetWalletName.trim().isNotEmpty) {
            Tools.showToast(context, "已从备份文件识别到钱包名称：${presetWalletName.trim()}，可在下一步确认或修改");
          }
          final walletName = await QccWalletFactory.showWalletNameDialog(
            context,
            defaultName: (presetWalletName != null && presetWalletName.trim().isNotEmpty)
                ? presetWalletName.trim()
                : "User wallet",
          );

          LogObj.log("钱包本地恢复($sourceLabel): ${wallet.address}");
          QccStorage.saveSingleWallet(wallet,walletName, payPass);
          if (Navigator.canPop(context)) Navigator.pop(context);
          return true;
        }
      } else {
        LogObj.log("钱包本地恢复错误 数据读取失败");
        Tools.showToast(context, "支付密码或恢复验证码错误,无法恢复钱包");
      }
    } catch (e) {
      //Tools.hideLoading(context);
      LogObj.log("恢复异常: $e");
      Tools.showToast(context, "数据解析失败，请重试");
    }
    if (Navigator.canPop(context)) Navigator.pop(context); // 关闭 Loading
    return false;
  }

}
class _PickedBackupFile {
  final String qrData;
  final String suggestedName;
  _PickedBackupFile(this.qrData, this.suggestedName);
}