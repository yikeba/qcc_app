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
}