import 'package:flutter/material.dart';
import '../../../../views/setting/AppTranslator.dart';

/// 【新增】原来 AssetIssuanceHubPage.dart 里的 _buildHubCard——现在拆成
/// 三个二级菜单页（SingleSigAssetHubPage / MultiSigIssuanceHubPage /
/// MultiSigAssetManageHubPage）都要用同一张功能入口卡片，抽成一个公共
/// 函数，避免同一段 UI 代码复制三份、以后改样式要同时改三处。
Widget buildAssetHubCard(
  BuildContext context,
  String title,
  String desc,
  IconData icon,
  Color color,
  Widget target,
) {
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
