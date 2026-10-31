import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'MailMimeBuilder.dart';

/// 附件选取 / 保存。
///   选取：file_picker（FilePicker.platform.pickFiles，与工程现有用法一致）
///   保存：path_provider + dart:io 直接写文件（不走 FilePicker.saveFile，避开各版本签名差异）
///
/// macOS 沙盒 Runner/*.entitlements 需要：
///   com.apple.security.files.user-selected.read-only = true   （选附件）
///   com.apple.security.files.downloads.read-write    = true   （保存到"下载"）
/// iOS 想在"文件"App 里看到保存的附件，Info.plist 需要：
///   UIFileSharingEnabled = YES，LSSupportsOpeningDocumentsInPlace = YES
class MailFileHelper {
  /// 单封邮件附件总量上限（与常见邮件服务一致，base64 后约 33MB）
  static const int maxTotalBytes = 25 * 1024 * 1024;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 选择多个文件作为附件；用户取消返回空列表。
  /// 与工程里钱包备份选择同一套 API：FilePicker.platform.pickFiles + withData。
  static Future<List<OutgoingAttachment>> pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择附件',
      type: FileType.any,
      allowMultiple: true,
      withData: true, // 桌面/移动/Web 都直接拿 bytes，不强依赖 path
    );
    if (result == null || result.files.isEmpty) return const [];
    final out = <OutgoingAttachment>[];
    for (final f in result.files) {
      var bytes = f.bytes;
      // 个别平台 withData 未生效时，用 path 兜底读取
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) continue;
      out.add(OutgoingAttachment(
        filename: f.name,
        mimeType: OutgoingAttachment.guessMime(f.name),
        bytes: bytes,
      ));
    }
    return out;
  }

  /// 保存附件，返回完整路径。
  ///   桌面：~/Downloads/QccMail/
  ///   移动：<App Documents>/QccMail/
  /// 同名文件自动追加 (1)(2)… 不覆盖。
  static Future<String> saveAttachment({
    required String filename,
    required Uint8List bytes,
  }) async {
    Directory? base;
    if (_isDesktop) base = await getDownloadsDirectory();
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}QccMail');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = await _uniqueFile(dir, _safeName(filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 用系统默认程序打开（桌面可用；Android 需要 FileProvider，不保证成功）
  static Future<bool> open(String path) async {
    try {
      return await launchUrl(Uri.file(path));
    } catch (_) {
      return false;
    }
  }

  static bool get canOpen => _isDesktop;

  static Future<File> _uniqueFile(Directory dir, String name) async {
    final sep = Platform.pathSeparator;
    var f = File('${dir.path}$sep$name');
    if (!await f.exists()) return f;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1;; i++) {
      f = File('${dir.path}$sep$stem ($i)$ext');
      if (!await f.exists()) return f;
    }
  }

  /// 去掉路径分隔符和非法字符，防止附件名里带 ../ 写到目录外
  static String _safeName(String name) {
    final n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    return n.isEmpty || n == '.' || n == '..' ? 'attachment' : n;
  }

  static String humanSize(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}