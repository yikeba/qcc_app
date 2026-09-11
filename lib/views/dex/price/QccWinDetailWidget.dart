import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';
import '../QccOpenDataManager.dart';

class QccWinDetailWidget extends StatelessWidget {
  final String txHash; // Win 交易本身的哈希

  const QccWinDetailWidget({super.key, required this.txHash});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Trans("成交明细回执"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: QccOpenDataManager.getTransactionDetail(txHash),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }

          final winData = snapshot.data;
          if (winData == null) {
            return _buildErrorState();
          }

          return _buildContent(context, winData);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> win) {
    // 1. 基础数据解析
    String payAsset = win['assetId'] ?? "USDS";
    double payRaw = (win['amount'] as num).toDouble();
    double payHuman = QccAssetService().getHumanAmountNum(payAsset, payRaw);

    String openHash = win['matcHash'] ?? ""; // 关联的 Open 单
    String time = DateFormat('yyyy-MM-dd HH:mm:ss').format(
        DateTime.fromMillisecondsSinceEpoch(win['timestamp'] ?? 0)
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 状态头部
          _buildStatusHeader(payHuman, payAsset),

          const SizedBox(height: 24),

          // 核心对账卡片
          _buildDetailCard([
            _infoRow("支付资产", "$payHuman $payAsset"),
            _infoRow("成交类型", "现货碰撞 (Win)"),
            _infoRow("成交时间", time),
            const Divider(height: 30),
            _infoRow("交易哈希 (TxID)", txHash, isHash: true),
            _infoRow("关联挂单 (Open)", openHash, isHash: true),
          ]),

          const SizedBox(height: 24),

          // 提示：Win 交易特性
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Trans(
                    "此交易为原子性撮合，一旦上链无法撤回。获得的资产已实时结算至您的状态机余额中。",
                    style: TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // 联动功能：查看关联的 Open 单
          if (openHash.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () {
                // 这里可以跳转到之前写的 Open 明细页进行反向查询
                LogObj.log("跳转查看关联挂单: $openHash");
              },
              icon: const Icon(Icons.link),
              label: const Trans("查看关联挂单明细"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: Colors.blue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(double amount, String asset) {
    return Column(
      children: [
        const CircleAvatar(
          radius: 30,
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white, size: 35),
        ),
        const SizedBox(height: 16),
        const Trans("成交成功", style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 8),
        Text(
            "-$amount $asset",
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)
        ),
      ],
    );
  }

  Widget _buildDetailCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)],
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow(String label, String value, {bool isHash = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: isHash ? 'monospace' : null,
                  color: isHash ? Colors.blueGrey : Colors.black87,
                  fontWeight: FontWeight.w500
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Trans("无法获取交易详情，请检查网络或稍后再试"),
        ],
      ),
    );
  }
}