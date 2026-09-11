import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';
import '../../utile/LogObj.dart';

/// 资产增发(铸造)结果页 —— 专门对标 AssetMintRule 的字段形状
/// (assetId / amount / receiver / proof)，不同于 AssetIssueSuccessPage.dart
/// 所展示的 AssetMeta 发行结果字段形状 (assetId / owner / precision /
/// initialSupply / mintable / freezable)。两者字段不兼容，直接复用
/// AssetIssueSuccessPage 会把 precision/mintable/freezable 显示成误导性的
/// 默认值，所以这里单独实现一个页面。
class AssetMintSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const AssetMintSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";

    String assetId = "---";
    num rawAmount = 0;
    String receiver = "---";
    String proof = "";
    // 增发结果本身不携带精度信息（AssetMintRule 没有 precision 字段），
    // 只能原样显示链上原始整数值，不做精度换算，避免展示错误的小数。

    try {
      Map<String, dynamic>? mint;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        mint = (inner['ruleJson'] != null) ? jsonDecode(inner['ruleJson']) : inner;
      } else if (ruleData['ruleJson'] != null) {
        mint = jsonDecode(ruleData['ruleJson']);
      }

      if (mint != null) {
        assetId = mint['assetId'] ?? "Unknown";
        rawAmount = mint['amount'] is String ? num.parse(mint['amount']) : (mint['amount'] ?? 0);
        receiver = mint['receiver'] ?? receiver;
        proof = mint['proof'] ?? "";
      }
    } catch (e) {
      LogObj.log("AssetMintSuccessPage 解析异常: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("增发结果"),
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
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Trans("资产增发交易已受理", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  _infoRow(context, "本次增发数量 (原始值)", rawAmount.toString()),
                  const Divider(height: 30),
                  _infoRow(context, "接收地址 (Receiver)", receiver, isAddr: true, canCopy: true),
                  if (proof.isNotEmpty) ...[
                    const Divider(height: 30),
                    _infoRow(context, "铸造证明", proof),
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
                          color: isStrong ? Colors.blueAccent : Colors.black87
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
