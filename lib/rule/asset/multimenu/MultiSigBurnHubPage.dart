import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/multiburn/MultiSigAssetBurnWidget.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../coin/AssetHubCard.dart';
import '../multiburn/MultiSigAssetBurnFollowSignWidget.dart';
import '../multiburn/MultiSigBurnStatusCenterPage.dart';


/// 多签销毁二级菜单——按你的要求"多签销毁（提案/追随/中心）"三项独立入口，
/// 和 MultiSigMintHubPage.dart / MultiSigFreezeHubPage.dart 结构完全对称。
///
/// 【需要你核实】"多签销毁提案"这一项引用的 MultiSigAssetBurnWidget.dart
/// 我没有拿到真实源码，这次没有改动它——只新增了"追随销毁签署"和
/// "多签销毁状态中心"两个配套页面。如果 MultiSigAssetBurnWidget.dart 现在
/// 还是走老的签名方式（compute + QccDataProtocol.encodeTransaction，本
/// session 里其它页面都确认过这个方法签名恒为空），或者它的 saveTask 调用
/// 没有存 assetId/targetAddress/owners/threshold 这些字段，麻烦把这个文件
/// 发我，我按和 MultiSigAssetFreezeWidget.dart 这次同样的方式修一遍，这一
/// 组"提案/追随/中心"才能真正跑通。
class MultiSigBurnHubPage extends StatelessWidget {
  const MultiSigBurnHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签销毁")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "多签销毁提案", "选择已发行资产，发起销毁提案，需成员共同签署", Icons.delete_forever_outlined, Colors.teal, const MultiSigAssetBurnWidget()),
          buildAssetHubCard(context, "追随销毁签署", "粘贴 TxHash 参与他人发起的销毁提案签署", Icons.draw_outlined, Colors.teal, const MultiSigAssetBurnFollowSignWidget()),
          buildAssetHubCard(context, "多签销毁状态中心", "查看本机发起的多签销毁提案与签署进度", Icons.list_alt_outlined, Colors.teal, const MultiSigBurnStatusCenterPage()),
        ],
      ),
    );
  }
}
