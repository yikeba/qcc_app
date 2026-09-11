import 'package:flutter/material.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../txdata/Multi/QccFollowTransactionPage.dart';
import '../AssetStatusCenterWidget.dart';
import '../multiburn/MultiSigAssetBurnWidget.dart';
import '../freezeasset/ multi/MultiSigAssetFreezeWidget.dart';
import '../coin/AsseIdRule/MultiSigAssetMintWidget.dart';
import 'MultiSigStableCoinFollowSignWidget.dart';
import 'MultiSigStableCoinIssueWidget.dart';

class StablecoinHubPage extends StatelessWidget {
  const StablecoinHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 浅灰背景，更显商务
      appBar: AppBar(
        title: Trans("稳定币发行与管理"),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15,5,15,10),
        children: [
          // --- 1. 顶部高安全说明栏目 ---
          _buildSecurityNotice(),
          const SizedBox(height: 5),
          // --- 2. 功能操作区 ---
          _buildSectionTitle("管理入口 (Management)"),
          _buildHubCard(
              context,
              "发行稳定币",
              "稳定币需要多签发起，满足高安全度金融资产监管要求",
              Icons.monetization_on_outlined,
              Colors.orange,
              const MultiSigStableCoinIssueWidget()
          ),
          _buildHubCard(
              context,
              "增发铸造提案稳定币",
              "现有资产进行增加发行",
              Icons.account_tree_outlined,
              Colors.redAccent,
              const MultiSigAssetMintWidget()
          ),
          _buildHubCard(
              context,
              "追随签署",
              "粘贴 TxHash 参与他人发起的发行提案签署，完成多签确认",
              Icons.draw_outlined,
              Colors.purple,
              const MultiSigStableCoinFollowSignWidget()
          ),

          _buildHubCard(
              context,
              "冻结提案地址",
              "对违规/稳定币资产地址进行冻结",
              Icons.invert_colors_on_outlined,
              Colors.lightBlueAccent,
              const MultiSigAssetFreezeWidget()
          ),
          _buildHubCard(
              context,
              "稳定币赎回/销毁",
              "对资产持有地址进行销毁",
              Icons.delete_forever_outlined,
              Colors.lightBlueAccent,
              const MultiSigAssetBurnWidget()
          ),
          _buildHubCard(
              context,
              "销毁追随签署",
              "签署销毁稳定币订单",
              Icons.remove_circle_outline,
              Colors.lightBlueAccent,
              const QccFollowTransactionPage()
          ),

          const SizedBox(height: 10),
          // --- 3. 状态中心 ---
          _buildSectionTitle("资产监控 (Monitor)"),
          _buildHubCard(
              context,
              "稳定币中心",
              "申请铸币，稳定币生态...",
              Icons.analytics_outlined,
              Colors.teal,
              const AssetStatusCenterWidget()
          ),
        ],
      ),
    );
  }

  /// 顶部高安全说明组件
  Widget _buildSecurityNotice() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade800, Colors.blueGrey.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Colors.amber, size: 26),
              const SizedBox(width: 10),
              Trans("高安全资产说明",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          Trans(
            "稳定币为Qcc 公链高安全度资产。其规则为系统“创世规则”，不可更改。要求如下：",
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            maxLines: 2,
          ),
          const SizedBox(height: 5),
          _buildNoticeItem(Icons.lock_clock, "必须由多签地址发布与管理"),
          _buildNoticeItem(Icons.attach_money, "需质押 10 万 QCC 原生代币"),
          _buildNoticeItem(Icons.gas_meter, "需支付 1 万 QCC Gas 费用"),
          _buildNoticeItem(Icons.label_important, "公链将自动标记资产类型为: stablecoin"),
        ],
      ),
    );
  }

  Widget _buildNoticeItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber.withOpacity(0.8), size: 16),
          const SizedBox(width: 8),
          Expanded(child: Trans(text, style: const TextStyle(color: Colors.white, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Trans(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildHubCard(BuildContext context, String title, String desc, IconData icon, Color color, Widget target) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color)
        ),
        title: Trans(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Trans(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
      ),
    );
  }
}