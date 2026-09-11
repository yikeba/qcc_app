import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'AppTranslator.dart';

class FontSizeSettingPage extends StatelessWidget {
  const FontSizeSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fontManager = FontManager.instance;

    return Scaffold(
      appBar: AppBar(title: const Trans("字号设置")), // 假设 Trans 是你的翻译组件
      body: ListenableBuilder(
        listenable: fontManager,
        builder: (context, _) {
          return Column(
            children: [
              // 1. 直观预览区：实时反映字号变化
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(
                          "QCC 钱包字号预览",
                          style: TextStyle(fontSize: fontManager.fontSize, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "0x71C7656EC7ab88b098defB751B7401B5f6d8976F",
                          style: TextStyle(fontSize: fontManager.fontSize * 0.8, color: Colors.blueGrey),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "通过滑动下方的进度条，您可以调整全局字体大小。这对老年用户阅读账单非常有帮助。",
                          style: TextStyle(fontSize: fontManager.fontSize),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 2. 控制区：滑动条
              Container(
                padding: const EdgeInsets.fromLTRB(30, 20, 30, 50),
                color: Colors.white,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text("A", style: TextStyle(fontSize: 14)),
                        Text("标准", style: TextStyle(fontSize: 14)),
                        Text("A", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: fontManager.fontSize,
                      min: 14.0,
                      max: 28.0,
                      divisions: 7, // 阶梯感
                      label: "${fontManager.fontSize.toInt()} PX",
                      onChanged: (val) => fontManager.setFontSize(val),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


class FontManager extends ChangeNotifier {
  static final FontManager instance = FontManager._internal();
  factory FontManager() => instance;
  FontManager._internal();

  // 默认字号 16.0
  double _fontSize = 16.0;
  double get fontSize => _fontSize;

  // 初始化加载：建议在 main.dart 启动时调用
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('qcc_font_size') ?? 16.0;
    notifyListeners();
  }

  // 修改字号并保存
  Future<void> setFontSize(double size) async {
    if (_fontSize == size) return;
    _fontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('qcc_font_size', size);
    notifyListeners(); // 触发全局 UI 刷新
  }
}