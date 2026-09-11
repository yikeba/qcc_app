import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import 'MultiSigPledgeHubPage.dart';
import 'QccPledgeHubPage.dart';

/// 质押规则——顶层入口页。
///
/// 【目录划分，对应你的要求"单签一个目录搞定/多签区分一下"】
/// - 单签：pledge/single/ 一整个目录，内部用 TabBar 把"普通质押/超级节点
///   质押/授权质押/我的记录"四类操作收进 QccPledgeHubPage 这一个页面——
///   不像资产规则/白名单那样拆成多张并列卡片，是刻意按你的原话做的。
/// - 多签：pledge/multi/ 单独一个目录，MultiSigPledgeHubPage 内部再拆
///   "质押提案"和"追随质押签署"两个子页面。
///
/// 只做2张卡片，逻辑简单，不需要 StatefulWidget。
class QccPledgeRuleListPage extends StatelessWidget {
  const QccPledgeRuleListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Trans("质押规则"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildCard(
            context,
            title: "单签质押管理",
            subtitle: "普通质押(自我信托) / 超级节点质押 / 授权质押(去中心化鉴权) / 我的记录，同一页面内切换",
            icon: Icons.lock_person_outlined,
            color: Colors.indigo,
            target: const QccPledgeHubPage(),
          ),
          _buildCard(
            context,
            title: "多签质押",
            subtitle: "质押提案(目前仅确认支持稳定币质押) / 追随质押签署",
            icon: Icons.groups_2_outlined,
            color: Colors.deepPurple,
            target: const MultiSigPledgeHubPage(),
          ),
          const SizedBox(height: 40),
          _buildFootnote(),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget target,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Trans(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Trans(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.5), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFootnote() {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 12),
        Opacity(
          opacity: 0.5,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Trans(
                  "锁仓参与共识与收益分配：超级节点质押、授权质押(按tag归属利息)、稳定币质押与解押。",
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
