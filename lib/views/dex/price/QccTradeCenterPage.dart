import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/dex/price/MyDexOrdersWidget.dart';
import 'package:qcc_flutter/views/dex/price/MyWinHistoryWidget.dart';
import '../../setting/AppTranslator.dart';

class QccTradeCenterPage extends StatelessWidget {
  const QccTradeCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Trans("我的交易管理"),
          centerTitle: true,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: Colors.blue,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: "现货挂单 (Open)"),
              Tab(text: "成交记录 (Win)"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MyDexOrdersWidget(), // 挂单管理
            MyWinHistoryWidget(), // 现货成交历史
          ],
        ),
      ),
    );
  }
}
