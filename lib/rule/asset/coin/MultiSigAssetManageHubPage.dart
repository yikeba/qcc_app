import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/multiburn/MultiSigAssetBurnWidget.dart';
import 'package:qcc_flutter/rule/asset/freezeasset/%20multi/MultiSigAssetFreezeWidget.dart';
import 'package:qcc_flutter/rule/asset/coin/AsseIdRule/MultiSigAssetMintWidget.dart';
// 增发提案的专属跟签页，和 MultiSigAssetMintWidget.dart 同目录——如果你
// 项目里实际放的位置不一样，改这一行就行，不影响其它内容。
import 'package:qcc_flutter/rule/asset/coin/AsseIdRule/AssetMintFollowSignWidget.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../freezeasset/QccFreezeHistoryPage.dart';
import 'AssetHubCard.dart';

/// 多签资产管理二级菜单——针对"已发行资产"的增发 / 冻结 / 销毁提案与跟签，
/// 以及冻结状态查询，都需要多签共同签署。和"多签发行"分开列，跟签时不会
/// 选错功能（增发的 hash 只会被引导到这里的"追随增发签署"，不会误粘到
/// 发行跟签页面）。
class MultiSigAssetManageHubPage extends StatelessWidget {
  const MultiSigAssetManageHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签资产管理")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "多签资产增发", "多签地址发起增发提案，需成员共同签署", Icons.add_chart_outlined, Colors.deepPurple, const MultiSigAssetMintWidget()),
          buildAssetHubCard(context, "追随增发签署", "粘贴 TxHash 参与他人发起的增发提案签署", Icons.draw_outlined, Colors.deepPurple, const AssetMintFollowSignWidget()),
          buildAssetHubCard(context, "多签资产销毁", "销毁/赎回现有资产", Icons.delete_forever_outlined, Colors.teal, const MultiSigAssetBurnWidget()),
          buildAssetHubCard(context, "多签冻结提案", "冻结资产地址", Icons.icecream_outlined, Colors.black87, const MultiSigAssetFreezeWidget()),
          buildAssetHubCard(context, "冻结状态中心", "显示被冻结地址与资产", Icons.list_alt_outlined, Colors.red, const QccFreezeHistoryPage()),
        ],
      ),
    );
  }
}
