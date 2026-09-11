import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/dex/trade/QccDexEngine.dart';
import '../../setting/AppTranslator.dart';

class QccOrderBookWidget extends StatelessWidget {
  final String baseAsset;
  final int depthLimit; // 显示几档，默认 10 档

  const QccOrderBookWidget({
    super.key,
    required this.baseAsset,
    this.depthLimit = 10,
  });

  @override
  Widget build(BuildContext context) {
    // 从全局引擎获取最新的深度数据
    final depthData = QccDexEngine().getDepth(baseAsset);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 盘口表头 (保持不变)
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Trans("买(数量)", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Trans("价格(USD)", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Trans("价格(USD)", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const Trans("卖(数量)", style: TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 双栏深度列表
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：买盘 (Bids) - 绿色
              Expanded(
                child: Column(
                  children: List.generate(depthLimit, (index) {
                    if (index >= depthData.bids.length) {
                      return _buildEmptyRow(index, isAsk: false);
                    }
                    final item = depthData.bids[index];
                    return _buildDepthRow(item, index, isAsk: false);
                  }),
                ),
              ),
              const SizedBox(width: 10),

              // 右侧：卖盘 (Asks) - 红色
              Expanded(
                child: Column(
                  children: List.generate(depthLimit, (index) {
                    if (index >= depthData.asks.length) {
                      return _buildEmptyRow(index, isAsk: true);
                    }
                    final item = depthData.asks[index];
                    return _buildDepthRow(item, index, isAsk: true);
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ 渲染单行深度 (增加了 index 参数)
  Widget _buildDepthRow(DepthItem item, int index, {required bool isAsk}) {
    Color priceColor = isAsk ? Colors.redAccent : Colors.green;
    String label = isAsk ? "卖${index + 1}" : "买${index + 1}";

    // 买卖双方的布局对称：
    // 买盘：[序号] [数量居左] [价格居右]
    // 卖盘：[价格居左] [数量居右] [序号]
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: isAsk
            ? [
          Text(item.price.toStringAsFixed(4), style: TextStyle(color: priceColor, fontWeight: FontWeight.bold, fontSize: 12)),
          Expanded(child: Text(item.amount.toStringAsFixed(2), style: const TextStyle(color: Colors.black87, fontSize: 12), textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          SizedBox(width: 26, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.right)),
        ]
            : [
          SizedBox(width: 26, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.left)),
          const SizedBox(width: 6),
          Expanded(child: Text(item.amount.toStringAsFixed(2), style: const TextStyle(color: Colors.black87, fontSize: 12), textAlign: TextAlign.left)),
          Text(item.price.toStringAsFixed(4), style: TextStyle(color: priceColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ✅ 空白占位行 (同步增加了 index 参数，保持队列整齐)
  Widget _buildEmptyRow(int index, {required bool isAsk}) {
    String label = isAsk ? "卖${index + 1}" : "买${index + 1}";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: isAsk
            ? [
          const Text("--", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const Expanded(child: Text("--", style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.right)),
          const SizedBox(width: 6),
          SizedBox(width: 26, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.right)),
        ]
            : [
          SizedBox(width: 26, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.left)),
          const SizedBox(width: 6),
          const Expanded(child: Text("--", style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.left)),
          const Text("--", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}