import 'package:flutter/material.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../freezeasset/QccBurnPage.dart';
import '../freezeasset/QccFreezeHistoryPage.dart';
import '../freezeasset/QccFreezePage.dart';
import '../coin/AssetHubCard.dart';
import '../coin/SingleSigAssetMintWidget.dart';
import '../coin/SingleSigTokenIssueWidget.dart';

/// 单签资产管理二级菜单——发行 / 增发 / 冻结 / 销毁 / 冻结状态，
/// 单签地址直接操作，全部即时生效，不需要多签共同签署。
class SingleSigAssetHubPage extends StatelessWidget {
  const SingleSigAssetHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("单签资产管理")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          buildAssetHubCard(context, "单签资产发行", "单签地址直接发布资产，即时生效", Icons.person_outline, Colors.blue, const SingleSigTokenIssueWidget()),
          buildAssetHubCard(context, "单签资产增发", "单签地址对已发行资产直接增发，即时生效", Icons.add_circle_outline, Colors.indigo, const SingleSigAssetMintWidget()),
          buildAssetHubCard(context, "单签资产冻结", "冻结资产地址", Icons.icecream_outlined, Colors.black38, const QccFreezePage()),
          buildAssetHubCard(context, "单签资产销毁", "销毁/赎回现有资产", Icons.delete_forever_outlined, Colors.teal, const QccBurnPage()),
          buildAssetHubCard(context, "冻结状态中心", "显示被冻结地址与资产", Icons.list_alt_outlined, Colors.red, const QccFreezeHistoryPage()),
        ],
      ),
    );
  }
}
