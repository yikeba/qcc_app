import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:html/parser.dart' as dom_parser;

import 'QccMailInAppWebView.dart'; // 👈 增加别名


class MailUtils {
  static String emailid="";


  static String getMailfrom(){
    return "${MailUtils.emailid}@qccio.com";
  }

  static String decodeSubject(String? subject) {
    if (subject == null || subject.isEmpty) return "(无主题)";

    // 匹配 RFC 2047 编码格式: =?UTF-8?B?....?= 或 =?UTF-8?Q?....?=
    final regExp = RegExp(r'=\?([\w-]+)\?([BQbq])\?([^\?]+)\?=', caseSensitive: false);

    // 如果没有编码标记，直接返回
    if (!subject.contains('=?')) return subject;

    String recsubject= subject.split(RegExp(r'\s+')).map((part) {
      final match = regExp.firstMatch(part);
      if (match == null) return part; // 没匹配到的部分（比如空格或符号）保持原样
      String charset = match.group(1)!.toUpperCase();
      String encoding = match.group(2)!.toUpperCase();
      String encodedText = match.group(3)!;

      try {
        if (encoding == 'B') {
          // Base64 解码
          return utf8.decode(base64.decode(encodedText), allowMalformed: true);
        } else if (encoding == 'Q') {
          // Quoted-Printable 解码
          return _decodeQuotedPrintableHeader(encodedText);
        }
      } catch (e) {
        return part;
      }
      return part;
    }).join(' ');
    return recsubject;
  }

  // 专门处理 Header 里的 QP 解码（把 _ 代替为空格）
  static String _decodeQuotedPrintableHeader(String input) {
    String decoded = input.replaceAll('_', ' '); // RFC 2047 中 _ 代表空格
    return _decodeQuotedPrintable(decoded); // 复用你之前的 QP 字节解码逻辑
  }

  // 提取纯文本正文 (从复杂的 MIME 结构中剥离)
  static String getCleanBody(String? fullBody) {
    if (fullBody == null) return "";
    String raw = fullBody.trim();
    // 1. 如果字符串直接以 <!doctype 或 <html 开始，说明后端已经给出了纯 HTML
    if (raw.toLowerCase().startsWith('<!doctype') || raw.toLowerCase().startsWith('<html')) {
      return raw;
    }

    // 优先提取 HTML 部分（用于渲染，保留格式）
    if (fullBody.contains("Content-Type: text/html")) {
      RegExp htmlReg = RegExp(
        r"Content-Type: text/html;.*?(\r\n\r\n|\n\n)(.*?)(?=\r\n--|\n--|$)",
        dotAll: true,
      );
      var htmlMatch = htmlReg.firstMatch(fullBody);
      if (htmlMatch != null) {
        String content = htmlMatch.group(2) ?? "";
        if (fullBody.contains("Content-Transfer-Encoding: base64")) {
          try {
            return utf8.decode(base64.decode(content.trim()));
          } catch (e) {}
        }
        // quoted-printable 解码
        if (fullBody.contains("Content-Transfer-Encoding: quoted-printable")) {
          return _decodeQuotedPrintable(content.trim());
        }
        return content.trim();
      }
    }

    // 其次提取 plain text 部分（用于文本解析）
    if (fullBody.contains("Content-Type: text/plain")) {
      RegExp regExp = RegExp(
        r"Content-Type: text/plain;.*?(\r\n\r\n|\n\n)(.*?)(?=\r\n--|\n--|$)",
        dotAll: true,
      );
      var match = regExp.firstMatch(fullBody);
      if (match != null) {
        String content = match.group(2) ?? "";
        if (fullBody.contains("Content-Transfer-Encoding: base64")) {
          try {
            return utf8.decode(base64.decode(content.trim()));
          } catch (e) {}
        }
        if (fullBody.contains("Content-Transfer-Encoding: quoted-printable")) {
          return _decodeQuotedPrintable(content.trim());
        }
        return content.trim();
      }
    }

    // 如果是纯 HTML，直接返回
    if (fullBody.trimLeft().startsWith('<')) {
      return fullBody;
    }

    // 最后 fallback：用 html 解析器提取文本
    var document = dom_parser.parse(fullBody);
    return dom_parser.parse(document.body?.text).documentElement?.text ?? fullBody;
  }

  /// 解码 quoted-printable 编码（常见于中文邮件）
  static String _decodeQuotedPrintable(String input) {
    // 1. 处理软换行（行末 = 表示续行）
    String result = input.replaceAll(RegExp(r'=\r\n'), '').replaceAll(RegExp(r'=\n'), '');
    // 2. 解码 =XX 十六进制转义
    result = result.replaceAllMapped(RegExp(r'=([0-9A-Fa-f]{2})'), (m) {
      int code = int.parse(m.group(1)!, radix: 16);
      return String.fromCharCode(code);
    });
    // 3. 尝试 UTF-8 修复（中文场景）
    try {
      List<int> bytes = result.codeUnits;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return result;
    }
  }
}

// ─────────────────────────────────────────────
//  HTML 复杂度判断（优化版）
// ─────────────────────────────────────────────

class HtmlComplexity {
  static bool isComplex(String html) {
    if (html.isEmpty) return false;

    // 不含任何 HTML 标签 → 纯文本，不复杂
    if (!html.contains('<')) return false;

    int score = 0;

    // 1. table 邮件（经典营销 / 通知邮件布局）
    if (RegExp(r'<table', caseSensitive: false).hasMatch(html)) score += 2;

    // 2. 内联 CSS（style 属性，大量样式控制排版）
    // 修正版：使用三引号或者更稳健的匹配方式
   // if (RegExp(r'style\s*=\s*["\']', caseSensitive: false).hasMatch(html)) score += 1;

// 如果上面的还报错，推荐用这个最稳妥的写法：
        if (html.toLowerCase().contains("style=") || html.contains("style='")) score += 1;

        // 3. style 块（外部样式表，flutter_html 不支持）
        if (RegExp(r'<style[\s>]', caseSensitive: false).hasMatch(html)) score += 2;

    // 4. MSO / Outlook 专有标记
    if (html.contains("mso-") || html.contains("<!--[if mso")) score += 2;

    // 5. 多图片（营销邮件）
    if (RegExp(r'<img', caseSensitive: false).allMatches(html).length > 3) score += 2;

    // 6. 多层嵌套 div（复杂布局）
    int divCount = RegExp(r'<div', caseSensitive: false).allMatches(html).length;
    if (divCount > 10) score += 2;

    // 7. media query（响应式邮件）
    if (html.contains("@media")) score += 2;

    // 8. 外部字体 / webfont
    if (html.contains("@font-face") || html.contains("fonts.googleapis")) score += 1;

    // 阈值提高到 4，避免误判普通邮件
    return score >= 4;
  }
}

// ─────────────────────────────────────────────
//  邮件类型枚举 & 解析结果
// ─────────────────────────────────────────────

// 1. 在枚举中增加类型
enum MailType { otp, order, magicLink, unknown }

class ParsedMail {
  final MailType type;
  final Map<String, dynamic> data;

  ParsedMail({required this.type, required this.data});
}

// ─────────────────────────────────────────────
//  邮件解析器（优化版）
// ─────────────────────────────────────────────

class MailParser {
  /// 外部调用入口：先用 getCleanBody 清洗 MIME 再解析
  static ParsedMail parse(String rawContent) {
    String content = MailUtils.getCleanBody(rawContent);
    String text = _htmlToText(content).toLowerCase();

    if (_isOTP(text)) return _parseOTP(text, content);

    // 🏆 新增：识别魔法链接
    if (text.contains("sign in") || text.contains("magic link") || text.contains("登录链接")) {
      // 提取按钮里的 href 链接
      RegExp linkReg = RegExp(r'href="(https://claude\.ai/magic-link[^"]+)"');
      var match = linkReg.firstMatch(content);
      if (match != null) {
        return ParsedMail(type: MailType.magicLink, data: {"url": match.group(1)!});
      }
    }

    if (_isOrder(text)) return _parseOrder(text);

    return ParsedMail(type: MailType.unknown, data: {"html": content});
  }

  static String _htmlToText(String html) {
    if (!html.contains('<')) return html;
    try {
      // 1. 使用别名调用 html 库的解析器，返回的是 dom_parser.Document
      var document = dom_parser.parse(html);
      // 2. Document 对象才有 body 属性
      String text = document.body?.text ?? "";
      // 3. 简单清理下空白符，方便正则匹配
      return text.replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (e) {
      LogObj.log("HTML转文本失败: $e");
      return html;
    }
  }

  // ── OTP 检测 ──

  static bool _isOTP(String text) {
    String lower = text.toLowerCase();
    bool hasKeyword =
        lower.contains("验证码") ||
            lower.contains("verification code") ||
            lower.contains("login code") ||
            lower.contains("one-time") ||
            lower.contains("passcode") ||
            lower.contains("otp") ||
            lower.contains("security code") ||
            lower.contains("confirm.*code") ||
            lower.contains("动态密码");

    if (!hasKeyword) return false;
    return RegExp(r'\b\d{4,8}\b').hasMatch(text);
  }

  static ParsedMail _parseOTP(String text, String originalHtml) {
    // 策略1：关键词紧邻数字
    RegExp contextReg = RegExp(
      r'(验证码|动态密码|code|passcode|verification|otp)[^\d]{0,30}(\d{4,8})',
      caseSensitive: false,
    );
    var m = contextReg.firstMatch(text);
    if (m != null) {
      return ParsedMail(type: MailType.otp, data: {"code": m.group(2)!});
    }

    // 策略2：HTML 标签包裹的大数字（如 <strong>123456</strong>）
    RegExp tagReg = RegExp(r'<(?:strong|b|span|td|p|h\d)[^>]*>\s*(\d{4,8})\s*</', caseSensitive: false);
    var tagMatch = tagReg.firstMatch(originalHtml);
    if (tagMatch != null) {
      return ParsedMail(type: MailType.otp, data: {"code": tagMatch.group(1)!});
    }

    // 策略3：letter-spacing 样式（验证码常见排版）
    RegExp styleReg = RegExp(r'letter-spacing[^>]*>(\d{4,8})<', caseSensitive: false);
    var styleMatch = styleReg.firstMatch(originalHtml);
    if (styleMatch != null) {
      return ParsedMail(type: MailType.otp, data: {"code": styleMatch.group(1)!});
    }

    // 策略4：fallback，过滤明显错误数字
    for (var m in RegExp(r'\b(\d{4,8})\b').allMatches(text)) {
      String val = m.group(1)!;
      if (_isLikelyNoise(val)) continue;
      return ParsedMail(type: MailType.otp, data: {"code": val});
    }

    return ParsedMail(type: MailType.unknown, data: {});
  }

  /// 过滤掉明显不是验证码的数字
  static bool _isLikelyNoise(String val) {
    if (val.length == 4 && val.startsWith("20")) return true; // 年份
    if (val.contains("000")) return true;                      // 像素/尺寸
    if (RegExp(r'^0+$').hasMatch(val)) return true;            // 全零
    return false;
  }

  // ── 订单检测 ──

  static bool _isOrder(String text) {
    String lower = text.toLowerCase();
    return lower.contains("order") ||
        lower.contains("订单") ||
        lower.contains("payment") ||
        lower.contains("invoice") ||
        lower.contains("发票") ||
        lower.contains("receipt");
  }

  static ParsedMail _parseOrder(String text) {
    RegExp amountReg = RegExp(r'(\$|USD|¥|CNY|€)\s?\d+(\.\d+)?', caseSensitive: false);
    var match = amountReg.firstMatch(text);
    return ParsedMail(
      type: MailType.order,
      data: {"amount": match?.group(0) ?? ""},
    );
  }
}

// ─────────────────────────────────────────────
//  QccMailViewer（主 Widget 入口）
// ─────────────────────────────────────────────
class QccMailViewer extends StatelessWidget {
  final String html;

  const QccMailViewer({super.key, required this.html});

  @override
  Widget build(BuildContext context) {

    // 🚨 先判断复杂HTML
    if (HtmlComplexity.isComplex(html)) {
      return QccMailWebView(html: html);
    }

    final parsed = MailParser.parse(html);

    switch (parsed.type) {
      case MailType.otp:
        return _OtpView(parsed: parsed);

      case MailType.order:
        return _OrderView(parsed: parsed);

      default:
        return _RawHtmlView(html: html);
    }
  }
}

// ─────────────────────────────────────────────
//  各类型 UI
// ─────────────────────────────────────────────

class _OtpView extends StatelessWidget {
  final ParsedMail parsed;
  const _OtpView({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final code = parsed.data["code"] ?? "";
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text("登录验证码",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SelectableText(code,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 8)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text("复制验证码"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("已复制验证码")));
            },
          ),
        ],
      ),
    );
  }
}

class _OrderView extends StatelessWidget {
  final ParsedMail parsed;
  const _OrderView({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final amount = parsed.data["amount"] ?? "未知金额";
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("订单信息",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text("金额: $amount",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: () {}, child: const Text("去支付（接 QCC）")),
        ],
      ),
    );
  }
}

class _RawHtmlView extends StatelessWidget {
  final String html;
  const _RawHtmlView({required this.html});

  String _sanitize(String html) {
    html = html.replaceAll(RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true), '');
    html = html.replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '');
    html = html.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    html = html.replaceAll(RegExp(r'<!--\[if.*?\]>.*?<!\[endif\]-->', dotAll: true), '');
    return html;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Html(
        data: _sanitize(html),
        style: {
          "body": Style(margin: Margins.zero, padding: HtmlPaddings.all(8)),
          "img": Style(width: Width(100, Unit.percent)),
          "table": Style(width: Width(100, Unit.percent)),
        },
      ),
    );
  }
}