import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';


/// 【新增】TagTransfer 专属成功/详情页——展示标签名称、原持有者(from)、
/// 受让地址(newOwner)，风格对齐已有的几个规则成功页。
class TagTransferSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const TagTransferSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String prevOwner = ruleData['from'] ?? "";
    String tagName = "";
    String newOwner = "";

    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        prevOwner = inner['from'] ?? prevOwner;
        if (inner['ruleJson'] != null) {
          innerParams = jsonDecode(inner['ruleJson']);
        } else {
          innerParams = inner;
        }
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }

      if (innerParams != null) {
        tagName = innerParams['tagName'] ?? tagName;
        newOwner = innerParams['newOwner'] ?? newOwner;
      }
    } catch (e) {
      LogObj.log("TagTransferSuccessPage 解析失败: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("标签转让详情"),
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
            const Icon(Icons.swap_horiz_rounded, color: Colors.purple, size: 70),
            const SizedBox(height: 16),
            Trans("标签资产已转让", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEBE1FF)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "TagTransfer"),
                  const Divider(height: 32),
                  _infoRow(context, "标签名称", tagName.isEmpty ? "--" : tagName, canCopy: tagName.isNotEmpty),
                  const Divider(height: 32),
                  _infoRow(context, "原持有地址", prevOwner, isAddr: true, canCopy: true),
                  const Divider(height: 32),
                  _infoRow(context, "新持有地址", newOwner, isAddr: true, canCopy: newOwner.isNotEmpty),
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
      {bool isAddr = false, bool canCopy = false}) {
    String displayValue = value;
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
            onTap: canCopy
                ? () {
                    Clipboard.setData(ClipboardData(text: value));
                    Tools.showToast(context, "已复制到剪贴板");
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    displayValue.isEmpty ? "--" : displayValue,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: canCopy ? Colors.blueAccent : Colors.black87,
                    ),
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
                Expanded(
                    child: Text(hash,
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
