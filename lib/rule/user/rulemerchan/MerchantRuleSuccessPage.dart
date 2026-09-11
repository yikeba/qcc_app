import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';

class MerchantRuleSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const MerchantRuleSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    // --- 商户规则解析逻辑 ---
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String address = ruleData['from'] ?? "";
    bool gasDelegation = false;
    String assetId = "QCC";

    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        if (inner['ruleJson'] != null) {
          innerParams = jsonDecode(inner['ruleJson']);
        } else {
          innerParams = inner;
        }
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }

      if (innerParams != null) {
        address = innerParams['address'] ?? address;
        gasDelegation = innerParams['gasDelegation'] ?? false;
        assetId = innerParams['assetId'] ?? "QCC";
      }
    } catch (e) {
      LogObj.log("MerchantRuleSuccessPage 解析失败: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("商户规则详情"),
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
            // 商户特有图标
            const Icon(Icons.storefront_rounded, color: Colors.indigo, size: 70),
            const SizedBox(height: 16),
            Trans("商户身份已激活", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD1D9E6)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "MerchantRule"),
                  const Divider(height: 32),
                  _infoRow(context, "Gas代付策略", gasDelegation ? "已开启 (Delegation)" : "未开启",
                      valueColor: gasDelegation ? Colors.green : Colors.grey),
                  const Divider(height: 32),
                  _infoRow(context, "绑定资产", assetId),
                  const Divider(height: 32),
                  // 核心复制功能：商户地址
                  _infoRow(context, "商户地址", address, isAddr: true, canCopy: true),
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

  Widget _infoRow(BuildContext context, String label, String value,
      {bool isAddr = false, bool canCopy = false, Color? valueColor}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy ? () {
              Clipboard.setData(ClipboardData(text: value));
              Tools.showToast(context, "内容已复制");
            } : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(displayValue,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: valueColor ?? (canCopy ? Colors.blue : Colors.black87),
                      )
                  ),
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

  Widget _buildHashSection(BuildContext context, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("交易哈希 (Transaction Hash)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
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