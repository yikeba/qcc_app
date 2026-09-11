import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';
import '../QccOpenDataManager.dart';

class QccOrderWinDetailWidget extends StatelessWidget {
  final Map<String, dynamic> order;

  const QccOrderWinDetailWidget({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    // 挂单核心数据
    final String openAssetId = order['assetId'] ?? "";       // 锁定的资产 (如: 买入时是 USD, 卖出时是 QCC)
    final Map<String, dynamic> matchLogic = order['matchLogic'] ?? {};
    final String targetAssetId = matchLogic['pairAssetId'] ?? ""; // 目标资产
    final double rate = (matchLogic['rate'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Trans("成交对账明细"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: QccOpenDataManager.getWinHashTx(order["id"]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }

          final List<dynamic> winList = snapshot.data ?? [];

          // ======================== 核心状态重现逻辑 ========================

          // 1. 原始挂单锁定量 (人类金额)
          double originalLockedHuman = QccAssetService().getHumanAmountNum(openAssetId, order['amount']);

          double totalSpentHuman = 0.0;    // 累计消耗的锁定资产
          double totalObtainedHuman = 0.0; // 累计获得的目标资产

          for (var win in winList) {
            String winAssetId = win['assetId'];
            double winAmountHuman = QccAssetService().getHumanAmountNum(winAssetId, win['amount']);

            if (winAssetId.toUpperCase() == openAssetId.toUpperCase()) {
              // 情况 A：Win 返回的是锁定资产（通常是卖出单，消耗 QCC 得到 USD）
              double spent = winAmountHuman;
              totalSpentHuman += spent;
              totalObtainedHuman += (spent * rate);
            } else {
              // 情况 B：Win 返回的是目标资产（如你日志所示：买入单，获得 QCC）
              double obtained = winAmountHuman;
              totalObtainedHuman += obtained;
              // 反推消耗了多少锁定资产：消耗 = 获得 / 汇率
              totalSpentHuman += (rate > 0 ? obtained / rate : 0);
            }
          }

          // 2. 实时库存重现：剩余 = 原始锁定 - 累计消耗
          double currentInventory = originalLockedHuman - totalSpentHuman;
          // 防止浮点数精度抖动导致极小的负数显示
          if (currentInventory < 0.00000001) currentInventory = 0;

          // 3. 计算整体进度
          int progress = originalLockedHuman > 0
              ? ((totalSpentHuman / originalLockedHuman) * 100).toInt()
              : 0;

          return CustomScrollView(
            slivers: [
              // 顶部的对账看板
              SliverToBoxAdapter(
                child: _buildAccountCard(
                    originalLockedHuman,
                    totalSpentHuman,
                    currentInventory,
                    totalObtainedHuman,
                    openAssetId,
                    targetAssetId,
                    progress
                ),
              ),

              // 碰撞流水明细
              if (winList.isEmpty)
                SliverFillRemaining(child: _buildEmpty())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildWinDetailCard(
                          winList[index],
                          openAssetId,
                          targetAssetId,
                          rate
                      ),
                      childCount: winList.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          );
        },
      ),
    );
  }

  // ✅ 资产对账看板 (核心数据展示)
  Widget _buildAccountCard(double ori, double spent, double rem, double obt, String lid, String tid, int progress) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem("委托总量", "${ori.toStringAsFixed(2)} $lid", Colors.white70),
              _statItem("累计获得", "${obt.toStringAsFixed(4)} $tid", Colors.greenAccent),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: Colors.white10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem("累计已消耗", "${spent.toStringAsFixed(4)} $lid", Colors.white),
              _statItem("实时库存", "${rem.toStringAsFixed(4)} $lid", Colors.blueAccent, isHighlight: true),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: progress / 100,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(progress >= 100 ? Colors.green : Colors.blueAccent),
          )
        ],
      ),
    );
  }

  // ✅ 单笔明细卡片
  Widget _buildWinDetailCard(Map<String, dynamic> win, String openId, String targetId, double rate) {
    String winAssetId = win["assetId"];
    double winAmtHuman = QccAssetService().getHumanAmountNum(winAssetId, win['amount']);

    double spent;
    double obtained;

    if (winAssetId.toUpperCase() == openId.toUpperCase()) {
      spent = winAmtHuman;
      obtained = spent * rate;
    } else {
      obtained = winAmtHuman;
      spent = rate > 0 ? obtained / rate : 0;
    }

    String time = DateFormat('MM-dd HH:mm:ss').format(
        DateTime.fromMillisecondsSinceEpoch(win['timestamp'] ?? 0)
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("支出: ${spent.toStringAsFixed(4)} $openId", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.add_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    "${obtained.toStringAsFixed(4)} $targetId",
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Text("Hash: ${win['id'].toString().substring(0, 6)}...", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(
            color: color,
            fontSize: isHighlight ? 16 : 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace'
        )),
      ],
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Trans("暂无碰撞成交记录", style: TextStyle(color: Colors.grey)));
  }
}