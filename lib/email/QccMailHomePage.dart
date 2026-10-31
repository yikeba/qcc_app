import 'dart:async';

import 'package:flutter/material.dart';

import 'ComposeMailPage.dart';
import 'GmailStyleMailList.dart';
import 'MailCenter.dart';
import 'MailSettingsPage.dart';
import 'QccMailDetailPage.dart';

/// 邮箱首页（Gmail 式）：
///   窄屏：抽屉文件夹 + 列表，点开进入详情页
///   宽屏（≥900，macOS / 平板横屏）：侧栏 + 列表 + 阅读窗格
/// 启动页 case "email" 仍然 push 这个页面，构造参数不变。
class QccMailHomePage extends StatefulWidget {
  final String user;
  const QccMailHomePage({super.key, required this.user});

  @override
  State<QccMailHomePage> createState() => _QccMailHomePageState();
}

class _QccMailHomePageState extends State<QccMailHomePage> {
  late final MailCenter _center = MailCenter.of(widget.user);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchCtrl = TextEditingController();

  MailFolder _folder = MailFolder.inbox;
  bool _searching = false;
  String _query = '';
  final Set<String> _selected = {};
  String? _activeKey; // 宽屏阅读窗格当前邮件
  Timer? _autoSync;

  static const double _wideBreakpoint = 900;

  @override
  void initState() {
    super.initState();
    _center.init();
    // 前台每 2 分钟自动差额同步一次
    _autoSync = Timer.periodic(const Duration(minutes: 2), (_) => _center.refresh());
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MailItem> get _items => _center.itemsOf(_folder, query: _query);

  List<MailItem> get _selectedItems =>
      _selected.map(_center.byKey).whereType<MailItem>().toList();

  // ───────────────────────── 动作 ─────────────────────────

  void _switchFolder(MailFolder f) {
    setState(() {
      _folder = f;
      _selected.clear();
      _activeKey = null;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  void _toggleSelect(MailItem m) => setState(() {
        if (!_selected.remove(m.key)) _selected.add(m.key);
      });

  Future<void> _open(MailItem m, bool wide) async {
    if (m.kind == MailKind.draft) {
      final draft = await _center.loadDraft(m);
      if (!mounted || draft == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ComposeMailPage(
              user: widget.user, initial: draft, title: '编辑草稿'),
        ),
      );
      return;
    }
    if (wide) {
      setState(() => _activeKey = m.key);
      if (!m.read) _center.setRead([m], true);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QccMailDetailPage(user: widget.user, itemKey: m.key),
      ),
    );
  }

  void _compose() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComposeMailPage(user: widget.user)),
      );

  void _moveWithUndo(List<MailItem> items, String folder, String text) {
    if (items.isEmpty) return;
    final snapshot = _center.move(items, folder);
    setState(() {
      _selected.clear();
      if (items.any((m) => m.key == _activeKey)) _activeKey = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${items.length} 封$text'),
        action: SnackBarAction(
            label: '撤销', onPressed: () => _center.undoMove(snapshot)),
      ));
  }

  Future<void> _deleteForever(List<MailItem> items) async {
    if (items.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('将从本机永久删除 ${items.length} 封邮件，无法撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _center.deleteForever(items);
    setState(() {
      _selected.clear();
      _activeKey = null;
    });
  }

  void _deleteAction(List<MailItem> items) {
    if (_folder == MailFolder.trash || _folder == MailFolder.drafts) {
      _deleteForever(items);
    } else {
      _moveWithUndo(items, 'trash', '已移至已删除');
    }
  }

  // ───────────────────────── 构建 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _center,
      builder: (context, _) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= _wideBreakpoint;
        // 被移走的邮件从选择集中剔除
        _selected.removeWhere((k) => _center.byKey(k) == null);
        final list = _buildList(wide);
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.white,
          appBar: _selected.isEmpty ? _normalBar(wide) : _selectionBar(),
          drawer: wide ? null : Drawer(child: _sidebar()),
          floatingActionButton: _selected.isEmpty
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFFC2E7FF),
                  foregroundColor: const Color(0xFF001D35),
                  onPressed: _compose,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('写邮件'),
                )
              : null,
          body: wide
              ? Row(children: [
                  SizedBox(width: 240, child: _sidebar()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 400, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(child: _readingPane()),
                ])
              : list,
        );
      }),
    );
  }

  PreferredSizeWidget _normalBar(bool wide) => AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        leading: wide
            ? (Navigator.canPop(context) ? const BackButton() : null)
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        titleSpacing: wide ? 16 : 0,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '在${_folder.label}中搜索',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(
                wide ? 'Qccio 存证邮箱' : _folder.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _query = '';
              }
            }),
          ),
          if (!wide && Navigator.canPop(context))
            IconButton(
              tooltip: '退出邮箱',
              icon: const Icon(Icons.logout),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      );

  PreferredSizeWidget _selectionBar() {
    final items = _selectedItems;
    final allRead = items.every((m) => m.read);
    final allStar = items.isNotEmpty && items.every((m) => m.star);
    final inTrash = _folder == MailFolder.trash;
    final inSpam = _folder == MailFolder.spam;
    return AppBar(
      backgroundColor: const Color(0xFFE8F0FE),
      foregroundColor: Colors.black87,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length}'),
      actions: [
        if (_folder != MailFolder.archive &&
            _folder != MailFolder.drafts &&
            !inTrash &&
            !inSpam)
          IconButton(
            tooltip: '归档',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _moveWithUndo(items, 'archive', '已归档'),
          ),
        IconButton(
          tooltip: inTrash || _folder == MailFolder.drafts ? '永久删除' : '删除',
          icon: Icon(inTrash ? Icons.delete_forever_outlined : Icons.delete_outline),
          onPressed: () => _deleteAction(items),
        ),
        if (_folder != MailFolder.drafts && _folder != MailFolder.sent)
          IconButton(
            tooltip: allRead ? '标为未读' : '标为已读',
            icon: Icon(allRead
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined),
            onPressed: () {
              _center.setRead(items, !allRead);
              setState(_selected.clear);
            },
          ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'all':
                setState(() => _selected.addAll(_items.map((m) => m.key)));
                break;
              case 'star':
                _center.setStar(items, !allStar);
                setState(_selected.clear);
                break;
              case 'spam':
                _moveWithUndo(items, 'spam', '已标记为垃圾邮件');
                break;
              case 'inbox':
                _moveWithUndo(items, 'inbox', inSpam ? '已标记为非垃圾邮件' : '已移至收件箱');
                break;
              case 'block':
                _blockSenders(items);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('全选')),
            if (_folder != MailFolder.drafts)
              PopupMenuItem(
                  value: 'star', child: Text(allStar ? '移除星标' : '加星标')),
            if (!inSpam && _folder != MailFolder.drafts && _folder != MailFolder.sent)
              const PopupMenuItem(value: 'spam', child: Text('标记为垃圾邮件')),
            if (inSpam || inTrash || _folder == MailFolder.archive)
              PopupMenuItem(
                  value: 'inbox', child: Text(inSpam ? '不是垃圾邮件' : '移至收件箱')),
            if (_folder != MailFolder.drafts && _folder != MailFolder.sent)
              const PopupMenuItem(value: 'block', child: Text('屏蔽这些发件人')),
          ],
        ),
      ],
    );
  }

  Future<void> _blockSenders(List<MailItem> items) async {
    final senders = items
        .where((m) => m.kind == MailKind.received && m.senderEmail.isNotEmpty)
        .map((m) => m.senderEmail)
        .toSet();
    if (senders.isEmpty) return;
    for (final s in senders) {
      await _center.block(s);
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已屏蔽 ${senders.length} 个发件人'),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () async {
          for (final s in senders) {
            await _center.unblock(s);
          }
        },
      ),
    ));
  }

  Widget _buildList(bool wide) {
    final items = _items;
    final swipe = _folder != MailFolder.drafts;
    // 注意：滑动后该项必须立即离开当前列表（Dismissible 约束），
    // 星标视图里归档后仍可见，所以星标视图不开放滑动归档
    final archivable = swipe &&
        _folder != MailFolder.starred &&
        _folder != MailFolder.archive &&
        _folder != MailFolder.trash &&
        _folder != MailFolder.spam;
    return GmailStyleMailList(
      items: items,
      selected: _selected,
      activeKey: wide ? _activeKey : null,
      onRefresh: _center.refresh,
      onTap: (m) => _open(m, wide),
      onToggleSelect: _toggleSelect,
      onToggleStar: (m) => _center.setStar([m], !m.star),
      onSwipeArchive:
          archivable ? (m) => _moveWithUndo([m], 'archive', '已归档') : null,
      onSwipeDelete: swipe && _folder != MailFolder.trash
          ? (m) => _moveWithUndo([m], 'trash', '已移至已删除')
          : null,
      emptyText: _query.isNotEmpty
          ? '没有匹配"$_query"的邮件'
          : (_center.loading ? '加载中…' : '${_folder.label}为空'),
      header: _statusHeader(),
    );
  }

  Widget? _statusHeader() {
    if (_center.syncing) {
      final t = _center.syncTotal;
      return Column(children: [
        LinearProgressIndicator(
          value: t > 0 ? _center.syncDone / t : null,
          minHeight: 2,
        ),
        if (t > 0)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text('正在同步 ${_center.syncDone}/$t',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
      ]);
    }
    if (_center.lastError != null) {
      return Container(
        color: const Color(0xFFFCE8E6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 16, color: Color(0xFFD93025)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('同步失败，显示的是本地缓存',
                style: TextStyle(fontSize: 13)),
          ),
          TextButton(onPressed: _center.refresh, child: const Text('重试')),
        ]),
      );
    }
    if (_folder == MailFolder.trash && _items.isNotEmpty) {
      return _emptyBar('已删除的邮件可在此恢复，或永久删除', '清空',
          () => _deleteForever(_items));
    }
    if (_folder == MailFolder.spam && _items.isNotEmpty) {
      return _emptyBar('黑名单发件人的邮件会自动进入这里', '清空',
          () => _deleteForever(_items));
    }
    return null;
  }

  Widget _emptyBar(String text, String action, VoidCallback onTap) => Container(
        color: const Color(0xFFF1F3F4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.black54))),
          TextButton(onPressed: onTap, child: Text(action)),
        ]),
      );

  Widget _readingPane() {
    final key = _activeKey;
    if (key == null || _center.byKey(key) == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.mail_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('选择一封邮件阅读', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }
    return QccMailDetailPage(
      key: ValueKey(key),
      user: widget.user,
      itemKey: key,
      embedded: true,
      onClosed: () => setState(() => _activeKey = null),
    );
  }

  Widget _sidebar() {
    Widget tile(MailFolder f) {
      final unread = f == MailFolder.drafts
          ? _center.count(f)
          : (f == MailFolder.sent ? 0 : _center.unreadCount(f));
      final active = f == _folder;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: ListTile(
          dense: true,
          selected: active,
          selectedTileColor: const Color(0xFFD3E3FD),
          selectedColor: const Color(0xFF001D35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          leading: Icon(active ? _filledIcon(f) : f.icon, size: 20),
          title: Text(f.label,
              style: TextStyle(
                  fontWeight: active || unread > 0
                      ? FontWeight.bold
                      : FontWeight.normal)),
          trailing: unread > 0
              ? Text('$unread',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold))
              : null,
          onTap: () => _switchFolder(f),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 16, 4),
            child: Text('Qccio 存证邮箱',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
            child: Text(_center.me.email,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          ...MailFolder.values.map(tile),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              dense: true,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: const Text('设置（签名 / 黑名单）'),
              onTap: () {
                if (_scaffoldKey.currentState?.isDrawerOpen == true) {
                  Navigator.pop(context);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MailSettingsPage(user: widget.user)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _filledIcon(MailFolder f) => const {
        MailFolder.inbox: Icons.inbox,
        MailFolder.starred: Icons.star,
        MailFolder.sent: Icons.send,
        MailFolder.drafts: Icons.drafts,
        MailFolder.archive: Icons.archive,
        MailFolder.spam: Icons.report,
        MailFolder.trash: Icons.delete,
      }[f]!;
}
