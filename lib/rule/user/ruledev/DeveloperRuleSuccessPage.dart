import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';

class DeveloperRuleSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const DeveloperRuleSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    // --- 鲁棒性解析逻辑 ---
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    double rewardRate = 0.2;
    // 优先尝试从 history 记录的 'from' 字段读取地址
    String address = ruleData['from'] ?? "";

    try {
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        address = inner['address'] ?? address;
        rewardRate = (inner['rewardRate'] ?? 0.2).toDouble();

        if (inner['ruleJson'] != null) {
          var ruleObj = jsonDecode(inner['ruleJson']);
          address = ruleObj['address'] ?? address;
          rewardRate = (ruleObj['rewardRate'] ?? rewardRate).toDouble();
        }
      }
      else if (ruleData['ruleJson'] != null) {
        var ruleObj = jsonDecode(ruleData['ruleJson']);
        address = ruleObj['address'] ?? address;
        rewardRate = (ruleObj['rewardRate'] ?? 0.3).toDouble();
      }
    } catch (e) {
      LogObj.log("DeveloperRuleSuccessPage 解析数据异常: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("开发者规则详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.verified_user, color: Colors.blueAccent, size: 70),
            const SizedBox(height: 16),
            Trans("开发者身份状态", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEDF2F7)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "业务类型", ruleData['ruleName'] ?? "DeveloperRule"),
                  const Divider(height: 32),
                  _infoRow(context, "奖励比例", "${(rewardRate * 100).toStringAsFixed(0)}%"),
                  const Divider(height: 32),
                  // 这里启用了 copy 功能
                  _infoRow(context, "开发者地址", address, isAddr: true, canCopy: true),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHashSection(context, txHash),
          ],
        ),
      ),
    );
  }

  /// 增强版的行组件，支持点击复制完整值
  Widget _infoRow(BuildContext context, String label, String value, {bool isAddr = false, bool canCopy = false}) {
    String displayValue = value;
    // UI 上缩略显示长地址
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy ? () {
              Clipboard.setData(ClipboardData(text: value)); // 复制的是完整 value
              Tools.showToast(context, "已复制到剪贴板");
            } : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                      displayValue,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: canCopy ? Colors.blueAccent : Colors.black87,
                      )
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHashSection(BuildContext context, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("交易哈希", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: hash));
            Tools.showToast(context, "哈希已复制");
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(child: Text(hash, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}