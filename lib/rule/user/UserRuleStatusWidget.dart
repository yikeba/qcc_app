import 'package:flutter/material.dart';
import 'UserRuleFileStorage.dart';
import 'QccRuleInitiatedPage.dart';
import 'ruledev/DeveloperRuleSuccessPage.dart';
import 'rulemerchan/MerchantRuleSuccessPage.dart'; // 1. 引入商户成功页面
import '../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';

class UserRuleStatusWidget extends StatefulWidget {
  const UserRuleStatusWidget({super.key});

  @override
  State<UserRuleStatusWidget> createState() => _UserRuleStatusWidgetState();
}

class _UserRuleStatusWidgetState extends State<UserRuleStatusWidget> {
  late Future<List<dynamic>> _rulesFuture;

  @override
  void initState() {
    super.initState();
    _refreshRules();
  }

  void _refreshRules() {
    setState(() {
      _rulesFuture = UserRuleFileStorage.getAllRules();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _rulesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rules = snapshot.data ?? [];
        if (rules.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Trans("暂无规则记录", style: const TextStyle(color: Colors.grey)),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rules.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[100]),
          itemBuilder: (context, index) {
            final item = rules[index] as Map<String, dynamic>;
            final String ruleName = item['ruleName'] ?? "Unknown Rule";
            final String txHash = item['txHash'] ?? "";

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: _getLeadingIcon(ruleName),
              title: Text(ruleName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(
                "TxHash: ${txHash.length > 20 ? "${txHash.substring(0, 8)}...${txHash.substring(txHash.length - 8)}" : txHash}",
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              onTap: () => _handleNavigation(context, ruleName, item),
            );
          },
        );
      },
    );
  }

  // --- 核心分流逻辑：根据 ruleName 跳转到不同详情页 ---
  void _handleNavigation(BuildContext context, String ruleName, Map<String, dynamic> data) {
    Widget targetPage;

    if (ruleName == "DeveloperRule") {
      targetPage = DeveloperRuleSuccessPage(ruleData: data);
    } else if (ruleName == "PayCallRule") {
      targetPage = QccRuleInitiatedPage(ruleData: data);
    } else if (ruleName == "MerchantRule") {
      // 2. 处理商户规则跳转
      targetPage = MerchantRuleSuccessPage(ruleData: data);
    } else {
      // 默认回退到通用详情页
      targetPage = QccRuleInitiatedPage(ruleData: data);
    }

    Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => targetPage)
    ).then((_) => _refreshRules()); // 返回列表时自动刷新，保持状态同步
  }

  // --- 视觉分类：为不同规则匹配图标 ---
  Widget _getLeadingIcon(String name) {
    IconData iconData = Icons.rule;
    Color color = Colors.blue;

    if (name == "DeveloperRule") {
      iconData = Icons.code_rounded; // 开发者：代码图标
      color = Colors.orange;
    } else if (name == "PayCallRule") {
      iconData = Icons.notifications_active_outlined; // 支付回调：通知图标
      color = Colors.green;
    } else if (name == "MerchantRule") {
      iconData = Icons.storefront_outlined; // 商户：店铺图标
      color = Colors.indigo;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: color, size: 22),
    );
  }
}