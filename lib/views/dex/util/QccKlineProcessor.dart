import 'dart:math';
import 'QccKLineWidget.dart';
import '../../../procotol/QccMatchLogic.dart'; // 引入你的枚举和逻辑类

class QccKlineProcessor {
  /// 将离散的交易列表转换为 K 线图数据
  ///
  /// [rawTxs] 公链接口返回并解析后的交易列表 (需包含 timestamp, amount, matchLogic)
  /// [interval] K 线的时间周期 (如 1m, 15m)
  /// [precision] 资产精度，默认为 10^9
  static List<KlineCandle> processToCandles({
    required List<Map<String, dynamic>> rawTxs,
    required KlineInterval interval,
    double precision = 1000000000.0,
  }) {
    if (rawTxs.isEmpty) return [];

    // 1. 过滤并提取有效的 DEX 交易数据
    List<_TradePoint> trades = [];
    for (var tx in rawTxs) {
      final logicMap = tx['matchLogic'];
      if (logicMap == null) continue;

      final String rule = logicMap['rule'] ?? '';
      // 仅处理 DEX 类型的交易
      if (rule != 'dex' && rule != 'exchange') continue;

      final double rate = (logicMap['rate'] as num?)?.toDouble() ?? 0.0;
      final double volume = ((tx['amount'] as num?)?.toDouble() ?? 0.0) / precision;
      final int timestamp = tx['timestamp'] ?? 0;

      if (rate > 0 && timestamp > 0) {
        trades.add(_TradePoint(timestamp: timestamp, price: rate, volume: volume));
      }
    }

    if (trades.isEmpty) return [];

    // 2. 按时间升序排序（确保历史数据在前）
    trades.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 3. 确定时间周期 (毫秒)
    int intervalMs = _getIntervalMs(interval);

    // 4. 时间分桶 (Time Binning)
    Map<int, List<_TradePoint>> buckets = {};
    for (var t in trades) {
      // 计算该交易属于哪一个时间桶
      int bucketTime = (t.timestamp ~/ intervalMs) * intervalMs;
      buckets.putIfAbsent(bucketTime, () => []).add(t);
    }

    // 5. 计算 OHLC 并填补空档期
    List<KlineCandle> candles = [];
    var sortedBucketTimes = buckets.keys.toList()..sort();

    int firstTime = sortedBucketTimes.first;
    int lastTime = sortedBucketTimes.last;
    double lastClose = buckets[firstTime]!.first.price;

    // 遍历从第一个桶到最后一个桶的时间段
    for (int currentTime = firstTime; currentTime <= lastTime; currentTime += intervalMs) {
      final tradesInBucket = buckets[currentTime];

      if (tradesInBucket != null && tradesInBucket.isNotEmpty) {
        // 该时间段内有交易，计算真实的 OHLC
        double open = tradesInBucket.first.price;
        double close = tradesInBucket.last.price;
        double high = tradesInBucket.map((t) => t.price).reduce(max);
        double low = tradesInBucket.map((t) => t.price).reduce(min);
        double volume = tradesInBucket.fold(0.0, (sum, t) => sum + t.volume);

        candles.add(KlineCandle(
          time: DateTime.fromMillisecondsSinceEpoch(currentTime),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ));
        lastClose = close; // 记录收盘价供下一个空档期使用
      } else {
        // 该时间段内【无任何交易】，走势为一条直线，交易量为 0
        candles.add(KlineCandle(
          time: DateTime.fromMillisecondsSinceEpoch(currentTime),
          open: lastClose,
          high: lastClose,
          low: lastClose,
          close: lastClose,
          volume: 0.0,
        ));
      }
    }

    return candles;
  }

  // 辅助方法：获取毫秒数
  static int _getIntervalMs(KlineInterval iv) {
    switch (iv) {
      case KlineInterval.m1: return 60 * 1000;
      case KlineInterval.m15: return 15 * 60 * 1000;
      case KlineInterval.h1: return 60 * 60 * 1000;
      case KlineInterval.d1: return 24 * 60 * 60 * 1000;
    }
  }
}

/// 内部私有类：用于暂存洗好的交易点数据
class _TradePoint {
  final int timestamp;
  final double price;
  final double volume;

  _TradePoint({required this.timestamp, required this.price, required this.volume});
}