import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';
import '../../utile/LogObj.dart';

class AssetIssueSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const AssetIssueSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    // 基础数据提取
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";

    // 初始化展示变量
    String assetId = "---";
    int precision = 9;
    num rawSupply = 0;
    String owner = ruleData['from'] ?? "---";
    bool mintable = true;
    bool freezable = true;

    try {
      Map<String, dynamic>? meta;
      // 兼容公链返回的原始 data 字符串或本地缓存后的 ruleJson
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        meta = (inner['ruleJson'] != null) ? jsonDecode(inner['ruleJson']) : inner;
      } else if (ruleData['ruleJson'] != null) {
        meta = jsonDecode(ruleData['ruleJson']);
      }

      // 如果存在 AssetMintRule 包装，进入资产元数据层
      if (meta != null && meta.containsKey('assetMeta')) {
        meta = meta['assetMeta'];
      }

      if (meta != null) {
        assetId = meta['assetId'] ?? "Unknown";
        precision = meta['precision'] ?? 9;
        // 兼容 String 或 Number 类型
        rawSupply = meta['initialSupply'] is String
            ? num.parse(meta['initialSupply'])
            : (meta['initialSupply'] ?? 0);
        owner = meta['owner'] ?? owner;
        mintable = meta['mintable'] ?? true;
        freezable = meta['freezable'] ?? true;
      }
    } catch (e) {
      LogObj.log("AssetIssueSuccessPage 解析异常: $e");
    }

    // 根据精度计算显示的 Token 数量
    double displaySupply = rawSupply / pow(10, precision);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("资产发行结果"),
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          // 逻辑：直接返回到钱包首页
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Trans("代币发行交易已受理", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  // 使用本地实现的格式化方法
                  _infoRow(context, "初始发行总量", "${_formatAmount(displaySupply, precision)} $assetId"),
                  const Divider(height: 30),
                  _infoRow(context, "发行精度", "$precision 位"),
                  const Divider(height: 30),
                  _infoRow(context, "所有者地址 (Owner)", owner, isAddr: true, canCopy: true),
                  const Divider(height: 30),
                  _infoRow(context, "后续增发 (Mintable)", mintable ? "允许" : "禁止"),
                  const Divider(height: 30),
                  _infoRow(context, "资产冻结 (Freezable)", freezable ? "允许" : "禁止"),
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

  // --- 内部逻辑辅助 ---

  /// 替代 Tools.formatAmount 的本地实现
  /// 逻辑：保留对应精度的小数位，并去除末尾多余的零
  String _formatAmount(double amount, int precision) {
    String str = amount.toStringAsFixed(precision);
    if (!str.contains('.')) return str;
    // 正则去除末尾无用的 0 和小数点
    return str.replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
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
                          // 使用 w900 替代 FontWeight.black
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