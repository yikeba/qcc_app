import 'dart:convert';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccHttp.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

import '../../../home/QccExplorerService.dart';

/// 📈 单笔成交记录模型
class DexTradeRecord {
  final String txHash;
  final int timestamp;
  final double amount; // 成交数量 (Base Asset)
  final double price;  // 成交价格 (Rate)

  DexTradeRecord({
    required this.txHash,
    required this.timestamp,
    required this.amount,
    required this.price,
  });
}

/// 📊 市场行情指标模型
class DexMarketTicker {
  final double latestPrice;
  final double recommendedPrice;
  final double change24h;
  final double volume24h;
  final List<DexTradeRecord> recentTrades;

  DexMarketTicker({
    required this.latestPrice,
    required this.recommendedPrice,
    required this.change24h,
    required this.volume24h,
    required this.recentTrades,
  });
}

class QccMarketTickerService {
  // 静态缓存：缓存 Opentx 的汇率、锁定资产、对价资产
  static final Map<String, Map<String, dynamic>> _openHashCache = {};

  static Future<DexMarketTicker?> getMarketTicker(String baseAsset, String quoteAsset) async {
    try {
      // 1. 获取 Win 成交记录
      final response = await QccHttp.get("${QccExplorerService.baseUrl}/v1/wintx?assetId=$baseAsset");
      if (response.statusCode != 200) return null;

      dynamic decodedRes = jsonDecode(response.body);
      List<dynamic> winList = [];
      if (decodedRes is List) {
        winList = decodedRes;
      } else if (decodedRes is Map && decodedRes['data'] != null) {
        winList = decodedRes['data'] is String ? jsonDecode(decodedRes['data']) : decodedRes['data'];
      }

      if (winList.isEmpty) return null;

      // 2. 提取所有未被缓存的 matcHash
      Set<String> missingOpenHashes = {};
      for (var win in winList) {
        String matcHash = win['matcHash'] ?? "";
        if (matcHash.isNotEmpty && !_openHashCache.containsKey(matcHash)) {
          missingOpenHashes.add(matcHash);
        }
      }

      // 3. 并发拉取缺失的原始链上数据 (Hash)
      if (missingOpenHashes.isNotEmpty) {
        List<Future<void> Function()> tasks = [];
        for (String hash in missingOpenHashes) {
          tasks.add(() => _fetchAndCacheRawTx(hash));
        }
        await QccHttp.runInBatches(tasks, batchSize: 5);
      }

      // 4. 数据清洗与组装 (✅ 核心修复：双向判断)
      List<DexTradeRecord> validTrades = [];
      for (var win in winList) {
        String matcHash = win['matcHash'] ?? "";
        Map<String, dynamic>? openData = _openHashCache[matcHash];

        if (openData != null) {
          String lockedAsset = openData['lockedAsset']; // Maker 锁仓的币
          String pairAsset = openData['pairAsset'];     // Maker 想要的币
          double rate = openData['rate'];

          double actualPrice = 0.0;
          bool isValidPair = false;

          // 情况 1: 卖单 (Maker 锁了 QCC, 想要 USD)
          if (lockedAsset == baseAsset && pairAsset == quoteAsset) {
            actualPrice = rate;
            isValidPair = true;
          }
          // 情况 2: 买单 (Maker 锁了 USD, 想要 QCC) 👈 你的日志被拦截的就是这些单子！
          else if (lockedAsset == quoteAsset && pairAsset == baseAsset) {
            // 买单的汇率是倒数，需要还原成人类可读价格
            actualPrice = rate > 0 ? (1.0 / rate) : 0.0;
            isValidPair = true;
          }

          if (isValidPair) {
            double rawAmount = double.tryParse(win['amount'].toString()) ?? 0.0;
            double humanAmount = QccAssetService().getHumanAmountNum(baseAsset, rawAmount);
            int ts = int.tryParse(win['timestamp'].toString()) ?? 0;

            validTrades.add(DexTradeRecord(
              txHash: win['txHash'] ?? "",
              timestamp: ts,
              amount: humanAmount,
              price: actualPrice,
            ));
          } else {
            // 确实是其他的杂乱资产才过滤
            LogObj.log("⚠️ 过滤: 挂单 [$matcHash] ($lockedAsset -> $pairAsset) 不属于 $baseAsset/$quoteAsset 交易对");
          }
        }
      }

      LogObj.log("✅ 清洗完成，符合双向交易的有效成交记录: ${validTrades.length} 条");
      if (validTrades.isEmpty) return null;

      validTrades.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return _calculateMetrics(validTrades);

    } catch (e) {
      LogObj.log("❌ 获取行情异常: $e");
      return null;
    }
  }

  /// 获取底层最原始数据
  static Future<void> _fetchAndCacheRawTx(String matcHash) async {
    try {
      final res = await QccHttp.get("${QccExplorerService.baseUrl}/v1/hash/$matcHash");
      if (res.statusCode == 200) {
        dynamic resJson = jsonDecode(res.body);

        if (resJson is Map && resJson['ok'] == true && resJson['data'] != null) {

          dynamic dataWrapper = resJson['data'] is String ? jsonDecode(resJson['data']) : resJson['data'];

          if (dataWrapper is Map && dataWrapper['tx'] != null) {
            dynamic txData = dataWrapper['tx'] is String ? jsonDecode(dataWrapper['tx']) : dataWrapper['tx'];

            dynamic logic = txData['matchLogic'];
            if (logic is String) {
              try { logic = jsonDecode(logic); } catch (_) {}
            }

            if (logic != null && logic is Map) {
              double rate = double.tryParse(logic['rate']?.toString() ?? '0') ?? 0.0;
              String pairAsset = logic['pairAssetId'] ?? "UNKNOWN";

              // ✅ 核心修复：把 Maker 锁仓的资产名也抓出来
              String lockedAsset = txData['assetId'] ?? "UNKNOWN";

              _openHashCache[matcHash] = {
                "rate": rate,
                "pairAsset": pairAsset,
                "lockedAsset": lockedAsset // 加入缓存
              };
            }
          }
        }
      }
    } catch (e) {
      LogObj.log("❌ 溯源底层 Hash 异常 [$matcHash]: $e");
    }
  }

  static DexMarketTicker _calculateMetrics(List<DexTradeRecord> trades) {
    double latestPrice = trades.first.price;
    double totalValue = 0.0;
    double totalAmount = 0.0;
    int recommendSampleCount = trades.length > 20 ? 20 : trades.length;

    for (int i = 0; i < recommendSampleCount; i++) {
      totalValue += trades[i].price * trades[i].amount;
      totalAmount += trades[i].amount;
    }
    double recommendedPrice = totalAmount > 0 ? (totalValue / totalAmount) : latestPrice;

    int nowTs = DateTime.now().millisecondsSinceEpoch;
    int oneDayAgoTs = nowTs - (24 * 60 * 60 * 1000);
    double volume24h = 0.0;
    double price24hAgo = latestPrice;
    bool found24hAgoPrice = false;

    for (var trade in trades) {
      if (trade.timestamp >= oneDayAgoTs) {
        volume24h += trade.amount;
      } else {
        if (!found24hAgoPrice) {
          price24hAgo = trade.price;
          found24hAgoPrice = true;
        }
      }
    }

    double change24h = 0.0;
    if (price24hAgo > 0) {
      change24h = ((latestPrice - price24hAgo) / price24hAgo) * 100.0;
    }

    return DexMarketTicker(
      latestPrice: latestPrice,
      recommendedPrice: recommendedPrice,
      change24h: change24h,
      volume24h: volume24h,
      recentTrades: trades,
    );
  }
}