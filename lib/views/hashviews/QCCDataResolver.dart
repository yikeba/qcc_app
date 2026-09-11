import 'dart:convert';
import 'dart:typed_data';

/// QCC 链数据解析结果模型
class QccResolveResult {
  final String type; // 'IMAGE', 'TEXT', 'JSON', 'FILE'
  final dynamic data;
  final String? mime;

  QccResolveResult({required this.type, required this.data, this.mime});
}

class QccDataResolver {
  static QccResolveResult resolve(List<int> payload) {
    // 1. 处理补码逻辑并转为 Uint8List
    // Dart 的 Uint8List.fromList 会自动处理超出 0-255 的整数位流
    final Uint8List bytes = Uint8List.fromList(payload);

    if (bytes.isEmpty) {
      return QccResolveResult(type: 'EMPTY', data: null);
    }

    // 2. 识别图片 (Magic Numbers)
    if (_isPng(bytes)) {
      return QccResolveResult(type: 'IMAGE', data: bytes, mime: 'image/png');
    }
    if (_isJpeg(bytes)) {
      return QccResolveResult(type: 'IMAGE', data: bytes, mime: 'image/jpeg');
    }

    // 3. 尝试解析为 文本 或 JSON
    try {
      // utf8.decode 会处理多字节字符（如中文）
      final String text = utf8.decode(bytes);

      // 判断是否为 JSON
      if ((text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'))) {
        return QccResolveResult(type: 'JSON', data: jsonDecode(text));
      }
      return QccResolveResult(type: 'TEXT', data: text);
    } catch (e) {
      // 4. 解析失败则作为二进制文件
      return QccResolveResult(type: 'FILE', data: bytes);
    }
  }

  static bool _isPng(Uint8List b) =>
      b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  static bool _isJpeg(Uint8List b) =>
      b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
}