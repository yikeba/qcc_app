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

  // ---- 工具 ----
  static String _pad(int seq) => seq.toString().padLeft(seqWidth, '0');

  static String _safe(String user) =>
      user.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_');
}