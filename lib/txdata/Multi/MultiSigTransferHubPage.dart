/// 【新增】QCC 综合交易页里「多签转账」磁贴点进来的二级菜单。
///
/// 之前 QccTxManagerPage.dart 里"多签转账"这块磁贴是直接
/// `builder: (_) => QccMultiSigTransferPage()`——点进去只能发起新提案，
/// 追随签署（QccFollowTransactionPage）完全没有入口，只能靠手动改路由才能
/// 到达。现在按你的要求拆成三个独立入口，各自进各自的功能页，避免追随
/// 签署时选错功能：
///   1. 多签转账提案 → QccMultiSigTransferPage（发起新的多签转账）
///   2. 多签转账签署 → QccFollowTransactionPage（追随签署已发起的提案）
///   3. 多签转账明细 → MultiSigTransferHistoryPage（新增：本地存储 +
///      展示"发起成功"的多签转账记录及签署进度）
///
/// 卡片样式直接沿用本次会话里已经在用的"入口卡片"视觉（图标+标题+副标题+
/// 箭头），没有跨模块导入 AssetHubCard.dart 里那个公共函数——那个函数是资产
/// 发行模块（rule/asset/...）下的东西，这里是交易模块（跟 Multi/ 同级），
/// 图省事去 import 一个不同业务域的文件容易在你后续重构时把两个模块意外
/// 耦合在一起，所以就地写了一份完全等价的小函数。
library;

import 'package:flutter/material.dart';

import '../../views/setting/AppTranslator.dart';
import 'MultiSigTransferHistoryPage.dart';
import 'QccFollowTransactionPage.dart';
import 'QccMultiSigTransferPage.dart';

class MultiSigTransferHubPage extends StatelessWidget {
  const MultiSigTransferHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("多签转账"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEntryCard(
            context,
            title: "多签转账提案",
            desc: "选择多签地址与资产类型，发起一笔新的多签转账提案",
            icon: Icons.north_east_rounded,
            color: Colors.blue,
            target: const QccMultiSigTransferPage(),
          ),
          _buildEntryCard(
            context,
            title: "多签转账签署",
            desc: "粘贴/扫描交易 Hash，追加签署他人发起的多签转账提案",
            icon: Icons.edit_note_rounded,
            color: Colors.orange,
            target: const QccFollowTransactionPage(),
          ),
          _buildEntryCard(
            context,
            title: "多签转账明细",
            desc: "查看本地发起成功的多签转账记录与签署进度",
            icon: Icons.receipt_long_outlined,
            color: Colors.teal,
            target: const MultiSigTransferHistoryPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context, {
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required Widget target,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color)),
        title: Trans(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Trans(desc, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => target)),
      ),
    );
  }
}
