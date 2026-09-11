import 'dart:convert';
import 'package:http/http.dart' as http;
import '../views/hashviews/GasRecord.dart';
import '../views/hashviews/QccDataMeta.dart';
import '../qccnodemap/QccNodeManager.dart';

class QccExplorerService {
  static String get baseUrl => QccNodeManager.instance.currentBaseUrl();
  //static const String baseUrl = "https://test.qccio.com";
 // static const String baseUrl = "http://192.131.142.226:9080";
 // static const String baseUrl = "http://192.168.1.138:9080";
  static Future<List<String>> fetchAddressHashes(String address) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/v1/address/$address"));
      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        // 根据日志：地址返回在 decoded['data']['txHashes']
        if (decoded['ok'] == true && decoded['data'] != null) {
          final List? hashList = decoded['data']['txHashes'];
          return List<String>.from(hashList ?? []);
        }
      }
    } catch (e) {
      print("解析地址历史异常: $e");
    }
    return [];
  }

  static Future<QccDataMeta> fetchDetail(String hash) async {
    final response = await http.get(Uri.parse("$baseUrl/v1/hash/$hash"));
    final Map<String, dynamic> rawResponse = jsonDecode(response.body);

    Map<String, dynamic> txDetail = {};
    try {
      // 1. 获取 data 字段
      var dataField = rawResponse['data'];
      if (dataField != null) {
        Map<String, dynamic> dataMap;

        // 核心修正：如果 data 是字符串，先解析它
        if (dataField is String) {
          dataMap = jsonDecode(dataField);
        } else {
          dataMap = dataField;
        }

        // 2. 获取 tx 字段
        var txField = dataMap['tx'];
        if (txField != null) {
          if (txField is String) {
            txDetail = jsonDecode(txField);
          } else {
            txDetail = txField;
          }
        }
      }
    } catch (e) {
      print("解析 QCC 嵌套 JSON 失败: $e");
    }

    // 3. 此时 txDetail 已经包含了 typeCode 和 assetId
    // 日志 1: typeCode 为 3 (entity) -> 数据
    // 日志 2: typeCode 为 1 (transaction) -> 转账
    // 日志 2: typeCode 为 2 (rule) -> 规则发布
    bool isData = txDetail['typeCode'] == 3 || txDetail['assetId'] == 'QCCData';

    return QccDataMeta(
      metaHash: hash,
      hashes: [hash],
      timestamp: txDetail['timestamp'] ?? rawResponse['timestamp'] ?? 0,
      entryType: isData ? QccEntryType.data : QccEntryType.transaction,
      // 只有是数据时才去提取摘要，否则显示“转账交易”
      title: isData ? _extractSummary(txDetail) : "转账交易",
      extra: txDetail, // 确保这个 Map 被传给详情页，避免重复解析
    );
  }
// 提取摘要的辅助方法
  static String _extractSummary(Map<String, dynamic> txDetail) {
    try {
      // 尝试解析 payload 看看里面写了什么
      final List<int> payload = List<int>.from(txDetail['payload'] ?? []);
      if (payload.isNotEmpty) {
        // 尝试解码前 20 个字节作为标题预览
        String text = utf8.decode(payload.take(30).toList(), allowMalformed: true);
        return text.replaceAll('\n', ' ').trim();
      }
    } catch (_) {}
    return "存证数据实体";
  }


  static Future<GasRecordPage> fetchGasDetails(String address) async {
    String url = "${QccExplorerService.baseUrl}/v1/gas/?address=$address";
    //if(kDebugMode)url = "http://192.168.1.184:9080/v1/gas/?address=$address";
    final resp = await http.get(Uri.parse(url));
    final Map<String, dynamic> json = jsonDecode(resp.body); // ← 正确：Map
    return GasRecordPage.fromJson(json);
  }


}