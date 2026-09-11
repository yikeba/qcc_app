import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';

/// 【新增】TagRule 专属成功/详情页——和 DeveloperRuleSuccessPage /
/// MerchantRuleSuccessPage / PayCallRuleSuccessPage 保持同样的"两种数据源
/// 兼容"写法：提交成功后直接传 HTTP 响应体（resData['data'] 是二层 JSON
/// 字符串），从 UserRuleFileStorage 本地记录重新打开时传的是已拍平记录
/// （顶层直接有 ruleJson 字符串）。
///
/// 【新增】归属地址(from/owner)旁边带上本机备注名——跟 Common/Authorized/
/// SuperNode 质押 widget、PledgeRecordsWidget 里同样的
/// QccStorage.getAllWalletNames() 查法，没有备注名就还是只显示地址。
/// 因为要异步查名字，这里从 StatelessWidget 改成了 StatefulWidget。
class TagRuleSuccessPage extends StatefulWidget {
  final Map<String, dynamic> ruleData;

  const TagRuleSuccessPage({super.key, required this.ruleData});

  @override
  State<TagRuleSuccessPage> createState() => _TagRuleSuccessPageState();
}

class _TagRuleSuccessPageState extends State<TagRuleSuccessPage> {
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  @override
  Widget build(BuildContext context) {
    final ruleData = widget.ruleData;
    String txHash = ruleData['txHash'] ?? ruleData['id'] ?? "";
    String owner = ruleData['from'] ?? "";
    String tagName = "";

    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        owner = inner['from'] ?? owner;
        if (inner['ruleJson'] != null) {
          innerParams = jsonDecode(inner['ruleJson']);
        } else {
          innerParams = inner;
        }
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }

      if (innerParams != null) {
        tagName = innerParams['tagName'] ?? tagName;
        owner = innerParams['owner'] ?? owner;
      }
    } catch (e) {
      LogObj.log("TagRuleSuccessPage 解析失败: $e");
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("标签注册详情"),
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
            const Icon(Icons.sell_rounded, color: Colors.purple, size: 70),
            const SizedBox(height: 16),
            Trans("标签资产已注册", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEBE1FF)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "TagRule"),
                  const Divider(height: 32),
                  _infoRow(context, "标签名称", tagName.isEmpty ? "--" : tagName, canCopy: tagName.isNotEmpty),
                  const Divider(height: 32),
                  _infoRow(context, "归属地址", owner, isAddr: true, canCopy: true, nick: _walletNames[owner]),
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
      {bool isAddr = false, bool canCopy = false, String? nick}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 【新增】有本机备注名就在地址上面单独显示一行，没有就跳过。
                if (nick != null && nick.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      nick,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        displayValue,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: nick != null && nick.isNotEmpty ? FontWeight.normal : FontWeight.bold,
                          fontSize: nick != null && nick.isNotEmpty ? 12 : 14,
                          fontFamily: 'monospace',
                          color: canCopy
                              ? Colors.blueAccent
                              : (nick != null && nick.isNotEmpty ? Colors.grey[600] : Colors.black87),
                        ),
                      ),
                    ),
                    if (canCopy) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                    ]
                  ],
                ),
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