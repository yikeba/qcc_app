/// QCC 资产 ID 前端校验 —— 逐条对齐公链 qcc.rule.assetRule.AssetIdSecurity。
///
/// 前端拦截只是为了避免浪费一次签名和一次提交，链上仍是最终判定。
/// Java 那边规则一改，这里必须同步改。
class AssetIdSecurity {
  AssetIdSecurity._();

  static const int minLength = 2;
  static const int maxLength = 16;

  /// Java: ^[\p{L}\p{N}-]{2,16}$
  /// Dart 需要 unicode: true 才支持 \p{..}；该模式下 {2,16} 按码点计数，
  /// 与 Java 正则一致（Java 的量词同样按码点匹配）。
  static final RegExp _pattern = RegExp(r'^[\p{L}\p{N}-]{2,16}$', unicode: true);

  /// 单个字符是否合法，用于定位第一个非法字符给出提示。
  static final RegExp _charOk = RegExp(r'^[\p{L}\p{N}-]$', unicode: true);

  static const Set<String> _reserved = {
    // 核心法币（ISO 3 字母代码）
    "USD", "EUR", "GBP", "CAD", "CHF", "JPY", "CNY", "KRW", "INR", "TWD",
    "HKD", "SGD", "AUD", "NZD", "THB", "VND", "PHP", "MYR", "SAR", "AED",
    // 核心加密货币
    "BTC", "ETH", "SOL", "BNB", "XRP", "USDT", "USDC", "DAI",
  };

  /// Java validate()
  static bool validate(String? assetId) {
    if (assetId == null || assetId.isEmpty) return false;
    return _pattern.hasMatch(assetId);
  }

  /// Java isStablecoinReserved()。注意 Java 用 String.length()（UTF-16 单元），
  /// Dart String.length 语义相同，这里照抄。
  static bool isStablecoinReserved(String assetId) {
    if (_reserved.contains(assetId)) return true;

    if (assetId.length >= 4 && assetId.length <= 6 && assetId.endsWith("S")) {
      final prefix = assetId.substring(0, assetId.length - 1);
      if (_reserved.contains(prefix)) return true;
    }

    if (assetId.contains("-")) {
      for (final part in assetId.split("-")) {
        if (_reserved.contains(part)) return true;
        if (part.length >= 4 && part.length <= 6 && part.endsWith("S")) {
          final p = part.substring(0, part.length - 1);
          if (_reserved.contains(p)) return true;
        }
      }
    }
    return false;
  }

  /// 给输入框用：合法返回 null，否则返回具体原因（指出第一个非法字符）。
  static String? explain(String? raw) {
    final v = raw ?? "";
    if (v.isEmpty) return "资产代码不能为空";

    for (final rune in v.runes) {
      final ch = String.fromCharCode(rune);
      if (!_charOk.hasMatch(ch)) {
        final shown = ch == " " ? "空格" : (ch == "_" ? "下划线 _" : "“$ch”");
        return "不支持 $shown，只能使用字母、数字和中划线 -";
      }
    }

    final int n = v.runes.length;
    if (n < minLength || n > maxLength) {
      return "长度需为 $minLength–$maxLength 个字符（当前 $n）";
    }
    if (!validate(v)) return "资产代码格式不符合公链规则";

    if (isStablecoinReserved(v)) {
      return "“$v”属于法币/主流币保留代码，不能注册";
    }
    return null;
  }
}
