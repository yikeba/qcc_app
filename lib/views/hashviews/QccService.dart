import 'dart:convert';
import 'package:http/http.dart' as http;

import 'QCCDataResolver.dart';
import '../../home/QccExplorerService.dart';

class QccService {
  // 根据 Hash 或 URL 获取数据并解析
  static Future<Map<String, dynamic>> fetchAndResolve(String input) async {
    String url = input;

    // 如果输入的是纯 Hash，拼凑 API 地址
    if (!input.startsWith('http')) {
      url = "${QccExplorerService.baseUrl}/v1/address/$input";
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final rawData = jsonDecode(response.body);
        // 提取 payload
        final dataPart = jsonDecode(rawData['data']);
        final List<int> payload = List<int>.from(dataPart['payload']);

        // 调用之前的解析器
        final resolved = QccDataResolver.resolve(payload);

        return {
          "success": true,
          "resolved": resolved,
          "txHash": rawData['txHash'] ?? input,
        };
      }
    } catch (e) {
      return {"success": false, "error": e.toString()};
    }
    return {"success": false};
  }
}