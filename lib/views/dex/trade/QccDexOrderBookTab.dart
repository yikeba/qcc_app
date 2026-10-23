import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/procotol/QccMatchLogic.dart';
import 'package:qcc_flutter/views/dex/trade/QccDexEngine.dart';
import 'dart:async';
import '../../../utile/Tools.dart';
import '../../setting/AppTranslator.dart';
import '../QccOpenDataManager.dart';
import '../win/QccWinTransactionPage.dart';
import 'QccOrderBookWidget.dart';


class QccDexOrderBookTab extends StatefulWidget {
  final String baseAssetId;

  const QccDexOrderBookTab({super.key, required this.baseAssetId});

  @override
  State<QccDexOrderBookTab> createState() => _QccDexOrderBookTabState();
}

class _QccDexOrderBookTabState extends State<QccDexOrderBookTab> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAndProcessData();
  }

  @override
  void didUpdateWidget(covariant QccDexOrderBookTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当父组件切换资产 (比如从 QCC 换到 MCZX) 时，触发重新拉取
    if (oldWidget.baseAssetId != widget.baseAssetId) {
      setState(() {});
      _fetchAndProcessData(); // ✅ 确保切换资产后立即刷新数据
    }
  }

  // ✅ 核心：拉取数据并喂给撮合引擎
  Future<void> _fetchAndProcessData() async {
    setState(() => _isLoading = true);

    // 1. 从网络或本地缓存获取所有活跃的 Open 交易
    await QccOpenDataManager.syncFromNetwork();
    final allOrders = QccOpenDataManager.getOrdersByType(QccMatchType.dex);

    LogObj.log("读取现有交易单数量:${allOrders.length}");


    // 2. 喂给 DEX 引擎进行清洗、分类(买/卖)和同价位合并
    QccDexEngine().processRawOrders(allOrders);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 从引擎获取当前资产的深度数据
    final depthData = QccDexEngine().getDepth(widget.baseAssetId);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      // clipBehavior 确保底部的按钮不会超出圆角
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          // 1. 顶部盘口列表 (占据剩余空间)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchAndProcessData,
              child: _isLoading && depthData.asks.isEmpty && depthData.bids.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // 引入专业双栏盘口 Widget
                  QccOrderBookWidget(
                    baseAsset: widget.baseAssetId,
                    depthLimit: 15, // 显示 15 档买卖盘
                  ),
                ],
              ),
            ),
          ),

          // 2. 底部快捷买卖操作区
          const Divider(height: 1, color: Color(0xFFEEEEEE)), // 分割线
          _buildBottomActionPanel(depthData),
          SizedBox(height: 10,),
        ],
      ),
    );
  }

  // ✅ 底部快捷买卖面板
  Widget _buildBottomActionPanel(DexDepthData depthData) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          // 🟢 快捷买入按钮
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () => _handleQuickTrade(isBuy: true, depthData: depthData),
              child: const Trans("买入", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 15),
          // 🔴 快捷卖出按钮
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () => _handleQuickTrade(isBuy: false, depthData: depthData),
              child: const Trans("卖出", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 核心处理逻辑：寻找最优挂单并跳转
  void _handleQuickTrade({required bool isBuy, required DexDepthData depthData}) {
    List<Map<String, dynamic>> targetOrders = [];
    String actionName = isBuy ? "买入" : "卖出";

    if (isBuy) {
      // 想买入 -> 吃掉最便宜的卖单 (卖1)
      if (depthData.asks.isNotEmpty) {
        targetOrders = depthData.asks.first.rawOrders;
      }
    } else {
      // 想卖出 -> 吃掉出价最高的买单 (买1)
      if (depthData.bids.isNotEmpty) {
        targetOrders = depthData.bids.first.rawOrders;
      }
    }

    // 1. 判空拦截
    if (targetOrders.isEmpty) {
      Tools.showToast(context, "当前暂无适合的对手盘，请稍后再试");
      return;
    }

    // 2. 取出最优价位下的第一笔原始订单 (FIFO)
    final targetOrder = targetOrders.first;
    final targetHash = targetOrder["id"];
    LogObj.log("用户点击匹配hash $targetOrder");
    LogObj.log("用户点击 $actionName, 匹配到最优 Hash: $targetHash");

    // 3. 携带 Hash 跳转到 Win 碰撞页面
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => QccWinTransactionPage(initialHash: targetHash),
        )
    ).then((_) {
      // 从 Win 页返回后立即用本地扣减重算盘口，不必等下一次手动下拉刷新
      if (mounted) {
        QccDexEngine().processRawOrders(QccOpenDataManager.getOrdersByType(QccMatchType.dex));
        setState(() {});
      }
    });
  }
}