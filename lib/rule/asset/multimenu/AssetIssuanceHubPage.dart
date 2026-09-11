import 'package:flutter/material.dart';
import '../../../../views/setting/AppTranslator.dart';
import 'MultiSigBurnHubPage.dart';
import 'MultiSigFreezeHubPage.dart';
import 'MultiSigIssuanceHubPage.dart';
import 'MultiSigMintHubPage.dart';
import 'SingleSigAssetHubPage.dart';

/// 【再次重构，按你的最新要求】"由于多签每个都对应提案，追随，那么我们
/// 把多签菜单继续细化"——原来"多签增发/多签冻结/多签销毁"这三个入口全部
/// 指向同一个 MultiSigAssetManageHubPage（增发+冻结+销毁+冻结状态混在
/// 一个列表里，卡片描述文字甚至都是一模一样的三段复制粘贴），现在拆成
/// 三组完全独立、结构对称的二级菜单，每组都是"提案/追随/中心"三项：
/// - MultiSigMintHubPage：多签增发提案 / 追随增发签署 / 多签增发状态中心
/// - MultiSigFreezeHubPage：多签冻结提案 / 追随冻结签署 / 多签冻结状态中心
/// - MultiSigBurnHubPage：多签销毁提案 / 追随销毁签署 / 多签销毁状态中心
/// 结构完全清晰对称，追随签署时不会在一个大杂烩列表里选错功能。
/// MultiSigAssetManageHubPage 不再从这里链接（该文件本身没有删除，只是
/// 不再是唯一入口——里面的功能已经按类别拆到上面三个新页面里去了）。
///
/// 五个子菜单页：
/// - SingleSigAssetHubPage：单签管理（发行/增发/冻结/销毁/冻结状态）
/// - MultiSigIssuanceHubPage：多签发行（提案 + 跟签，只处理发行）
/// - MultiSigMintHubPage / MultiSigFreezeHubPage / MultiSigBurnHubPage：
///   多签增发 / 多签冻结 / 多签销毁，各自独立的提案/追随/中心三件套
class AssetIssuanceHubPage extends StatelessWidget {
  const AssetIssuanceHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("代币资产发行管理")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        children: [
          _buildEntryCard(
            context,
            "单签管理",
            "发行、增发、冻结、销毁、冻结状态——单签地址直接操作，即时生效",
            Icons.person_outline,
            Colors.blue,
            const SingleSigAssetHubPage(),
          ),
          _buildEntryCard(
            context,
            "多签发行",
            "发起资产发行提案，并在这里追随签署，只处理发行，不含增发",
            Icons.account_tree_outlined,
            Colors.orange,
            const MultiSigIssuanceHubPage(),
          ),
          _buildEntryCard(
            context,
            "多签增发",
            "增发提案、追随签署、增发状态中心",
            Icons.add_chart_outlined,
            Colors.deepPurple,
            const MultiSigMintHubPage(),
          ),
          _buildEntryCard(
            context,
            "多签冻结",
            "冻结/解冻提案、追随签署、冻结状态中心",
            Icons.icecream_outlined,
            Colors.black87,
            const MultiSigFreezeHubPage(),
          ),
          _buildEntryCard(
            context,
            "多签销毁",
            "销毁提案、追随签署、销毁状态中心",
            Icons.delete_forever_outlined,
            Colors.teal,
            const MultiSigBurnHubPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
      BuildContext context,
      String title,
      String desc,
      IconData icon,
      Color color,
      Widget target,
      ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Trans(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Trans(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}