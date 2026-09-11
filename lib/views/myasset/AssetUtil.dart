import 'package:flutter/cupertino.dart';

import '../setting/AppTranslator.dart';

class Assetutil {

  static Future<String?> showTextInputDialog(BuildContext context, String hint, String label,String desStr) async {
    String? inputText;

    const int maxDescLength = 100;

    return await showCupertinoDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: Text(label),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: 380, // 加宽弹出框
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoTextField(
                    placeholder: hint,
                    autofocus: true,
                    onChanged: (val) => inputText = val,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    desStr,
                    maxLines: maxDescLength,
                    style: const TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(child: const Trans("取消"), onPressed: () => Navigator.pop(context)),
            CupertinoDialogAction(child: const Trans("确认"), onPressed: () => Navigator.pop(context, inputText)),
          ],
        ),
      ),
    );
  }
}