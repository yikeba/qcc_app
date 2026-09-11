import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/dex/QccMarketListPage.dart';
import 'package:qcc_flutter/views/dex/QccOpenMarketPage.dart';
import 'package:qcc_flutter/views/dex/QccOrderListWidget.dart';
import 'package:qcc_flutter/views/dex/win/QccWinTransactionPage.dart';
import 'package:qcc_flutter/views/dex/other/QccAssetDividendPage.dart';
import 'package:qcc_flutter/views/dex/other/QccClaimDividendPage.dart';
import 'package:qcc_flutter/views/dex/price/MyDexOrdersWidget.dart';
import 'package:qcc_flutter/views/dex/trade/DexMatchWidget.dart';
import '../setting/AppTranslator.dart';
import 'QccCreateMatchWidget.dart';
import 'price/QccTradeCenterPage.dart'; // 您已有的发起 Widget

class QccMatchManagerPage extends StatelessWidget {
  const QccMatchManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Trans("QCC 现货交易中心"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. 交易发起区 (Open) ---
            _buildSectionTitle("发起新交易 (Open)"),
            _buildActionCard(
              context,
              title: "现货挂单交易",
              desc: "资产交易(DEX)，一键广播至公链。",
              icon: Icons.add_business_rounded,
              color: Colors.blueAccent,
              onTap: () => _navTo(context, "CreateOpen"),
            ),
            _buildActionCard(
              context,
              title: "分红交易(待测试)",
              desc: "资产方发布分红",
              icon: Icons.payments_rounded,
              color: Colors.pinkAccent,
              onTap: () => _navTo(context, "Dividend"),
            ),
            _buildActionCard(
              context,
              title: "空投/红包(待测试)",
              desc: "发布空投/红包交易",
              icon: Icons.real_estate_agent,
              color: Colors.purpleAccent,
              onTap: () => _navTo(context, "Dividend"),
            ),
            _buildActionCard(
              context,
              title: "我的交易",
              desc: "交易单/成交单据",
              icon: Icons.bookmark_border,
              color: Colors.cyan,
              onTap: () => _navTo(context, "MyTrade"),
            ),
            const SizedBox(height: 24),
            // --- 2. 动态参与区 (Win) ---
            _buildSectionTitle("业务参与 (Action)"),
            _buildActionCard(
              context,
              title: "领取分红/派息(待测试)",
              desc: "通过输入 OpenHash 领取分红。",
              icon: Icons.recommend_rounded,
              color: Colors.orangeAccent,
              onTap: () => _navTo(context, "WinAction"),
            ),
           /* _buildActionCard(
              context,
              title: "Hash交易 (分红/红包/空投领取)",
              desc: "通过输入 OpenHash 参与已存在的撮合交易，实时计算碰撞结果并结算资产。",
              icon: Icons.flash_on_rounded,
              color: Colors.orangeAccent,
              onTap: () => _navTo(context, "WinAction"),
            ),*/

            const SizedBox(height: 24),

          /*  // --- 3. 数据看板 (Query) ---
            _buildSectionTitle("市场数据 (Market)"),
            _buildActionCard(
              context,
              title: "现货市场交易",
              desc: "查看公链上正在进行的 Open 交易，通过索引服务器实时获取 Hash 状态。",
              icon: Icons.storefront,
              color: Colors.red, // 这里的颜色可以自定义
              onTap: () => _navTo(context, "MarketList"),
            ),*/
          ],
        ),
      ),
    );
  }

  // 复用您的 _buildSectionTitle 风格
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Trans(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  // 复用并优化您的卡片组件
  Widget _buildActionCard(BuildContext context, {required String title, required String desc, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Trans(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Trans(desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _navTo(BuildContext context, String path) {
    switch (path) {
      case "CreateOpen":
      // 跳转到您已有的 QccCreateMatchWidget
        //Navigator.push(context, MaterialPageRoute(builder: (context) => const QccCreateMatchWidget()));
        Navigator.push(context, MaterialPageRoute(builder: (context) => const DexMatchWidget()));

        break;
      case "WinAction":
        //Navigator.push(context, MaterialPageRoute(builder: (context) => const QccWinTransactionPage()));
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QccClaimDividendPage()));

        break;
      case "MyTrade" :
     //   Navigator.push(context, MaterialPageRoute(builder: (context) => const MyDexOrdersWidget()));
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QccTradeCenterPage()));
        break;
      case "MarketList":
      // 跳转到列表页面 (需新建)
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QccMarketListPage()));

        break;
      case "Dividend":
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QccAssetDividendPage()));

        break;

    }
  }
}