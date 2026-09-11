import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';

/// 【新增】PayCallRule 专属成功/详情页——之前 PayCallRuleWidget 提交成功后
/// 跳的是通用的 QccRuleInitiatedPage（只显示业务类型+Hash+二维码，看不到
/// 回调地址、监听资产这些真正有用的字段）。这里参照
/// DeveloperRuleSuccessPage / MerchantRuleSuccessPage 的样式和"两种数据源
/// 兼容"写法补上专属页面。
class PayCallRuleSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const PayCallRuleSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    // --- 兼容两种数据来源 ---
    // 1. 提交成功后，PayCallRuleWidget 直接把 HTTP 响应体（resData）传进来：
    //    resData['data'] 是一层 JSON 字符串，里面才是真正的 ruleJson。
    // 2. 从 UserRuleFileStorage 本地记录重新打开时传进来的、已经拍平过的
    //    记录：顶层直接就有 ruleJson 字符串，没有 data 字段。
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String address = ruleData['from'] ?? "";
    String callUrl = "";
    String assetId = "QCC";

    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        if (inner['ruleJson'] != null) {
          innerParams = jsonDecode(inner['ruleJson']);
        } else {
          innerParams = inner;
        }
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }

      if (innerParams != null) {
        address = innerParams['address'] ?? address;
        callUrl = innerParams['callUrl'] ?? callUrl;
        assetId = innerParams['assetId'] ?? assetId;
      }
    } catch (e) {
      LogObj.log("PayCallRuleSuccessPage 解析失败: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("支付回调规则详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.blue, size: 70),
            const SizedBox(height: 16),
            Trans("支付回调已配置", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6E4FF)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "PayCallRule"),
                  const Divider(height: 32),
                  _infoRow(context, "监听资产", assetId),
                  const Divider(height: 32),
                  _infoRow(context, "回调地址", callUrl.isEmpty ? "--" : callUrl,
                      canCopy: callUrl.isNotEmpty),
                  const Divider(height: 32),
                  _infoRow(context, "发起地址", address, isAddr: true, canCopy: true),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHashSection(context, txHash),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value,
      {bool isAddr = false, bool canCopy = false}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy
                ? () {
              Clipboard.setData(ClipboardData(text: value));
              Tools.showToast(context, "已复制到剪贴板");
            }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: canCopy ? Colors.blueAccent : Colors.black87,
                    ),
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHashSection(BuildContext context, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("交易哈希", style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                Expanded(
                    child: Text(hash,
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}