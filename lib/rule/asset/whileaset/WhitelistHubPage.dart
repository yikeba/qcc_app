import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import 'MultiSigWhitelistFollowSignWidget.dart';
import 'MultiSigWhitelistProposalWidget.dart';
import 'QccWhitelistManagePage.dart';

/// 白名单管理——独立顶层目录入口。
///
/// 【为什么白名单需要单独立一个目录，不挂在"稳定币/代币"发行管理菜单下】
/// 按你的说明：白名单是 QCC 公链底层协议区别于其它公链的重要功能，目前
/// 支持 5000-10000 级白名单配置，未来要支持到亿级——这是一个独立的协议
/// 能力维度（"某个地址能不能参与某资产的转账"），不是某个具体资产生命
/// 周期动作（发行/增发/冻结/销毁）的附属功能，所以在 QccFinanceRuleListPage
/// 顶层单独给一张卡片、单独一个目录，而不是塞进 AssetIssuanceHubPage 或
/// StablecoinHubPage 内部的某个二级菜单项里。
///
/// 三个子页面，对应你的要求"单单签实现一个白名单维护管理，多签就是白名单
/// 提案/白名单追随多签"：
/// - QccWhitelistManagePage：白名单维护管理(单签)——直接 ADD/REMOVE，
///   立即生效。
/// - MultiSigWhitelistProposalWidget：白名单提案(多签)——发起需要多签
///   共同签署的加白/减白提案。
/// - MultiSigWhitelistFollowSignWidget：追随白名单签署(多签)——粘贴 Hash
///   参与他人发起的白名单提案签署。
class WhitelistHubPage extends StatelessWidget {
  const WhitelistHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("白名单管理")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        children: [
          _buildEntryCard(
            context,
            "白名单维护管理(单签)",
            "直接对资产的转账白名单执行加白/减白，单签立即生效，无时间锁",
            Icons.playlist_add_check,
            Colors.blueAccent,
            const QccWhitelistManagePage(),
          ),
          _buildEntryCard(
            context,
            "白名单提案(多签)",
            "发起需要多签成员共同签署的加白/减白提案",
            Icons.rule_folder_outlined,
            Colors.deepPurple,
            const MultiSigWhitelistProposalWidget(),
          ),
          _buildEntryCard(
            context,
            "追随白名单签署(多签)",
            "粘贴 TxHash 参与他人发起的白名单提案签署",
            Icons.draw_outlined,
            Colors.deepPurple,
            const MultiSigWhitelistFollowSignWidget(),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: 0.5,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Trans(
                    "当前支持 5000-10000 级地址批量配置，未来将支持亿级白名单，届时提交方式可能改为分片/分页。",
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    String title,
    String desc,
    IconData icon,
    Color color,
    Widget target,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withOpacity(0.1),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Trans(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Trans(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
