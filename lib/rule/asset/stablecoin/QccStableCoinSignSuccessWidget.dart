
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
class QccStableCoinSignSuccessWidget extends StatelessWidget {
  final Map<String, dynamic> responseData;

  const QccStableCoinSignSuccessWidget({super.key, required this.responseData});

  @override
  Widget build(BuildContext context) {
    // 1. 解析外层数据
    String signTxHash = responseData['txHash'] ?? ""; // 本次签署的交易哈希

    // 2. 解析 data 内部字符串 (核心业务数据)
    Map<String, dynamic> innerData = {};
    Map<String, dynamic> assetMeta = {};
    Map<String, dynamic> appendSigns = {};

    try {
      if (responseData['data'] != null) {
        innerData = jsonDecode(responseData['data']);

        // 解析原始规则 (包含 AssetID, initialSupply, precision)
        if (innerData['ruleJson'] != null) {
          assetMeta = jsonDecode(innerData['ruleJson']);
        }

        // 解析追加的签名列表
        if (innerData['ruleAppendJson'] != null) {
          appendSigns = jsonDecode(innerData['ruleAppendJson']);
        }
      }
    } catch (e) {
      LogObj.log("解析稳定币返回数据异常: $e");
    }

    // 计算展示金额：initialSupply / 10^precision
    String assetId = assetMeta['assetId'] ?? "Unknown";
    int precision = assetMeta['precision'] ?? 0;
    num rawSupply = assetMeta['initialSupply'] ?? 0;
    double displaySupply = rawSupply / (10 * precision);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("签署完成"),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Trans("稳定币发行签署已成功广播",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            // 资产明细卡片
            _buildAssetCard(assetId, displaySupply, precision),

            const SizedBox(height: 24),

            // 签署进度卡片
            _buildSignStatusCard(appendSigns.length + 1), // +1 是因为原始提案自带一个发起者签名

            const SizedBox(height: 24),

            // 交易凭证展示
            _buildHashItem(context, "本次签名交易哈希", signTxHash),

            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Trans("完成"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetCard(String id, double supply, int precision) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("拟发行资产", style: const TextStyle(color: Colors.grey)),
              Text(id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
            ],
          ),
          const Divider(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("面值数量", style: const TextStyle(color: Colors.grey)),
              Text(supply.toStringAsFixed(precision),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text("精度: $precision", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          )
        ],
      ),
    );
  }

  Widget _buildSignStatusCard(int currentCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.people, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "当前已收集到 $currentCount 个有效签名。若达到多签阈值，资产将自动入账。",
              style: const TextStyle(fontSize: 13, color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHashItem(BuildContext context, String title, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              Expanded(child: Text(hash, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), maxLines: 2)),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.blueGrey),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  Tools.showToast(context, "已复制哈希");
                },
              )
            ],
          ),
        ),
      ],
    );
  }
}