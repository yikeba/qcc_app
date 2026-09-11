import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'LoanIssueWidget.dart';
import 'LoanRepayWidget.dart';
import 'LoanStatusWidget.dart';

/// 借贷管理 —— 统一入口页，对应 QccTxManagerPage.dart 里的"借贷"磁贴。
///
/// 【对应你的要求】"点击进入下一级菜单：借款/还款/借贷状态实现"——单签场景，
/// 用一个 TabBar 把 3 个操作收进同一个页面，和 QccPledgeHubPage.dart(单签
/// 质押管理)是同一个设计语言。
///
/// 撤销/核销(cancelloan)按 QccTxManagerPage.dart 自己的设计注释——
/// "撤销不设独立入口——由「交易明细」进入详情后判断并执行"，放在"借贷状态"
/// 标签页的详情弹窗里，不单独占一个标签。
class LoanHubPage extends StatefulWidget {
  const LoanHubPage({super.key});

  @override
  State<LoanHubPage> createState() => _LoanHubPageState();
}

class _LoanHubPageState extends State<LoanHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        title: Trans("借贷管理"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: Tools.getTra("借款")),
            Tab(text: Tools.getTra("还款")),
            Tab(text: Tools.getTra("借贷状态")),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          LoanIssueWidget(),
          LoanRepayWidget(),
          LoanStatusWidget(),
        ],
      ),
    );
  }
}
