import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';

/// 资产销毁结果页 —— 对应 AssetBurnRule 的字段形状
/// (assetId / targetAddress / amount / legalBasis / memo)，和发行
/// (AssetIssueSuccessPage) / 增发 (AssetMintSuccessPage) 各自独立，字段不通用。
class AssetBurnSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const AssetBurnSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";

    String assetId = "---";
    String targetAddress = "---";
    num rawAmount = 0;
    String? legalBasis;
    String? memo;

    try {
      Map<String, dynamic>? burn;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        burn = (inner['ruleJson'] != null) ? jsonDecode(inner['ruleJson']) : inner;
      } else if (ruleData['ruleJson'] != null) {
        burn = jsonDecode(ruleData['ruleJson']);
      }

      if (burn != null) {
        assetId = burn['assetId'] ?? "Unknown";
        targetAddress = burn['targetAddress'] ?? targetAddress;
        rawAmount = burn['amount'] is String ? num.parse(burn['amount']) : (burn['amount'] ?? 0);
        legalBasis = burn['legalBasis'];
        memo = burn['memo'];
      }
    } catch (e) {
      LogObj.log("AssetBurnSuccessPage 解析异常: $e");
    }

    bool isThirdParty = legalBasis != null && legalBasis.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("销毁结果"),
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.local_fire_department, color: Colors.orange.shade800, size: 80),
            const SizedBox(height: 16),
            Trans(isThirdParty ? "第三方地址资产销毁已受理" : "资产自烧已受理",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  _infoRow(context, "资产标识 (AssetId)", assetId, isStrong: true),
                  const Divider(height: 30),
                  _infoRow(context, "本次销毁数量 (原始值)", rawAmount.toString()),
                  const Divider(height: 30),
                  _infoRow(context, isThirdParty ? "被销毁地址 (第三方)" : "被销毁地址 (自己)", targetAddress, isAddr: true, canCopy: true),
                  if (legalBasis != null && legalBasis.isNotEmpty) ...[
                    const Divider(height: 30),
                    _infoRow(context, "合规依据", legalBasis),
                  ],
                  if (memo != null && memo.isNotEmpty) ...[
                    const Divider(height: 30),
                    _infoRow(context, "备注", memo),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHashBox(context, txHash),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value,
      {bool isAddr = false, bool canCopy = false, bool isStrong = false}) {
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
                          fontFamily: isAddr ? 'monospace' : null,
                          fontWeight: isStrong ? FontWeight.w900 : FontWeight.bold,
                          fontSize: isStrong ? 16 : 14,
                          color: isStrong ? Colors.deepOrange : Colors.black87
                      )),
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

  Widget _buildHashBox(BuildContext context, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("交易哈希 (TxHash)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
