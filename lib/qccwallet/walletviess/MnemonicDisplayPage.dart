
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../views/setting/AppTranslator.dart';
import 'QccWalletFactory.dart';

class MnemonicDisplayPage extends StatelessWidget {
  final String mnemonic;
  const MnemonicDisplayPage({super.key, required this.mnemonic});

  @override
  Widget build(BuildContext context) {
    final words = mnemonic.split(' ');
    return Scaffold(
      appBar: AppBar(title: Trans("备份助记词")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Trans("请抄写以下 24 个单词并安全保存：", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, childAspectRatio: 2.5, crossAxisSpacing: 8, mainAxisSpacing: 8,
                ),
                itemCount: 24,
                itemBuilder: (context, i) => Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text("${i + 1}. ${words[i]}", style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
            Trans("⚠️ 警告：请勿截图！任何人获得助记词都将拥有您的资产。",
                style: TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: () async {

                final wallet=await QccWalletFactory.createByManual(context, mnemonic);
                Navigator.pop(context); // 关掉展示页
               // LogObj.log("返回随机24个助记词创建的钱包${wallet!.address}");
                Navigator.pop(context, wallet); // 返回钱包对象
              },
              child: Trans("生成钱包"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}