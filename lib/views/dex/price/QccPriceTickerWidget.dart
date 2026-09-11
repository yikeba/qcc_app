import 'dart:developer' as LogObj;

import 'package:flutter/material.dart';

import '../../setting/AppTranslator.dart';
import 'DexTradeRecord.dart';

class QccPriceTickerWidget extends StatefulWidget {
  final String baseAssetId;
  final String quoteAssetId;
  /// 当获取到推荐价格时的回调，父组件可以用它来自动填充输入框
  final Function(double recommendedPrice)? onPriceFetched;

  const QccPriceTickerWidget({
    super.key,
    required this.baseAssetId,
    this.quoteAssetId = "USDS",
    this.onPriceFetched,
  });

  @override
  State<QccPriceTickerWidget> createState() => _QccPriceTickerWidgetState();
}

class _QccPriceTickerWidgetState extends State<QccPriceTickerWidget> {
  bool _isLoading = true;
  DexMarketTicker? _ticker;

  @override
  void initState() {
    super.initState();
    _fetchTicker();
  }

  @override
  void didUpdateWidget(covariant QccPriceTickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当父组件切换了交易对时，重新触发加载
    if (oldWidget.baseAssetId != widget.baseAssetId || oldWidget.quoteAssetId != widget.quoteAssetId) {
      _fetchTicker();
    }
  }

  Future<void> _fetchTicker() async {
    setState(() => _isLoading = true);

    final ticker = await QccMarketTickerService.getMarketTicker(widget.baseAssetId, widget.quoteAssetId);
    LogObj.log("读取到assetid 参考价格:$ticker");
    if (mounted) {
      setState(() {
        _ticker = ticker;
        _isLoading = false;
      });
      // 如果拿到了有效数据，并通过回调通知父组件
      if (ticker != null && widget.onPriceFetched != null) {
        widget.onPriceFetched!(ticker.recommendedPrice);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 横向滚动条等待加载状态
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Trans("正在测算公允指导价...", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            // ✅ 修复：为进度条增加固定的宽度限制
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const SizedBox(
                width: 100, // 👈 增加定宽，解决 Infinity 报错
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Color(0xFFE3F2FD),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. 没有任何历史成交数据的冷启动状态
    if (_ticker == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Trans("暂无最新市场成交数据，请自主定价", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      );
    }

    // 3. 数据加载完毕的行情展示状态
    final bool isUp = _ticker!.change24h >= 0;
    final Color changeColor = isUp ? Colors.green : Colors.redAccent;
    final String sign = isUp ? "+" : "";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: changeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: changeColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.show_chart, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  const Trans("系统指导价", style: TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                ],
              ),
              // 涨跌幅标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: changeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  "$sign${_ticker!.change24h.toStringAsFixed(2)}%",
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _ticker!.recommendedPrice.toStringAsFixed(4),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: changeColor),
              ),
              const SizedBox(width: 4),
              Text(widget.quoteAssetId, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              Text("最新: ${_ticker!.latestPrice.toStringAsFixed(4)}", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }
}