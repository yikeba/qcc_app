import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';

class MultiSigSuccessDetailPage extends StatelessWidget {
  final String multiAddress;
  final List<String> owners;
  final int threshold;
  final String txHash;

  const MultiSigSuccessDetailPage({
    super.key,
    required this.multiAddress,
    required this.owners,
    required this.threshold,
    required this.txHash,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> uniqueOwners = LinkedHashSet<String>.from(owners).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Trans("多签账户详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. 成功状态头
            const Icon(Icons.verified_user, color: Colors.green, size: 60),
            const SizedBox(height: 12),
            Trans("多签合约已正式生效",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 24),

            // 2. 多签地址卡片 (核心)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  Trans("多签虚拟地址 (M-Address)", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 16),
                  QrImageView(data: multiAddress, size: 140),
                  const SizedBox(height: 16),
                  Text(multiAddress,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: multiAddress));
                      Tools.showToast(context, "多签地址已复制");
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: Trans("复制地址"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.withOpacity(0.1), foregroundColor: Colors.blue, elevation: 0),
                  )
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. 权重规则
            _buildInfoRow("生效权重", "需 $threshold / ${owners.length} 人签名确认"),
            const SizedBox(height: 16),

            // 4. 明细单签地址列表
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Trans("参与者明细 (Owners)", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: uniqueOwners.length, // 使用去重后的长度
              itemBuilder: (context, index) => _buildOwnerItem(index + 1, uniqueOwners[index]),
            ),
            const SizedBox(height: 30),

            // 5. 操作按钮：发起多签转账
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // 这里跳转到多签转账发起逻辑
                  Tools.showToast(context, "功能开发中：使用此地址发起多签转账");
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: Trans("使用此账户发起转账"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildOwnerItem(int index, String address) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          CircleAvatar(radius: 12, backgroundColor: Colors.blue.shade50, child: Text("$index", style: const TextStyle(fontSize: 10))),
          const SizedBox(width: 12),
          Expanded(child: Text(address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          IconButton(
            icon: const Icon(Icons.copy, size: 14, color: Colors.grey),
            onPressed: () => Clipboard.setData(ClipboardData(text: address)),
          )
        ],
      ),
    );
  }
}