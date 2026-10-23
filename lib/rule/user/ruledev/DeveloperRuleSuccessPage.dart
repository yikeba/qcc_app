import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';
import '../UserRuleFileStorage.dart';

/// 开发者规则详情页。
///
/// 入口同商户规则：发布后上链确认跳进来（confirmed），或从规则状态列表点进来
/// （可能是 pending / 旧记录）。非 confirmed 时进页面自动查一次链上状态。
class DeveloperRuleSuccessPage extends StatefulWidget {
  final Map<String, dynamic> ruleData;

  const DeveloperRuleSuccessPage({super.key, required this.ruleData});

  @override
  State<DeveloperRuleSuccessPage> createState() => _DeveloperRuleSuccessPageState();
}

class _DeveloperRuleSuccessPageState extends State<DeveloperRuleSuccessPage> {
  static const double _fixedRewardRate = 0.2;

  late String _chainStatus; // confirmed / failed / pending
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
        // 【假设】saveRuleTask 按 txHash/id 合并已有记录
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
    final ruleData = widget.ruleData;
    // 原来 ruleJson 分支兜底是 0.3，data 分支是 0.2，同一字段两个默认值；
    // 统一为系统固定 20%。
    double rewardRate = _fixedRewardRate;
    String address = (ruleData['from'] ?? "").toString();

    try {
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        address = (inner['address'] ?? address).toString();
        rewardRate = (inner['rewardRate'] ?? rewardRate).toDouble();
        if (inner['ruleJson'] != null) {
          var ruleObj = jsonDecode(inner['ruleJson']);
          address = (ruleObj['address'] ?? address).toString();
          rewardRate = (ruleObj['rewardRate'] ?? rewardRate).toDouble();
        }
      } else if (ruleData['ruleJson'] != null) {
        var ruleObj = jsonDecode(ruleData['ruleJson']);
        address = (ruleObj['address'] ?? address).toString();
        rewardRate = (ruleObj['rewardRate'] ?? rewardRate).toDouble();
      }
    } catch (e) {
      LogObj.log("DeveloperRuleSuccessPage 解析数据异常: $e");
    }

    final bool confirmed = _chainStatus == 'confirmed';
    final bool failed = _chainStatus == 'failed';

    IconData headIcon;
    Color headColor;
    String headTitle;
    String headSub;
    if (confirmed) {
      headIcon = Icons.verified_user;
      headColor = Colors.blueAccent;
      headTitle = "开发者身份已生效";
      headSub = _blockHeight != null ? "已打包进区块 #$_blockHeight" : "链上已查到该规则交易";
    } else if (failed) {
      headIcon = Icons.error_outline;
      headColor = Colors.red;
      headTitle = "开发者规则上链失败";
      headSub = _chainMsg ?? "未知原因";
    } else {
      headIcon = Icons.hourglass_top_rounded;
      headColor = Colors.orange;
      headTitle = "申请已受理，等待上链";
      headSub = "上链前不计算开发者奖励";
    }

    final gas = ruleData['gas'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("开发者规则详情"),
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEDF2F7)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "业务类型", (ruleData['ruleName'] ?? "DeveloperRule").toString()),
                  const Divider(height: 32),
                  _infoRow(context, "奖励比例", "${(rewardRate * 100).toStringAsFixed(0)}%"),
                  const Divider(height: 32),
                  _infoRow(context, "开发者地址", address, isAddr: true, canCopy: true),
                  if (gas is num) ...[
                    const Divider(height: 32),
                    _infoRow(context, "手续费", "$gas QCC"),
                  ],
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
                  child: Text(displayValue,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: valueColor ?? (canCopy ? Colors.blueAccent : Colors.black87),
                      )),
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
