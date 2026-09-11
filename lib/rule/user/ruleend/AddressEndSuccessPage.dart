import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';


/// 【新增】AddressEnd 专属详情页——故意不采用其他规则成功页那种"庆祝"
/// 风格（绿色对勾/彩色图标），因为这不是一件值得庆祝的事：地址已经被
/// 判定为死亡地址，这里用偏肃穆/警示的红灰配色，明确告知用户结果。
class AddressEndSuccessPage extends StatelessWidget {
  final Map<String, dynamic> ruleData;

  const AddressEndSuccessPage({super.key, required this.ruleData});

  @override
  Widget build(BuildContext context) {
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String address = ruleData['from'] ?? "";

    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        address = inner['from'] ?? address;
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
      }
    } catch (e) {
      LogObj.log("AddressEndSuccessPage 解析失败: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("地址状态：已终止"),
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
            const Icon(Icons.block_rounded, color: Colors.red, size: 70),
            const SizedBox(height: 16),
            Trans("此地址已被全网标记为死亡地址",
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Trans("此地址此后将无法再签发任何交易，操作已不可撤销。",
                style: const TextStyle(fontSize: 12.5, color: Colors.grey), ),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD9D9)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "AddressEnd"),
                  const Divider(height: 32),
                  _infoRow(context, "已终止地址", address, isAddr: true, canCopy: true),
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
                      color: canCopy ? Colors.redAccent : Colors.black87,
                    ),
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.redAccent),
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
