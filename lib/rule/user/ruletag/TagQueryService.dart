import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../home/QccExplorerService.dart';
import '../../../utile/LogObj.dart';

/// GET /v1/tag/{tagName} 的查询结果 —— 字段对齐 Java TxTagRuleTest /
/// TxTagTransferTest 里记录的 TagQuery 返回：
///   {"ok":true,"found":true,"data":{"tagName","owner","credentialHash",
///                                   "regTime","prevOwner","transferTime"}}
///   {"ok":true,"found":false,"data":null}
///   {"ok":false,"message"|"error":"..."}     —— 真正的查询失败
class TagInfo {
  /// 查询本身是否成功（ok:true）。false 时 found/owner 等都不可信。
  final bool ok;
  final bool found;
  final String? owner;
  final String? prevOwner;
  final String? credentialHash;
  final int? regTime;
  final int? transferTime;
  final String? error;

  const TagInfo({
    required this.ok,
    this.found = false,
    this.owner,
    this.prevOwner,
    this.credentialHash,
    this.regTime,
    this.transferTime,
    this.error,
  });

  factory TagInfo.failed(String? msg) => TagInfo(ok: false, error: msg);
}

/// 标签查询 —— TagRule / TagTransfer 两个页面和两个详情页共用。
///
/// 原来两个 widget 各自写死 https://tx.qccio.com/v1/tag/，现在统一走
/// QccExplorerService.baseUrl：存证 /v1/data、转账 /v1/txm、规则 /v1/rule
/// 都已经在 baseUrl 上实测成功，没有理由让标签查询单独指向另一个 host。
class TagQueryService {
  TagQueryService._();

  static Future<TagInfo> query(String tagName) async {
    final name = tagName.trim();
    if (name.isEmpty) return TagInfo.failed("标签名称为空");
    try {
      final resp = await http
          .get(Uri.parse("${QccExplorerService.baseUrl}/v1/tag/${Uri.encodeComponent(name)}"))
          .timeout(const Duration(seconds: 15));
      final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is! Map) return TagInfo.failed("返回格式异常");
      // 不能只看 HTTP 状态码：节点异常时 body 结构完好但 ok:false
      if (body['ok'] != true) {
        return TagInfo.failed((body['message'] ?? body['error'])?.toString());
      }
      if (body['found'] != true) return const TagInfo(ok: true, found: false);

      final Map d = body['data'] is Map ? body['data'] as Map : const {};
      return TagInfo(
        ok: true,
        found: true,
        owner: d['owner']?.toString(),
        prevOwner: d['prevOwner']?.toString(),
        credentialHash: d['credentialHash']?.toString(),
        regTime: _int(d['regTime']),
        transferTime: _int(d['transferTime']),
      );
    } catch (e) {
      LogObj.log("TagQuery 异常: $e");
      return TagInfo.failed(null);
    }
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : (v != null ? int.tryParse(v.toString()) : null);

  static String formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }
}
