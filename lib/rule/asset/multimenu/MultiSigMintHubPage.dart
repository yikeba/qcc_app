import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/coin/AsseIdRule/MultiSigAssetMintWidget.dart';
import 'package:qcc_flutter/rule/asset/coin/AsseIdRule/AssetMintFollowSignWidget.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../coin/AsseIdRule/MultiSigMintStatusCenterPage.dart';
import '../coin/AssetHubCard.dart';


/// 多签增发二级菜单——按你的要求"多签增发（提案/追随/中心）"三项独立入口，
/// 和 MultiSigFreezeHubPage.dart / MultiSigBurnHubPage.dart 结构完全对称。
/// 原来"多签增发/多签冻结/多签销毁"三个入口全部指向同一个
/// MultiSigAssetManageHubPage（混着增发+冻结+销毁+冻结状态一起显示），
/// 现在拆开成三组各自独立的"提案/追随/中心"，结构更清晰，也彻底避免
/// 追随签署时在一个大杂烩列表里选错功能。
class MultiSigMintHubPage extends StatelessWidget {
  const MultiSigMintHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签增发")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "多签增发提案", "选择已发行资产，发起增发提案，需成员共同签署", Icons.add_chart_outlined, Colors.deepPurple, const MultiSigAssetMintWidget()),
          buildAssetHubCard(context, "追随增发签署", "粘贴 TxHash 参与他人发起的增发提案签署", Icons.draw_outlined, Colors.deepPurple, const AssetMintFollowSignWidget()),
          buildAssetHubCard(context, "多签增发状态中心", "查看本机发起的多签增发提案与签署进度", Icons.list_alt_outlined, Colors.deepPurple, const MultiSigMintStatusCenterPage()),
        ],
      ),
    );
  }
}
