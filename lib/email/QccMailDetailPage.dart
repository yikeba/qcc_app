import 'package:flutter/material.dart';
import 'MailSyncService.dart';
import 'QccMimeParser.dart';
import 'QccMailInAppWebView.dart'; // 你已有的 QccMailWebView
import 'ComposeMailPage.dart';

/// 邮件详情页。
/// 按 seq 取本地缓存的 .eml（没有则下载），用自写 QccMimeParser 本地解析，
/// QccMailWebView 渲染正文，附件本地解码后可保存/分享，底部支持回复。
class QccMailDetailPage extends StatefulWidget {
  final MailSyncService sync;
  final int seq;
  final String subject;
  final String? from;          // 原发件人，用于回复
  final String? expectSha256;

  const QccMailDetailPage({
    super.key,
    required this.sync,
    required this.seq,
    required this.subject,
    this.from,
    this.expectSha256,
  });

  @override
  State<QccMailDetailPage> createState() => _QccMailDetailPageState();
}

class _QccMailDetailPageState extends State<QccMailDetailPage> {
  ParsedMail? _parsed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.sync
          .getRawCached(widget.seq, expectSha256: widget.expectSha256);
      final parsed = QccMimeParser.parse(raw); // 本地解析
      if (mounted) setState(() => _parsed = parsed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // 提取纯邮箱地址：从 "Name <a@b.com>" 里抠出 a@b.com
  String _extractAddress(String from) {
    final lt = from.indexOf('<');
    final gt = from.indexOf('>');
    if (lt >= 0 && gt > lt) return from.substring(lt + 1, gt).trim();
    return from.trim();
  }

  void _reply() {
    final fromAddr = _extractAddress(widget.from ?? '');
    final subj = widget.subject.startsWith('Re:') || widget.subject.startsWith('回复:')
        ? widget.subject
        : 'Re: ${widget.subject}';

    // 引用原文（取纯文本预览，避免把整段 html 塞进去）
    String quoted = '';
    final p = _parsed;
    if (p != null) {
      final plain = _htmlToPlain(p.html);
      if (plain.trim().isNotEmpty) {
        quoted = '\n\n--------------- 原始邮件 ---------------\n'
            '发件人: ${widget.from ?? ''}\n'
            '主题: ${widget.subject}\n\n'
            '$plain';
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComposeMailPage(
          presetTo: fromAddr,
          presetSubject: subj,
          presetBody: quoted,
        ),
      ),
    );
  }

  String _htmlToPlain(String html) {
    return html
        .replaceAll(RegExp(r'<(style|script)[^>]*>.*?</\1>', dotAll: true), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.subject,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _buildBody(),
      bottomNavigationBar: _parsed == null ? null : _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _reply,
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('回复'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blueAccent,
                  side: const BorderSide(color: Colors.blueAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: 存证上链（v2 接 QCC 容器 / proof-of-data）
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('存证上链功能开发中')),
                  );
                },
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('存证上链'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2933),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
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
    if (parsed == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final renderHtml = parsed.isHtml ? parsed.html : _plainToHtml(parsed.html);
    final hasBody = renderHtml.trim().isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBody)
            QccMailWebView(html: renderHtml)
          else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('此邮件无正文', style: TextStyle(color: Colors.grey)),
            ),
          if (parsed.attachments.isNotEmpty) _buildAttachments(parsed.attachments),
        ],
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
          ...attachments.map(_attachmentTile),
        ],
      ),
    );
  }

  Widget _attachmentTile(MailAttachment a) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.blueAccent),
      title: Text(a.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_humanSize(a.size)),
      trailing: const Icon(Icons.download_outlined, size: 20),
      onTap: () {
        // 附件字节已在本地（a.bytes）。TODO: 接 path_provider 写临时文件 +
        // open_filex 打开，或 share_plus 分享。
        _toast('已解码 ${a.filename}：${_humanSize(a.size)}（字节已在本地）');
      },
    );
  }

  String _plainToHtml(String text) {
    final esc = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<pre style="white-space:pre-wrap;word-break:break-word;'
        "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;"
        'font-size:15px;line-height:1.6;margin:0;">$esc</pre>';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _humanSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}