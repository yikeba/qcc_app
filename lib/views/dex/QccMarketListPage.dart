import 'package:flutter/material.dart';

import '../setting/AppTranslator.dart';
import 'QccOpenDataManager.dart';
import 'QccOpenMarketPage.dart';

class QccMarketListPage extends StatefulWidget {
  const QccMarketListPage({super.key});

  @override
  State<QccMarketListPage> createState() => _QccMarketListPageState();
}

class _QccMarketListPageState extends State<QccMarketListPage> {
  List<QccTicker> _tickerList = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _tickerList = QccOpenDataManager.getMarketTickers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QCC 实时行情")),
      // ✅ 3. 动态监听器：数据中心每同步到一个订单，这里就会刷新
      body: ValueListenableBuilder<int>(
        valueListenable: QccOpenDataManager.marketUpdateNotifier,
        builder: (context, version, _) {
          final tickers = QccOpenDataManager.getMarketTickers();

          if (tickers.isEmpty) {
            return _buildSkeleton(); // 数据还没回来时，显示骨架屏
          }

          return ListView.builder(
            itemCount: tickers.length,
            itemBuilder: (context, index) {
              final ticker = tickers[index];
              // ✅ 这里你的排序逻辑（QCC 第一）依然生效
              return _buildTickerItem(ticker);
            },
          );
        },
      ),
    );
  }

  // ✅ 4. 骨架屏：在动态加载出第一个对价前，给用户视觉反馈
  Widget _buildSkeleton() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        leading: CircleAvatar(backgroundColor: Colors.grey.shade200),
        title: Container(height: 12, width: 60, color: Colors.grey.shade200),
        subtitle: Container(height: 10, width: 100, color: Colors.grey.shade100),
      ),
    );
  }


  Widget _buildTickerItem(QccTicker ticker) {
    bool isQcc = ticker.assetId.toUpperCase() == "QCC";

    // ✅ 1. 字符长度控制：不超过 6 个字符
    String displayAssetId = ticker.assetId.length > 6
        ? "${ticker.assetId.substring(0, 6)}.."
        : ticker.assetId;

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) =>
            QccOpenMarketPage(assetId: ticker.assetId))); // 修正为 targetAssetId
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isQcc ? Colors.blue.withOpacity(0.03) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2)
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              if (isQcc)
                Container(
                  width: 4,
                  height: 60,
                  color: Colors.blue,
                ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      // ✅ 2. 调高 flex 占比 (从 2 提升至 2.5)，给左侧更多宽度
                      Expanded(
                        flex: 25,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ✅ 3. 使用 Flexible 保护 Text，防止它挤压右侧组件
                                Flexible(
                                  child: Text(
                                    displayAssetId,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text("/${ticker.quoteAsset}", style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                const SizedBox(width: 4),
                                // 标签显示
                                if (isQcc) _buildMainBadge() else _buildLabelBadge(),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text("Vol: ${ticker.volume.toStringAsFixed(2)}",
                                style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade300)),
                          ],
                        ),
                      ),

                      // B. 右侧：报价区域保持不变，但 flex 微调
                      Expanded(
                        flex: 30,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _priceColumn("卖出价", ticker.bestSell, Colors.redAccent),
                            const SizedBox(width: 18),
                            _priceColumn("买入价", ticker.bestBuy, Colors.green),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ✅ 辅助组件：价格展示列
  Widget _priceColumn(String label, double price, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Trans(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          price == 0 ? "--" : "\$${price.toStringAsFixed(4)}",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  // ✅ QCC 专属主币角标
  Widget _buildMainBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.blue, Colors.lightBlueAccent]),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text("MAIN", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }


  // ✅ QCC 专属主币角标
  Widget _buildLabelBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.yellow, Colors.red]),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Trans("现货", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }
}