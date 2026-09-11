import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'InheritCreateWidget.dart';
import 'InheritStatusWidget.dart';

/// 继承管理 —— 统一入口页，对应 QccTxManagerPage.dart 里的"继承"磁贴。
/// 跟 LoanHubPage.dart 是同一个设计语言：TabController 把创建/管理收进
/// 同一个页面。
///
/// 撤销/领取按 QccTxManagerPage.dart 自己的设计注释——"撤销不设独立入口——
/// 由「交易明细」进入详情后判断并执行"，放在"继承中心"标签页的详情弹窗里，
/// 不单独占一个标签（跟借贷的核销处理方式一致）。
class InheritHubPage extends StatefulWidget {
  const InheritHubPage({super.key});

  @override
  State<InheritHubPage> createState() => _InheritHubPageState();
}

class _InheritHubPageState extends State<InheritHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: Trans("继承管理"),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: Tools.getTra("创建信托")),
            Tab(text: Tools.getTra("继承中心")),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          InheritCreateWidget(),
          InheritStatusWidget(),
        ],
      ),
    );
  }
}
