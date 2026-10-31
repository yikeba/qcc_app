import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'MailCenter.dart';

/// Gmail 风格邮件列表（纯展示组件，状态由 QccMailHomePage / MailCenter 管理）。
///
/// 交互：
///   点击       → 打开（多选模式下为勾选）
///   长按/点头像 → 进入多选
///   右滑       → 归档      左滑 → 删除（均可撤销）
///   星标图标   → 加/去星标
class GmailStyleMailList extends StatelessWidget {
  final List<MailItem> items;
  final Set<String> selected;
  final String? activeKey;
  final Future<void> Function() onRefresh;
  final void Function(MailItem) onTap;
  final void Function(MailItem) onToggleSelect;
  final void Function(MailItem) onToggleStar;
  final void Function(MailItem)? onSwipeArchive;
  final void Function(MailItem)? onSwipeDelete;
  final String emptyText;
  final Widget? header;

  const GmailStyleMailList({
    super.key,
    required this.items,
    required this.selected,
    required this.onRefresh,
    required this.onTap,
    required this.onToggleSelect,
    required this.onToggleStar,
    this.onSwipeArchive,
    this.onSwipeDelete,
    this.activeKey,
    this.emptyText = '没有邮件',
    this.header,
  });

  bool get _selecting => selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (header != null) header!,
                const SizedBox(height: 120),
                Center(
                  child: Column(children: [
                    Icon(Icons.mark_email_read_outlined,
                        size: 56, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(emptyText, style: const TextStyle(color: Colors.grey)),
                  ]),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + (header == null ? 0 : 1),
              itemBuilder: (context, i) {
                if (header != null) {
                  if (i == 0) return header!;
                  i -= 1;
                }
                return _buildRow(context, items[i]);
              },
            ),
    );
  }

  Widget _buildRow(BuildContext context, MailItem m) {
    final tile = _MailTile(
      item: m,
      selected: selected.contains(m.key),
      active: m.key == activeKey,
      onTap: () => _selecting ? onToggleSelect(m) : onTap(m),
      onLongPress: () => onToggleSelect(m),
      onAvatarTap: () => onToggleSelect(m),
      onStar: m.kind == MailKind.draft ? null : () => onToggleStar(m),
    );
    if (_selecting || (onSwipeArchive == null && onSwipeDelete == null)) {
      return tile;
    }
    return Dismissible(
      key: ValueKey('dismiss_${m.key}'),
      direction: onSwipeArchive == null
          ? DismissDirection.endToStart
          : (onSwipeDelete == null
              ? DismissDirection.startToEnd
              : DismissDirection.horizontal),
      background: _swipeBg(Icons.archive_outlined, '归档', Colors.green[600]!,
          Alignment.centerLeft),
      secondaryBackground: _swipeBg(Icons.delete_outline, '删除',
          Colors.red[400]!, Alignment.centerRight),
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          (onSwipeArchive ?? onSwipeDelete)?.call(m);
        } else {
          onSwipeDelete?.call(m);
        }
      },
      child: tile,
    );
  }

  Widget _swipeBg(IconData icon, String label, Color color, Alignment align) {
    final left = align == Alignment.centerLeft;
    return Container(
      color: color,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left) Text(label, style: const TextStyle(color: Colors.white)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (left) const SizedBox(width: 8),
          if (left) Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _MailTile extends StatelessWidget {
  final MailItem item;
  final bool selected;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;
  final VoidCallback? onStar;

  const _MailTile({
    required this.item,
    required this.selected,
    required this.active,
    required this.onTap,
    required this.onLongPress,
    required this.onAvatarTap,
    required this.onStar,
  });

  static const _palette = [
    Color(0xFF1A73E8), Color(0xFFD93025), Color(0xFF188038),
    Color(0xFFE37400), Color(0xFF9334E6), Color(0xFF12B5CB),
    Color(0xFFC5221F), Color(0xFF5F6368),
  ];

  @override
  Widget build(BuildContext context) {
    final m = item;
    final unread = !m.read;
    final name = m.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final color = m.parseError
        ? Colors.grey
        : _palette[name.hashCode.abs() % _palette.length];

    Color? bg;
    if (selected) {
      bg = const Color(0xFFD3E3FD);
    } else if (active) {
      bg = const Color(0xFFF2F6FC);
    }

    return Material(
      color: bg ?? Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? const CircleAvatar(
                          key: ValueKey('sel'),
                          backgroundColor: Color(0xFF1A73E8),
                          child: Icon(Icons.check, color: Colors.white),
                        )
                      : CircleAvatar(
                          key: const ValueKey('ava'),
                          backgroundColor: color,
                          child: m.kind == MailKind.draft
                              ? const Icon(Icons.edit_note,
                                  color: Colors.white, size: 20)
                              : Text(initial,
                                  style: const TextStyle(color: Colors.white)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w500,
                            color: m.kind == MailKind.draft
                                ? const Color(0xFFD93025)
                                : Colors.black87,
                          ),
                        ),
                      ),
                      if (m.hasAttachments)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.attach_file,
                              size: 14, color: Colors.grey),
                        ),
                      const SizedBox(width: 4),
                      Text(
                        smartDate(m.epoch),
                        style: TextStyle(
                          fontSize: 12,
                          color: unread ? Colors.black87 : Colors.grey,
                          fontWeight:
                              unread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      m.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (m.preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (onStar != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onStar,
                  icon: Icon(
                    m.star ? Icons.star : Icons.star_border,
                    color: m.star ? const Color(0xFFF4B400) : Colors.grey,
                    size: 20,
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表时间：今天 → HH:mm；今年 → M月d日；跨年 → yyyy/M/d
String smartDate(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return DateFormat('HH:mm').format(dt);
  }
  if (dt.year == now.year) return DateFormat('M月d日').format(dt);
  return DateFormat('yyyy/M/d').format(dt);
}

/// 详情页时间：yyyy年M月d日 HH:mm
String fullDate(int ms) {
  if (ms <= 0) return '';
  return DateFormat('yyyy年M月d日 HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(ms).toLocal());
}
