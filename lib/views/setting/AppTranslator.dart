import 'package:flutter/material.dart';
import 'package:translator/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTranslationManager extends ChangeNotifier {
  static final AppTranslationManager instance = AppTranslationManager._internal();
  factory AppTranslationManager() => instance;

  AppTranslationManager._internal() {
    _initLanguage();
  }

  final _translator = GoogleTranslator();
  final Map<String, String> _cache = {};

  String _targetLanguage = 'en';
  String get targetLanguage => _targetLanguage;

  final Map<String, String> supportedLanguages = {
    'en': 'English',
    'zh-cn': '简体中文',
    'ja': '日本語',
    'ko': '한국어',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'id': 'Bahasa Indonesia',
    'hi': 'हिन्दी',
    'tr': 'Türkçe',
    'ar': 'العربية',
    'fa': 'فارسی',            // 波斯语（RTL）：伊朗/阿富汗/塔吉克
    'es': 'Español',
    'pt': 'Português',
    'ru': 'Русский',
    'fr': 'Français',
    'de': 'Deutsch',
  };

  // RTL 语言（阿拉伯、波斯、希伯来）
  bool get isRtl =>
      _targetLanguage == 'ar' ||
          _targetLanguage == 'fa' ||
          _targetLanguage == 'he';

  static const String _storageKey = "qcc_user_language";

  Future<void> _initLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedLang = prefs.getString(_storageKey);

    if (savedLang != null && supportedLanguages.containsKey(savedLang)) {
      _targetLanguage = savedLang;
    } else {
      String browserLang =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
      for (var key in supportedLanguages.keys) {
        if (browserLang.startsWith(key.split('-')[0])) {
          _targetLanguage = key;
          break;
        }
      }
    }
    notifyListeners();
  }

  void changeLanguage(String langCode) {
    if (_targetLanguage == langCode) return;
    _targetLanguage = langCode;
    notifyListeners();
  }

  Future<String> translateText(String text) async {
    if (text.isEmpty) return "";
    String cacheKey = "${_targetLanguage}_$text";
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      var translation = await _translator.translate(text, to: _targetLanguage);
      _cache[cacheKey] = translation.text;
      return translation.text;
    } catch (e) {
      return text;
    }
  }

  String getTranslatedSync(String text) {
    String cacheKey = "${_targetLanguage}_$text";
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    translateText(text);
    return text;
  }
}

/// [Trans] —— 支持异步翻译的 Text 替代品
///
/// 参数说明：
/// - [isFlexible]  适合 Row 内需要"占剩余空间"的场景，外层套 Flexible
/// - [shrink]      适合固定空间（Grid 卡片、AppBar、按钮）内文字可能超长的场景，
///                 使用 FittedBox 按比例缩小，永远不溢出
/// - 两者互斥，[shrink] 优先级高于 [isFlexible]
class Trans extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextOverflow overflow;
  final int? maxLines;
  final bool isFlexible;

  /// 固定空间内自适应缩放，防止溢出。
  /// 适合：Grid 卡片文字、AppBar title、按钮文字、顶部卡片小标签等。
  final bool shrink;

  const Trans(
      this.text, {
        super.key,
        this.style,
        this.overflow = TextOverflow.ellipsis,
        this.maxLines = 1,
        this.isFlexible = false,
        this.shrink = false,
      });

  Widget _buildText(String content) {
    return Text(
      content,
      style: style,
      overflow: overflow,
      maxLines: maxLines,
      softWrap: maxLines != 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = AppTranslationManager();

    final Widget textWidget = ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        return FutureBuilder<String>(
          key: ValueKey('${manager.targetLanguage}_$text'),
          future: manager.translateText(text),
          builder: (context, snapshot) {
            final content = snapshot.data ?? text;

            if (shrink) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _buildText(content),
              );
            }

            return _buildText(content);
          },
        );
      },
    );

    if (isFlexible && !shrink) {
      return Flexible(child: textWidget);
    }

    return textWidget;
  }
}