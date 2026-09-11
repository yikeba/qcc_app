import 'package:flutter/material.dart';
import 'AssetFileStorage.dart'; // ✅ 唯一合法的数据源
import 'AssetIssueSuccessPage.dart';
import '../../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';

class AssetMultiSigStatusWidget extends StatefulWidget {
  const AssetMultiSigStatusWidget({super.key});

  @override
  State<AssetMultiSigStatusWidget> createState() => _AssetMultiSigStatusWidgetState();
}

class _AssetMultiSigStatusWidgetState extends State<AssetMultiSigStatusWidget> {
  late Future<List<dynamic>> _assetsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      // ✅ 严格从 AssetFileStorage 获取本地保存的资产/提案记录
      _assetsFuture = AssetFileStorage.getAllAssets();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Trans("资产提案状态"),
        centerTitle: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _assetsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Trans("本地记录读取失败"));
          }

          final allRecords = snapshot.data ?? [];

          if (allRecords.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_edu_outlined, size: 50, color: Colors.grey),
                  SizedBox(height: 12),
                  Trans("暂无任何资产发行或多签提案"),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: allRecords.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                // 安全转化
                final item = Map<String, dynamic>.from(allRecords[index]);
                return _buildStatusCard(context, item);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, Map<String, dynamic> item) {
    String assetId = (item['assetId'] ?? "Unknown").toString();
    String txHash = (item['txHash'] ?? "N/A").toString();

    // QCC 逻辑：ACCEPTED 代表已入池但未最终生效（多签提案中）
    bool isProposal = item['status'] == "ACCEPTED";

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // ✅ 修正：必须使用 BorderSide
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Text(assetId, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const Spacer(),
            // 状态标签
            _buildStatusBadge(isProposal),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text("TxHash: ${txHash.length > 20 ? '${txHash.substring(0, 15)}...' : txHash}",
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey)),
            const SizedBox(height: 4),
            Text("Owner: ${item['owner'] ?? "---"}",
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssetIssueSuccessPage(ruleData: item),
            ),
          ).then((_) => _refresh());
        },
      ),
    );
  }

  Widget _buildStatusBadge(bool isProposal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isProposal ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: isProposal
          ? const Trans("提案待生效")
          : const Trans("规则已激活"),
    );
  }
}