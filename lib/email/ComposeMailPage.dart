import 'package:flutter/material.dart';

import 'MailCenter.dart';
import 'MailFileHelper.dart';
import 'MailMimeBuilder.dart';
import 'MailUtils.dart';
import 'QccMimeParser.dart';

/// 写信页：收件人/抄送/密送（标签式 + 联系人补全）、群发单显、附件、
/// 草稿、回复/转发引用、5 秒撤销发送。
class ComposeMailPage extends StatefulWidget {
  /// 邮箱账户（与 QccMailHomePage.user 相同）；不传则用 MailUtils.emailid
  final String? user;

  /// 预填内容（回复/转发/草稿/撤销发送后恢复）
  final OutgoingMail? initial;

  /// 标题：写邮件 / 回复 / 全部回复 / 转发
  final String? title;

  // 兼容旧调用方式
  final String? presetTo;
  final String? presetSubject;
  final String? presetBody;

  const ComposeMailPage({
    super.key,
    this.user,
    this.initial,
    this.title,
    this.presetTo,
    this.presetSubject,
    this.presetBody,
  });

  @override
  State<ComposeMailPage> createState() => _ComposeMailPageState();
}

class _ComposeMailPageState extends State<ComposeMailPage> {
  late final MailCenter _center =
      MailCenter.of(widget.user ?? MailUtils.emailid);

  final List<MailAddr> _to = [];
  final List<MailAddr> _cc = [];
  final List<MailAddr> _bcc = [];
  final List<OutgoingAttachment> _attachments = [];
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;
  final FocusNode _bodyFocus = FocusNode();

  final _toKey = GlobalKey<_RecipientFieldState>();
  final _ccKey = GlobalKey<_RecipientFieldState>();
  final _bccKey = GlobalKey<_RecipientFieldState>();

  bool _showCcBcc = false;
  bool _individually = false;
  bool _showQuoted = false;
  String? _draftId;
  String? _quotedHtml;
  String? _quotedText;
  String? _inReplyTo;
  String? _references;

  @override
  void initState() {
    super.initState();
    _center.init();
    final m = widget.initial;
    if (m != null) {
      _to.addAll(m.to);
      _cc.addAll(m.cc);
      _bcc.addAll(m.bcc);
      _attachments.addAll(m.attachments);
      _individually = m.individually;
      _draftId = m.draftId;
      _quotedHtml = m.quotedHtml;
      _quotedText = m.quotedText;
      _inReplyTo = m.inReplyTo;
      _references = m.references;
      _showCcBcc = m.cc.isNotEmpty || m.bcc.isNotEmpty;
    } else if (widget.presetTo != null) {
      _to.addAll(MailAddr.parseList(widget.presetTo!));
    }
    _subjectCtrl =
        TextEditingController(text: m?.subject ?? widget.presetSubject ?? '');
    var body = m?.body ?? widget.presetBody ?? '';
    if (m == null && widget.presetBody == null && _center.signature.isNotEmpty) {
      body = '\n\n-- \n${_center.signature}';
    }
    _bodyCtrl = TextEditingController(text: body)
      ..selection = const TextSelection.collapsed(offset: 0);
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  OutgoingMail _collect() {
    // 把输入框里还没回车确认的地址也收进来
    _toKey.currentState?.commit();
    _ccKey.currentState?.commit();
    _bccKey.currentState?.commit();
    return OutgoingMail(
      to: List.of(_to),
      cc: List.of(_cc),
      bcc: List.of(_bcc),
      subject: _subjectCtrl.text.trim(),
      body: _bodyCtrl.text,
      attachments: List.of(_attachments),
      quotedHtml: _quotedHtml,
      quotedText: _quotedText,
      inReplyTo: _inReplyTo,
      references: _references,
      individually: _individually,
      draftId: _draftId,
    );
  }

  // ───────────────────────── 发送 ─────────────────────────

  Future<void> _send() async {
    final mail = _collect();
    if (mail.allRecipients.isEmpty) {
      _toast('请至少填写一个收件人');
      return;
    }
    if (mail.subject.isEmpty) {
      final go = await _ask('没有主题', '确定发送没有主题的邮件吗？', '发送');
      if (go != true) return;
    }
    final total = mail.attachments.fold<int>(0, (s, a) => s + a.size);
    if (total > MailFileHelper.maxTotalBytes) {
      _toast('附件总大小 ${MailFileHelper.humanSize(total)} 超过 25MB 上限');
      return;
    }
    if (!mounted) return;
    scheduleSend(
      context: context,
      center: _center,
      mail: mail,
      user: widget.user,
      title: widget.title,
    );
    Navigator.pop(context, true);
  }

  /// 撤销发送：先给 5 秒窗口，再真正投递。点"撤销"重新打开写信页。
  static void scheduleSend({
    required BuildContext context,
    required MailCenter center,
    required OutgoingMail mail,
    String? user,
    String? title,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var cancelled = false;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(mail.individually
            ? '正在逐个发送给 ${mail.allRecipients.length} 位收件人…'
            : '正在发送…'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            cancelled = true;
            navigator.push(MaterialPageRoute(
              builder: (_) => ComposeMailPage(
                  user: user, initial: mail, title: title ?? '写邮件'),
            ));
          },
        ),
      ));

    Future.delayed(const Duration(seconds: 5), () async {
      if (cancelled) return;
      String msg;
      try {
        final r = await center.send(mail);
        if (r.failed.isEmpty) {
          msg = mail.individually ? '🚀 已逐个发送 ${r.ok} 封' : '🚀 邮件已发送';
          if (r.legacy) msg += '（旧接口，纯文本）';
        } else {
          msg = '成功 ${r.ok}，失败 ${r.failed.length}：${r.failed.first}';
          // 失败的保存为草稿，避免内容丢失
          await center.saveDraft(mail);
          msg += '（已存入草稿）';
        }
      } catch (e) {
        await center.saveDraft(mail);
        msg = '❌ 发送失败: $e（已存入草稿）';
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  // ───────────────────────── 关闭 / 草稿 ─────────────────────────

  Future<void> _close() async {
    final mail = _collect();
    final sig = _center.signature.isEmpty ? '' : '\n\n-- \n${_center.signature}';
    final untouched = mail.allRecipients.isEmpty &&
        mail.subject.isEmpty &&
        mail.attachments.isEmpty &&
        (mail.body.trim().isEmpty || mail.body == sig);
    if (untouched) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存草稿？'),
        content: const Text('这封邮件还没有发送。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'edit'),
              child: const Text('继续编辑')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('丢弃', style: TextStyle(color: Colors.red))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('保存草稿')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _center.saveDraft(mail);
      if (!mounted) return;
      _toast('已保存到草稿');
      Navigator.pop(context);
    } else if (choice == 'discard') {
      if (_draftId != null) await _center.deleteDraft(_draftId!);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final files = await MailFileHelper.pickAttachments();
      if (files.isNotEmpty) setState(() => _attachments.addAll(files));
    } catch (e) {
      _toast('选择附件失败: $e');
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final recipientsCount = {..._to, ..._cc, ..._bcc}.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _close),
          title: Text(widget.title ?? '写邮件',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: '添加附件',
              icon: const Icon(Icons.attach_file),
              onPressed: _pickAttachments,
            ),
            IconButton(
              tooltip: '发送',
              icon: const Icon(Icons.send, color: Color(0xFF1A73E8)),
              onPressed: _send,
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'draft') {
                  // 回写 draftId，之后再次保存覆盖同一份草稿
                  _draftId = await _center.saveDraft(_collect());
                  _toast('已保存到草稿');
                } else if (v == 'notary') {
                  // TODO[v2]: 发送后对原文 .eml 计算 sha256 并上链存证
                  _toast('发信存证功能开发中');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'draft', child: Text('保存草稿')),
                PopupMenuItem(value: 'notary', child: Text('发送并存证（即将上线）')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _fromRow(),
            const Divider(height: 1),
            _RecipientField(
              key: _toKey,
              label: '收件人',
              center: _center,
              values: _to,
              onChanged: () => setState(() {}),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(_showCcBcc ? Icons.expand_less : Icons.expand_more),
                onPressed: () => setState(() => _showCcBcc = !_showCcBcc),
              ),
            ),
            if (_showCcBcc) ...[
              const Divider(height: 1),
              _RecipientField(
                key: _ccKey,
                label: '抄送',
                center: _center,
                values: _cc,
                onChanged: () => setState(() {}),
              ),
              const Divider(height: 1),
              _RecipientField(
                key: _bccKey,
                label: '密送',
                center: _center,
                values: _bcc,
                onChanged: () => setState(() {}),
              ),
            ],
            if (recipientsCount > 1) ...[
              const Divider(height: 1),
              SwitchListTile(
                dense: true,
                title: const Text('群发单显'),
                subtitle: const Text('每位收件人单独收到一封，彼此看不到对方'),
                value: _individually,
                onChanged: (v) => setState(() => _individually = v),
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                    hintText: '主题', border: InputBorder.none),
                style: const TextStyle(fontSize: 16),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  TextField(
                    controller: _bodyCtrl,
                    focusNode: _bodyFocus,
                    maxLines: null,
                    minLines: 10,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                        hintText: '撰写邮件', border: InputBorder.none),
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  if (_quotedText != null) _quotedSection(),
                  if (_attachments.isNotEmpty) _attachmentsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fromRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 56,
            child: Text('发件人',
                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          ),
          Expanded(
            child: Text(_center.me.email, style: const TextStyle(fontSize: 15)),
          ),
        ]),
      );

  Widget _quotedSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700], padding: EdgeInsets.zero),
            onPressed: () => setState(() => _showQuoted = !_showQuoted),
            icon: Icon(_showQuoted ? Icons.unfold_less : Icons.more_horiz),
            label: Text(_showQuoted ? '隐藏引用内容' : '显示引用内容'),
          ),
          if (_showQuoted)
            Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey[300]!, width: 2)),
              ),
              child: Text(_quotedText!,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _quotedText = null;
                _quotedHtml = null;
              }),
              child: const Text('删除引用', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );

  Widget _attachmentsSection() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _attachments
              .map((a) => InputChip(
                    avatar: const Icon(Icons.attach_file, size: 16),
                    label: Text(
                        '${a.filename} (${MailFileHelper.humanSize(a.size)})',
                        overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _attachments.remove(a)),
                  ))
              .toList(),
        ),
      );

  Future<bool?> _ask(String title, String content, String ok) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
          ],
        ),
      );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ───────────────────────── 收件人输入（标签 + 补全） ─────────────────────────

class _RecipientField extends StatefulWidget {
  final String label;
  final MailCenter center;
  final List<MailAddr> values;
  final VoidCallback onChanged;
  final Widget? trailing;

  const _RecipientField({
    super.key,
    required this.label,
    required this.center,
    required this.values,
    required this.onChanged,
    this.trailing,
  });

  @override
  State<_RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<_RecipientField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  static final _emailRe = RegExp(r'^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) commit();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 把输入框中的文本解析成地址标签
  void commit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final parsed = MailAddr.parseList(text);
    var added = false;
    for (final a in parsed) {
      if (_emailRe.hasMatch(a.email) && !widget.values.contains(a)) {
        widget.values.add(a);
        added = true;
      }
    }
    if (parsed.isNotEmpty) _ctrl.clear();
    if (added) widget.onChanged();
  }

  void _add(MailAddr a) {
    if (!widget.values.contains(a)) widget.values.add(a);
    _ctrl.clear();
    widget.onChanged();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            child: Text(widget.label,
                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...widget.values.map((a) => InputChip(
                      label: Text(a.display),
                      tooltip: a.email,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: widget.center.isBlocked(a.email)
                          ? Colors.red[50]
                          : null,
                      onDeleted: () {
                        widget.values.remove(a);
                        widget.onChanged();
                      },
                    )),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 160, maxWidth: 480),
                  child: RawAutocomplete<MailAddr>(
                    textEditingController: _ctrl,
                    focusNode: _focus,
                    displayStringForOption: (a) => a.email,
                    optionsBuilder: (v) => widget.center
                        .suggest(v.text)
                        .where((a) => !widget.values.contains(a)),
                    onSelected: _add,
                    fieldViewBuilder: (context, ctrl, focus, onSubmit) =>
                        TextField(
                      controller: ctrl,
                      focusNode: focus,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true),
                      style: const TextStyle(fontSize: 15),
                      onChanged: (v) {
                        if (v.endsWith(',') ||
                            v.endsWith(';') ||
                            v.endsWith(' ') ||
                            v.endsWith('，') ||
                            v.endsWith('；')) {
                          ctrl.text = v.substring(0, v.length - 1);
                          commit();
                        }
                      },
                      onSubmitted: (_) => commit(),
                    ),
                    optionsViewBuilder: (context, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 260, maxWidth: 360),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: options
                                .map((a) => ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 14,
                                        child: Text(a.display.isEmpty
                                            ? '?'
                                            : a.display.characters.first
                                                .toUpperCase()),
                                      ),
                                      title: Text(a.name.isEmpty ? a.email : a.name),
                                      subtitle:
                                          a.name.isEmpty ? null : Text(a.email),
                                      onTap: () => onSelected(a),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
