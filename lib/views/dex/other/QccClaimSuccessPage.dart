import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../utile/Tools.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';

class QccClaimSuccessPage extends StatelessWidget {
  final Map<String, dynamic> result; // 包含 win 交易返回的数据及预估金额

  const QccClaimSuccessPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    // 1. 数据提取
    final String txHash = result['txHash'] ?? "N/A";
    final String assetId = result['assetId'] ?? "USDS";
    final String baseAsset = result['baseAssetId'] ?? "";
    final String amount = result['estimatedAmount'] ?? "0.00"; // 认领虽是 0，但展示预估收益
    final String unlockTime = result['unlockTime'] ?? "";
    final String time = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF004D40), Color(0xFF00695C)], // 深邃绿，代表财富与增长
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
                      const SizedBox(height: 10),
                      _buildSuccessIcon(),
                      const SizedBox(height: 16),
                      const Trans("红利认领成功",
                          style: TextStyle(color: Color(0xFFFFD700), fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const Text("Dividend Claimed Successfully",
                          style: TextStyle(color: Colors.white54, fontSize: 10)),

                      const SizedBox(height: 40),

                      // ✅ 财富到账卡片
                      _buildWealthCard(amount, assetId, baseAsset, unlockTime, time),

                      const SizedBox(height: 30),

                      // ✅ 链上存证 Hash
                      _buildHashBox(context, txHash),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              // ✅ 底部操作
              _buildBottomButton(context),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI 构建块 ---

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
          const Trans("收益凭证", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.circle, color: const Color(0xFFFFD700).withOpacity(0.1), size: 100),
        const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFD700), size: 50),
        Positioned(
          right: 10, top: 10,
          child: Icon(Icons.auto_awesome, color: Colors.amber.shade200, size: 24),
        )
      ],
    );
  }

  Widget _buildWealthCard(String amount, String assetId, String baseAsset, String unlock, String time) {
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
          const Trans("预估红利收益", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text(
            "+ $amount $assetId",
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32), fontFamily: 'monospace'),
          ),
          const SizedBox(height: 20),
          const Divider(thickness: 1, color: Color(0xFFF5F5F5)),
          const SizedBox(height: 20),
          _infoRow("认领资产", baseAsset),
          _infoRow("解冻时间", unlock), // 资产方设置的截止期即为解冻期
          _infoRow("认领协议", "QCC-WIN-COLLISION"),
          const SizedBox(height: 24),
          Text("结算时间: $time", style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
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
              Icon(Icons.verified_user_rounded, color: Color(0xFFFFD700), size: 14),
              SizedBox(width: 8),
              Trans("链上认领存证 (TX Hash)", style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(hash, style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.4)),
          const SizedBox(height: 12),
          const Text("* 该认领指令已固化至 QCC 公链，收益分配受状态机强制保护。",
              style: TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildBottomButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: const Color(0xFF004D40),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Trans("确认并返回", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }
}