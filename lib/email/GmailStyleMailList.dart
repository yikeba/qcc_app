import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'MailSyncService.dart';
import 'QccMailDetailPage.dart';

/// Gmail 风格邮件列表。
/// 数据源是本地索引（MailLocalStore），下拉触发差额同步。离线也能看列表。
class GmailStyleMailList extends StatefulWidget {
  final String user;
  const GmailStyleMailList({super.key, required this.user});

  @override
  State<GmailStyleMailList> createState() => _GmailStyleMailListState();
}

class _GmailStyleMailListState extends State<GmailStyleMailList> {
  late final MailSyncService _sync = MailSyncService(widget.user);
  List<Map<String, dynamic>> _mails = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 先显示本地（秒开），再后台同步
    _mails = await _sync.loadList();
    if (mounted) setState(() => _loading = false);
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      await _sync.sync();
      final list = await _sync.loadList();
      if (mounted) setState(() {
        _mails = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // 倒序：最新（seq 最大）在最上
    final view = _mails.where((m) => m['deleted'] != true).toList().reversed.toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: view.isEmpty
          ? ListView(children: [
        const SizedBox(height: 120),
        Center(child: Text(_error == null ? '收件箱为空' : '同步失败: $_error',
            style: const TextStyle(color: Colors.grey))),
      ])
          : ListView.separated(
        itemCount: view.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) => _tile(view[i]),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> m) {
    final int seq = (m['seq'] as num).toInt();
    final String subject = (m['subject']?.toString().isNotEmpty ?? false)
        ? m['subject'].toString()
        : '(无主题)';
    final String from = m['from']?.toString() ?? '';
    String senderName = m['fromName']?.toString() ?? '';
    if (senderName.isEmpty) {
      senderName = from.contains('@') ? from.split('@').first : from;
    }
    if (senderName.isEmpty) senderName = 'Unknown';
    final String initial = senderName[0].toUpperCase();
    final int epoch = (m['dateEpochMillis'] as num?)?.toInt() ?? 0;
    final bool hasAtt = m['hasAttachments'] == true;
    final bool parseError = m['parseError'] == true;
    final String preview = m['preview']?.toString() ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: parseError ? Colors.grey : Colors.blueAccent,
        child: Text(initial, style: const TextStyle(color: Colors.white)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(senderName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(_smartDate(epoch),
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasAtt)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.attach_file, size: 14, color: Colors.grey),
                ),
              Expanded(
                child: Text(subject,
                    style: const TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(preview,
                style: TextStyle(color: Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QccMailDetailPage(
            sync: _sync,
            seq: seq,
            subject: subject,
            from: from,
            expectSha256: m['sha256']?.toString(),
          ),
        ),
      ),
    );
  }

  String _smartDate(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('今天 HH:mm').format(dt);     // 今天：今天 14:57
    }
    if (dt.year == now.year) {
      return DateFormat('MM-dd HH:mm').format(dt);    // 今年：06-26 10:31
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(dt); // 跨年：2025-12-08 09:31
  }
}