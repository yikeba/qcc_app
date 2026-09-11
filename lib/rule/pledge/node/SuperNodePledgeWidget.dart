import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/RuleData.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import '../../../procotol/PledgeRules.dart';
import '../../../procotol/PledgetType.dart';
import '../../../views/myasset/QccAssetService.dart' as server;
import '../util/PledgeFileStorage.dart';

/// 超级节点质押——对应 PledgeNodeTest.java / PledgeSignNodeTest.java。
/// protocol = PledgetType.superNode，assetId 两个测试都只用了 "QCC"。
///
/// 🐛 FIX（解押模型重写）：原来解押要求用户从"本机某一笔具体的 lock 记录"里
/// 选一条、拿它的 txHash 当 credentialHash 提交，注释里也标了"未经测试文件
/// 验证"。现在核对过 PledgeRuleManager.java 的 executeNodeUnlock()：
///   NodePledge record = nodePledgeStore.get(pr.address);   // 只按地址查
///   if (record == null || record.amount < pr.amount) { ... }
///   record.amount -= pr.amount;                            // 直接扣总额
/// 服务端根本不读 pr.credentialHash——超级节点质押是"按地址累加成一个总额"，
/// 不是像普通质押那样每笔 lock 各自独立、靠 credentialHash 区分。选择"哪一条
/// 记录"对结果没有任何影响，之前的设计会误导用户以为质押是分笔管理的。
/// 现在改成：解押直接复用金额输入框填"这次要解押多少"（跟发起质押对称），
/// 不再需要/要求选择具体记录；原来的记录下拉框降级成纯展示的"本机质押历史"，
/// 只做参考，不参与提交。
///
/// 🐛 FIX：金额输入同样改成走 server.QccAssetService().getAmountRaw() 换算，
/// 不再要求用户自己心算最小单位。
///
/// 查询部分对应 GET /v1/pledge/{address}?type=SuperNode&assetId=QCC，
/// 响应体 data 字段是服务端内部转发的原始字符串，这里做了"能双重解析就
/// 双重解析，解析不了就原样展示"的兜底（PledgeContext.java 的 data 是
/// 没有预解析的转发字符串，具体内层结构未知，防止显示端直接崩溃）。
class SuperNodePledgeWidget extends StatefulWidget {
  const SuperNodePledgeWidget({super.key});

  @override
  State<SuperNodePledgeWidget> createState() => _SuperNodePledgeWidgetState();
}

class _SuperNodePledgeWidgetState extends State<SuperNodePledgeWidget> {
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  final _assetIdController = TextEditingController(text: "QCC");
  final _amountController = TextEditingController();

  bool _isLock = true;
  bool _isSubmitting = false;
  bool _isQuerying = false;
  String? _queryResultText;

  // 仅供参考的本机质押历史（不驱动提交，unlock 不再依赖选中某一条）。
  List<Map<String, dynamic>> _myLockRecords = [];

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final names = await QccStorage.getAllWalletNames();
    final addrs = QccObj.readWallets().map((e) => e.address).toSet().toList();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localAddrs = addrs;
      if (addrs.isNotEmpty) {
        final active = QccObj.activeWallet?.address;
        nowaddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
    _loadMyLockRecords();
  }

  Future<void> _loadMyLockRecords() async {
    if (nowaddress.isEmpty) return;
    final all = await PledgeFileStorage.getTasksForAddress(nowaddress);
    final assetId = _assetIdController.text.trim();
    final matched = all
        .where((t) =>
    (t['protocol'] ?? '') == PledgetType.superNode &&
        (t['assetId'] ?? '') == assetId)
        .toList()
      ..sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    if (!mounted) return;
    setState(() {
      _myLockRecords = matched;
    });
  }

  Future<void> _handleQuery() async {
    if (nowaddress.isEmpty) return;
    setState(() {
      _isQuerying = true;
      _queryResultText = null;
    });
    try {
      final assetId = _assetIdController.text.trim();
      final url = "${QccExplorerService.baseUrl}/v1/pledge/$nowaddress?type=${PledgetType.superNode}&assetId=$assetId";
      final resp = await http.get(Uri.parse(url));
      final outer = jsonDecode(resp.body);
      String pretty = resp.body;
      // 【兜底双重解析】data 字段可能是"再套一层 JSON"的字符串（转发自内部
      // TCP 查询），也可能干脆是错误文案 "error"——两种都要能正常展示。
      if (outer is Map && outer['ok'] == true && outer['data'] is String) {
        final dataStr = outer['data'] as String;
        try {
          final inner = jsonDecode(dataStr);
          pretty = const JsonEncoder.withIndent('  ').convert(inner);
        } catch (_) {
          pretty = dataStr;
        }
      }
      if (!mounted) return;
      setState(() => _queryResultText = pretty);
    } catch (e) {
      if (!mounted) return;
      setState(() => _queryResultText = "查询失败: $e");
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择本机地址"));
      return;
    }
    final assetId = _assetIdController.text.trim();
    if (assetId.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入资产ID"));
      return;
    }
    // 🐛 FIX：改成走 getAmountRaw() 换算。lock 和 unlock 现在共用同一个
    // 金额输入框——lock 填"要追加质押多少"，unlock 填"这次要解押多少"，
    // 语义对称，都是 PledgeRules.amount 这个字段。
    final amount = server.QccAssetService().getAmountRaw(assetId, _amountController.text.trim());
    if (amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的质押数量"));
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        final pledge = PledgeRules(
          address: wallet.address,
          assetId: assetId,
          amount: amount,
          actionType: _isLock ? PledgeActionType.lock : PledgeActionType.unlock,
          protocol: PledgetType.superNode,
          // 🐛 FIX：SuperNode unlock 服务端不读 credentialHash（executeNodeUnlock
          // 只按 address+amount 处理），这里不再传——避免让人误以为这个字段
          // 对超级节点解押有实际作用。
        );

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "PledgeRule";
        rule.ruleName = "PledgeRule";
        rule.ruleJson = jsonEncode(pledge.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();

        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/rule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final txHash = result.data?['txHash']?.toString() ?? "";
      await PledgeFileStorage.saveTask({
        'txHash': txHash,
        'address': nowaddress,
        'assetId': assetId,
        'amount': amount, // 存的是换算后的最小单位，跟提交给链上的值保持一致
        'protocol': PledgetType.superNode,
        'actionType': _isLock ? PledgeActionType.lock : PledgeActionType.unlock,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': _isLock ? 'LOCKED' : 'UNLOCKED',
      });
      Tools.showToast(context, _isLock ? "✅ 超级节点质押已提交" : "✅ 解押已提交");
      _amountController.clear();
      _loadMyLockRecords();
    } else {
      LogObj.log("超级节点质押提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState(Icons.account_balance_wallet_outlined, "本机未导入任何钱包，无法进行质押操作。");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 操作类型", Icons.rule_folder_outlined, _buildActionSelector()),
          const SizedBox(height: 16),
          _buildSectionCard("2. 质押地址", Icons.person_outline, _buildAddressPicker()),
          const SizedBox(height: 16),
          _buildSectionCard(_isLock ? "3. 资产与追加质押数量" : "3. 资产与本次解押数量", Icons.token_outlined, _buildAssetAmountInput()),
          const SizedBox(height: 16),
          _buildSectionCard("本机质押历史（仅供参考）", Icons.receipt_long_outlined, _buildLockHistory()),
          const SizedBox(height: 32),
          _buildSubmitButton(),
          const SizedBox(height: 24),
          _buildSectionCard("查询该地址的超级节点质押记录", Icons.search, _buildQuerySection()),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.teal),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildActionSelector() {
    return SegmentedButton<bool>(
      segments: <ButtonSegment<bool>>[
        ButtonSegment<bool>(value: true, label: Trans("追加质押(lock)"), icon: const Icon(Icons.lock_outline, size: 18)),
        ButtonSegment<bool>(value: false, label: Trans("解押(unlock)"), icon: const Icon(Icons.lock_open_outlined, size: 18)),
      ],
      selected: <bool>{_isLock},
      onSelectionChanged: (s) {
        setState(() => _isLock = s.first);
        _loadMyLockRecords();
      },
      style: SegmentedButton.styleFrom(selectedBackgroundColor: Colors.teal, selectedForegroundColor: Colors.white, side: BorderSide.none),
    );
  }

  Widget _buildAddressPicker() {
    return DropdownButtonFormField<String>(
      initialValue: nowaddress.isEmpty ? null : nowaddress,
      isExpanded: true,
      items: _localAddrs
          .map((a) => DropdownMenuItem(value: a, child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
          .toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            nowaddress = val;
            _queryResultText = null;
          });
          _loadMyLockRecords();
        }
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildAssetAmountInput() {
    return Column(
      children: [
        TextField(
          controller: _assetIdController,
          enabled: _isLock,
          decoration: InputDecoration(labelText: Tools.getTra("资产ID (测试用例均为 QCC)"), border: const OutlineInputBorder()),
          onChanged: (_) => _loadMyLockRecords(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          // 🐛 FIX：允许小数，按资产单位（如 QCC）填写，不再要求换算成最小单位。
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration: InputDecoration(
            labelText: Tools.getTra(_isLock
                ? "追加质押数量 (${_assetIdController.text.trim().isEmpty ? 'QCC' : _assetIdController.text.trim()})"
                : "本次解押数量 (${_assetIdController.text.trim().isEmpty ? 'QCC' : _assetIdController.text.trim()})"),
            border: const OutlineInputBorder(),
          ),
        ),
        if (nowaddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("当前余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(nowaddress, _assetIdController.text.trim().isEmpty ? "QCC" : _assetIdController.text.trim(), fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ),
      ],
    );
  }

  /// 本机质押历史——纯展示，不驱动提交。SuperNode 在服务端是按地址累加成
  /// 一个总额（NodePledge.amount），不是每笔 lock 独立记录，所以这里只是
  /// 给用户一个"我大概什么时候质押过多少"的参考，不代表链上真实分笔状态；
  /// 要看当前真实总额，请用下面的查询功能。
  Widget _buildLockHistory() {
    if (_myLockRecords.isEmpty) {
      return Text(
        "本机没有该地址+该资产的质押/解押提交记录（可能不是本机发起，或还没操作过）。",
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      );
    }
    return Column(
      children: _myLockRecords.take(10).map((r) {
        final isLock = (r['actionType'] ?? '') == PledgeActionType.lock;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(isLock ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 14, color: isLock ? Colors.teal : Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "${isLock ? '+' : '-'}${r['amount']} (最小单位) · ${_shortHash(r['txHash']?.toString() ?? '')}",
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuerySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_isQuerying || nowaddress.isEmpty) ? null : _handleQuery,
            icon: _isQuerying ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
            label: Trans("查询"),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
          ),
        ),
        if (_queryResultText != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: SelectableText(_queryResultText!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ],
    );
  }

  String _shortHash(String h) => h.length < 14 ? h : "${h.substring(0, 10)}...${h.substring(h.length - 4)}";

  Widget _buildEmptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = !_isSubmitting && nowaddress.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.teal, Colors.tealAccent]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans(_isLock ? "确认发起质押" : "确认解押", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}