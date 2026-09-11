import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'QccCreateMultiSigPage.dart';
import 'QccFollowMultiSigPage.dart';
import '../QccMultiAddressListPage.dart';
import 'QccMultiSigCenterPage.dart';


class QccMultiSigManagerPage extends StatefulWidget {
  const QccMultiSigManagerPage({super.key});

  @override
  State<QccMultiSigManagerPage> createState() => _QccMultiSigManagerPageState();
}

class _QccMultiSigManagerPageState extends State<QccMultiSigManagerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
     // appBar: AppBar(title: const Text("多签管理中心 (Multiple)")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMenuCard(
            title: "生成多签 (Create)",
            subtitle: "发起多签地址创建，生成管理规则",
            icon: Icons.group_add,
            color: Colors.blue,
            onTap: _onCreateMultiSig,
          ),
          _buildMenuCard(
            title: "多签状态中心 (Center)",
            subtitle: "查询已发起的记录及上链完成情况",
            icon: Icons.history_edu_rounded,
            color: Colors.purple, // 换个颜色区分
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QccMultiSigCenterPage()),
              );
            },
          ),
          _buildMenuCard(
            title: "追随多签 (Follow)",
            subtitle: "扫描二维码或输入 Hash 参与多签",
            icon: Icons.qr_code_scanner,
            color: Colors.orange,
            onTap: _onFollowMultiSig,
          ),
          _buildMenuCard(
            title: "多签地址 (Transaction)",
            subtitle: "管理多签地址",
            icon: Icons.add_reaction_sharp,
            color: Colors.green,
            onTap: _onMultiSigaddress,
          ),
         /* _buildMenuCard(
            title: "多签交易 (Transaction)",
            subtitle: "发起或签署多签资产转移交易",
            icon: Icons.send_and_archive,
            color: Colors.green,
            onTap: _onMultiSigdata,
          ),
          _buildMenuCard(
            title: "追随交易 (Follow)",
            subtitle: "输入Hash。签署同意多签交易 ",
            icon: Icons.follow_the_signs,
            color: Colors.orange,
            onTap: _onFollowdata,
          ),*/
        ],
      ),
    );
  }

/*// 1. 发起交易逻辑：需要先让用户选一个多签地址
  void _onMultiSigdata() {
    // 最佳体验：直接跳转到地址列表，点击某项后进入转账页
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QccMultiSigTransferPage()),
    );
    // 或者直接弹出对话框让用户选
  }

// 2. 追随交易逻辑
  void _onFollowdata() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QccFollowTransactionPage()),
    );
  }*/

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          radius: 28,
          child: Icon(icon, color: color, size: 30),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.fromLTRB(0,4.0,0,0),
          child: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _onMultiSigaddress() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QccMultiAddressListPage(), // 跳转到新的独立列表页
      ),
    );
  }

  // 2. 追随多签逻辑：跳转到专门的追随页面
  void _onFollowMultiSig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QccFollowMultiSigPage(),
      ),
    );
  }


  // 1. 生成多签逻辑：跳转到独立的生成页面
  void _onCreateMultiSig() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QccCreateMultiSigPage(),
      ),
    );
  }

}
