import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../home/QccExplorerService.dart';
import '../../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';

class QccRuleInitiatedPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const QccRuleInitiatedPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    // 兼容公链返回的不同格式，提取 TxHash
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String ruleName = ruleData['ruleName'] ?? "QCC Rule";

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("规则发起结果"),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Trans("规则交易已广播", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Trans("公链已受理并进入暂存池", style: const TextStyle(color: Colors.grey)),

            const SizedBox(height: 32),
            _buildDetailCard(context, ruleName, txHash),
            const SizedBox(height: 32),
            _buildQrSection(txHash),
            const SizedBox(height: 40),

            _buildHomeButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context, String name, String hash) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!)
      ),
      child: Column(
        children: [
          _infoRow("业务类型", name),
          const Divider(height: 24),
          _infoRow("交易哈希", hash, isAddr: true, canCopy: true, context: context),
        ],
      ),
    );
  }

  Widget _buildQrSection(String hash) {
    return Column(
      children: [
        Trans("扫码在浏览器中查询", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        QrImageView(
          data: "${QccExplorerService.baseUrl}/tx/$hash",
          version: QrVersions.auto,
          size: 160.0,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(10),
        ),
      ],
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Trans("返回钱包首页"),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isAddr = false, bool canCopy = false, BuildContext? context}) {
    String displayValue = value;
    if (isAddr && displayValue.length > 20) {
      displayValue = "${displayValue.substring(0, 10)}...${displayValue.substring(displayValue.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: canCopy && context != null ? () {
              Clipboard.setData(ClipboardData(text: value));
              Tools.showToast(context, "已复制到剪贴板");
            } : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(displayValue,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.blue),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }
}