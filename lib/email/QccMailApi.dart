import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// QccEmail 网络层。对应后端高度差额同步协议：
///   GET /v1/mail/count?user=             → {maxSeq, count}
///   GET /v1/mail/index?user=&from=&to=   → {from,to,maxSeq,items:[...]}
///   GET /v1/mail/raw?user=&seq=          → 完整 .eml 字节（响应头带 X-Mail-Sha256）
class QccMailApi {
  static const String base = "http://192.131.142.226:8081";
  //static const String base = "http://145.14.158.49:8081";
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    // TODO[v2]: headers: {'Authorization': 'Bearer <token>'}
  ));

  /// 账户当前最大高度（= 总数）。
  static Future<int> fetchMaxSeq(String user) async {
    final resp = await _dio.get('$base/v1/mail/count',
        queryParameters: {'user': user});
    final data = resp.data;
    if (data is Map && data['maxSeq'] != null) {
      return (data['maxSeq'] as num).toInt();
    }
    throw Exception('count 返回异常: $data');
  }

  /// 拉区间索引 [from, to]（含端点）。返回 items 列表。
  static Future<List<dynamic>> fetchIndexRange(
      String user, int from, int to) async {
    final resp = await _dio.get('$base/v1/mail/index', queryParameters: {
      'user': user,
      'from': from,
      'to': to,
    });
    final data = resp.data;
    if (data is Map && data['items'] is List) {
      return data['items'] as List;
    }
    throw Exception('index 返回异常: $data');
  }

  /// 按 seq 下载完整 .eml 原始字节，同时返回响应头里的 sha256（可校验）。
  static Future<({Uint8List bytes, String? sha256})> fetchRaw(
      String user, int seq) async {
    final resp = await _dio.get<List<int>>(
      '$base/v1/mail/raw',
      queryParameters: {'user': user, 'seq': seq},
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(resp.data!);
    final sha = resp.headers.value('x-mail-sha256');
    return (bytes: bytes, sha256: sha);
  }

  // ────────────────────────── 发信 ──────────────────────────

  /// 【新接口，需后端实现】原始 .eml 投递。
  ///   POST /v1/mail/sendRaw
  ///   body: {from: "a@qccio.com", rcpt: ["x@y.com", ...], raw: "<base64 .eml>"}
  ///   resp: {success: true, sha256?: "..."}
  /// 服务端只需：校验 from 属于当前用户 → 按 rcpt 逐个 SMTP 投递 raw 原文（不改写）。
  /// rcpt = To + Cc + Bcc（Bcc 不在 raw 头里，只在信封里）。
  ///
  /// 后端未实现（404/405/501）时抛 [SendRawUnsupported]，上层自动降级到 [sendLegacy]。
  static Future<void> sendRaw({
    required String from,
    required List<String> rcpt,
    required Uint8List raw,
  }) async {
    try {
      final resp = await _dio.post('$base/v1/mail/sendRaw', data: {
        'from': from,
        'rcpt': rcpt,
        'raw': base64.encode(raw),
      });
      final data = resp.data;
      if (data is Map && data['success'] == true) return;
      throw Exception('sendRaw 返回异常: $data');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404 || code == 405 || code == 501) {
        throw SendRawUnsupported();
      }
      rethrow;
    }
  }

  /// 旧接口：POST /v1/mail/send {from,to,subject,body}，仅纯文本、单收件人。
  static Future<void> sendLegacy({
    required String from,
    required String to,
    required String subject,
    required String body,
  }) async {
    final resp = await _dio.post('$base/v1/mail/send', data: {
      'from': from,
      'to': to,
      'subject': subject,
      'body': body,
    });
    final data = resp.data;
    if (data is Map && data['success'] == true) return;
    throw Exception('发送失败: $data');
  }
}

/// 后端尚未提供 /v1/mail/sendRaw
class SendRawUnsupported implements Exception {
  @override
  String toString() => '服务器尚未支持 /v1/mail/sendRaw';
}