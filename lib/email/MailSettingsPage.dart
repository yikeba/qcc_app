import 'package:flutter/material.dart';

import 'MailCenter.dart';

/// 邮箱设置：签名、黑名单管理
class MailSettingsPage extends StatefulWidget {
  final String user;
  const MailSettingsPage({super.key, required this.user});

  @override
  State<MailSettingsPage> createState() => _MailSettingsPageState();
}

class _MailSettingsPageState extends State<MailSettingsPage> {
  late final MailCenter _center = MailCenter.of(widget.user);
  late final TextEditingController _sigCtrl =
      TextEditingController(text: _center.signature);

  @override
  void dispose() {
    _sigCtrl.dispose();
    super.dispose();
  }

  Future<void> _addBlock() async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加到黑名单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'spam@example.com 或 @example.com',
            helperText: '以 @ 开头表示屏蔽整个域名',
          ),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('添加')),
        ],
      ),
    );
    ctrl.dispose();
    final e = v?.trim().toLowerCase() ?? '';
    if (e.isEmpty) return;
    if (!e.contains('@') || e.endsWith('@')) {
      _toast('格式不正确');
      return;
    }
    await _center.block(e);
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('邮箱设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: ListenableBuilder(
        listenable: _center,
        builder: (context, _) {
          final list = _center.blacklist.toList()..sort();
          return ListView(
            children: [
              const _Section('签名'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _sigCtrl,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText: '新邮件 / 回复时自动附加在正文末尾',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: FilledButton(
                    onPressed: () async {
                      await _center.setSignature(_sigCtrl.text.trim());
                      _toast('签名已保存');
                    },
                    child: const Text('保存签名'),
                  ),
                ),
              ),
              _Section('黑名单（${list.length}）',
                  trailing: IconButton(
                    tooltip: '添加',
                    icon: const Icon(Icons.add),
                    onPressed: _addBlock,
                  )),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '黑名单发件人的邮件自动归入"垃圾邮件"。当前仅在本机生效，'
                  '服务器仍会收下这些邮件。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('黑名单为空', style: TextStyle(color: Colors.grey))),
                ),
              ...list.map((e) => ListTile(
                    leading: Icon(
                        e.startsWith('@') ? Icons.domain_disabled : Icons.block,
                        color: Colors.redAccent),
                    title: Text(e),
                    subtitle: e.startsWith('@') ? const Text('整个域名') : null,
                    trailing: TextButton(
                      onPressed: () => _center.unblock(e),
                      child: const Text('移除'),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _Section(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}
