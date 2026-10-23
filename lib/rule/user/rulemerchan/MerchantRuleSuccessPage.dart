import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';
import '../UserRuleFileStorage.dart';

/// 商户规则详情页。
///
/// 两个入口：
///   1. MerchantRuleWidget 发布后、确认上链时跳转进来（chainStatus=confirmed）；
///   2. 规则状态列表点进来，此时记录可能仍是 pending，或者是没有 chainStatus
///      的旧记录。
/// 所以页面不能默认写"已激活"，要按链上状态显示；不是 confirmed 时，进入页面
/// 先自动查一次 /v1/hash/{txHash}，也可以手动刷新。
class MerchantRuleSuccessPage extends StatefulWidget {
  final Map<String, dynamic> ruleData;

  const MerchantRuleSuccessPage({super.key, required this.ruleData});

  @override
  State<MerchantRuleSuccessPage> createState() => _MerchantRuleSuccessPageState();
}

class _MerchantRuleSuccessPageState extends State<MerchantRuleSuccessPage> {
  late String _chainStatus; // confirmed / failed / pending（旧记录无字段时按 pending）
  int? _blockHeight;
  String? _chainMsg;
  bool _checking = false;

  String get _txHash => (widget.ruleData['txHash'] ?? widget.ruleData['id'] ?? "").toString();

  @override
  void initState() {
    super.initState();
    _chainStatus = (widget.ruleData['chainStatus'] ?? 'pending').toString();
    final bh = widget.ruleData['blockHeight'];
    _blockHeight = bh is num ? bh.toInt() : int.tryParse("${bh ?? ''}");
    _chainMsg = widget.ruleData['chainMsg']?.toString();
    if (_chainStatus != 'confirmed' && _txHash.isNotEmpty) _check(silent: true);
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final st = await QccTxStatusService.checkOnce(_txHash);
      if (!mounted) return;
      setState(() {
        _chainStatus = st.state.name;
        if (st.blockHeight != null) _blockHeight = st.blockHeight;
        _chainMsg = st.message;
      });
      if (st.isFinal) {
        // 【假设】saveRuleTask 按 txHash/id 合并已有记录；若不去重会多出一条。
        await UserRuleFileStorage.saveRuleTask({
          ...widget.ruleData,
          'chainStatus': st.state.name,
          if (st.blockHeight != null) 'blockHeight': st.blockHeight,
          if (st.message != null) 'chainMsg': st.message,
        });
      }
      if (!silent && mounted && !st.isFinal) {
        Tools.showToast(context, "尚未上链${st.message != null ? '（${st.message}）' : ''}");
      }
    } catch (e) {
      if (!silent && mounted) Tools.showToast(context, "查询失败：$e", isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- 商户规则解析逻辑（兼容旧格式 data 字段与新格式 ruleJson）---
    final ruleData = widget.ruleData;
    String address = (ruleData['from'] ?? "").toString();
    bool gasDelegation = false;
    String assetId = "";

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
        address = (innerParams['address'] ?? address).toString();
        gasDelegation = innerParams['gasDelegation'] == true;
        assetId = (innerParams['assetId'] ?? "").toString();
      }
    } catch (e) {
      LogObj.log("MerchantRuleSuccessPage 解析失败: $e");
    }

    final bool confirmed = _chainStatus == 'confirmed';
    final bool failed = _chainStatus == 'failed';

    // 状态头：图标 / 标题 / 副标题都跟着链上状态走
    IconData headIcon;
    Color headColor;
    String headTitle;
    String headSub;
    if (confirmed) {
      headIcon = Icons.storefront_rounded;
      headColor = Colors.indigo;
      headTitle = gasDelegation ? "商户 Gas 到付已生效" : "商户规则已上链";
      headSub = _blockHeight != null ? "已打包进区块 #$_blockHeight" : "链上已查到该规则交易";
    } else if (failed) {
      headIcon = Icons.error_outline;
      headColor = Colors.red;
      headTitle = "商户规则上链失败";
      headSub = _chainMsg ?? "未知原因";
    } else {
      headIcon = Icons.hourglass_top_rounded;
      headColor = Colors.orange;
      headTitle = "规则已受理，等待上链";
      headSub = "上链前规则不生效";
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("商户规则详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!confirmed)
            IconButton(
              tooltip: "查询上链状态",
              icon: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, color: Colors.black87),
              onPressed: _checking ? null : () => _check(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(headIcon, color: headColor, size: 70),
            const SizedBox(height: 16),
            Text(headTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(headSub, style: TextStyle(fontSize: 12, color: failed ? Colors.red : Colors.grey)),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD1D9E6)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "MerchantRule"),
                  const Divider(height: 32),
                  _infoRow(context, "Gas代付策略", gasDelegation ? "已开启 (Delegation)" : "未开启",
                      valueColor: gasDelegation ? Colors.green : Colors.grey),
                  const Divider(height: 32),
                  // assetId 为空表示不限资产（与发布页"不填则默认为所有资产"一致）
                  _infoRow(context, "绑定资产", assetId.isEmpty ? "全部资产" : assetId),
                  const Divider(height: 32),
                  _infoRow(context, "商户地址", address, isAddr: true, canCopy: true),
                  const Divider(height: 32),
                  _infoRow(context, "链上状态", confirmed ? "已上链" : (failed ? "失败" : "等待上链"),
                      valueColor: confirmed ? Colors.green : (failed ? Colors.red : Colors.orange)),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHashSection(context, _txHash),

            if (confirmed && _txHash.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text("链上查询"),
                  onPressed: () => QccTxStatusService.openChainUrl(context, _txHash),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value,
      {bool isAddr = false, bool canCopy = false, Color? valueColor}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy
                ? () {
              Clipboard.setData(ClipboardData(text: value));
              Tools.showToast(context, "内容已复制");
            }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(displayValue,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: valueColor ?? (canCopy ? Colors.blue : Colors.black87),
                      )),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.blue),
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
        Trans("交易哈希 (Transaction Hash)", style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                Expanded(child: Text(hash, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}