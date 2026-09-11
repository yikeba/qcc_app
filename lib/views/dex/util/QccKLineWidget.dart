import 'dart:math';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────

/// 单根 K 线数据
class KlineCandle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const KlineCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  bool get isBullish => close >= open;
}

/// 时间周期枚举
enum KlineInterval {
  m1('1m'),
  m15('15m'),
  h1('1h'),
  d1('1d');

  final String label;
  const KlineInterval(this.label);
}

// ─────────────────────────────────────────
// 主 Widget
// ─────────────────────────────────────────

/// DEX K线图组件
///
/// 用法：
/// ```dart
/// QccMiniKlineChart(
///   assetId: 'QCC',
///   candles: myCandles,           // 可选，传 null 则显示骨架占位
///   quoteSymbol: 'USD',
///   onIntervalChanged: (iv) { ... },
/// )
/// ```
class QccMiniKlineChart extends StatefulWidget {
  final String assetId;
  final String quoteSymbol;
  final List<KlineCandle>? candles;
  final KlineInterval initialInterval;
  final ValueChanged<KlineInterval>? onIntervalChanged;


  // 优化配色方案
  static const Color _bullColor = Color(0xFF26A69A); // 霓虹绿
  static const Color _bearColor = Color(0xFFEF5350); // 霓虹红
  static const Color _volColor = Color(0x1A90A4AE);  // 成交量背景（10% 不透明）

  /// 图表高度（不含时间选择栏）
  final double chartHeight;

  const QccMiniKlineChart({
    super.key,
    required this.assetId,
    this.quoteSymbol = 'USDS',
    this.candles,
    this.initialInterval = KlineInterval.m15,
    this.onIntervalChanged,
    this.chartHeight = 140,
  });

  @override
  State<QccMiniKlineChart> createState() => _QccMiniKlineChartState();
}

class _QccMiniKlineChartState extends State<QccMiniKlineChart>
    with SingleTickerProviderStateMixin {
  late KlineInterval _interval;

  // 长按十字线
  Offset? _crosshair;

  // 动画控制器（入场渐显）
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _interval = widget.initialInterval;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(QccMiniKlineChart old) {
    super.didUpdateWidget(old);
    // 数据刷新时重播入场动画
    if (old.candles != widget.candles) {
      _animCtrl.forward(from: 0);
      _crosshair = null;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── 构建 ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIntervalBar(),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.chartHeight,
          child: widget.candles == null || widget.candles!.isEmpty
              ? _buildSkeleton()
              : _buildChart(),
        ),
        if (_crosshair != null && widget.candles != null)
          _buildCrosshairInfo(),
      ],
    );
  }

  /// 时间周期选择栏
  Widget _buildIntervalBar() {
    return Row(
      children: KlineInterval.values.map((iv) {
        final selected = iv == _interval;
        return GestureDetector(
          onTap: () {
            if (selected) return;
            setState(() => _interval = iv);
            widget.onIntervalChanged?.call(iv);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1A73E8).withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              iv.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? const Color(0xFF1A73E8)
                    : Colors.blueGrey.shade400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 骨架占位图（数据加载中）
  Widget _buildSkeleton() {
    return CustomPaint(
      painter: _SkeletonPainter(),
      child: const SizedBox.expand(),
    );
  }

  /// 真实 K 线图
  Widget _buildChart() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: GestureDetector(
        onLongPressStart: (d) =>
            setState(() => _crosshair = d.localPosition),
        onLongPressMoveUpdate: (d) =>
            setState(() => _crosshair = d.localPosition),
        onLongPressEnd: (_) => setState(() => _crosshair = null),
        child: CustomPaint(
          painter: _KlinePainter(
            candles: widget.candles!,
            crosshair: _crosshair,
            progress: _fadeAnim.value,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// 十字线悬停时的信息条
  Widget _buildCrosshairInfo() {
    if (_crosshair == null || widget.candles == null) return const SizedBox();
    // 根据 x 坐标映射到对应 candle（简单线性映射）
    final candles = widget.candles!;
    final ratio = (_crosshair!.dx).clamp(0.0, 1000.0) / 1000.0;
    final idx =
    (ratio * (candles.length - 1)).round().clamp(0, candles.length - 1);
    final c = candles[idx];
    final color = c.isBullish ? const Color(0xFF0ECB81) : const Color(0xFFF6465D);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _infoChip('O', c.open, color),
          _infoChip('H', c.high, color),
          _infoChip('L', c.low, color),
          _infoChip('C', c.close, color),
          _infoChip('V', c.volume, Colors.blueGrey.shade300, prefix: ''),
        ],
      ),
    );
  }

  Widget _infoChip(String label, double value, Color color,
      {String prefix = '\$'}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 10),
        children: [
          TextSpan(
              text: '$label:',
              style: TextStyle(color: Colors.blueGrey.shade300)),
          TextSpan(
            text:
            ' $prefix${value >= 1000 ? value.toStringAsFixed(0) : value.toStringAsFixed(4)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// CustomPainter — K 线绘制
// ─────────────────────────────────────────

class _KlinePainter extends CustomPainter {
  final List<KlineCandle> candles;
  final Offset? crosshair;
  final double progress; // 0~1，入场动画进度

  static const double _candleSpacing = 2;
  static const double _wickWidth = 1;
  static const Color _bullColor = Color(0xFF0ECB81); // 涨
  static const Color _bearColor = Color(0xFFF6465D); // 跌
  static const Color _gridColor = Color(0xFFECEFF1);
  static const Color _crosshairColor = Color(0xFF90A4AE);

  _KlinePainter({
    required this.candles,
    required this.crosshair,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    // ── 数据范围 ──────────────────────────
    double minPrice = candles.map((c) => c.low).reduce(min);
    double maxPrice = candles.map((c) => c.high).reduce(max);
    final priceRange = maxPrice - minPrice;
    // 留 10% 上下 padding
    minPrice -= priceRange * 0.1;
    maxPrice += priceRange * 0.1;
    final range = maxPrice - minPrice;

    double toY(double price) =>
        size.height - (price - minPrice) / range * size.height;

    // ── 蜡烛宽度计算 ─────────────────────
    final totalW = size.width;
    final n = candles.length;
    final candleW =
    ((totalW - _candleSpacing * (n - 1)) / n).clamp(2.0, 16.0);

    // ── 背景网格（3 条横线）──────────────
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 3; i++) {
      final y = size.height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── 绘制蜡烛 ─────────────────────────
    final bullPaint = Paint()..color = _bullColor;
    final bearPaint = Paint()..color = _bearColor;
    final bullWickPaint = Paint()
      ..color = _bullColor
      ..strokeWidth = _wickWidth;
    final bearWickPaint = Paint()
      ..color = _bearColor
      ..strokeWidth = _wickWidth;

    // 入场动画：从右侧逐步显示
    final visibleCount = (n * progress).round().clamp(1, n);
    final startIdx = n - visibleCount;

    for (int i = startIdx; i < n; i++) {
      final c = candles[i];
      final isBull = c.isBullish;
      final x = i * (candleW + _candleSpacing);
      final centerX = x + candleW / 2;

      final bodyTop = toY(max(c.open, c.close));
      final bodyBottom = toY(min(c.open, c.close));
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, size.height);

      final wickPaint = isBull ? bullWickPaint : bearWickPaint;
      final bodyPaint = isBull ? bullPaint : bearPaint;

      // 影线
      canvas.drawLine(
        Offset(centerX, toY(c.high)),
        Offset(centerX, toY(c.low)),
        wickPaint,
      );
      // 实体
      canvas.drawRect(
        Rect.fromLTWH(x, bodyTop, candleW, bodyH),
        bodyPaint,
      );
    }

    // ── 十字线 ───────────────────────────
    if (crosshair != null) {
      final chPaint = Paint()
        ..color = _crosshairColor
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      // 映射到最近蜡烛中心
      final idx =
      (crosshair!.dx / (candleW + _candleSpacing)).round().clamp(0, n - 1);
      final snapX = idx * (candleW + _candleSpacing) + candleW / 2;

      canvas.drawLine(
          Offset(snapX, 0), Offset(snapX, size.height), chPaint);
      canvas.drawLine(Offset(0, crosshair!.dy),
          Offset(size.width, crosshair!.dy), chPaint);

      // 十字线价格标签
      final price = minPrice +
          (1 - crosshair!.dy / size.height) * range;
      _drawPriceLabel(canvas, size, crosshair!.dy, price);
    }
  }

  void _drawPriceLabel(Canvas canvas, Size size, double y, double price) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: price.toStringAsFixed(price >= 100 ? 2 : 4),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rectW = textPainter.width + 8;
    final rectH = textPainter.height + 4;
    final rx = size.width - rectW;
    final ry = (y - rectH / 2).clamp(0.0, size.height - rectH);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(rx, ry, rectW, rectH), const Radius.circular(3)),
      Paint()..color = _crosshairColor,
    );
    textPainter.paint(canvas, Offset(rx + 4, ry + 2));
  }

  @override
  bool shouldRepaint(_KlinePainter old) =>
      old.candles != candles ||
          old.crosshair != crosshair ||
          old.progress != progress;
}

// ─────────────────────────────────────────
// 骨架占位 Painter
// ─────────────────────────────────────────

class _SkeletonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFECEFF1)
      ..style = PaintingStyle.fill;

    final rng = Random(42);
    const n = 30;
    final w = (size.width - 2.0 * (n - 1)) / n;
    for (int i = 0; i < n; i++) {
      final h = 20.0 + rng.nextDouble() * (size.height - 30);
      final x = i * (w + 2);
      final y = size.height - h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w.clamp(2, 12), h),
            const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => false;
}




class KlineMockData {
  static List<KlineCandle> generate({
    int count = 60,
    double startPrice = 1.5,
  }) {
    final rng = Random();
    final List<KlineCandle> result = [];
    double currentPrice = startPrice;

    // 模拟趋势因子 (让价格有方向感)
    double trend = (rng.nextDouble() - 0.5) * 0.01;

    for (int i = 0; i < count; i++) {
      // 随机行走逻辑
      double volatility = 0.02 * currentPrice;
      double open = currentPrice;

      // 计算收盘价：趋势 + 随机波动
      double change = (rng.nextDouble() - 0.48 + trend) * volatility;
      double close = open + change;

      // 影线逻辑：随机在实体外延展
      double high = max(open, close) + rng.nextDouble() * 0.005 * currentPrice;
      double low = min(open, close) - rng.nextDouble() * 0.005 * currentPrice;
      double volume = 5000 + rng.nextDouble() * 20000;

      result.add(KlineCandle(
        time: DateTime.now().subtract(Duration(minutes: (count - i) * 15)),
        open: open,
        high: high,
        low: low.clamp(0.0001, double.infinity),
        close: close,
        volume: volume,
      ));

      currentPrice = close;
      // 概率性改变趋势
      if (rng.nextDouble() > 0.9) trend = (rng.nextDouble() - 0.5) * 0.01;
    }
    return result;
  }
}