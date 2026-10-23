import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';

import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../UserRuleFileStorage.dart';
import 'TagQueryService.dart';

/// TagRule 详情页。
///
/// 两层确认：
///   1. 交易是否上链 —— /v1/hash/{txHash}（QccTxStatusService）
///   2. 业务结果是否成立 —— /v1/tag/{tagName}，owner 是否等于本次注册地址。
/// 第 2 层不能省：交易上链只说明这笔规则被打包执行了，标签可能在你之前一刻
/// 已被别人注册（抢注），此时链上归属不是你。Java TxTagRuleTest 也是以
/// /v1/tag 的 owner 作为最终判定，而不是 /v1/hash。
class TagRuleSuccessPage extends StatefulWidget {
  final Map<String, dynamic> ruleData;

  const TagRuleSuccessPage({super.key, required this.ruleData});

  @override
  State<TagRuleSuccessPage> createState() => _TagRuleSuccessPageState();
}

class _TagRuleSuccessPageState extends State<TagRuleSuccessPage> {
  Map<String, String> _walletNames = {};

  late String _chainStatus; // confirmed / failed / pending
  int? _blockHeight;
  String? _chainMsg;
  bool _checking = false;

  TagInfo? _tagInfo; // 链上实际归属，confirmed 后查询
  bool _queryingTag = false;

  String _txHash = "";
  String _owner = "";
  String _tagName = "";

  @override
  void initState() {
    super.initState();
    _parse();
    _chainStatus = (widget.ruleData['chainStatus'] ?? 'pending').toString();
    final bh = widget.ruleData['blockHeight'];
    _blockHeight = bh is num ? bh.toInt() : int.tryParse("${bh ?? ''}");
    _chainMsg = widget.ruleData['chainMsg']?.toString();
    _loadWalletNames();

    if (_chainStatus == 'confirmed') {
      _queryTag();
    } else if (_txHash.isNotEmpty) {
      _check(silent: true);
    }
  }

  /// 兼容旧格式（data 二层 JSON）与新格式（顶层 ruleJson）
  void _parse() {
    final ruleData = widget.ruleData;
    _txHash = (ruleData['txHash'] ?? ruleData['id'] ?? "").toString();
    _owner = (ruleData['from'] ?? "").toString();
    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        _owner = (inner['from'] ?? _owner).toString();
        innerParams = inner['ruleJson'] != null ? jsonDecode(inner['ruleJson']) : inner;
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }
      if (innerParams != null) {
        _tagName = (innerParams['tagName'] ?? _tagName).toString();
        _owner = (innerParams['owner'] ?? _owner).toString();
      }
    } catch (e) {
      LogObj.log("TagRuleSuccessPage 解析失败: $e");
    }
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
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
      if (st.state == TxChainState.confirmed) _queryTag();
      if (!silent && mounted && !st.isFinal) {
        Tools.showToast(context, "尚未上链${st.message != null ? '（${st.message}）' : ''}");
      }
    } catch (e) {
      if (!silent && mounted) Tools.showToast(context, "查询失败：$e", isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _queryTag() async {
    if (_tagName.isEmpty || _queryingTag) return;
    setState(() => _queryingTag = true);
    final info = await TagQueryService.query(_tagName);
    if (!mounted) return;
    setState(() {
      _tagInfo = info;
      _queryingTag = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool confirmed = _chainStatus == 'confirmed';
    final bool failed = _chainStatus == 'failed';
    final TagInfo? t = _tagInfo;
    final bool tagIsMine = t != null && t.ok && t.found && t.owner == _owner;
    final bool tagTakenByOther = t != null && t.ok && t.found && t.owner != _owner;
    final bool tagMissing = t != null && t.ok && !t.found;

    IconData headIcon;
    Color headColor;
    String headTitle;
    String headSub;
    if (failed) {
      headIcon = Icons.error_outline;
      headColor = Colors.red;
      headTitle = "标签注册上链失败";
      headSub = _chainMsg ?? "未知原因";
    } else if (!confirmed) {
      headIcon = Icons.hourglass_top_rounded;
      headColor = Colors.orange;
      headTitle = "注册已受理，等待上链";
      headSub = "上链前标签不归属任何人";
    } else if (tagTakenByOther) {
      headIcon = Icons.report_gmailerrorred_rounded;
      headColor = Colors.red;
      headTitle = "标签已被他人注册";
      headSub = "交易已上链，但链上归属不是本地址（可能被抢先注册），本次注册未生效";
    } else if (tagIsMine) {
      headIcon = Icons.sell_rounded;
      headColor = Colors.purple;
      headTitle = "标签资产已注册";
      headSub = _blockHeight != null ? "已打包进区块 #$_blockHeight，链上归属已复核" : "链上归属已复核";
    } else {
      headIcon = Icons.sell_rounded;
      headColor = Colors.purple;
      headTitle = "注册交易已上链";
      headSub = _queryingTag
          ? "正在复核链上归属…"
          : (tagMissing ? "链上暂未查到该标签，索引可能尚未同步，可稍后刷新" : "链上归属复核失败，可稍后刷新");
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
        actions: [
          IconButton(
            tooltip: "刷新",
            icon: (_checking || _queryingTag)
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.black87),
            onPressed: (_checking || _queryingTag) ? null : () => confirmed ? _queryTag() : _check(),
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
            Text(headSub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: (failed || tagTakenByOther) ? Colors.red : Colors.grey)),
            const SizedBox(height: 28),

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
                  _infoRow(context, "标签名称", _tagName.isEmpty ? "--" : _tagName, canCopy: _tagName.isNotEmpty),
                  const Divider(height: 32),
                  _infoRow(context, "注册地址", _owner, isAddr: true, canCopy: true, nick: _walletNames[_owner]),
                  if (t != null && t.ok && t.found) ...[
                    const Divider(height: 32),
                    _infoRow(context, "链上归属", t.owner ?? "--",
                        isAddr: true,
                        canCopy: t.owner != null,
                        nick: t.owner == null ? null : _walletNames[t.owner!],
                        valueColor: tagIsMine ? Colors.green : Colors.red),
                    if (t.regTime != null) ...[
                      const Divider(height: 32),
                      _infoRow(context, "注册时间", TagQueryService.formatTime(t.regTime!)),
                    ],
                  ],
                  if (widget.ruleData['gas'] is num) ...[
                    const Divider(height: 32),
                    _infoRow(context, "手续费", "${widget.ruleData['gas']} QCC"),
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
      {bool isAddr = false, bool canCopy = false, String? nick, Color? valueColor}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }
    final bool hasNick = nick != null && nick.isNotEmpty;

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
                if (hasNick)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(nick,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
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
                          fontWeight: hasNick ? FontWeight.normal : FontWeight.bold,
                          fontSize: hasNick ? 12 : 14,
                          fontFamily: 'monospace',
                          color: valueColor ??
                              (canCopy ? Colors.blueAccent : (hasNick ? Colors.grey[600] : Colors.black87)),
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
