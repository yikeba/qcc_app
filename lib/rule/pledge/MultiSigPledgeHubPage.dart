import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'MultiSigPledgeProposalWidget.dart';
import 'MultiSigPledgeFollowSignWidget.dart';

/// 多签质押——独立入口页，对应你的要求"多签区分一下"：多签质押和单签
/// 质押（QccPledgeHubPage）在 QccPledgeRuleListPage 里是并列的两个顶层
/// 入口，多签内部再拆"质押提案"和"追随质押签署"两个子页面，和白名单的
/// 多签结构（WhitelistHubPage 里那两张多签卡片）保持同样的组织方式。
class MultiSigPledgeHubPage extends StatelessWidget {
  const MultiSigPledgeHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签质押")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          _buildEntryCard(
            context,
            "质押提案(多签)",
            "发起需要多签成员共同签署的质押提案（目前仅确认支持稳定币质押类型）",
            Icons.rule_folder_outlined,
            Colors.deepPurple,
            const MultiSigPledgeProposalWidget(),
          ),
          _buildEntryCard(
            context,
            "追随质押签署(多签)",
            "粘贴 TxHash 参与他人发起的质押提案签署",
            Icons.draw_outlined,
            Colors.deepPurple,
            const MultiSigPledgeFollowSignWidget(),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: 0.5,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Trans(
                    "普通质押/超级节点质押/授权质押目前只在单签场景下有测试验证，未确认是否支持多签，暂未在此提供入口。",
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
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
              CircleAvatar(radius: 26, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 26)),
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
