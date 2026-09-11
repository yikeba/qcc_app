import 'package:flutter/material.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../coin/AssetHubCard.dart';
import '../coin/creatcoin/AssetFollowSignWidget.dart';
import '../coin/creatcoin/MultiSigTokenIssueWidget.dart';

/// 多签资产发行二级菜单——单独一类，只包含"发行"这一件事：发起发行提案
/// + 追随发行提案签署。刻意不和"多签管理"（增发/冻结/销毁）放在一起，
/// 这样追随签署时不会把发行提案的 hash 和增发提案的 hash 弄混（两者跟签
/// 页面的摘要字段完全不同：AssetFollowSignWidget 只认 AssetMeta，增发的
/// 跟签走 MultiSigAssetManageHubPage 里的"追随增发签署"）。
class MultiSigIssuanceHubPage extends StatelessWidget {
  const MultiSigIssuanceHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签资产发行")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "多签资产提案", "多签地址发起发行申请，需成员共同签署", Icons.account_tree_outlined, Colors.orange, const MultiSigTokenIssueWidget()),
          buildAssetHubCard(context, "追随资产签署", "粘贴 TxHash 参与他人发起的资产发行提案签署", Icons.draw_outlined, Colors.purple, const AssetFollowSignWidget()),
        ],
      ),
    );
  }
}
