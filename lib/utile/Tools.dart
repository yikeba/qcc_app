import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../views/setting/AppTranslator.dart';
import 'package:url_launcher/url_launcher.dart';

class Tools{

  static copytext(BuildContext context, String str) async {
    Clipboard.setData(ClipboardData(text: str));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("COPY $str ..."))
    );
  }

  static String getTra(String text){
    String? tra=AppTranslationManager.instance.getTranslatedSync(text);
    if(tra==null) return text;
    return tra;
  }


  static openChrome(String _url) async {
    try {
      if (!await launchUrl(Uri.parse(_url))) {
        throw Exception('Could not launch $_url');
      }
    } catch (e) {
      print("打开错误，打开下载页面");
      return await launch(_url);
    }
  }


  /// 全局轻提示
  static void showToast(BuildContext context, String message, {bool isError = false}) {
    // 先移除当前可能存在的 SnackBar，避免堆叠延迟
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.black87,
        behavior: SnackBarBehavior.floating, // 悬浮样式
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(20), // 悬浮时的外边距
      ),
    );
  }

  /// 全局加载框
  static void showLoading(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false, // 点击外部不消失
      builder: (context) => PopScope(
        canPop: false, // 禁用返回键关闭
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}