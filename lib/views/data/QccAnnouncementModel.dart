import 'dart:convert';
import 'package:qcc_flutter/utile/LogObj.dart';

class QccAnnouncementModel {
  final String hash;
  final String rawContent;
  final String time;
  final bool isError;

  QccAnnouncementModel({
    required this.hash,
    required this.rawContent,
    required this.time,
    this.isError = false,
  });

  // ✅ 核心解码逻辑：处理有符号字节并还原 UTF-8
  static String decodePayload(List<dynamic> payload) {
    try {
      // 1. 将有符号字节转换为无符号字节 (Dart 规范)
      List<int> uBytes = payload.map((e) {
        int val = e as int;
        return val < 0 ? val + 256 : val;
      }).toList();

      // 2. 尝试还原字符串
      return utf8.decode(uBytes);
    } catch (e) {
      LogObj.log("解码公告失败: $e");
      return "[解析失败: 数据可能为加密文件或非文本格式]";
    }
  }

  // 获取摘要（前 50 字）
  String get summary {
    if (rawContent.length > 50) {
      return "${rawContent.substring(0, 50)}...";
    }
    return rawContent;
  }
}