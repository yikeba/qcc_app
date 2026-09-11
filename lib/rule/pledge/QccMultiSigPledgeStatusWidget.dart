import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utile/LogObj.dart';
import '../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';

class QccMultiSigPledgeStatusWidget extends StatelessWidget {
  final Map<String, dynamic> rawData; // 传入您提供的完整 JSON 数据

  const QccMultiSigPledgeStatusWidget({super.key, required this.rawData});

  @override
  Widget build(BuildContext context) {
    // 1. 数据安全性检查与提取
    final List sessions = rawData['data']?['pendingUniversalSessions'] ?? [];
    if (sessions.isEmpty) {
      return _buildEmptyState();
    }

    // 取第一个正在进行的任务（或者根据业务逻辑过滤）
    final session = sessions.first;
    final int current = session['currentCount'] ?? 0;
    final int threshold = session['threshold'] ?? 0;
    final List owners = session['owners'] ?? [];
    final List signedOwners = session['signedOwners'] ?? [];

    // 2. 解析 ruleJson 获取业务详情
    Map<String, dynamic> pledgeDetail = {};
    try {
      String jsonStr = session['ruleData']?['ruleJson'] ?? "{}";
      pledgeDetail = jsonDecode(jsonStr);
    } catch (e) {
      LogObj.log("解析 ruleJson 失败: $e");
    }

    double progress = current / threshold;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：业务概览
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.purple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Trans("多签质押提案进度", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                      child: Text("$current / $threshold", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            ),
          ),

          // 中间：质押金额
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildInfoRow("质押金额", "${(pledgeDetail['amount'] ?? 0) ~/ 1000000000} QCC", isPrice: true),
                _buildInfoRow("目标地址", _shortAddr(pledgeDetail['address'] ?? "")),
                _buildInfoRow("提案哈希", _shortAddr(session['txHash'] ?? "")),
                const Divider(height: 32),

                // 签署成员状态列表
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Trans("成员签名状态：", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 12),
                ...owners.map((addr) {
                  bool hasSigned = signedOwners.contains(addr);
                  return _buildMemberTile(addr, hasSigned);
                }).toList(),
              ],
            ),
          ),

          // 底部提示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
            child: Center(
              child: Trans(current >= threshold ? "提案已完成，等待入账" : "还需 ${threshold - current} 人签署即可生效",
                  style: TextStyle(color: current >= threshold ? Colors.green : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isPrice = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
          Text(value, style: TextStyle(
              fontSize: isPrice ? 18 : 13,
              fontWeight: isPrice ? FontWeight.bold : FontWeight.normal,
              color: isPrice ? Colors.orange : Colors.black87
          )),
        ],
      ),
    );
  }

  Widget _buildMemberTile(String address, bool signed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(signed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: signed ? Colors.green : Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(address, style: TextStyle(fontSize: 11, color: signed ? Colors.black87 : Colors.grey, fontFamily: 'monospace'))),
          if (signed) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
            child: const Trans("已签", style: TextStyle(color: Colors.green, fontSize: 9)),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Trans("暂无待处理的多签质押提案"));
  }

  String _shortAddr(String addr) {
    if (addr.length < 16) return addr;
    return "${addr.substring(0, 8)}...${addr.substring(addr.length - 8)}";
  }
}