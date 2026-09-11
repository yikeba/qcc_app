import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

class QccHttp {
  // 1. 全局单例的持久化 Client，复用 TCP/TLS 握手，极大提高请求速度
  static final http.Client _client = http.Client();

  // 2. 默认的全局请求头（伪装成浏览器，避免被云拦截）
  static const Map<String, String> _defaultHeaders = {
    "User-Agent": "Mozilla/5.0 (App; QCC-DEX)",
    "Content-Type": "application/json",
  };

  /// 封装 GET 请求
  /// [timeoutSeconds] 默认配置为 3 秒超时
  static Future<http.Response> get(String url, {Map<String, String>? headers, int timeoutSeconds = 3}) {
    final mergedHeaders = {..._defaultHeaders, ...?headers};
    return _client.get(Uri.parse(url), headers: mergedHeaders)
        .timeout(Duration(seconds: timeoutSeconds));
  }

  /// 封装 POST 请求
  static Future<http.Response> post(String url, {Map<String, String>? headers, Object? body, int timeoutSeconds = 5}) {
    final mergedHeaders = {..._defaultHeaders, ...?headers};
    return _client.post(Uri.parse(url), headers: mergedHeaders, body: body)
        .timeout(Duration(seconds: timeoutSeconds));
  }

  /// ✅ 核心：分批并发执行器 (模拟浏览器最高并发数限制)
  /// 将海量任务切分成小批次，防止瞬间高并发触发服务器 DDoS 拦截
  /// [tasks] 是一个返回 Future 的函数列表
  static Future<List<T>> runInBatches<T>(List<Future<T> Function()> tasks, {int batchSize = 5}) async {
    List<T> results = [];
    for (int i = 0; i < tasks.length; i += batchSize) {
      int end = min(i + batchSize, tasks.length);
      // 提取这一批次的任务并执行
      var batchTasks = tasks.sublist(i, end).map((task) => task());
      // 等待这一批次完成，将结果加入总集合
      results.addAll(await Future.wait(batchTasks));
    }
    return results;
  }
}