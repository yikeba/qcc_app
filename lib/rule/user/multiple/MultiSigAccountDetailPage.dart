import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../utile/Tools.dart';

class MultiSigAccountDetailPage extends StatelessWidget {
  final Map<String, dynamic> data; // 包含 multiaddress, owners, threshold 等

  const MultiSigAccountDetailPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    String mAddress = data['multiaddress'] ?? "生成中...";
    List owners = data['owners'] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text("多签账户详情")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 1. 顶部状态卡片
            _buildStatusHeader(),
            const SizedBox(height: 24),

            // 2. M 地址展示与二维码
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]
              ),
              child: Column(
                children: [
                  const Text("最终多签虚拟地址", style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),
                  QrImageView(data: mAddress, size: 160),
                  const SizedBox(height: 12),
                  Text(mAddress,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Colors.blue),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mAddress));
                      Tools.showToast(context, "地址已复制");
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. 管理规则复核
            _buildSectionTitle("管理规则"),
            _buildInfoTile("权重门槛", "需 ${data['threshold']} / ${owners.length} 人签名生效"),
            const Divider(),

            // 4. 持有人列表
            _buildSectionTitle("持有人名单 (${owners.length})"),
            ...owners.asMap().entries.map((e) => _buildOwnerItem(e.key + 1, e.value)).toList(),

            const SizedBox(height: 40),

            // 5. 操作按钮
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.green,
              ),
              onPressed: () {
                // TODO: 跳转到多签转账发起页面
                //Tools.showToast(context, "功能开发中：使用此地址发起转账");
                //QccMultiSigTransferPage

              },
              child: const Text("使用此地址发起转账", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified, color: Colors.green, size: 28),
        SizedBox(width: 8),
        Text("已正式生效", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }

  Widget _buildOwnerItem(int index, String addr) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(radius: 10, child: Text("$index", style: const TextStyle(fontSize: 10))),
          const SizedBox(width: 8),
          Expanded(child: Text(addr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}