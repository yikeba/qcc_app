import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'AssetFileStorage.dart';
import 'AssetIssueSuccessPage.dart';
import 'AssetMultiSigProposalPage.dart'; // ✅ 导入多签提案适配页
import '../../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';
import '../../utile/LogObj.dart';

class AssetStatusCenterWidget extends StatefulWidget {
  const AssetStatusCenterWidget({super.key});

  @override
  State<AssetStatusCenterWidget> createState() => _AssetStatusCenterWidgetState();
}

class _AssetStatusCenterWidgetState extends State<AssetStatusCenterWidget> {
  late Future<List<dynamic>> _assetsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _assetsFuture = AssetFileStorage.getAllAssets().catchError((e) {
        LogObj.log("读取资产列表失败: $e");
        return [];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Trans("资产状态中心"),
        centerTitle: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _assetsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Trans("数据加载异常"));
          }

          final assets = snapshot.data ?? [];

          if (assets.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Trans("暂无已发行的资产容器"),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: assets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final rawItem = assets[index];
              if (rawItem is! Map) return const SizedBox();

              final item = Map<String, dynamic>.from(rawItem);
              return _buildAssetCard(item);
            },
          );
        },
      ),
    );
  }

  Widget _buildAssetCard(Map<String, dynamic> asset) {
    // 1. 字段解析
    final String assetId = (asset['assetId'] ?? "Unknown").toString();
    final String owner = (asset['owner'] ?? "").toString();
    final int precision = int.tryParse(asset['precision']?.toString() ?? "9") ?? 9;

    // ✅ 识别是否为多签地址 (以 'M' 开头)
    final bool isMultiSig = owner.startsWith('M');

    num rawSupply = 0;
    try {
      var s = asset['initialSupply'];
      if (s != null) {
        rawSupply = s is num ? s : num.parse(s.toString());
      }
    } catch (_) {
      rawSupply = 0;
    }

    final double displayAmount = rawSupply / pow(10, precision);
    final bool isMintable = asset['mintable'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        onTap: () {
          // ✅ 核心跳转分流逻辑
          Widget targetPage;
          if (isMultiSig) {
            // 如果地址是 M 开头，跳转到提案详情页（显示复制 Hash 逻辑）
            targetPage = AssetMultiSigProposalPage(
              txHash: asset['txHash'],
            );
          } else {
            // 普通单签发行，跳转到成功结果页
            targetPage = AssetIssueSuccessPage(ruleData: {
              "ruleJson": jsonEncode(asset),
              "txHash": asset['txHash'] ?? "N/A"
            });
          }

          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetPage),
          ).then((_) => _refresh());
        },
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isMultiSig ? Colors.orange.withOpacity(0.1) : Colors.blueAccent.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
              isMultiSig ? Icons.account_tree_outlined : Icons.token,
              color: isMultiSig ? Colors.orange : Colors.blueAccent
          ),
        ),
        title: Row(
          children: [
            Text(assetId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(width: 8),
            // ✅ 视觉标签区分
            if (isMultiSig)
              _buildBadge("多签提案", Colors.orange)
            else if (isMintable)
              _buildBadge("MINTABLE", Colors.green),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Total: ${_formatValue(displayAmount, precision)}",
                style: TextStyle(color: Colors.blueGrey[700], fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                "Owner: ${owner.length > 20 ? '${owner.substring(0, 10)}...' : owner}",
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Trans(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  String _formatValue(double val, int p) {
    try {
      String str = val.toStringAsFixed(p);
      if (!str.contains('.')) return str;
      return str.replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
    } catch (e) {
      return val.toString();
    }
  }
}