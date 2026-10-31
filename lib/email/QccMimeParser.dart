import 'dart:convert';
import 'dart:typed_data';

/// 自写轻量 MIME 解析器（不依赖 enough_mail / pointycastle）。
/// 在本地把 raw .eml 解析成可渲染 HTML + 附件清单。
///
/// 覆盖：multipart 递归、boundary 拆分、quoted-printable / base64 传输编码、
/// charset 解码（utf-8 / gbk / big5 等经 systemEncoding 兜底）、RFC2047 头解码、
/// cid 内联图片转 data URI、附件分离。
class QccMimeParser {
  /// 解析入口。返回 {isHtml, html, attachments:[{partId,filename,mimeType,size,bytes}]}
  static ParsedMail parse(Uint8List raw) {
    try {
      final root = _parseEntity(raw);
      final leaves = <_Leaf>[];
      _collectLeaves(root, leaves);

      // 收集 cid → 叶子，用于内联图片
      final cidMap = <String, _Leaf>{};
      for (final lf in leaves) {
        final cid = lf.headers['content-id'];
        if (cid != null) cidMap[_stripAngle(cid)] = lf;
      }

      String? html;
      String? text;
      for (final lf in leaves) {
        if (lf.isAttachment) continue;
        if (lf.isMime('text/html') && html == null) {
          html = lf.decodeText();
        } else if (lf.isMime('text/plain') && text == null) {
          text = lf.decodeText();
        }
      }

      String body;
      bool isHtml;
      if (html != null && html.trim().isNotEmpty) {
        body = _inlineCids(html, cidMap);
        isHtml = true;
      } else if (text != null && text.trim().isNotEmpty) {
        body = text;
        isHtml = false;
      } else {
        body = '';
        isHtml = false;
      }

      // 附件：attachment 处置，或非文本且未作为 cid 图片内联
      final attachments = <MailAttachment>[];
      for (int i = 0; i < leaves.length; i++) {
        final lf = leaves[i];
        final inlinedImage = html != null &&
            lf.isMime('image/') &&
            lf.headers['content-id'] != null;
        if (lf.isAttachment || (!lf.isText && !inlinedImage)) {
          final bytes = lf.decodeBytes();
          attachments.add(MailAttachment(
            partId: i,
            filename: lf.fileName ?? 'attachment_$i${_guessExt(lf.mimeType)}',
            mimeType: lf.mimeType,
            bytes: bytes,
          ));
        }
      }

      return ParsedMail(
        isHtml: isHtml,
        html: body,
        attachments: attachments,
        headers: root.headers,
        plainText: text,
      );
    } catch (e) {
      return ParsedMail(
          isHtml: false, html: '(解析失败: $e)', attachments: const []);
    }
  }

  // ============ MIME 实体解析 ============
  static _Entity _parseEntity(Uint8List bytes) {
    final sep = _findHeaderEnd(bytes);
    // 头部按 UTF-8 容错解码（兼容 8bit 原始中文头）；RFC2047 编码字在取值时再解
    final headerStr =
        utf8.decode(bytes.sublist(0, sep.headerEnd), allowMalformed: true);
    final body = bytes.sublist(sep.bodyStart);
    final headers = _parseHeaders(headerStr);

    final ct = headers['content-type'] ?? 'text/plain';
    final ctParams = _parseParams(ct);
    final mimeType = _firstToken(ct).toLowerCase();

    final entity = _Entity(headers: headers, mimeType: mimeType, body: body);

    if (mimeType.startsWith('multipart/')) {
      final boundary = ctParams['boundary'];
      if (boundary != null && boundary.isNotEmpty) {
        for (final seg in _splitMultipart(body, boundary)) {
          entity.children.add(_parseEntity(seg));
        }
      }
    }
    return entity;
  }

  static void _collectLeaves(_Entity e, List<_Leaf> out) {
    if (e.mimeType.startsWith('multipart/')) {
      for (final c in e.children) {
        _collectLeaves(c, out);
      }
    } else {
      out.add(_Leaf(e));
    }
  }

  // 找头尾分隔（\r\n\r\n 或 \n\n），返回 headerEnd 与 bodyStart
  static ({int headerEnd, int bodyStart}) _findHeaderEnd(Uint8List b) {
    for (int i = 0; i + 1 < b.length; i++) {
      if (b[i] == 10 && b[i + 1] == 10) {
        return (headerEnd: i, bodyStart: i + 2);
      }
      if (i + 3 < b.length &&
          b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return (headerEnd: i, bodyStart: i + 4);
      }
    }
    return (headerEnd: b.length, bodyStart: b.length);
  }

  static Map<String, String> _parseHeaders(String headerStr) {
    final headers = <String, String>{};
    String? key;
    final buf = StringBuffer();
    void flush() {
      if (key != null) headers[key!] = buf.toString().trim();
      buf.clear();
    }

    for (var line in headerStr.split('\n')) {
      line = line.replaceAll('\r', '');
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && key != null) {
        buf.write(' ');
        buf.write(line.trim());
      } else {
        final c = line.indexOf(':');
        if (c < 0) continue;
        flush();
        key = line.substring(0, c).trim().toLowerCase();
        buf.write(line.substring(c + 1).trim());
      }
    }
    flush();
    return headers;
  }

  static String _firstToken(String v) => _splitSemis(v).first.trim();

  static Map<String, String> _parseParams(String v) {
    final params = <String, String>{};
    final segs = _splitSemis(v);
    for (int i = 1; i < segs.length; i++) {
      final s = segs[i].trim();
      final eq = s.indexOf('=');
      if (eq < 0) continue;
      final k = s.substring(0, eq).trim().toLowerCase();
      var val = s.substring(eq + 1).trim();
      if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
        val = val.substring(1, val.length - 1);
      }
      params[k] = val;
    }
    return params;
  }

  static List<String> _splitSemis(String v) {
    final out = <String>[];
    final buf = StringBuffer();
    bool q = false;
    for (int i = 0; i < v.length; i++) {
      final ch = v[i];
      if (ch == '"') q = !q;
      if (ch == ';' && !q) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static List<Uint8List> _splitMultipart(Uint8List body, String boundary) {
    final delim = latin1.encode('--$boundary');
    final parts = <Uint8List>[];
    final positions = <int>[];
    for (int i = 0; i <= body.length - delim.length; i++) {
      bool match = true;
      for (int j = 0; j < delim.length; j++) {
        if (body[i + j] != delim[j]) {
          match = false;
          break;
        }
      }
      if (match) positions.add(i);
    }
    for (int p = 0; p < positions.length - 1; p++) {
      int start = positions[p] + delim.length;
      // 跳过 boundary 后的 \r\n
      while (start < body.length && (body[start] == 13 || body[start] == 10)) {
        start++;
      }
      int end = positions[p + 1];
      // 去掉 part 末尾的 \r\n
      while (end > start && (body[end - 1] == 13 || body[end - 1] == 10)) {
        end--;
      }
      if (end > start) parts.add(body.sublist(start, end));
    }
    return parts;
  }

  static String _inlineCids(String html, Map<String, _Leaf> cidMap) {
    var result = html;
    cidMap.forEach((cid, lf) {
      if (!lf.isMime('image/')) return;
      final token = 'cid:$cid';
      if (!result.contains(token)) return;
      final b64 = base64.encode(lf.decodeBytes());
      result = result.replaceAll(token, 'data:${lf.mimeType};base64,$b64');
    });
    return result;
  }

  static String _stripAngle(String cid) {
    var s = cid.trim();
    if (s.startsWith('<') && s.endsWith('>')) s = s.substring(1, s.length - 1);
    return s;
  }

  static String _guessExt(String mime) {
    if (mime.contains('zip')) return '.zip';
    if (mime.contains('pdf')) return '.pdf';
    if (mime.contains('png')) return '.png';
    if (mime.contains('jpeg') || mime.contains('jpg')) return '.jpg';
    return '.bin';
  }

  // ============ RFC2047 头解码（文件名等用） ============
  static String decodeHeaderWord(String text) {
    if (!text.contains('=?')) return text;
    // 相邻编码字之间的空白按 RFC2047 §6.2 应忽略（否则长中文主题中间会多空格）
    text = text.replaceAll(RegExp(r'\?=\s+=\?'), '?==?');
    final re =RegExp(r'=\?([\w-]+)\?([BbQq])\?(.*?)\?=');
    return text.replaceAllMapped(re, (m) {
      final cs = m.group(1)!.toLowerCase();
      final enc = m.group(2)!.toUpperCase();
      final data = m.group(3)!;
      try {
        final bytes = enc == 'B'
            ? base64.decode(_padB64(data))
            : _qpDecode(data.replaceAll('_', ' '));
        return _decodeCharset(Uint8List.fromList(bytes), cs);
      } catch (_) {
        return m.group(0)!;
      }
    });
  }

  // ============ 编码工具（供 _Leaf 调用） ============
  static List<int> qpDecode(String s) => _qpDecode(s);

  static List<int> _qpDecode(String data) {
    final s = data.replaceAll('=\r\n', '').replaceAll('=\n', '');
    final out = <int>[];
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '=' && i + 2 < s.length) {
        final hex = s.substring(i + 1, i + 3);
        final v = int.tryParse(hex, radix: 16);
        if (v != null) {
          out.add(v);
          i += 2;
          continue;
        }
      }
      out.add(ch.codeUnitAt(0));
    }
    return out;
  }

  static String _padB64(String s) {
    final clean = s.replaceAll(RegExp(r'\s'), '');
    final mod = clean.length % 4;
    return mod == 0 ? clean : clean + '=' * (4 - mod);
  }

  static String decodeCharset(Uint8List bytes, String charset) =>
      _decodeCharset(bytes, charset);

  static String _decodeCharset(Uint8List bytes, String charset) {
    final cs = charset.toLowerCase();
    try {
      if (cs.contains('utf-8') || cs.contains('utf8') || cs.isEmpty) {
        return utf8.decode(bytes, allowMalformed: true);
      }
      if (cs.contains('ascii') || cs.contains('latin') || cs.contains('8859')) {
        return latin1.decode(bytes, allowInvalid: true);
      }
      // gbk / gb2312 / big5 等：Dart 内置不支持，用 utf-8 容错兜底。
      // 若后续中文邮件出现乱码，可在此接 charset_converter（不引 pointycastle）。
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}

// ============ 数据结构 ============
class ParsedMail {
  final bool isHtml;
  final String html;
  final List<MailAttachment> attachments;

  /// 顶层原始头（键已小写，值未做 RFC2047 解码）
  final Map<String, String> headers;

  /// text/plain 正文（若有），回复/转发引用时优先用它
  final String? plainText;

  ParsedMail({
    required this.isHtml,
    required this.html,
    required this.attachments,
    this.headers = const {},
    this.plainText,
  });

  String header(String name) =>
      QccMimeParser.decodeHeaderWord(headers[name.toLowerCase()] ?? '');

  String get subject => header('subject');
  String get messageId => (headers['message-id'] ?? '').trim();
  String get references => (headers['references'] ?? '').trim();
  String get dateRaw => headers['date'] ?? '';

  List<MailAddr> get from => MailAddr.parseList(header('from'));
  List<MailAddr> get to => MailAddr.parseList(header('to'));
  List<MailAddr> get cc => MailAddr.parseList(header('cc'));
  List<MailAddr> get replyTo => MailAddr.parseList(header('reply-to'));

  /// 引用用纯文本：有 text/plain 用它，否则把 html 粗转文本
  String get quotableText {
    final t = plainText;
    if (t != null && t.trim().isNotEmpty) return t;
    if (!isHtml) return html;
    return html
        .replaceAll(
            RegExp(r'<(style|script)[^>]*>.*?</\1>',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
            RegExp(r'</(p|div|tr|li|h\d)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

/// 邮件地址（显示名 + 地址）
class MailAddr {
  final String name;
  final String email;
  const MailAddr(this.name, this.email);

  String get display => name.isEmpty ? email : name;

  @override
  String toString() => name.isEmpty ? email : '$name <$email>';

  @override
  bool operator ==(Object other) =>
      other is MailAddr && other.email.toLowerCase() == email.toLowerCase();

  @override
  int get hashCode => email.toLowerCase().hashCode;

  /// 解析单个地址："Name <a@b>" / "<a@b>" / "a@b"
  static MailAddr? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final lt = s.lastIndexOf('<');
    final gt = s.lastIndexOf('>');
    if (lt >= 0 && gt > lt) {
      final email = s.substring(lt + 1, gt).trim();
      var name = s.substring(0, lt).trim();
      if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1);
      }
      if (!email.contains('@')) return null;
      return MailAddr(name.replaceAll(r'\"', '"').trim(), email);
    }
    if (!s.contains('@')) return null;
    return MailAddr('', s.replaceAll(RegExp(r'[\s;,<>]'), ''));
  }

  /// 解析地址列表：逗号/分号分隔，忽略引号和尖括号内的分隔符
  static List<MailAddr> parseList(String raw) {
    final out = <MailAddr>[];
    final buf = StringBuffer();
    var inQuote = false;
    var inAngle = false;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '"') inQuote = !inQuote;
      if (ch == '<') inAngle = true;
      if (ch == '>') inAngle = false;
      if ((ch == ',' || ch == ';') && !inQuote && !inAngle) {
        final a = parse(buf.toString());
        if (a != null) out.add(a);
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    final a = parse(buf.toString());
    if (a != null) out.add(a);
    return out;
  }
}

class MailAttachment {
  final int partId;
  final String filename;
  final String mimeType;
  final Uint8List bytes;
  MailAttachment({
    required this.partId,
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
  int get size => bytes.length;
}

class _Entity {
  final Map<String, String> headers;
  final String mimeType;
  final Uint8List body;
  final List<_Entity> children = [];
  _Entity({required this.headers, required this.mimeType, required this.body});
}

/// 叶子节点（非 multipart），承载实际内容。
class _Leaf {
  final _Entity e;
  _Leaf(this.e);

  Map<String, String> get headers => e.headers;
  String get mimeType => e.mimeType;

  bool isMime(String prefix) => e.mimeType.startsWith(prefix);
  bool get isText => e.mimeType.startsWith('text/');

  String? get disposition {
    final d = e.headers['content-disposition'];
    return d == null ? null : QccMimeParser._firstToken(d).toLowerCase();
  }

  bool get isAttachment => disposition == 'attachment';

  String? get fileName {
    final cd = e.headers['content-disposition'];
    if (cd != null) {
      final p = QccMimeParser._parseParams(cd);
      final fn = p['filename'] ?? p['filename*'];
      if (fn != null) return QccMimeParser.decodeHeaderWord(_decodeRfc2231(fn));
    }
    final ct = e.headers['content-type'];
    if (ct != null) {
      final p = QccMimeParser._parseParams(ct);
      final name = p['name'] ?? p['name*'];
      if (name != null) return QccMimeParser.decodeHeaderWord(_decodeRfc2231(name));
    }
    return null;
  }

  String get _encoding =>
      (e.headers['content-transfer-encoding'] ?? '').trim().toLowerCase();

  String get _charset {
    final ct = e.headers['content-type'];
    if (ct == null) return 'utf-8';
    return QccMimeParser._parseParams(ct)['charset'] ?? 'utf-8';
  }

  /// 解码传输编码 → 原始字节
  Uint8List decodeBytes() {
    final bodyStr = latin1.decode(e.body);
    switch (_encoding) {
      case 'base64':
        try {
          return base64.decode(bodyStr.replaceAll(RegExp(r'\s'), ''));
        } catch (_) {
          return e.body;
        }
      case 'quoted-printable':
        return Uint8List.fromList(QccMimeParser.qpDecode(bodyStr));
      default: // 7bit / 8bit / binary / 空
        return e.body;
    }
  }

  /// 文本 part → 字符串（先解传输编码，再按 charset 解码）
  String decodeText() {
    return QccMimeParser.decodeCharset(decodeBytes(), _charset);
  }

  static String _decodeRfc2231(String v) {
    // filename*=utf-8''%E4%B8%AD.zip
    final idx = v.indexOf("''");
    if (idx >= 0) {
      try {
        return Uri.decodeFull(v.substring(idx + 2));
      } catch (_) {
        return v.substring(idx + 2);
      }
    }
    return v;
  }
}