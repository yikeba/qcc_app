import 'dart:convert';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../qccnodemap/QccNodeManager.dart';
import '../views/hashviews/QccDataMeta.dart';
import '../home/QccExplorerService.dart';
class QccApiService {
  // 注意：这里必须是 `get`（每次访问都重新计算），不能是普通 static 字段。
  // 普通 `static String baseUrl = "...";` 只会在第一次被访问时求值一次，
  // 之后就被冻结了——QccNodeManager 内部无论怎么切换（SSL 恢复/失败、
  // 节点探测结果变化、新节点加入等），这里都感知不到，永远用的是最早那个
  // 过期值。改成 getter 后每次都会重新取 QccExplorerService.baseUrl
  // （进而是 QccNodeManager.currentBaseUrl()）的最新值。
  //
  // 但光这样还不够：下面的请求已经改成走 QccNodeManager.instance.get()
  // 而不是直接拿这个 baseUrl 拼 Uri 自己发请求——原因见 get() 内部注释，
  // 简单说就是只有走 QccNodeManager.get() 才会在请求失败/网关错误时
  // reportFailure，SSL 入口失败次数才会真正累积，currentBaseUrl() 才
  // 会在阈值达到后切到健康节点，而不是死认一个已经连不上的入口。
  // 这里保留 baseUrl 是为了兼容其它可能还在用它的地方，仅供参考用途。
  static String get baseUrl => "${QccExplorerService.baseUrl}/v1";

  Future<List<QccTransaction>> getTransactionHistory(String address, String targetAssetId) async {
    final historyRes = await QccNodeManager.instance.get('/v1/address/$address');
    if (historyRes == null || historyRes.statusCode != 200) {
      throw Exception("获取历史失败");
    }

    final historyData = jsonDecode(historyRes.body);

    // 1. 获取原始 Hash 列表
    List<dynamic> rawHashes = historyData['data']['txHashes'] ?? [];

    // --- 【核心修复：去重逻辑】 ---
    // 使用 toSet() 自动过滤掉重复的 Hash，再转回 List
    List<dynamic> uniqueHashes = rawHashes.toSet().toList();
    LogObj.log("QCC历史记录去重: 原始条数 ${rawHashes.length}, 去重后条数 ${uniqueHashes.length}");

    // 2. 截取最近的 50 条唯一交易进行解析
    final limitedHashes = uniqueHashes.take(50).toList();
    List<QccTransaction> filteredList = [];

    // 3. 批量并发请求详情
    List<Future<void>> futures = limitedHashes.map((hash) async {
      try {
        final detailRes = await QccNodeManager.instance.get('/v1/hash/$hash');
        if (detailRes == null || detailRes.statusCode != 200) return;
        final detailData = jsonDecode(detailRes.body);

        // 解析第一层 data
        var rawData = detailData['data'];
        Map<String, dynamic> innerData = (rawData is String) ? jsonDecode(rawData) : rawData;

        // 解析第二层 tx (交易核心体)
        var rawTx = innerData['tx'];
        Map<String, dynamic> txDetail = (rawTx is String) ? jsonDecode(rawTx) : rawTx;

        String currentAssetId = txDetail['assetId'] ?? "";
        String txType = txDetail['txType'] ?? "";

        // 过滤资产
        if (currentAssetId == targetAssetId) {

          // 【保留之前的优化】针对 win 类型交易金额读取 winAmount
          num finalAmount = 0;
          if (txType == "win") {
            finalAmount = innerData['winAmount'] ?? txDetail['amount'] ?? 0;
          } else {
            finalAmount = txDetail['amount'] ?? 0;
          }

          filteredList.add(QccTransaction(
            id: txDetail['id'] ?? "",
            containerId: innerData['containerId:'] ?? innerData['containerId'] ?? "",
            assetId: currentAssetId,
            from: txDetail['from'] ?? "",
            to: txDetail['to'] ?? "",
            amount: finalAmount.toInt(),
            timestamp: txDetail['timestamp'] ?? detailData['timestamp'] ?? 0,
            type: txType,
          ));
        }
      } catch (e) {
        LogObj.log("解析 QCC 交易 $hash 失败: $e");
      }
    }).toList();

    await Future.wait(futures);

    // 按交易时间倒序排序
    filteredList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return filteredList;
  }



}



class QccTransaction {
  final String id;
  final String containerId;
  final String assetId;
  final String from;
  final String to;
  final int amount;
  final int timestamp;
  final String type;

  QccTransaction({
    required this.id,
    required this.containerId,
    required this.assetId,
    required this.from,
    required this.to,
    required this.amount,
    required this.timestamp,
    required this.type,
  });
}



class QccBalance {
  final String address;
  final String assetId;
  late final String url;

  // 精度：9位小数（1 QCC = 1_000_000_000 单位）
  int precision = 9;
  BigInt unit = BigInt.from(1000000000); // 10^9

  // 只走 QccNodeManager.get() 时实际使用的相对路径（不含 host）。
  late final String _path;

  QccBalance(this.address, this.assetId) {
    _path = '/v1/balance/$address?asset=$assetId';
    // 仍然保留一份完整 url，仅供日志/调试展示用，不再用它直接发请求。
    url = "${QccApiService.baseUrl}/balance/$address?asset=$assetId";
    unit = BigInt.from(precision); // 10^9
  }
  /// 获取原始余额字符串（最小单位，例如 "800000000000000"）
  ///
  /// 改用 QccNodeManager.instance.get() 而不是直接 http.get(Uri.parse(url))：
  /// 后者只会打固定的那个（可能已经失效的）baseUrl，请求失败也不会反馈给
  /// QccNodeManager，SSL 入口一旦挂了就永远读不出余额。走 get() 之后会
  /// 自动在 SSL 入口 / 健康节点（含 IPv6）之间失败重试、切换。
  Future<String> getRawBalance() async {
    try {
      final response = await QccNodeManager.instance.get(_path);
      if (response == null) {
        print('所有节点均不可达，读取余额失败');
        return '0';
      }
      if (response.statusCode == 200) {
        final outerJson = jsonDecode(response.body) as Map<String, dynamic>;
        if (outerJson['ok'] != true) {
          print('API 返回非成功状态: ${outerJson['ok']}');
          return '0';
        }
        //LogObj.log("get Raw qcc 余额查询返回:$outerJson");
        final dataStr = outerJson['data'] as String?;
        if (dataStr == null || dataStr.isEmpty) {
          print('data 字段为空');
          return '0';
        }

        final innerJson = jsonDecode(dataStr) as Map<String, dynamic>;
        final balanceValue = innerJson['balance'];

        if (balanceValue != null) {
          return balanceValue.toString();
        } else {
          print('balance 字段不存在');
          return '0';
        }
      } else {
        print('HTTP 错误: ${response.statusCode} - ${response.body}');
        return '0';
      }
    } catch (e) {
      print('getRawBalance 异常: $e');
      return '0';
    }
  }


  /// 新增：返回人类可读的正常金额（例如 800.000000000 QCC）
  /// - 自动转换为小数
  /// - 默认保留 9 位小数（可自定义保留位数）
  /// - 如果余额为 0，返回 "0"
  Future<String> getFormattedBalance({int decimalPlaces = 9}) async {
    final rawStr = await getRawBalance();
    if (rawStr == '0') {
      return '0';
    }
    try {
      final rawBigInt = BigInt.parse(rawStr);
      // 整数部分 = raw / 10^9
      final integerPart = rawBigInt ~/ unit;
      // 小数部分 = raw % 10^9
      var decimalPart = (rawBigInt % unit).toString().padLeft(precision, '0');
      // 截取指定小数位（从左往右取，避免末尾0过多）
      if (decimalPlaces < precision) {
        decimalPart = decimalPart.substring(0, decimalPlaces);
      }
      // 去除小数部分末尾的0（美观）
      decimalPart = decimalPart.replaceAll(RegExp(r'0+$'), '');
      if (decimalPart.isEmpty) {
        return integerPart.toString();
      }
      return '$integerPart.$decimalPart';
    } catch (e) {
      print('格式化余额异常: $e');
      return '0';
    }
  }
}