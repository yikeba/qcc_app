import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ComposeMailPage.dart';
import 'GmailStyleMailList.dart';
import 'MailCenter.dart';
import 'MailFileHelper.dart';
import 'MailMimeBuilder.dart';
import 'QccMailInAppWebView.dart'; // 你已有的 QccMailWebView
import 'QccMimeParser.dart';

/// 邮件详情页。
/// 按 key 从 MailCenter 取列表项；原文本地缓存优先（没有则下载），
/// QccMimeParser 本地解析，QccMailWebView 渲染正文。
///
/// [embedded] = true 时嵌在宽屏右侧阅读窗格中（无返回键，操作后回调 [onClosed]）。
class QccMailDetailPage extends StatefulWidget {
  final String user;
  final String itemKey;
  final bool embedded;
  final VoidCallback? onClosed;

  const QccMailDetailPage({
    super.key,
    required this.user,
    required this.itemKey,
    this.embedded = false,
    this.onClosed,
  });

  @override
  State<QccMailDetailPage> createState() => _QccMailDetailPageState();
}

class _QccMailDetailPageState extends State<QccMailDetailPage> {
  late final MailCenter _center = MailCenter.of(widget.user);
  ParsedMail? _parsed;
  String? _error;
  bool _showDetails = false;

  MailItem? get _item => _center.byKey(widget.itemKey);

  @override
  void initState() {
    super.initState();
    final m = _item;
    if (m != null && !m.read) _center.setRead([m], true);
    _load();
  }

  Future<void> _load() async {
    final m = _item;
    if (m == null) {
      setState(() => _error = '邮件不存在');
      return;
    }
    try {
      final raw = await _center.rawOf(m);
      final parsed = QccMimeParser.parse(raw); // 本地解析
      if (mounted) setState(() => _parsed = parsed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ───────────────────────── 操作 ─────────────────────────

  void _close() {
    if (widget.embedded) {
      widget.onClosed?.call();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _moveTo(String folder, String doneText) {
    final m = _item;
    if (m == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final snapshot = _center.move([m], folder);
    _close();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(doneText),
        action: SnackBarAction(
            label: '撤销', onPressed: () => _center.undoMove(snapshot)),
      ));
  }

  Future<void> _deleteForever() async {
    final m = _item;
    if (m == null) return;
    final ok = await _confirm('永久删除', '此操作将从本机永久删除该邮件，无法撤销。');
    if (ok != true) return;
    await _center.deleteForever([m]);
    _close();
  }

  Future<void> _block() async {
    final m = _item;
    if (m == null) return;
    final email = m.senderEmail;
    final at = email.lastIndexOf('@');
    final domain = at >= 0 ? email.substring(at) : '';
    if (_center.isBlocked(email)) {
      final entry = _center.blacklist.contains(email) ? email : domain;
      await _center.unblock(entry);
      _toast('已取消屏蔽 $entry');
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('屏蔽发件人'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, email),
            child: Text('仅屏蔽 $email'),
          ),
          if (domain.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, domain),
              child: Text('屏蔽整个域名 $domain'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await _center.block(choice);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _close();
    messenger.showSnackBar(SnackBar(
      content: Text('已屏蔽 $choice，其邮件将进入垃圾邮件'),
      action: SnackBarAction(
          label: '撤销', onPressed: () => _center.unblock(choice)),
    ));
  }

  void _compose(OutgoingMail mail, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ComposeMailPage(user: widget.user, initial: mail, title: title),
      ),
    );
  }

  /// 回复 / 全部回复
  void _reply({required bool all}) {
    final m = _item;
    final p = _parsed;
    if (m == null || p == null) return;
    final me = _center.me;

    List<MailAddr> to;
    var cc = <MailAddr>[];
    if (m.kind == MailKind.sent) {
      // 回复自己发出的邮件 = 再发给原收件人
      to = p.to;
      if (all) cc = p.cc;
    } else {
      to = p.replyTo.isNotEmpty ? p.replyTo : p.from;
      if (to.isEmpty && m.from.isNotEmpty) to = [MailAddr(m.fromName, m.from)];
      if (all) {
        final seen = <MailAddr>{me, ...to};
        to = [...to, ...p.to.where(seen.add)];
        cc = p.cc.where(seen.add).toList();
      }
    }
    to = to.where((a) => a != me).toList();

    final subj = _prefixed(p.subject.isEmpty ? m.subject : p.subject, 'Re: ',
        const ['re:', '回复:', '答复:']);
    final who = p.from.isNotEmpty ? p.from.first.toString() : m.from;
    final head = '在 ${fullDate(m.epoch)}，$who 写道：';
    final quotedText =
        '$head\n${p.quotableText.split('\n').map((l) => '> $l').join('\n')}';
    final quotedHtml =
        '${_esc(head)}<br>${p.isHtml ? _sanitize(p.html) : MailMimeBuilder.textToHtml(p.html)}';

    _compose(
      OutgoingMail(
        to: to,
        cc: cc,
        subject: subj,
        body: _center.signature.isEmpty ? '' : '\n\n-- \n${_center.signature}',
        quotedText: quotedText,
        quotedHtml: quotedHtml,
        inReplyTo: p.messageId.isEmpty ? null : p.messageId,
        references: p.references.isEmpty ? null : p.references,
      ),
      all ? '全部回复' : '回复',
    );
  }

  void _forward() {
    final m = _item;
    final p = _parsed;
    if (m == null || p == null) return;
    final subj = _prefixed(p.subject.isEmpty ? m.subject : p.subject, 'Fwd: ',
        const ['fwd:', 'fw:', '转发:']);
    final head = StringBuffer()
      ..writeln('---------- 转发的邮件 ----------')
      ..writeln('发件人: ${p.from.isNotEmpty ? p.from.first : m.from}')
      ..writeln('日期: ${fullDate(m.epoch)}')
      ..writeln('主题: ${p.subject.isEmpty ? m.subject : p.subject}')
      ..writeln('收件人: ${p.to.join(', ')}');
    if (p.cc.isNotEmpty) head.writeln('抄送: ${p.cc.join(', ')}');

    _compose(
      OutgoingMail(
        subject: subj,
        body: _center.signature.isEmpty ? '' : '\n\n-- \n${_center.signature}',
        quotedText: '$head\n${p.quotableText}',
        quotedHtml:
            '${MailMimeBuilder.textToHtml(head.toString())}<br>${p.isHtml ? _sanitize(p.html) : MailMimeBuilder.textToHtml(p.html)}',
        attachments: p.attachments
            .map((a) => OutgoingAttachment(
                filename: a.filename, mimeType: a.mimeType, bytes: a.bytes))
            .toList(),
      ),
      '转发',
    );
  }

  Future<void> _saveAttachment(MailAttachment a) async {
    try {
      final path = await MailFileHelper.saveAttachment(
          filename: a.filename, bytes: a.bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已保存到 $path'),
        action: MailFileHelper.canOpen
            ? SnackBarAction(
                label: '打开', onPressed: () => MailFileHelper.open(path))
            : null,
      ));
    } catch (e) {
      _toast('保存失败: $e');
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _center,
      builder: (context, _) {
        final m = _item;
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            leading: widget.embedded
                ? IconButton(
                    icon: const Icon(Icons.close), onPressed: _close)
                : null,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0.5,
            actions: m == null ? null : _actions(m),
          ),
          body: m == null
              ? const Center(child: Text('邮件已移除'))
              : _buildBody(m),
          bottomNavigationBar:
              (_parsed == null || m == null) ? null : _buildBottomBar(),
        );
      },
    );
  }

  List<Widget> _actions(MailItem m) {
    final inTrash = m.folder == 'trash';
    final inSpam = m.folder == 'spam';
    return [
      if (m.folder != 'archive' && !inTrash && !inSpam)
        IconButton(
          tooltip: '归档',
          icon: const Icon(Icons.archive_outlined),
          onPressed: () => _moveTo('archive', '已归档'),
        ),
      if (inTrash)
        IconButton(
          tooltip: '永久删除',
          icon: const Icon(Icons.delete_forever_outlined),
          onPressed: _deleteForever,
        )
      else
        IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _moveTo('trash', '已移至已删除'),
        ),
      if (m.kind == MailKind.received)
        IconButton(
          tooltip: '标为未读',
          icon: const Icon(Icons.mark_email_unread_outlined),
          onPressed: () {
            _center.setRead([m], false);
            _close();
          },
        ),
      PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'inbox':
              _moveTo('inbox', m.kind == MailKind.sent ? '已移回已发送' : '已移至收件箱');
              break;
            case 'spam':
              _moveTo('spam', '已标记为垃圾邮件');
              break;
            case 'block':
              _block();
              break;
            case 'copy':
              Clipboard.setData(ClipboardData(text: m.from));
              _toast('已复制 ${m.from}');
              break;
            case 'star':
              _center.setStar([m], !m.star);
              break;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'star', child: Text(m.star ? '移除星标' : '加星标')),
          if (m.folder != 'inbox' && m.folder != 'sent')
            PopupMenuItem(
                value: 'inbox',
                child: Text(inSpam
                    ? '不是垃圾邮件'
                    : (m.kind == MailKind.sent ? '移回已发送' : '移至收件箱'))),
          if (!inSpam && m.kind == MailKind.received)
            const PopupMenuItem(value: 'spam', child: Text('标记为垃圾邮件')),
          if (m.kind == MailKind.received)
            PopupMenuItem(
              value: 'block',
              child: Text(_center.isBlocked(m.senderEmail)
                  ? '取消屏蔽发件人'
                  : '屏蔽发件人（加入黑名单）'),
            ),
          const PopupMenuItem(value: 'copy', child: Text('复制发件人地址')),
        ],
      ),
    ];
  }

  Widget _buildBody(MailItem m) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text('加载失败: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() => _error = null);
                  _load();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final parsed = _parsed;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSubject(m),
          _buildSender(m, parsed),
          if (_center.isBlocked(m.senderEmail) && m.kind == MailKind.received)
            _banner(Icons.block, '该发件人已在黑名单中', Colors.red[50]!),
          const Divider(height: 1),
          if (parsed == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_renderHtml(parsed).trim().isNotEmpty)
              QccMailWebView(
                  key: ValueKey(widget.itemKey), html: _renderHtml(parsed))
            else
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('此邮件无正文', style: TextStyle(color: Colors.grey)),
              ),
            if (parsed.attachments.isNotEmpty)
              _buildAttachments(parsed.attachments),
          ],
        ],
      ),
    );
  }

  Widget _buildSubject(MailItem m) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                _parsed?.subject.isNotEmpty == true ? _parsed!.subject : m.subject,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            if (m.kind != MailKind.draft)
              IconButton(
                onPressed: () => _center.setStar([m], !m.star),
                icon: Icon(m.star ? Icons.star : Icons.star_border,
                    color: m.star ? const Color(0xFFF4B400) : Colors.grey),
              ),
          ],
        ),
      );

  Widget _buildSender(MailItem m, ParsedMail? p) {
    final from = p?.from.isNotEmpty == true
        ? p!.from.first
        : MailAddr(m.fromName, m.from);
    final name = from.display;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF1A73E8),
                child: Text(initial, style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    InkWell(
                      onTap: () => setState(() => _showDetails = !_showDetails),
                      child: Row(children: [
                        Flexible(
                          child: Text(
                            p == null
                                ? m.from
                                : '至 ${p.to.map((e) => e.email == _center.me.email ? '我' : e.display).join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ),
                        Icon(_showDetails ? Icons.expand_less : Icons.expand_more,
                            size: 18, color: Colors.grey),
                      ]),
                    ),
                  ],
                ),
              ),
              Text(smartDate(m.epoch),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          if (_showDetails && p != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('发件人', from.toString()),
                  if (p.replyTo.isNotEmpty)
                    _detailRow('回复至', p.replyTo.join(', ')),
                  _detailRow('收件人', p.to.join(', ')),
                  if (p.cc.isNotEmpty) _detailRow('抄送', p.cc.join(', ')),
                  _detailRow('日期', fullDate(m.epoch)),
                  if (m.sha256 != null) _detailRow('SHA-256', m.sha256!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  Widget _banner(IconData icon, String text, Color bg) => Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _buildBottomBar() {
    ButtonStyle outline() => OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey[400]!),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _reply(all: false),
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('回复'),
                style: outline(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _reply(all: true),
                icon: const Icon(Icons.reply_all, size: 18),
                label: const Text('全部'),
                style: outline(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _forward,
                icon: const Icon(Icons.forward, size: 18),
                label: const Text('转发'),
                style: outline(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO[v2]: 存证上链 —— 原文 sha256(m.sha256 / 本地复算) 写入 QCC 容器
                  _toast('存证上链功能开发中');
                },
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('存证'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2933),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachments(List<MailAttachment> attachments) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('附件 (${attachments.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ...attachments.map((a) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconFor(a.mimeType), color: Colors.blueAccent),
                title: Text(a.filename,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(MailFileHelper.humanSize(a.size)),
                trailing: IconButton(
                  tooltip: '保存',
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: () => _saveAttachment(a),
                ),
                onTap: () => _saveAttachment(a),
              )),
        ],
      ),
    );
  }

  // ───────────────────────── 工具 ─────────────────────────

  String _renderHtml(ParsedMail p) =>
      p.isHtml ? p.html : _plainToHtml(p.html);

  String _plainToHtml(String text) {
    final esc = _esc(text);
    return '<pre style="white-space:pre-wrap;word-break:break-word;'
        "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;"
        'font-size:15px;line-height:1.6;margin:0;">$esc</pre>';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 引用原文时去掉脚本 / head，避免把对方的脚本带进自己发出的邮件
  static String _sanitize(String html) => html
      .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
          '')
      .replaceAll(
          RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'</?(html|body)[^>]*>', caseSensitive: false), '');

  static String _prefixed(String subject, String prefix, List<String> known) {
    final l = subject.trimLeft().toLowerCase();
    return known.any(l.startsWith) ? subject : '$prefix$subject';
  }

  static IconData _iconFor(String mime) {
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定', style: TextStyle(color: Colors.red))),
          ],
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
