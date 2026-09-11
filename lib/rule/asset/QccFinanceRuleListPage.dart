import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/whileaset/WhitelistHubPage.dart';
import '../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import 'multimenu/AssetIssuanceHubPage.dart';
import 'stablecoin/StablecoinHubPage.dart';

/// 【修改说明】
/// 1. 实体数据容器（Data Container：IssueData / UpdateData）已按你的确认
///    整体下线——未来 QCC 不再支持实体容器，全部走默认容器，所以这里连带
///    的分类标题、两张卡片、以及仅服务于这部分的死代码全部删除。
/// 2. 顶层仍按"稳定币 / 代币"资产类型分两张卡（维持现状，改动最小），
///    各自的发行/增发/冻结/赎回/销毁仍然在各自 Hub 页面内部管理，未做
///    按功能主线（发行增发 vs 资产管理）的整体拆分。
/// 3. 顺带清理：_goToIssuePage() 是从未被调用的死代码（真正的导航都走
///    _navToForm），随实体容器一起删除；其专属 import
///    （MultiSigTokenIssueWidget.dart / SingleSigTokenIssueWidget.dart）
///    也一并移除，因为已不再被本文件引用。
/// 4.【新增】白名单管理——单独第三张卡，不挂在"稳定币/代币"任何一个已有
///    菜单下面。按你的说明：白名单是 QCC 公链底层协议区别于其它公链的
///    重要功能，目前支持 5000-10000 级白名单配置，未来支持亿级白名单，
///    量级和战略重要性都足够单独占一个顶层入口，对应新增的
///    whitelist/WhitelistHubPage.dart（白名单维护管理单签 / 白名单提案
///    多签 / 追随白名单签署多签 三个子页面）。
class QccFinanceRuleListPage extends StatelessWidget {
  const QccFinanceRuleListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Trans("金融资产规则"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildFinanceCard(
            context,
            title: "稳定(消费)币发行/管理 (Asset Stablecoin)",
            subtitle: "稳定币定义，高安全度，高质押货币",
            icon: Icons.monetization_on_outlined,
            color: Colors.blueAccent,
            onTap: () => _navToForm(context, "stablecoin"),
          ),
          _buildFinanceCard(
            context,
            title: "代币发行/管理 (Asset Issue)",
            subtitle: "定义代币符号、精度、总量，生成全新 AssetId 容器",
            icon: Icons.price_change_outlined,
            color: Colors.blueAccent,
            onTap: () => _navToForm(context, "asset"),
          ),
          _buildFinanceCard(
            context,
            title: "白名单管理 (Whitelist)",
            subtitle: "资产转账白名单地址维护——单签直接维护，多签提案+追随签署",
            icon: Icons.playlist_add_check_circle_outlined,
            color: Colors.deepPurple,
            onTap: () => _navToForm(context, "whitelist"),
          ),

          const SizedBox(height: 40),
          _buildFootnote(),
        ],
      ),
    );
  }

  Widget _buildFinanceCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            // 【修复】withOpacity 已废弃，改用 withValues(alpha:)
            color: color.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
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
                Icon(Icons.add_circle_outline, color: color.withValues(alpha: 0.5), size: 20),
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
                  "QCC 默认容器进程支持自定义状态规则，资产发行后可按需挂载增发/冻结/销毁逻辑。",
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _navToForm(BuildContext context, String type) {
    if (type == "asset") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AssetIssuanceHubPage()),
      );
    } else if(type=="stablecoin"){
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const StablecoinHubPage()),
      );
    } else if(type=="whitelist"){
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WhitelistHubPage()),
      );
    }else {
      Tools.showToast(context, Tools.getTra("期待下个版本更新")+ type);
    }
  }
}