import 'dart:convert';

import 'package:qcc_flutter/utile/LogObj.dart';

import 'MailUtils.dart';

/// 邮件附件（二进制 part：zip / pdf / 图片 / DMARC 报告等）
class MailAttachment {
  final String filename;
  final String mimeType;
  final List<int> bytes;

  MailAttachment({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  int get size => bytes.length;
}

class QccMail {
  final int? mailIndex;
  final String? from;
  final String? subject;
  final String? date;

  /// 详情页直接渲染用的 HTML（始终是可渲染的 HTML 片段）
  final String? fullBody;

  /// 列表预览用的纯文本
  final String? preview;

  /// fullBody 是否为 HTML（恒为 true，保留字段方便上层判断）
  final bool isHtml;

  /// 非文本 part（zip/pdf/图片…）
  final List<MailAttachment> attachments;

  QccMail({
    this.mailIndex,
    this.from,
    this.subject,
    this.date,
    this.fullBody,
    this.preview,
    this.isHtml = true,
    this.attachments = const [],
  });

  factory QccMail.fromJson(Map<String, dynamic> json) {
    final raw = (json['fullBody'] ?? '').toString();

    // 解析 MIME 树 → 拿到正文 + 附件
    final parsed = _parseMessage(raw);

    return QccMail(
      mailIndex: json['mailIndex'] ?? 0,
      // from / subject 解码逻辑保持原样（之前已跑通，不动）
      from: MailUtils.decodeSubject(json['from']),
      subject: _decodeRFC2047(json['subject'] ?? ''),
      date: json['date'] ?? '',
      fullBody: parsed.renderHtml,
      preview: parsed.preview,
      isHtml: true,
      attachments: parsed.attachments,
    );
  }

  // =====================================================================
  //  MIME 解析入口
  // =====================================================================

  static _ParsedMail _parseMessage(String raw) {
    if (raw.isEmpty) {
      return _ParsedMail(renderHtml: '', preview: '', attachments: const []);
    }

    final result = _CollectResult();

    try {
      final root = _parseEntity(raw);
      _collect(root, result);
    } catch (e) {
      LogObj.log('MIME 解析异常: $e');
      // 兜底：当成纯文本/HTML 处理，绝不抛给 UI
      final t = raw.trimLeft().toLowerCase();
      if (t.startsWith('<!doctype') || t.startsWith('<html') || t.startsWith('<div')) {
        result.html = raw;
      } else {
        result.text = raw;
      }
    }

    // 选正文：优先 HTML，其次纯文本，再次仅附件
    String renderHtml;
    String preview;

    if (result.html != null && result.html!.trim().isNotEmpty) {
      renderHtml = result.html!;
      preview = _htmlToPreview(result.html!);
    } else if (result.text != null && result.text!.trim().isNotEmpty) {
      renderHtml = _plainToHtml(result.text!);
      preview = _shorten(result.text!.replaceAll(RegExp(r'\s+'), ' ').trim());
    } else if (result.attachments.isNotEmpty) {
      // 没有正文（典型如 DMARC 聚合报告：整封就是一个 zip 附件）
      renderHtml = _attachmentOnlyHtml(result.attachments);
      preview = '📎 ${result.attachments.first.filename}';
    } else {
      renderHtml = '';
      preview = '';
    }

    return _ParsedMail(
      renderHtml: renderHtml,
      preview: preview,
      attachments: result.attachments,
    );
  }

  /// 把一个 MIME 实体（headers + body）解析成 _MimePart 树
  static _MimePart _parseEntity(String raw) {
    // 顶层若直接是 HTML/XML 片段（没有 MIME 头），当成 html 叶子
    final lt = raw.trimLeft();
    if (lt.startsWith('<')) {
      return _MimePart(
        contentType: 'text/html',
        charset: 'utf-8',
        encoding: '',
        body: raw,
      );
    }

    // 切分 header 区与 body 区（第一个空行）
    final split = _splitHeaderBody(raw);
    final headers = _parseHeaders(split.headerText);

    final ctRaw = headers['content-type'] ?? 'text/plain';
    final ctParams = _parseParams(ctRaw);
    final contentType = _firstSegment(ctRaw).toLowerCase();

    final encoding =
    (headers['content-transfer-encoding'] ?? '').trim().toLowerCase();

    final dispRaw = headers['content-disposition'] ?? '';
    final disposition = _firstSegment(dispRaw).toLowerCase();
    final dispParams = _parseParams(dispRaw);

    // 文件名：Content-Disposition.filename 优先，其次 Content-Type.name
    String? filename = dispParams['filename'] ??
        dispParams['filename*'] ??
        ctParams['name'] ??
        ctParams['name*'];
    if (filename != null) filename = _decodeParamValue(filename);

    final part = _MimePart(
      contentType: contentType,
      charset: ctParams['charset'] ?? 'utf-8',
      encoding: encoding,
      disposition: disposition,
      filename: filename,
      body: split.body,
    );

    // multipart：按 boundary 拆子 part 并递归
    if (contentType.startsWith('multipart/')) {
      final boundary = ctParams['boundary'];
      if (boundary != null && boundary.isNotEmpty) {
        for (final seg in _splitMultipart(split.body, boundary)) {
          if (seg.trim().isEmpty) continue;
          part.children.add(_parseEntity(seg));
        }
      }
    }

    return part;
  }

  /// 遍历 MIME 树，分流出正文与附件
  static void _collect(_MimePart part, _CollectResult r) {
    if (part.contentType.startsWith('multipart/')) {
      for (final c in part.children) {
        _collect(c, r);
      }
      return;
    }

    final bytes = _decodeBytes(part);
    final isText = part.contentType.startsWith('text/');
    final isAttachmentDisp = part.disposition == 'attachment';

    // 判二进制：非 text/* 类型、或显式 attachment、或字节像二进制 → 进附件
    if (!isText || isAttachmentDisp || _looksBinary(bytes)) {
      r.attachments.add(MailAttachment(
        filename: part.filename ?? _guessFilename(part.contentType, bytes),
        mimeType: part.contentType,
        bytes: bytes,
      ));
      return;
    }

    final text = _decodeText(bytes, part.charset);
    if (part.contentType == 'text/html') {
      r.html ??= text;
    } else {
      r.text ??= text;
    }
  }

  // =====================================================================
  //  解码：transfer-encoding → bytes，charset → string
  // =====================================================================

  /// 按 Content-Transfer-Encoding 把 part body 解成原始字节
  static List<int> _decodeBytes(_MimePart part) {
    final body = part.body;
    switch (part.encoding) {
      case 'base64':
        try {
          return base64.decode(body.replaceAll(RegExp(r'\s+'), ''));
        } catch (_) {
          return latin1.encode(body);
        }
      case 'quoted-printable':
        return _qpDecodeBytes(body);
      case '7bit':
      case '8bit':
      case 'binary':
      case '':
      default:
      // 未编码：用 latin1 保字节（避免 utf8 二次破坏多字节序列）
        return latin1.encode(body);
    }
  }

  /// charset → String（支持 utf-8 / ascii / latin1，其余按 utf-8 容错）
  static String _decodeText(List<int> bytes, String charset) {
    final cs = charset.toLowerCase();
    try {
      if (cs.contains('ascii') ||
          cs.contains('latin') ||
          cs.contains('8859') ||
          cs.contains('windows-1252')) {
        return latin1.decode(bytes, allowInvalid: true);
      }
      // 默认 utf-8（含 gb 系列也先按 utf8 容错，避免乱抛）
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  /// Quoted-Printable 解成字节（正确处理 =3D、软换行、十六进制）
  static List<int> _qpDecodeBytes(String data) {
    // 软换行：行尾的 = 表示折行，去掉
    String s = data.replaceAll('=\r\n', '').replaceAll('=\n', '');
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
        out.add(ch.codeUnitAt(0)); // 非法十六进制，原样保留 '='
      } else {
        out.add(ch.codeUnitAt(0));
      }
    }
    return out;
  }

  // =====================================================================
  //  Header / 参数解析
  // =====================================================================

  static _HeaderBody _splitHeaderBody(String raw) {
    int idx = -1;
    int sepLen = 0;
    final a = raw.indexOf('\r\n\r\n');
    final b = raw.indexOf('\n\n');
    if (a != -1 && (b == -1 || a <= b)) {
      idx = a;
      sepLen = 4;
    } else if (b != -1) {
      idx = b;
      sepLen = 2;
    }
    if (idx == -1) {
      // 没有空行：整段当 header（极少见），body 为空
      return _HeaderBody(raw, '');
    }
    return _HeaderBody(raw.substring(0, idx), raw.substring(idx + sepLen));
  }

  /// 解析 header，处理折行（续行以空格/Tab 开头）
  static Map<String, String> _parseHeaders(String headerText) {
    final headers = <String, String>{};
    String? key;
    final buf = StringBuffer();

    void flush() {
      if (key != null) headers[key!] = buf.toString().trim();
      buf.clear();
    }

    for (var line in headerText.split('\n')) {
      line = line.replaceAll('\r', '');
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && key != null) {
        buf.write(' ');
        buf.write(line.trim());
      } else {
        final c = line.indexOf(':');
        if (c == -1) continue;
        flush();
        key = line.substring(0, c).trim().toLowerCase();
        buf.write(line.substring(c + 1).trim());
      }
    }
    flush();
    return headers;
  }

  /// `text/html; charset="utf-8"; boundary=xxx` → 取分号前主值
  static String _firstSegment(String value) {
    return _splitSemicolonsAware(value).first.trim();
  }

  /// 解析 header 参数（分号后的 k=v），处理引号
  static Map<String, String> _parseParams(String value) {
    final params = <String, String>{};
    final segs = _splitSemicolonsAware(value);
    for (int i = 1; i < segs.length; i++) {
      final s = segs[i].trim();
      final eq = s.indexOf('=');
      if (eq == -1) continue;
      final k = s.substring(0, eq).trim().toLowerCase();
      var v = s.substring(eq + 1).trim();
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      params[k] = v;
    }
    return params;
  }

  /// 按分号切，但忽略引号内的分号
  static List<String> _splitSemicolonsAware(String value) {
    final out = <String>[];
    final buf = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch == '"') inQuote = !inQuote;
      if (ch == ';' && !inQuote) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString());
    return out;
  }

  /// 参数值解码：兼容 RFC 2047(=?utf-8?B?..?=) 与 RFC 2231(utf-8''..%xx)
  static String _decodeParamValue(String v) {
    if (v.contains("''")) {
      // RFC 2231: charset'lang'percent-encoded
      final idx = v.indexOf("''");
      final encoded = v.substring(idx + 2);
      try {
        return Uri.decodeFull(encoded);
      } catch (_) {
        return encoded;
      }
    }
    return _decodeRFC2047(v);
  }

  // =====================================================================
  //  Multipart 拆分
  // =====================================================================

  static List<String> _splitMultipart(String body, String boundary) {
    final delim = '--$boundary';
    final close = '$delim--';
    final parts = <String>[];
    StringBuffer? cur;

    for (final rawLine in body.split('\n')) {
      final line = rawLine.replaceAll('\r', '');
      if (line == delim) {
        if (cur != null) parts.add(cur.toString());
        cur = StringBuffer();
      } else if (line == close) {
        if (cur != null) parts.add(cur.toString());
        cur = null;
        break;
      } else if (cur != null) {
        cur.write(rawLine);
        cur.write('\n');
      }
      // boundary 之前的 preamble 直接丢弃
    }
    return parts;
  }

  // =====================================================================
  //  二进制识别 / 文件名猜测
  // =====================================================================

  static bool _looksBinary(List<int> b) {
    if (b.isEmpty) return false;
    if (b.length >= 2 && b[0] == 0x50 && b[1] == 0x4B) return true; // PK (zip)
    if (b.length >= 2 && b[0] == 0x1F && b[1] == 0x8B) return true; // gzip
    if (b.length >= 4 &&
        b[0] == 0x25 &&
        b[1] == 0x50 &&
        b[2] == 0x44 &&
        b[3] == 0x46) return true; // %PDF
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return true; // jpeg
    }
    if (b.length >= 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) return true; // png

    // 控制字符比例过高 → 视为二进制
    final n = b.length < 512 ? b.length : 512;
    int ctrl = 0;
    for (int i = 0; i < n; i++) {
      final c = b[i];
      if (c == 0) return true;
      if (c < 9 || (c > 13 && c < 32)) ctrl++;
    }
    return ctrl > n * 0.1;
  }

  static String _guessFilename(String mime, List<int> b) {
    if (b.length >= 2 && b[0] == 0x50 && b[1] == 0x4B) return 'attachment.zip';
    if (b.length >= 2 && b[0] == 0x1F && b[1] == 0x8B) return 'attachment.gz';
    if (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50) return 'attachment.pdf';
    if (mime.contains('png')) return 'image.png';
    if (mime.contains('jpeg') || mime.contains('jpg')) return 'image.jpg';
    return 'attachment.bin';
  }

  // =====================================================================
  //  正文 → 渲染 HTML / 预览
  // =====================================================================

  static String _plainToHtml(String text) {
    final esc = _escapeHtml(text);
    return '<pre style="white-space:pre-wrap;word-break:break-word;'
        'font-family:-apple-system,BlinkMacSystemFont,\'PingFang SC\',sans-serif;'
        'font-size:15px;line-height:1.6;margin:0;">$esc</pre>';
  }

  static String _attachmentOnlyHtml(List<MailAttachment> atts) {
    final sb = StringBuffer(
        '<div style="font-family:-apple-system,sans-serif;color:#444;'
            'font-size:15px;line-height:1.8;">'
            '<p>此邮件不含正文，包含以下附件：</p><ul>');
    for (final a in atts) {
      sb.write('<li>📎 ${_escapeHtml(a.filename)} '
          '<span style="color:#999;">(${_humanSize(a.size)})</span></li>');
    }
    sb.write('</ul></div>');
    return sb.toString();
  }

  static String _htmlToPreview(String html) {
    String clean = html.replaceAll(
        RegExp(r'<(style|script)[^>]*>.*?</\1>', dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');
    clean = clean
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _shorten(clean);
  }

  static String _shorten(String s, [int max = 50]) {
    return s.length > max ? '${s.substring(0, max)}...' : s;
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _humanSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  // =====================================================================
  //  RFC 2047 标题解码（保留原实现，已跑通）
  // =====================================================================

  static String _decodeRFC2047(String text) {
    if (!text.contains('=?')) return text;
    final pattern = RegExp(r"=\?([\w-]+)\?([BbQq])\?(.*?)\?=");

    return text.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        final encoding = match.group(2)!.toUpperCase();
        final data = match.group(3)!;
        try {
          if (encoding == 'B') {
            return utf8.decode(base64.decode(data), allowMalformed: true);
          } else {
            // Q 编码：下划线代表空格
            return utf8.decode(_qpDecodeBytes(data.replaceAll('_', ' ')),
                allowMalformed: true);
          }
        } catch (e) {
          return match.group(0)!;
        }
      },
      onNonMatch: (String nonMatch) => nonMatch,
    );
  }

  // =====================================================================
  //  兼容旧调用：纯文本预览清洗（若别处仍在引用）
  // =====================================================================

  static String getCleanPreview(String decodedBody) {
    return _htmlToPreview(decodedBody);
  }
}

// =======================================================================
//  内部数据结构
// =======================================================================

class _MimePart {
  final String contentType; // 已小写，如 text/html
  final String charset;
  final String encoding; // 已小写，如 base64
  final String? disposition; // 已小写，如 attachment
  final String? filename;
  final String body; // 该 part 的原始 body 文本
  final List<_MimePart> children = [];

  _MimePart({
    required this.contentType,
    required this.charset,
    required this.encoding,
    this.disposition,
    this.filename,
    required this.body,
  });
}

class _CollectResult {
  String? html;
  String? text;
  final List<MailAttachment> attachments = [];
}

class _ParsedMail {
  final String renderHtml;
  final String preview;
  final List<MailAttachment> attachments;

  _ParsedMail({
    required this.renderHtml,
    required this.preview,
    required this.attachments,
  });
}

class _HeaderBody {
  final String headerText;
  final String body;
  _HeaderBody(this.headerText, this.body);
}