import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'QccMimeParser.dart';

/// 发信附件
class OutgoingAttachment {
  final String filename;
  final String mimeType;
  final Uint8List bytes;

  const OutgoingAttachment({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });

  int get size => bytes.length;

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'mimeType': mimeType,
        'b64': base64.encode(bytes),
      };

  static OutgoingAttachment? fromJson(Map<String, dynamic> j) {
    try {
      return OutgoingAttachment(
        filename: j['filename'] as String,
        mimeType: j['mimeType'] as String? ?? 'application/octet-stream',
        bytes: base64.decode(j['b64'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// 按扩展名猜 MIME 类型（常见类型即可，未知按二进制）
  static String guessMime(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
    const map = {
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'gz': 'application/gzip',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'svg': 'image/svg+xml',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'eml': 'message/rfc822',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}

/// 自写 RFC 5322 / MIME 构造器（不引第三方依赖）。
///
/// 结构：
///   无附件： multipart/alternative( text/plain , text/html )
///   有附件： multipart/mixed( multipart/alternative(...), 附件1, 附件2 ... )
///
/// 注意：Bcc 不写入邮件头（只出现在 SMTP 信封 rcpt 中），避免泄露密送人。
class MailMimeBuilder {
  static final Random _rnd = Random.secure();

  static ({Uint8List raw, String messageId}) build({
    required MailAddr from,
    required List<MailAddr> to,
    List<MailAddr> cc = const [],
    required String subject,
    required String text,
    String? html,
    List<OutgoingAttachment> attachments = const [],
    String? inReplyTo,
    String? references,
    DateTime? date,
  }) {
    final domain = from.email.contains('@')
        ? from.email.substring(from.email.indexOf('@') + 1)
        : 'qccio.com';
    final messageId = '<${_randomId(24)}.${DateTime.now().millisecondsSinceEpoch}@$domain>';

    final sb = StringBuffer();
    void h(String name, String value) => sb.write('$name: $value\r\n');

    h('Date', formatRfc5322Date(date ?? DateTime.now()));
    h('From', _addr(from));
    if (to.isNotEmpty) h('To', _foldAddrList(to));
    if (cc.isNotEmpty) h('Cc', _foldAddrList(cc));
    h('Subject', encodeHeaderText(subject));
    h('Message-ID', messageId);
    if (inReplyTo != null && inReplyTo.isNotEmpty) {
      h('In-Reply-To', inReplyTo);
      final refs = [
        if (references != null && references.isNotEmpty) references,
        inReplyTo,
      ].join(' ');
      h('References', _foldWords(refs));
    }
    h('MIME-Version', '1.0');
    h('X-Mailer', 'QCC Mail');

    final altBoundary = '=_alt_${_randomId(20)}';
    final alt = StringBuffer()
      ..write('--$altBoundary\r\n')
      ..write('Content-Type: text/plain; charset=UTF-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n\r\n')
      ..write(_b64Lines(utf8.encode(text)))
      ..write('--$altBoundary\r\n')
      ..write('Content-Type: text/html; charset=UTF-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n\r\n')
      ..write(_b64Lines(utf8.encode(html ?? textToHtml(text))))
      ..write('--$altBoundary--\r\n');

    if (attachments.isEmpty) {
      h('Content-Type', 'multipart/alternative; boundary="$altBoundary"');
      sb
        ..write('\r\n')
        ..write(alt);
    } else {
      final mixBoundary = '=_mix_${_randomId(20)}';
      h('Content-Type', 'multipart/mixed; boundary="$mixBoundary"');
      sb
        ..write('\r\n')
        ..write('--$mixBoundary\r\n')
        ..write('Content-Type: multipart/alternative; boundary="$altBoundary"\r\n\r\n')
        ..write(alt);
      for (final a in attachments) {
        // 引号参数内不折行，编码字之间用空格
        final encName =
            encodeHeaderText(a.filename.replaceAll('"', '')).replaceAll('\r\n ', ' ');
        final pct = Uri.encodeComponent(a.filename);
        sb
          ..write('--$mixBoundary\r\n')
          ..write('Content-Type: ${a.mimeType}; name="$encName"\r\n')
          ..write('Content-Transfer-Encoding: base64\r\n')
          ..write('Content-Disposition: attachment; '
              'filename="$encName"; filename*=UTF-8\'\'$pct\r\n\r\n')
          ..write(_b64Lines(a.bytes));
      }
      sb.write('--$mixBoundary--\r\n');
    }

    return (
      raw: Uint8List.fromList(utf8.encode(sb.toString())),
      messageId: messageId,
    );
  }

  // ───────────────────────── 工具 ─────────────────────────

  /// 纯文本 → HTML 片段（转义 + 换行）
  static String textToHtml(String text) {
    final esc = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '<br>\n');
    return '<div style="font-family:-apple-system,BlinkMacSystemFont,'
        '\'PingFang SC\',sans-serif;font-size:14px;line-height:1.6;">$esc</div>';
  }

  /// 头部文本编码：纯 ASCII 原样，否则 RFC2047 B 编码（按 UTF-8 字符边界切块，每块 ≤45 字节）
  static String encodeHeaderText(String s) {
    if (_isAscii(s)) return s;
    final words = <String>[];
    final chunk = <int>[];
    for (final rune in s.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (chunk.length + bytes.length > 45) {
        words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
        chunk.clear();
      }
      chunk.addAll(bytes);
    }
    if (chunk.isNotEmpty) words.add('=?UTF-8?B?${base64.encode(chunk)}?=');
    return words.join('\r\n ');
  }

  static String _addr(MailAddr a) {
    if (a.name.isEmpty) return a.email;
    if (_isAscii(a.name)) {
      return '"${a.name.replaceAll('"', '')}" <${a.email}>';
    }
    return '${encodeHeaderText(a.name)} <${a.email}>';
  }

  static String _foldAddrList(List<MailAddr> list) =>
      list.map(_addr).join(',\r\n ');

  static String _foldWords(String s) =>
      s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join('\r\n ');

  static String _b64Lines(List<int> bytes) {
    final b64 = base64.encode(bytes);
    final sb = StringBuffer();
    for (var i = 0; i < b64.length; i += 76) {
      sb
        ..write(b64.substring(i, min(i + 76, b64.length)))
        ..write('\r\n');
    }
    return sb.toString();
  }

  static bool _isAscii(String s) => s.codeUnits.every((c) => c < 128);

  static String _randomId(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(len, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  /// RFC 5322 日期：Wed, 28 Oct 2026 09:51:00 +0700
  static String formatRfc5322Date(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final local = dt.toLocal();
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = off.inHours.abs().toString().padLeft(2, '0');
    final om = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[local.weekday - 1]}, ${local.day} ${months[local.month - 1]} '
        '${local.year} ${two(local.hour)}:${two(local.minute)}:${two(local.second)} '
        '$sign$oh$om';
  }
}
