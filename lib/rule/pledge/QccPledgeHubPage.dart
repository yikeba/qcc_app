import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'CommonPledgeWidget.dart';
import 'PledgeRecordsWidget.dart';
import 'node/SuperNodePledgeWidget.dart';
import 'author/AuthorizedPledgeWidget.dart';

/// 单签质押管理——统一入口页。
///
/// 【对应你的要求】"单签一个目录搞定"：不像资产规则那样把"普通质押/超级
/// 节点质押/授权质押/我的记录"拆成 QccRuleManagerPage 底下一堆并列的二级
/// 菜单项，而是在质押这个大类目录下用一个 TabBar 把单签能做的全部操作
/// 收进同一个页面，用户进"质押规则"只看到"单签质押管理 / 多签质押"两个
/// 入口（见 QccPledgeRuleListPage.dart），点进单签之后才是这4个标签页。
///
/// 4个标签分别对应 6 个 Java 测试文件覆盖到的单签场景：
///   普通质押   -> PledgeCommonTest.java（自我信托，protocol=""）
///   超级节点质押 -> PledgeNodeTest.java / PledgeSignNodeTest.java（protocol=SuperNode）
///   授权质押   -> PledgeAuthorizedTest.java / PledgeUnlockTest.java（protocol=AuthorizedPledge）
///   我的记录   -> 本机 PledgeFileStorage 汇总视图（非 Java 直接对应，纯本地功能）
///
/// 【未纳入的 PledgetType.PledgeReleaseScheduler】见 PledgetType.dart 头部
/// 注释——6个测试文件都没有用到它，看起来是创世/系统层面自动产生的记录，
/// 不像用户能主动发起，本轮没给它做发起入口。
class QccPledgeHubPage extends StatefulWidget {
  const QccPledgeHubPage({super.key});

  @override
  State<QccPledgeHubPage> createState() => _QccPledgeHubPageState();
}

class _QccPledgeHubPageState extends State<QccPledgeHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Trans("单签质押管理"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: Tools.getTra("普通质押")),
            Tab(text: Tools.getTra("超级节点质押")),
            Tab(text: Tools.getTra("授权质押")),
            Tab(text: Tools.getTra("我的记录")),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          CommonPledgeWidget(),
          SuperNodePledgeWidget(),
          AuthorizedPledgeWidget(),
          PledgeRecordsWidget(),
        ],
      ),
    );
  }
}
