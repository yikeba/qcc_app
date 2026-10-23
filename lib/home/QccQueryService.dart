import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';

/// 执行层统一查询入口 —— 对应服务端 QueryContext.java
///   registerApi(ctx, "query", "/v1/query/*", new QueryContext(), READ);
///
/// 服务端响应形状（QueryContext.doGet）：
///   成功：{"ok":true,"kind":"<action>","data":{...}}   data 已是对象，不用再解一层
///   失败：{"ok":false,"error":"..."}                   HTTP 400 / 502
///
/// 存证（gas.quote）和下一步资产白名单（whitelist.*）共用这一个入口，
/// 新增 action 只需要在这里加一个便捷方法，不用再加新的 URL。
class QccQueryService {
  static const Duration _timeout = Duration(seconds: 10);

  /// 通用调用。返回 data 字段（通常是 Map，服务端解析失败时可能是 String）。
  /// params 里值为 null/空串的会被丢弃 —— 与服务端"空值跳过"的行为一致。
  static Future<dynamic> query(String action, [Map<String, Object?> params = const {}]) async {
    final qp = <String, String>{};
    params.forEach((k, v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      qp[k] = s;
    });

    final base = Uri.parse("${QccExplorerService.baseUrl}/v1/query/$action");
    final uri = qp.isEmpty ? base : base.replace(queryParameters: qp);

    final resp = await http.get(uri).timeout(_timeout);

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw QccQueryException(resp.statusCode, "非 JSON 响应: ${resp.body}");
    }
    if (decoded is! Map) {
      throw QccQueryException(resp.statusCode, "响应不是对象: ${resp.body}");
    }
    if (decoded['ok'] != true) {
      throw QccQueryException(resp.statusCode, (decoded['error'] ?? 'unknown error').toString());
    }
    return decoded['data'];
  }

  static Map<String, dynamic> _asMap(dynamic data, String action) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw QccQueryException(200, "$action 返回的 data 不是对象: $data");
  }

  // ---------------- gas.quote ----------------

  /// 费率总览 + 分段表（不带参数）。
  static Future<GasQuote> gasQuoteOverview() async =>
      GasQuote.fromMap(_asMap(await query("gas.quote"), "gas.quote"));

  /// 按字节数报价 —— 存证费用的权威来源。
  static Future<GasQuote> gasQuoteBytes(int byteSize) async =>
      GasQuote.fromMap(_asMap(await query("gas.quote", {"byteSize": byteSize}), "gas.quote"));

  /// 按资产报价（白名单资产等）。
  static Future<GasQuote> gasQuoteAsset(String assetId) async =>
      GasQuote.fromMap(_asMap(await query("gas.quote", {"assetId": assetId}), "gas.quote"));

  // ---------------- whitelist.*（下一步资产白名单用）----------------

  static Future<Map<String, dynamic>> whitelistCount(String assetId) async =>
      _asMap(await query("whitelist.count", {"assetId": assetId}), "whitelist.count");

  static Future<Map<String, dynamic>> whitelistCheck(String assetId, String address) async =>
      _asMap(await query("whitelist.check", {"assetId": assetId, "address": address}), "whitelist.check");

  static Future<Map<String, dynamic>> whitelistPage(String assetId, {int offset = 0, int limit = 1000}) async =>
      _asMap(await query("whitelist.page", {"assetId": assetId, "offset": offset, "limit": limit}), "whitelist.page");
}

class QccQueryException implements Exception {
  final int httpStatus;
  final String message;
  QccQueryException(this.httpStatus, this.message);
  @override
  String toString() => message;
}

/// gas.quote 返回解析 —— 严格对应执行层 handleGasQuote()：
///
/// data = {
///   gFactor, minTxBasegase, dataMaxSize, ruleGasQcc, ruleGasNano,
///   quote:    {byteSize, valid, reason?  |  kb, gasQcc, gasNano, tier}   // 仅传 byteSize 时
///   transfer: {assetId, gasQcc, gasNano, native}                       // 仅传 assetId 时
///   dataTiers:[...]
/// }
/// 不做键名猜测：字段对不上就是 null，页面会退回本地估算并显示原因。
class GasQuote {
  final Map<String, dynamic> raw;

  // 规则总览（顶层）
  final double? gFactor;
  final int? dataMaxSize;
  final int? minTxBasegase;
  final double? ruleGasQcc;
  final int? ruleGasNano;

  // 存证报价（data.quote）
  final bool hasQuote;
  final bool? valid;
  final String? reason; // valid=false 时的越界说明
  final int? kb;
  final double? gas; // = quote.gasQcc，单位 QCC
  final int? gasNano;
  final String? tier;

  // 转账报价（data.transfer）
  final double? transferGasQcc;
  final int? transferGasNano;

  final List<dynamic>? dataTiers;

  GasQuote._({
    required this.raw,
    this.gFactor,
    this.dataMaxSize,
    this.minTxBasegase,
    this.ruleGasQcc,
    this.ruleGasNano,
    required this.hasQuote,
    this.valid,
    this.reason,
    this.kb,
    this.gas,
    this.gasNano,
    this.tier,
    this.transferGasQcc,
    this.transferGasNano,
    this.dataTiers,
  });

  factory GasQuote.fromMap(Map<String, dynamic> m) {
    final q = m['quote'] is Map ? Map<String, dynamic>.from(m['quote']) : null;
    final t = m['transfer'] is Map ? Map<String, dynamic>.from(m['transfer']) : null;
    return GasQuote._(
      raw: m,
      gFactor: _d(m['gFactor']),
      dataMaxSize: _i(m['dataMaxSize']),
      minTxBasegase: _i(m['minTxBasegase']),
      ruleGasQcc: _d(m['ruleGasQcc']),
      ruleGasNano: _i(m['ruleGasNano']),
      hasQuote: q != null,
      valid: q?['valid'] is bool ? q!['valid'] as bool : null,
      reason: q?['reason']?.toString(),
      kb: _i(q?['kb']),
      gas: _d(q?['gasQcc']),
      gasNano: _i(q?['gasNano']),
      tier: q?['tier']?.toString(),
      transferGasQcc: _d(t?['gasQcc']),
      transferGasNano: _i(t?['gasNano']),
      dataTiers: m['dataTiers'] is List ? m['dataTiers'] as List : null,
    );
  }

  /// 服务端明确判定越界（valid=false）。
  bool get rejected => hasQuote && valid == false;

  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static int? _i(dynamic v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}
