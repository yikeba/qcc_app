import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../utile/Tools.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';

class QccWinSuccessSheet extends StatelessWidget {
  final Map<String, dynamic> responseData;

  const QccWinSuccessSheet({super.key, required this.responseData});

  /// 快捷唤起方法
  static void show(BuildContext context, String responseBody) {
    try {
      final Map<String, dynamic> res = jsonDecode(responseBody);
      // 🐛 返回的 status 是小写 accepted，code 才是大写 ACCEPTED；
      // 原判断 status=='ACCEPTED' 永不成立，每次成交都提示"未被接受"
      final String code = (res['code'] ?? res['status'] ?? '').toString().toUpperCase();
      if (code == 'ACCEPTED') {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible: false, // 强制用户点击按钮关闭，防止误触
          backgroundColor: Colors.transparent,
          builder: (_) => QccWinSuccessSheet(responseData: res),
        );
      } else {
        Tools.showToast(context, "交易未被接受: ${res['msg']}");
      }
    } catch (e) {
      Tools.showToast(context, "解析成功数据失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 从返回数据中解析内部的转义 JSON
    final String txHash = responseData['txHash'] ?? "";
    final String msg = responseData['msg'] ?? "Transaction pooled successfully";

    Map<String, dynamic> txData = {};
    try {
      final d = responseData['data'];
      txData = d is Map ? Map<String, dynamic>.from(d) : Map<String, dynamic>.from(jsonDecode(d));
    } catch (e) {
      debugPrint("解析 txData 失败: $e");
    }

    // 2. 提取核心展示字段
    // 注意：如果你的 amount 在链上放大了 10^9 倍，这里需要除以 1000000000.0
    // 根据你提供的 JSON，amount 是 12000，我这里先直接显示，请根据实际精度调整

    final String assetId = txData['assetId'] ?? "Unknown";
    double amount=QccAssetService().getHumanAmountNum(assetId,txData["amount"] );
    final String matchHash = txData['matcHash'] ?? "";
    final int timestamp = txData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;

    // 格式化时间
    final String timeString = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(timestamp));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ 顶部成功动画/图标
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 64),
          ),
          const SizedBox(height: 20),

          // ✅ 标题与提示
          Trans(responseData['chainStatus'] == 'confirmed' ? "成交已上链" : "交易已广播 (ACCEPTED)",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 13)),

          const SizedBox(height: 30),

          // ✅ 交易明细凭证卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildInfoRow("支付金额", "$amount $assetId", valueColor: Colors.orange.shade800, isBold: true),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

                _buildInfoRow("交易类型", txData['txType']?.toString().toUpperCase() ?? "WIN"),
                const SizedBox(height: 12),

                _buildInfoRow("交易时间", timeString),
                const SizedBox(height: 12),

                // 目标 Open 单哈希 (截断显示)
                _buildInfoRow(
                    "目标挂单 (Match)",
                    matchHash.length > 12 ? "${matchHash.substring(0, 6)}...${matchHash.substring(matchHash.length - 6)}" : matchHash
                ),
                const SizedBox(height: 12),

                // 本次 Win 交易哈希 (截断显示)
                _buildInfoRow(
                    "本次哈希 (TxHash)",
                    txHash.length > 12 ? "${txHash.substring(0, 6)}...${txHash.substring(txHash.length - 6)}" : txHash
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // ✅ 底部操作按钮组
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: () {
                    Tools.copytext(context,txHash);
                    Tools.showToast(context, "交易哈希已复制");
                  },
                  child: const Trans("复制哈希", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    // 1. 关闭当前成功弹窗
                    Navigator.pop(context);
                    // 2. 如果当前还在 Win 详情页，也一并关闭，退回到市场列表
                    // Navigator.pop(context);
                  },
                  child: const Trans("完成", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),

          // 适配全面屏底部安全区
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }

  /// 统一样式的明细行
  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'monospace', // 使用等宽字体显示哈希和金额更专业
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}