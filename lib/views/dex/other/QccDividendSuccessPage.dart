import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../utile/Tools.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';

class QccDividendSuccessPage extends StatelessWidget {
  final Map<String, dynamic> result; // 统一接收标准化存储的 Map

  const QccDividendSuccessPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    // 1. 数据解析 (确保类型安全)
    final String txHash = result['id'] ?? "N/A";
    final String assetId = result['quoteAssetId'] ?? "USDS";
    final String targetAsset = result['baseAssetId'] ?? "TOKEN";
    final int amount = result['amount'] ?? 0;
    final double rate = double.tryParse(result['rate'].toString()) ?? 0.0;
    final String memo = result['memo'] ?? "";
    final String time = DateFormat('yyyy-MM-dd HH:mm:ss').format(
        DateTime.fromMillisecondsSinceEpoch(result['timestamp'] ?? DateTime.now().millisecondsSinceEpoch)
    );
    final price=QccAssetService().getHumanAmount(assetId, amount);
    return Scaffold(
      // 沉浸式深红背景
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB71C1C), Color(0xFF7F0000)], // 极具质感的深红
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildFestiveIcon(), // 顶部装饰图标
                      const SizedBox(height: 16),
                      const Trans("分红公告已发布",
                          style: TextStyle(color: Color(0xFFFFD700), fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const Text("QCC Decentralized Dividend Certificate",
                          style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
                      const SizedBox(height: 40),

                      // ✅ 核心证书卡片 (截图重心)
                      _buildCertCard(price, assetId, targetAsset, rate, time),

                      const SizedBox(height: 30),

                      // ✅ 认领 Hash 盒
                      _buildHashBox(context, txHash),

                      const SizedBox(height: 20),

                      // 备注信息
                      if (memo.isNotEmpty) _buildMemo(memo),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // ✅ 底部操作按钮
              _buildBottomButton(context, txHash),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI 组件集 ---

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const Trans("分红确认", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(width: 48), // 占位保持对称
        ],
      ),
    );
  }

  Widget _buildFestiveIcon() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.1),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5), width: 2),
      ),
      child: const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 50),
    );
  }

  Widget _buildCertCard(String amount, String assetId, String target, double rate, String time) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          const Trans("发放红利总额", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text(
            "$amount $assetId",
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFFB71C1C), fontFamily: 'monospace', letterSpacing: -1),
          ),
          const SizedBox(height: 20),
          const Divider(thickness: 1, color: Color(0xFFF5F5F5)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _itemCert("派息比例", "1 $target = $rate $assetId"),
              _itemCert("结算共识", "QCC-OPEN"),
            ],
          ),
          const SizedBox(height: 24),
          Text("确认时间: $time", style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _itemCert(String label, String value) {
    return Column(
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildHashBox(BuildContext context, String hash) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security, color: Color(0xFFFFD700), size: 14),
              SizedBox(width: 8),
              Trans("链上唯一认领凭证 (Hash)", style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
              hash,
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace', height: 1.4)
          ),
          const SizedBox(height: 12),
          const Text("* 投资者凭借此 Hash 在 7 天内完成认领，逾期将自动退回。",
              style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMemo(String memo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        "“ $memo ”",
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontStyle: FontStyle.italic, fontWeight: FontWeight.w300),
      ),
    );
  }

  Widget _buildBottomButton(BuildContext context, String hash) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: const Color(0xFF8B0000),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            shadowColor: Colors.black45,
          ),
          icon: const Icon(Icons.copy_all_rounded, size: 22),
          label: const Trans("复制凭证并发布公告", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: hash));
            Tools.showToast(context, "凭证已复制，请发布存证公告");
          },
        ),
      ),
    );
  }
}