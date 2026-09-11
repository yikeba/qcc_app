import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../myasset/QccAssetService.dart';
import 'QCCDataResolver.dart';
import 'QccDataMeta.dart';

class QccDataWidget extends StatelessWidget {
  final QccDataMeta meta;
  final QccResolveResult? resolved;
  final String txHash;
  final bool isFullPage;

  const QccDataWidget({
    super.key,
    required this.meta,
    this.resolved,
    required this.txHash,
    this.isFullPage = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 根据类型选择展示 交易账单 或 数据预览
          meta.entryType == QccEntryType.data
              ? _buildDataView(context)
              : _buildTransactionView(meta.extra!),

          const SizedBox(height: 20),
          _buildFooter(context),
        ],
      ),
    );
  }

  // --- 场景一：展示转账交易账单 ---
  Widget _buildTransactionView(Map<String, dynamic> tx) {
    LogObj.log("转账明细内容:${tx.toString()}");
    String assetId=tx['assetId'];
    double amount=QccAssetService().getHumanAmountNum(tx['assetId'], tx['amount']  );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 10),
          const Text("转账成功", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          _buildTxRow("转出方", tx['from'] ?? "---"),
          _buildTxRow("接收方", tx['to'] ?? "---"),
          _buildTxRow("金额", "$amount  $assetId"),
          _buildTxRow("类型", tx['txType'] ?? "pay"),
          _buildTxRow("资产ID", tx['assetId'] ?? "QCC"),
          _buildTxRow("备注", tx['memo']?.isEmpty == true ? "无" : (tx['memo'] ?? "无")),
        ],
      ),
    );
  }

  // --- 场景二：展示存证数据解析 ---
  Widget _buildDataView(BuildContext context) {
    if (resolved == null) return const Center(child: Text("数据解析中或格式不支持"));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.description, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text("存证原始内容", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildResolvedContent(context),
        ],
      ),
    );
  }

  Widget _buildResolvedContent(BuildContext context) {
    switch (resolved!.type) {
      case 'IMAGE':
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(resolved!.data, fit: BoxFit.fitWidth),
        );
      case 'JSON':
      case 'TEXT':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            resolved!.data.toString(),
            style: const TextStyle(color: Color(0xFFADDB67), fontFamily: 'monospace'),
          ),
        );
      default:
        return const Text("二进制文件/不支持预览");
    }
  }

  // 公用：底部哈希显示
  Widget _buildFooter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("存证/交易哈希", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(txHash, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: txHash));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("哈希已复制")));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTxRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}