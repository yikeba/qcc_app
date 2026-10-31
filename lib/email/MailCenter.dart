import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'MailLocalStore.dart';
import 'MailMimeBuilder.dart';
import 'MailSyncService.dart';
import 'MailUtils.dart';
import 'QccMailApi.dart';
import 'QccMimeParser.dart';

/// 文件夹（视图）
enum MailFolder { inbox, starred, sent, drafts, archive, spam, trash }

extension MailFolderX on MailFolder {
  String get label => const {
        MailFolder.inbox: '收件箱',
        MailFolder.starred: '已加星标',
        MailFolder.sent: '已发送',
        MailFolder.drafts: '草稿',
        MailFolder.archive: '归档',
        MailFolder.spam: '垃圾邮件',
        MailFolder.trash: '已删除',
      }[this]!;

  IconData get icon => const {
        MailFolder.inbox: Icons.inbox_outlined,
        MailFolder.starred: Icons.star_outline,
        MailFolder.sent: Icons.send_outlined,
        MailFolder.drafts: Icons.drafts_outlined,
        MailFolder.archive: Icons.archive_outlined,
        MailFolder.spam: Icons.report_gmailerrorred_outlined,
        MailFolder.trash: Icons.delete_outline,
      }[this]!;
}

enum MailKind { received, sent, draft }

/// 列表项（收件 / 已发送 / 草稿 统一模型）
class MailItem {
  /// r<seq> 收件，s<id> 已发送，d<id> 草稿
  final String key;
  final MailKind kind;
  final int? seq;
  final String? localId;
  final String from;
  final String fromName;
  final String toLine;
  final String subject;
  final String preview;
  final int epoch;
  final bool hasAttachments;
  final bool parseError;
  final String? sha256;

  bool read;
  bool star;

  /// inbox / archive / spam / trash / sent / purged
  String folder;

  MailItem({
    required this.key,
    required this.kind,
    this.seq,
    this.localId,
    required this.from,
    required this.fromName,
    this.toLine = '',
    required this.subject,
    required this.preview,
    required this.epoch,
    this.hasAttachments = false,
    this.parseError = false,
    this.sha256,
    this.read = false,
    this.star = false,
    this.folder = 'inbox',
  });

  /// 列表上显示的"人"：收件显示发件人，已发送/草稿显示收件人
  String get displayName {
    if (kind != MailKind.received) {
      return toLine.isEmpty ? '(无收件人)' : '至: $toLine';
    }
    if (fromName.isNotEmpty) return fromName;
    if (from.contains('@')) return from.split('@').first;
    return from.isEmpty ? 'Unknown' : from;
  }

  String get senderEmail => from.toLowerCase();
}

/// 待发送邮件（撰写页 ↔ 发送逻辑 ↔ 草稿 共用）
class OutgoingMail {
  List<MailAddr> to;
  List<MailAddr> cc;
  List<MailAddr> bcc;
  String subject;
  String body;
  List<OutgoingAttachment> attachments;

  /// 回复/转发时的原文引用（不进入编辑框，发送时拼接在正文后面）
  String? quotedHtml;
  String? quotedText;
  String? inReplyTo;
  String? references;

  /// 群发单显：每个收件人单独一封，彼此不可见
  bool individually;

  /// 若由草稿打开，发送/保存后删除旧草稿
  String? draftId;

  OutgoingMail({
    List<MailAddr>? to,
    List<MailAddr>? cc,
    List<MailAddr>? bcc,
    this.subject = '',
    this.body = '',
    List<OutgoingAttachment>? attachments,
    this.quotedHtml,
    this.quotedText,
    this.inReplyTo,
    this.references,
    this.individually = false,
    this.draftId,
  })  : to = to ?? [],
        cc = cc ?? [],
        bcc = bcc ?? [],
        attachments = attachments ?? [];

  List<MailAddr> get allRecipients {
    final seen = <MailAddr>{};
    return [...to, ...cc, ...bcc].where(seen.add).toList();
  }

  bool get isEmpty =>
      allRecipients.isEmpty &&
      subject.trim().isEmpty &&
      body.trim().isEmpty &&
      attachments.isEmpty;

  Map<String, dynamic> toJson() => {
        'to': to.map((e) => e.toString()).toList(),
        'cc': cc.map((e) => e.toString()).toList(),
        'bcc': bcc.map((e) => e.toString()).toList(),
        'subject': subject,
        'body': body,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'quotedHtml': quotedHtml,
        'quotedText': quotedText,
        'inReplyTo': inReplyTo,
        'references': references,
        'individually': individually,
      };

  static OutgoingMail fromJson(Map<String, dynamic> j, {String? draftId}) {
    List<MailAddr> addrs(Object? v) => (v as List? ?? const [])
        .map((e) => MailAddr.parse(e.toString()))
        .whereType<MailAddr>()
        .toList();
    return OutgoingMail(
      to: addrs(j['to']),
      cc: addrs(j['cc']),
      bcc: addrs(j['bcc']),
      subject: j['subject'] as String? ?? '',
      body: j['body'] as String? ?? '',
      attachments: (j['attachments'] as List? ?? const [])
          .map((e) => OutgoingAttachment.fromJson(
              (e as Map).cast<String, dynamic>()))
          .whereType<OutgoingAttachment>()
          .toList(),
      quotedHtml: j['quotedHtml'] as String?,
      quotedText: j['quotedText'] as String?,
      inReplyTo: j['inReplyTo'] as String?,
      references: j['references'] as String?,
      individually: j['individually'] as bool? ?? false,
      draftId: draftId,
    );
  }
}

class SendReport {
  final int ok;
  final List<String> failed;

  /// 走了旧 /send 接口（纯文本、逐个发送）
  final bool legacy;

  const SendReport(this.ok, this.failed, {this.legacy = false});
}

/// 邮箱中枢：同步、列表、本地状态、黑名单、草稿、已发送、发信。
/// 每个 user 一个实例，页面间共享（用 ListenableBuilder 监听）。
class MailCenter extends ChangeNotifier {
  static final Map<String, MailCenter> _instances = {};

  static MailCenter of(String user) =>
      _instances.putIfAbsent(user, () => MailCenter._(user));

  final String user;
  final MailSyncService sync;
  MailLocalStore get store => sync.store;

  MailCenter._(this.user) : sync = MailSyncService(user);

  // ── 状态 ──────────────────────────────────────────────
  bool _initialized = false;
  bool loading = true;
  bool syncing = false;
  int syncDone = 0;
  int syncTotal = 0;
  String? lastError;

  List<MailItem> _items = [];
  Map<String, Map<String, dynamic>> _flags = {};
  Set<String> _blacklist = {};
  String signature = '';

  /// 联系人：email(lower) → 显示名
  final Map<String, String> _contacts = {};

  Timer? _flagSaveTimer;

  Set<String> get blacklist => Set.unmodifiable(_blacklist);

  /// 发件地址（沿用原工程 MailUtils.getMailfrom()）
  MailAddr get me => MailAddr('', MailUtils.getMailfrom());

  // ── 初始化 & 同步 ───────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _flags = await store.loadFlags();
    final s = await store.loadSettings();
    _blacklist = ((s['blacklist'] as List?) ?? const [])
        .map((e) => e.toString().toLowerCase())
        .toSet();
    signature = s['signature'] as String? ?? '';
    for (final c in (s['contacts'] as List?) ?? const []) {
      final a = MailAddr.parse(c.toString());
      if (a != null) _contacts[a.email.toLowerCase()] = a.name;
    }
    await _reloadItems();
    loading = false;
    notifyListeners();
    unawaited(refresh());
  }

  /// 差额同步（下拉刷新 / 定时调用）
  Future<void> refresh() async {
    if (syncing) return;
    syncing = true;
    syncDone = 0;
    syncTotal = 0;
    notifyListeners();
    try {
      final added = await sync.sync(onProgress: (done, total) {
        syncDone = done;
        syncTotal = total;
        notifyListeners();
      });
      if (added > 0) await _reloadItems();
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _reloadItems() async {
    final out = <MailItem>[];

    for (final m in await sync.loadList()) {
      if (m['deleted'] == true) continue;
      final seq = (m['seq'] as num).toInt();
      final key = 'r$seq';
      final f = _flags[key] ?? const {};
      final from = m['from']?.toString() ?? '';
      final fromAddr = MailAddr.parse(from);
      final email = (fromAddr?.email ?? from).toLowerCase();
      final fromName = (m['fromName']?.toString().isNotEmpty ?? false)
          ? m['fromName'].toString()
          : (fromAddr?.name ?? '');
      final folder = f['folder'] as String? ??
          (_isBlocked(email) ? 'spam' : 'inbox');
      if (folder == 'purged') continue;
      if (email.isNotEmpty) _contacts.putIfAbsent(email, () => fromName);
      out.add(MailItem(
        key: key,
        kind: MailKind.received,
        seq: seq,
        from: fromAddr?.email ?? from,
        fromName: fromName,
        subject: QccMimeParser.decodeHeaderWord(
            m['subject']?.toString().isNotEmpty == true
                ? m['subject'].toString()
                : '(无主题)'),
        preview: m['preview']?.toString() ?? '',
        epoch: (m['dateEpochMillis'] as num?)?.toInt() ?? 0,
        hasAttachments: m['hasAttachments'] == true,
        parseError: m['parseError'] == true,
        sha256: m['sha256']?.toString(),
        read: f['read'] == true,
        star: f['star'] == true,
        folder: folder,
      ));
    }

    for (final m in await store.loadSent()) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final key = 's$id';
      final f = _flags[key] ?? const {};
      final folder = f['folder'] as String? ?? 'sent';
      if (folder == 'purged') continue;
      out.add(MailItem(
        key: key,
        kind: MailKind.sent,
        localId: id,
        from: me.email,
        fromName: '我',
        toLine: m['to']?.toString() ?? '',
        subject: m['subject']?.toString() ?? '(无主题)',
        preview: m['preview']?.toString() ?? '',
        epoch: (m['epoch'] as num?)?.toInt() ?? 0,
        hasAttachments: m['hasAttachments'] == true,
        read: true,
        star: f['star'] == true,
        folder: folder,
      ));
    }

    for (final m in await store.loadDrafts()) {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final mail = OutgoingMail.fromJson(
          (m['mail'] as Map? ?? const {}).cast<String, dynamic>());
      out.add(MailItem(
        key: 'd$id',
        kind: MailKind.draft,
        localId: id,
        from: me.email,
        fromName: '草稿',
        toLine: mail.to.map((e) => e.display).join(', '),
        subject: mail.subject.isEmpty ? '(无主题)' : mail.subject,
        preview: _shorten(mail.body),
        epoch: (m['epoch'] as num?)?.toInt() ?? 0,
        hasAttachments: mail.attachments.isNotEmpty,
        read: true,
        folder: 'drafts',
      ));
    }

    out.sort((a, b) => b.epoch.compareTo(a.epoch)); // 最新在上
    _items = out;
  }

  // ── 查询 ──────────────────────────────────────────────
  List<MailItem> itemsOf(MailFolder folder, {String query = ''}) {
    Iterable<MailItem> it = _items.where((m) => _inFolder(m, folder));
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((m) =>
          m.subject.toLowerCase().contains(q) ||
          m.from.toLowerCase().contains(q) ||
          m.fromName.toLowerCase().contains(q) ||
          m.toLine.toLowerCase().contains(q) ||
          m.preview.toLowerCase().contains(q));
    }
    return it.toList();
  }

  bool _inFolder(MailItem m, MailFolder f) {
    switch (f) {
      case MailFolder.inbox:
        return m.kind == MailKind.received && m.folder == 'inbox';
      case MailFolder.starred:
        return m.star && m.folder != 'trash' && m.folder != 'spam';
      case MailFolder.sent:
        return m.kind == MailKind.sent && m.folder == 'sent';
      case MailFolder.drafts:
        return m.kind == MailKind.draft;
      case MailFolder.archive:
        return m.folder == 'archive';
      case MailFolder.spam:
        return m.folder == 'spam';
      case MailFolder.trash:
        return m.folder == 'trash';
    }
  }

  int unreadCount(MailFolder f) =>
      _items.where((m) => !m.read && _inFolder(m, f)).length;

  int count(MailFolder f) => _items.where((m) => _inFolder(m, f)).length;

  MailItem? byKey(String key) {
    for (final m in _items) {
      if (m.key == key) return m;
    }
    return null;
  }

  // ── 本地状态操作 ─────────────────────────────────────────
  void _setFlag(MailItem m, String k, Object? v) {
    final f = Map<String, dynamic>.from(_flags[m.key] ?? const {});
    if (v == null) {
      f.remove(k);
    } else {
      f[k] = v;
    }
    _flags[m.key] = f;
    _scheduleFlagSave();
  }

  void _scheduleFlagSave() {
    _flagSaveTimer?.cancel();
    _flagSaveTimer = Timer(const Duration(milliseconds: 400), () {
      store.saveFlags(_flags);
    });
  }

  void setRead(Iterable<MailItem> items, bool read) {
    for (final m in items) {
      if (m.kind != MailKind.received) continue;
      m.read = read;
      _setFlag(m, 'read', read);
    }
    notifyListeners();
  }

  void setStar(Iterable<MailItem> items, bool star) {
    for (final m in items) {
      if (m.kind == MailKind.draft) continue;
      m.star = star;
      _setFlag(m, 'star', star);
    }
    notifyListeners();
  }

  /// 移动到 inbox / archive / spam / trash（已发送的"inbox"即回到 sent）。
  /// 返回原文件夹快照，用于撤销。
  Map<String, String> move(Iterable<MailItem> items, String folder) {
    final undo = <String, String>{};
    for (final m in items) {
      if (m.kind == MailKind.draft) continue;
      undo[m.key] = m.folder;
      var target = folder;
      if (m.kind == MailKind.sent && (folder == 'inbox' || folder == 'spam')) {
        target = 'sent';
      }
      m.folder = target;
      _setFlag(m, 'folder', target);
      _setFlag(m, 'blk', null);
    }
    notifyListeners();
    return undo;
  }

  void undoMove(Map<String, String> snapshot) {
    snapshot.forEach((key, folder) {
      final m = byKey(key);
      if (m == null) return;
      m.folder = folder;
      _setFlag(m, 'folder', folder);
    });
    notifyListeners();
  }

  /// 永久删除（仅本地：隐藏 + 删除缓存原文；服务器上的副本不受影响）
  Future<void> deleteForever(Iterable<MailItem> items) async {
    for (final m in items.toList()) {
      switch (m.kind) {
        case MailKind.received:
          m.folder = 'purged';
          _setFlag(m, 'folder', 'purged');
          await store.deleteRaw(m.seq!);
          break;
        case MailKind.sent:
          await store.deleteSent(m.localId!);
          _flags.remove(m.key);
          _scheduleFlagSave();
          break;
        case MailKind.draft:
          await store.deleteDraft(m.localId!);
          break;
      }
      _items.remove(m);
    }
    notifyListeners();
  }

  // ── 黑名单 ──────────────────────────────────────────────
  // 条目：完整邮箱 a@b.com，或以 @ 开头的整域 @b.com
  bool _isBlocked(String email) {
    final e = email.toLowerCase();
    if (e.isEmpty) return false;
    if (_blacklist.contains(e)) return true;
    final at = e.lastIndexOf('@');
    return at >= 0 && _blacklist.contains(e.substring(at));
  }

  bool isBlocked(String email) => _isBlocked(email);

  /// 屏蔽发件人：加入黑名单，并把该发件人已有的收件箱/归档邮件移入垃圾邮件
  Future<void> block(String entry) async {
    final e = entry.trim().toLowerCase();
    if (e.isEmpty) return;
    _blacklist.add(e);
    for (final m in _items) {
      if (m.kind == MailKind.received &&
          (m.folder == 'inbox' || m.folder == 'archive') &&
          _isBlocked(m.senderEmail)) {
        m.folder = 'spam';
        if (_flags[m.key]?['folder'] != null) {
          // 有显式文件夹的，显式改成 spam，并打标记便于取消屏蔽时还原
          _setFlag(m, 'folder', 'spam');
          _setFlag(m, 'blk', true);
        } // 没有显式文件夹的，由黑名单推导即可，无需写 flag
      }
    }
    await _saveSettings();
    notifyListeners();
  }

  /// 取消屏蔽：移出黑名单，被自动归入垃圾邮件的邮件回到收件箱
  Future<void> unblock(String entry) async {
    final e = entry.trim().toLowerCase();
    _blacklist.remove(e);
    for (final m in _items) {
      if (m.kind != MailKind.received ||
          m.folder != 'spam' ||
          _isBlocked(m.senderEmail)) {
        continue;
      }
      final f = _flags[m.key];
      if (f?['blk'] == true) {
        _setFlag(m, 'folder', null);
        _setFlag(m, 'blk', null);
        m.folder = 'inbox';
      } else if (f?['folder'] == null) {
        m.folder = 'inbox'; // 原本就是黑名单推导出的 spam
      } // 用户手动标记的垃圾邮件保持不动
    }
    await _saveSettings();
    notifyListeners();
  }

  // ── 签名 / 联系人 ─────────────────────────────────────────
  Future<void> setSignature(String s) async {
    signature = s;
    await _saveSettings();
    notifyListeners();
  }

  /// 收件人自动补全
  List<MailAddr> suggest(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <MailAddr>[];
    _contacts.forEach((email, name) {
      if (out.length >= limit) return;
      if (email.contains(q) || name.toLowerCase().contains(q)) {
        out.add(MailAddr(name, email));
      }
    });
    return out;
  }

  Future<void> _rememberContacts(Iterable<MailAddr> list) async {
    for (final a in list) {
      final k = a.email.toLowerCase();
      if (a.name.isNotEmpty || !_contacts.containsKey(k)) _contacts[k] = a.name;
    }
    await _saveSettings();
  }

  Future<void> _saveSettings() => store.saveSettings({
        'blacklist': _blacklist.toList()..sort(),
        'signature': signature,
        // 只持久化最近的 2000 个，避免文件膨胀
        'contacts': _contacts.entries
            .take(2000)
            .map((e) => MailAddr(e.value, e.key).toString())
            .toList(),
      });

  // ── 原文 ──────────────────────────────────────────────
  Future<Uint8List> rawOf(MailItem m) async {
    if (m.kind == MailKind.sent) {
      final raw = await store.getSentRaw(m.localId!);
      if (raw == null) throw Exception('本地已发送原文丢失');
      return raw;
    }
    return sync.getRawCached(m.seq!, expectSha256: m.sha256);
  }

  // ── 草稿 ──────────────────────────────────────────────
  Future<String> saveDraft(OutgoingMail mail) async {
    final id = mail.draftId ?? DateTime.now().microsecondsSinceEpoch.toString();
    await store.putDraft(id, {
      'id': id,
      'epoch': DateTime.now().millisecondsSinceEpoch,
      'mail': mail.toJson(),
    });
    mail.draftId = id;
    await _reloadItems();
    notifyListeners();
    return id;
  }

  Future<OutgoingMail?> loadDraft(MailItem m) async {
    for (final d in await store.loadDrafts()) {
      if (d['id']?.toString() == m.localId) {
        return OutgoingMail.fromJson(
            (d['mail'] as Map).cast<String, dynamic>(),
            draftId: m.localId);
      }
    }
    return null;
  }

  Future<void> deleteDraft(String id) async {
    await store.deleteDraft(id);
    _items.removeWhere((m) => m.key == 'd$id');
    notifyListeners();
  }

  // ── 发信 ──────────────────────────────────────────────
  /// 优先 /v1/mail/sendRaw（完整 MIME：抄送/密送/HTML/附件/回复链）；
  /// 后端未实现时降级 /v1/mail/send（纯文本，逐个收件人）。
  Future<SendReport> send(OutgoingMail mail) async {
    final rcpts = mail.allRecipients;
    if (rcpts.isEmpty) throw Exception('没有收件人');

    final text = mail.quotedText == null
        ? mail.body
        : '${mail.body}\n\n${mail.quotedText}';
    var html = MailMimeBuilder.textToHtml(mail.body);
    if (mail.quotedHtml != null) {
      html += '<br><blockquote style="margin:0 0 0 .8ex;'
          'border-left:2px solid #ccc;padding-left:1ex;">'
          '${mail.quotedHtml}</blockquote>';
    }

    // 每个"批次"= 一封独立的 MIME：普通发送 1 批；群发单显 N 批
    final batches = <({List<MailAddr> to, List<MailAddr> cc, List<MailAddr> rcpt})>[
      if (mail.individually)
        for (final r in rcpts) (to: [r], cc: const <MailAddr>[], rcpt: [r])
      else
        (to: mail.to, cc: mail.cc, rcpt: rcpts),
    ];

    var ok = 0;
    final failed = <String>[];
    var legacy = false;

    for (final b in batches) {
      final built = MailMimeBuilder.build(
        from: me,
        to: b.to,
        cc: b.cc,
        subject: mail.subject,
        text: text,
        html: html,
        attachments: mail.attachments,
        inReplyTo: mail.inReplyTo,
        references: mail.references,
      );
      try {
        if (!legacy) {
          try {
            await QccMailApi.sendRaw(
              from: me.email,
              rcpt: b.rcpt.map((e) => e.email).toList(),
              raw: built.raw,
            );
          } on SendRawUnsupported {
            legacy = true;
          }
        }
        if (legacy) {
          if (mail.attachments.isNotEmpty) {
            throw Exception('服务器尚未支持附件发送（需实现 /v1/mail/sendRaw）');
          }
          for (final r in b.rcpt) {
            await QccMailApi.sendLegacy(
              from: me.email,
              to: r.email,
              subject: mail.subject,
              body: text,
            );
          }
        }
        ok += b.rcpt.length;
        await _recordSent(built.raw, built.messageId, b.to, b.cc, mail);
      } catch (e) {
        failed.addAll(b.rcpt.map((r) => '${r.email}: $e'));
      }
    }

    await _rememberContacts(rcpts);
    if (failed.isEmpty && mail.draftId != null) {
      await store.deleteDraft(mail.draftId!);
    }
    await _reloadItems();
    notifyListeners();
    return SendReport(ok, failed, legacy: legacy);
  }

  Future<void> _recordSent(Uint8List raw, String messageId, List<MailAddr> to,
      List<MailAddr> cc, OutgoingMail mail) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await store.putSent(id, raw, {
      'id': id,
      'messageId': messageId,
      'to': [...to, ...cc].map((e) => e.display).join(', '),
      'subject': mail.subject.isEmpty ? '(无主题)' : mail.subject,
      'preview': _shorten(mail.body),
      'epoch': DateTime.now().millisecondsSinceEpoch,
      'hasAttachments': mail.attachments.isNotEmpty,
    });
  }

  static String _shorten(String s, [int max = 80]) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  @override
  void dispose() {
    _flagSaveTimer?.cancel();
    store.saveFlags(_flags);
    super.dispose();
  }
}
