import 'package:flutter/material.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../coin/AssetHubCard.dart';
import '../freezeasset/ multi/MultiSigAssetFreezeFollowSignWidget.dart';
import '../freezeasset/ multi/MultiSigAssetFreezeWidget.dart';
import '../freezeasset/ multi/MultiSigFreezeStatusCenterPage.dart';

/// 多签冻结二级菜单——按你的要求"多签冻结（提案/追随/中心）"三项独立入口，
/// 和 MultiSigMintHubPage.dart / MultiSigBurnHubPage.dart 结构完全对称。
class MultiSigFreezeHubPage extends StatelessWidget {
  const MultiSigFreezeHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签冻结")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "多签冻结提案", "选择已发行资产，发起冻结/解冻提案，需成员共同签署", Icons.icecream_outlined, Colors.black87, const MultiSigAssetFreezeWidget()),
          buildAssetHubCard(context, "追随冻结签署", "粘贴 TxHash 参与他人发起的冻结/解冻提案签署", Icons.draw_outlined, Colors.black87, const MultiSigAssetFreezeFollowSignWidget()),
          buildAssetHubCard(context, "多签冻结状态中心", "查看本机发起的多签冻结/解冻提案与签署进度", Icons.list_alt_outlined, Colors.red, const MultiSigFreezeStatusCenterPage()),
        ],
      ),
    );
  }
}
