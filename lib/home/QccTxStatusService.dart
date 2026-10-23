import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/Tools.dart';

/// 交易上链状态查询 —— GET /v1/hash/{txHash}
///
/// /v1/data 返回 ACCEPTED 只表示"已受理"，是否真正上链要轮询这个接口。
///
/// 【假设，需要你确认 —— 我没见到 /v1/hash 的处理代码】判定规则按"宁可多等，
/// 不可误报上链"的原则：
///   - HTTP 404 / ok:false / data 为空            → 待上链
///   - data.status|code|result 含 fail/reject/error/invalid → 失败
///   - data.status|code|result 含 pending/accepted/queue    → 待上链
///   - 其余能拿到非空对象                          → 已上链
///   - 区块高度依次取 blockHeight / height / blockIndex / block
/// 把 /v1/hash 的 handler 贴给我，我再改成严格解析（和 gas.quote 一样）。
enum TxChainState { pending, confirmed, failed }

class TxChainStatus {
  final TxChainState state;
  final int? blockHeight;
  final String? message;
  final dynamic raw;

  const TxChainStatus(this.state, {this.blockHeight, this.message, this.raw});

  bool get isFinal => state != TxChainState.pending;
}

class QccTxStatusService {
  /// 链上查询链接。若有面向浏览器的区块浏览器页面，只改这一处。
  static String chainUrl(String txHash) => "${QccExplorerService.baseUrl}/v1/hash/$txHash";

  static Future<TxChainStatus> checkOnce(String txHash) async {
    final resp = await http.get(Uri.parse(chainUrl(txHash))).timeout(const Duration(seconds: 8));
    if (resp.statusCode == 404) {
      return const TxChainStatus(TxChainState.pending, message: "尚未上链");
    }

    dynamic body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return TxChainStatus(TxChainState.pending, message: "HTTP ${resp.statusCode}，返回非 JSON");
    }

    if (body is Map && body['ok'] == false) {
      return TxChainStatus(TxChainState.pending, message: (body['error'] ?? '尚未上链').toString(), raw: body);
    }

    dynamic d = (body is Map && body.containsKey('data')) ? body['data'] : body;
    if (d is String) {
      try {
        d = jsonDecode(d);
      } catch (_) {}
    }
    if (d == null || (d is Map && d.isEmpty) || (d is String && d.trim().isEmpty)) {
      return TxChainStatus(TxChainState.pending, message: "尚未上链", raw: body);
    }

    if (d is Map) {
      final s = "${d['status'] ?? d['code'] ?? d['result'] ?? ''}".toLowerCase();
      if (s.contains('fail') || s.contains('reject') || s.contains('error') || s.contains('invalid')) {
        return TxChainStatus(
          TxChainState.failed,
          message: (d['msg'] ?? d['reason'] ?? d['error'] ?? s).toString(),
          raw: d,
        );
      }
      if (s.contains('pending') || s.contains('accepted') || s.contains('queue')) {
        return TxChainStatus(TxChainState.pending, message: "已受理，等待打包", raw: d);
      }
      return TxChainStatus(
        TxChainState.confirmed,
        blockHeight: _int(d['blockHeight'] ?? d['height'] ?? d['blockIndex'] ?? d['block']),
        raw: d,
      );
    }
    return TxChainStatus(TxChainState.pending, message: "未识别的返回", raw: body);
  }

  /// 轮询直到出结果或超时。间隔：前 5 次 3 秒，之后 5 秒，15 次后 10 秒。
  /// 超时后流正常结束，最后一次状态仍是 pending —— 由调用方提示"稍后再查"。
  static Stream<TxChainStatus> poll(String txHash, {Duration timeout = const Duration(minutes: 3)}) async* {
    final sw = Stopwatch()..start();
    int attempt = 0;
    while (sw.elapsed < timeout) {
      TxChainStatus st;
      try {
        st = await checkOnce(txHash);
      } catch (e) {
        st = TxChainStatus(TxChainState.pending, message: "查询异常: $e");
      }
      yield st;
      if (st.isFinal) return;
      attempt++;
      final secs = attempt < 5 ? 3 : (attempt < 15 ? 5 : 10);
      await Future.delayed(Duration(seconds: secs));
    }
  }

  /// 写回本机发布记录的补丁（EntityDataFileStorage.saveTask 按 txHash 合并）。
  static Map<String, dynamic> toRecordPatch(String txHash, TxChainStatus st) => {
    "txHash": txHash,
    "status": st.state == TxChainState.confirmed ? "confirmed" : (st.state == TxChainState.failed ? "failed" : "pending"),
    if (st.blockHeight != null) "blockHeight": st.blockHeight,
    if (st.message != null) "chainMsg": st.message,
    "checkedAt": DateTime.now().millisecondsSinceEpoch,
  };

  /// 打开链上查询：直接用工程里的 Tools.openChrome 唤起浏览器。
  /// 只在打不开时才退回到复制链接（比如设备上没有可用的浏览器）。
  static Future<void> openChainUrl(BuildContext context, String txHash) async {
    final url = chainUrl(txHash);
    try {
      await Tools.openChrome(url);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) Tools.showToast(context, "无法打开浏览器，链接已复制");
    }
  }

  /// 解析提交接口（/v1/txm、/v1/rule、/v1/data）的受理响应，返回 txHash；
  /// 未受理则抛出带服务端 msg 的异常。
  /// 受理响应：{"status":"accepted","code":"ACCEPTED","txHash":"...","msg":"..."}
  /// 以 code 为准（status 是小写），兼容只有 status 的旧格式。
  /// 剩余各页面（DexMatchWidget / QccWinTransactionPage / 分红领取等）统一调这里，
  /// 不再各写一份判断 —— 之前每个页面都写成了 status=='ACCEPTED'，全部永不成立。
  static String parseAcceptedTxHash(http.Response resp) {
    Map<String, dynamic> body = {};
    try {
      final d = jsonDecode(resp.body);
      if (d is Map) body = Map<String, dynamic>.from(d);
    } catch (_) {}
    final code = (body['code'] ?? body['status'] ?? '').toString().toUpperCase();
    final txHash = body['txHash']?.toString() ?? '';
    if (resp.statusCode == 200 && code == 'ACCEPTED' && txHash.isNotEmpty) return txHash;
    throw Exception("交易未被节点受理: ${body['msg'] ?? body['code'] ?? 'HTTP ${resp.statusCode}'}");
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}