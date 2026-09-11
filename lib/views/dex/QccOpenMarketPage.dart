import 'dart:developer' as LogObj;
import 'dart:math'; // 聚合 K 线需要用到 min/max

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/dex/price/DexTradeRecord.dart';
import 'package:qcc_flutter/views/dex/price/QccPriceTickerWidget.dart';

import '../../qccwallet/QccActiveWallet.dart';
import '../setting/AppTranslator.dart';
import 'trade/QccDexOrderBookTab.dart';
import 'util/QccKLineWidget.dart';

class QccOpenMarketPage extends StatefulWidget {
  String assetId;
  QccOpenMarketPage({super.key,required this.assetId});

  @override
  State<QccOpenMarketPage> createState() => _QccOpenMarketPageState();
}

class _QccOpenMarketPageState extends State<QccOpenMarketPage> {
  String _currentAssetId = "QCC";
  final String _quoteAssetId = "USDS"; // 统一计价资产

  // ✅ 真实 K 线数据与当前时间周期
  List<KlineCandle>? _realCandles;
  KlineInterval _currentInterval = KlineInterval.m15;

  @override
  void initState() {
    super.initState();
    _currentAssetId=widget.assetId;
    _loadMarketData(); // 初始化时自动拉取数据
  }

  // ✅ 核心方法：拉取真实行情并聚合成 K 线
  Future<void> _loadMarketData() async {
    // 1. 设置为 null，触发 K 线图的骨架屏等待动画
    setState(() {
      _realCandles = null;
    });

    // 2. 拉取双向兼容的真实底层数据
    final ticker = await QccMarketTickerService.getMarketTicker(_currentAssetId, _quoteAssetId);

    if (ticker != null && ticker.recentTrades.isNotEmpty && mounted) {
      // 3. 将离散的逐笔成交，通过分桶算法转为 OHLCV K 线数据
      final candles = KlineDataHelper.generateFromTrades(ticker.recentTrades, _currentInterval);

      setState(() {
        _realCandles = candles;
      });
    } else if (mounted) {
      // 4. 如果没有数据，传入空数组显示“暂无数据”状态
      setState(() {
        _realCandles = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Trans("现货交易"),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // 顶部：资产筛选、行情价格、K 线图
          _buildDexHeader(),
          // 底部：买卖盘口深度列表
          Expanded(
            child: QccDexOrderBookTab(baseAssetId: _currentAssetId),
          ),
        ],
      ),
    );
  }

  Widget _buildDexHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 第一行：当前交易对选择器
          const Trans("当前交易对", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 2),
          Row(
            children: [
              const Trans("余额:"),
              const SizedBox(width: 5),
              QccActiveWallet.onlyCoins(
                QccObj.activeWallet!.address,
                _currentAssetId,
                color: Colors.black87,
                fontSize: 18,
                onAssetChanged: (value) {
                  if (value != _currentAssetId) {
                    setState(() {
                      _currentAssetId = value;
                    });
                    // ✅ 资产切换后，重新拉取行情并生成新 K 线
                    _loadMarketData();
                  }
                },
              ),
              const Text(" / USDS", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),

          const SizedBox(height: 12),

          // 2. 第二行：行情指导价格组件
          QccPriceTickerWidget(
            baseAssetId: _currentAssetId,
            quoteAssetId: _quoteAssetId,
            onPriceFetched: (value){
              LogObj.log("获得选择当前价格$value");
              // 如果你需要把价格传给下方的 OrderBook 或买卖表单，可以在这里处理
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          // 3. 第三行：K 线图区域
          _buildMiniChart(),
        ],
      ),
    );
  }

  Widget _buildMiniChart() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: QccMiniKlineChart(
        assetId: _currentAssetId,
        quoteSymbol: _quoteAssetId,
        // ✅ 传入真实的聚合 K 线数据，而不是假数据
        candles: _realCandles,
        initialInterval: _currentInterval,
        chartHeight: 160,
        onIntervalChanged: (iv) {
          LogObj.log("切换周期至: ${iv.label}");
          if (iv != _currentInterval) {
            setState(() {
              _currentInterval = iv;
            });
            // ✅ 用户切换周期 (如 1m 切 1h) 时，重新聚合计算
            _loadMarketData();
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
// 数据聚合转换器
// ─────────────────────────────────────────

class KlineDataHelper {
  /// 将底层的交易明细 (Tick) 聚合成 K 线 (Candle) 数据
  static List<KlineCandle> generateFromTrades(
      List<DexTradeRecord> trades,
      KlineInterval interval,
      ) {
    if (trades.isEmpty) return [];

    // 1. 将交易记录按时间从早到晚排序 (升序)
    final sortedTrades = List<DexTradeRecord>.from(trades)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 2. 确定分桶的时间跨度 (毫秒)
    int intervalMs;
    switch (interval) {
      case KlineInterval.m1: intervalMs = 60 * 1000; break;
      case KlineInterval.m15: intervalMs = 15 * 60 * 1000; break;
      case KlineInterval.h1: intervalMs = 60 * 60 * 1000; break;
      case KlineInterval.d1: intervalMs = 24 * 60 * 60 * 1000; break;
    }

    List<KlineCandle> candles = [];
    int currentBucket = -1;

    double open = 0, high = 0, low = 0, close = 0, volume = 0;

    for (var trade in sortedTrades) {
      // 计算这笔交易属于哪一个时间桶 (向下取整到最近的周期边界)
      int bucket = trade.timestamp - (trade.timestamp % intervalMs);

      if (currentBucket == -1) {
        // 第一笔数据，初始化第一个 K 线
        currentBucket = bucket;
        open = high = low = close = trade.price;
        volume = trade.amount;
      } else if (bucket == currentBucket) {
        // 还在同一个时间桶内，更新最高价、最低价、收盘价和成交量
        high = max(high, trade.price);
        low = min(low, trade.price);
        close = trade.price; // 最后一笔就是最新的收盘价
        volume += trade.amount;
      } else {
        // 进入了新的时间桶，把上一根 K 线保存起来
        candles.add(KlineCandle(
          time: DateTime.fromMillisecondsSinceEpoch(currentBucket),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ));

        // 开启新的一根 K 线
        currentBucket = bucket;
        open = high = low = close = trade.price;
        volume = trade.amount;
      }
    }

    // 循环结束，把最后一根还没有被触发保存的 K 线加进去
    if (currentBucket != -1) {
      candles.add(KlineCandle(
        time: DateTime.fromMillisecondsSinceEpoch(currentBucket),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ));
    }

    return candles;
  }
}