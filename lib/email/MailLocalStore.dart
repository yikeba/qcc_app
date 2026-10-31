import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 本地邮件存储，结构与服务器一致：
///   <app_docs>/qccemail/<user>/
///     account.json            {localMaxSeq: N}
///     0000000001.idx.json     轻量索引（同步即写）
///     0000000001.eml          原始字节（点开邮件时按需下载）
///
/// seq 定长 10 位零填充，文件名天然有序，与后端 AccountMailbox 对齐。
class MailLocalStore {
  static const int seqWidth = 10;

  final String user;
  late final Directory _dir;
  bool _ready = false;

  MailLocalStore(this.user);

  Future<void> _ensure() async {
    if (_ready) return;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/qccemail/${_safe(user)}');
    if (!await _dir.exists()) await _dir.create(recursive: true);
    _ready = true;
  }

  // ---- 高度 ----
  Future<int> localMaxSeq() async {
    await _ensure();
    final f = File('${_dir.path}/account.json');
    if (!await f.exists()) return 0;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (j['localMaxSeq'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setLocalMaxSeq(int seq) async {
    await _ensure();
    final f = File('${_dir.path}/account.json');
    await f.writeAsString(jsonEncode({'localMaxSeq': seq, 'user': user}));
  }

  // ---- 索引 ----
  Future<void> putIndex(Map<String, dynamic> idx) async {
    await _ensure();
    final seq = (idx['seq'] as num).toInt();
    final f = File('${_dir.path}/${_pad(seq)}.idx.json');
    await f.writeAsString(jsonEncode(idx));
  }

  /// 读取全部本地索引，按 seq 升序。列表渲染的数据源（离线可用）。
  Future<List<Map<String, dynamic>>> loadAllIndex() async {
    await _ensure();
    final out = <Map<String, dynamic>>[];
    final entries = await _dir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.idx.json')) {
        try {
          final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
          out.add(j);
        } catch (_) {/* 跳过损坏索引 */}
      }
    }
    out.sort((a, b) => (a['seq'] as num).compareTo(b['seq'] as num));
    return out;
  }

  // ---- 原文（.eml）按需缓存 ----
  Future<bool> hasRaw(int seq) async {
    await _ensure();
    return File('${_dir.path}/${_pad(seq)}.eml').exists();
  }

  Future<void> putRaw(int seq, Uint8List bytes) async {
    await _ensure();
    await File('${_dir.path}/${_pad(seq)}.eml').writeAsBytes(bytes);
  }

  Future<Uint8List?> getRaw(int seq) async {
    await _ensure();
    final f = File('${_dir.path}/${_pad(seq)}.eml');
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<void> deleteRaw(int seq) async {
    await _ensure();
    final f = File('${_dir.path}/${_pad(seq)}.eml');
    if (await f.exists()) await f.delete();
  }

  // ---- 本地状态（已读/星标/所在文件夹），键：r<seq> 收件 / s<id> 已发送 ----
  //   flags.json: { "r12": {"read":true,"star":false,"folder":"archive"}, ... }
  // 仅本地，换设备不同步；后端加 flags 接口后可改为双向同步。
  Future<Map<String, Map<String, dynamic>>> loadFlags() async {
    final j = await _readJson('flags.json');
    if (j is! Map) return {};
    return j.map((k, v) => MapEntry(
        k.toString(), (v as Map).cast<String, dynamic>()));
  }

  Future<void> saveFlags(Map<String, Map<String, dynamic>> flags) =>
      _writeJson('flags.json', flags);

  // ---- 设置：黑名单 / 签名 / 联系人 ----
  Future<Map<String, dynamic>> loadSettings() async {
    final j = await _readJson('settings.json');
    return j is Map ? j.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> saveSettings(Map<String, dynamic> s) =>
      _writeJson('settings.json', s);

  // ---- 已发送：sent/<id>.eml + sent/<id>.json ----
  Future<void> putSent(String id, Uint8List raw, Map<String, dynamic> meta) async {
    final d = await _sub('sent');
    await File('${d.path}/$id.eml').writeAsBytes(raw);
    await File('${d.path}/$id.json').writeAsString(jsonEncode(meta));
  }

  Future<List<Map<String, dynamic>>> loadSent() => _loadJsonDir('sent');

  Future<Uint8List?> getSentRaw(String id) async {
    final f = File('${(await _sub('sent')).path}/$id.eml');
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> deleteSent(String id) async {
    final d = await _sub('sent');
    for (final ext in ['eml', 'json']) {
      final f = File('${d.path}/$id.$ext');
      if (await f.exists()) await f.delete();
    }
  }

  // ---- 草稿：drafts/<id>.json ----
  Future<void> putDraft(String id, Map<String, dynamic> draft) async {
    final d = await _sub('drafts');
    await File('${d.path}/$id.json').writeAsString(jsonEncode(draft));
  }

  Future<List<Map<String, dynamic>>> loadDrafts() => _loadJsonDir('drafts');

  Future<void> deleteDraft(String id) async {
    final f = File('${(await _sub('drafts')).path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  // ---- 工具 ----
  Future<Directory> _sub(String name) async {
    await _ensure();
    final d = Directory('${_dir.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<Map<String, dynamic>>> _loadJsonDir(String name) async {
    final d = await _sub(name);
    final out = <Map<String, dynamic>>[];
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          out.add((jsonDecode(await e.readAsString()) as Map)
              .cast<String, dynamic>());
        } catch (_) {/* 跳过损坏文件 */}
      }
    }
    return out;
  }

  Future<Object?> _readJson(String name) async {
    await _ensure();
    final f = File('${_dir.path}/$name');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// 先写临时文件再 rename，避免写一半崩溃导致文件损坏
  Future<void> _writeJson(String name, Object value) async {
    await _ensure();
    final tmp = File('${_dir.path}/$name.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename('${_dir.path}/$name');
  }

  static String _pad(int seq) => seq.toString().padLeft(seqWidth, '0');

  static String _safe(String user) =>
      user.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_');
}