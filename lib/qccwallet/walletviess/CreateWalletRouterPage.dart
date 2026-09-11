import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../qccwallet/QccWallet.dart';
import '../../views/setting/AppTranslator.dart';
import 'ManualMnemonicEntryPage.dart';
import 'MnemonicDisplayPage.dart';

class CreateWalletRouterPage extends StatelessWidget {
  const CreateWalletRouterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Trans("创建 QCC 钱包")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildOptionCard(
            context,
            icon: Icons.auto_awesome,
            title: "1. 自动生成助记词",
            desc: "系统生成安全词库，您只需负责记录。",
            color: Colors.blue,
            onTap: () => _navigateToMnemonicDisplay(context, isAuto: true),
          ),
          _buildOptionCard(
            context,
            icon: Icons.edit_note,
            title: "2. 人工+密码高安全助记词",
            desc: "从 2048 个标准词库中亲自挑选 24 个单词。",
            color: Colors.purple,
            onTap: () => _navigateToManualEntry(context),
          ),
         /* _buildOptionCard(
            context,
            icon: Icons.flash_on,
            title: "3. 随机自动生成钱包",
            desc: "极速创建，适合快速测试（请务必事后备份）。",
            color: Colors.orange,
            onTap: () => _handleQuickCreate(context),
          ),*/
        ],
      ),
    );
  }

  Widget _buildOptionCard(BuildContext context, {required IconData icon, required String title, required String desc, required Color color, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Trans(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Trans(desc),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }


  // 1. 自动生成：接收 isAuto 参数（虽然目前只有自动模式会跳到展示页，但保留参数方便扩展）
  void _navigateToMnemonicDisplay(BuildContext context, {bool isAuto = true}) {
    // 生成 24 个词的随机助记词 (256 bits entropy)
    final String mnemonic = QccMnemonicWallet.generateRandomMnemonic();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MnemonicDisplayPage(mnemonic: mnemonic),
      ),
    );
  }

  // 2. 人工生产：跳转到我们刚才写的联想输入页面
  void _navigateToManualEntry(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManualMnemonicEntryPage(),
      ),
    );
  }

  // 3. 随机自动生成：静默创建并弹出成功对话框
  void _handleQuickCreate(BuildContext context) {
    // 直接调用你的核心算法生成
    final newWallet = QccMnemonicWallet.createRandom();
    showDialog(
      context: context,
      barrierDismissible: false, // 强制用户看一眼地址
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Trans("钱包已极速创建"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Trans("您的 QCC 钱包地址："),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(5)),
              child: Text(newWallet.address, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
            ),
            const SizedBox(height: 15),
            Trans("⚠️ 提示：应用在本地加密备份，请稍后前往“安全中心”导出助记词以防丢失。",
                style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              LogObj.log("返回随机快速创建的钱包${newWallet.address}");
              Navigator.pop(context, newWallet); // 返回钱包对象给上层
            },
            child: Trans("进入钱包"),
          ),
        ],
      ),
    );
  }
}