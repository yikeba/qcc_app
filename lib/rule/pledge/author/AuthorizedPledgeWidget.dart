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
import '../../../views/myasset/QccAssetService.dart';
import '../util/PledgeFileStorage.dart';
import 'AuthorizedPledge.dart';



/// 授权质押（去中心化鉴权）——对应 PledgeAuthorizedTest.java /
/// PledgeUnlockTest.java。protocol = PledgetType.authorizedPledge，
/// pledgeJson 装的是 AuthorizedPledge.toJson()。
///
/// 三个子功能，用顶部分段按钮切换：
/// 1. 建立授权(lock)：address=发起方(owner，本机钱包)，pledgeJson.to=被
///    授权地址(可留空表示自我鉴权)，pledgeJson.tag=授权标签。建立成功后
///    txHash 就是鉴权凭证第三要素，自动记进 PledgeFileStorage。
/// 2. 吊销授权(unlock)：pledgeJson.revokeHash=要吊销的那笔建立授权的
///    txHash——【关键，和普通/超级节点质押不同】revokeHash 是 pledgeJson
///    里的嵌套字段，PledgeRules 顶层的 credentialHash 在这条路径上完全
///    不使用（PledgeUnlockTest.java 的 doRevoke() 只设置了 revoke.revokeHash，
///    从没设置过 pledge.credentialHash）。
/// 3. 三要素查询：GET /v1/pledge/{address}?tag=&hash=，用来验证某个"被
///    授权地址+tag+hash"组合当前是否鉴权有效——这是一个独立于"本机是否
///    发起过授权"的通用查询工具，address 就填被授权方地址（不要求是本机
///    钱包），照 PledgeAuthorizedTest.java 的 isQualified() 做了双层 JSON
///    解析（data 字段是转发的字符串，需要再解析一次才能拿到真正的
///    qualified 布尔值）。
///
/// 🐛 FIX：金额输入框之前和 CommonPledgeWidget.dart 改之前一样，直接把用户
/// 输入的数字当"最小单位"整数提交（`int.tryParse`），跟 QccTransferPage.dart
/// 转账页面的处理方式不一致，会导致填"180"实际提交180个最小单位而不是180
/// QCC。这次同样改成用 `server.QccAssetService().getAmountRaw()` 换算，输入框
/// 也改成允许小数、按资产单位展示。
class AuthorizedPledgeWidget extends StatefulWidget {
  const AuthorizedPledgeWidget({super.key});

  @override
  State<AuthorizedPledgeWidget> createState() => _AuthorizedPledgeWidgetState();
}

enum _Mode { establish, revoke, query }

class _AuthorizedPledgeWidgetState extends State<AuthorizedPledgeWidget> {
  _Mode _mode = _Mode.establish;

  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  final _assetIdController = TextEditingController(text: "QCC");
  final _amountController = TextEditingController();
  final _toController = TextEditingController();
  final _tagController = TextEditingController();

  bool _isSubmitting = false;
  List<Map<String, dynamic>> _myAuthRecords = [];
  String? _selectedRevokeHash;

  // 查询工具的独立输入（不要求是本机地址）
  final _queryAddressController = TextEditingController();
  final _queryTagController = TextEditingController();
  final _queryHashController = TextEditingController();
  bool _isQuerying = false;
  String? _queryResultText;

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
    _loadMyAuthRecords();
  }

  Future<void> _loadMyAuthRecords() async {
    if (nowaddress.isEmpty) return;
    final all = await PledgeFileStorage.getTasksForAddress(nowaddress);
    final matched = all
        .where((t) =>
    (t['protocol'] ?? '') == PledgetType.authorizedPledge &&
        (t['actionType'] ?? '') == PledgeActionType.lock &&
        (t['status'] ?? '') != 'UNLOCKED')
        .toList();
    if (!mounted) return;
    setState(() {
      _myAuthRecords = matched;
      _selectedRevokeHash = matched.isNotEmpty ? matched.first['txHash']?.toString() : null;
    });
  }

  Future<void> _handleSubmit() async {
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择本机地址"));
      return;
    }
    final tag = _tagController.text.trim();
    if (tag.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入授权标签(tag)"));
      return;
    }

    if (_mode == _Mode.establish) {
      final assetId = _assetIdController.text.trim();
      // 🐛 FIX：改成和 QccTransferPage.dart / 改过的 CommonPledgeWidget.dart 一致，
      // 用 getAmountRaw() 把用户填的资产小数换算成链上最小单位整数。
      final amount = QccAssetService().getAmountRaw(assetId, _amountController.text.trim());
      if (assetId.isEmpty || amount <= 0) {
        Tools.showToast(context, Tools.getTra("请输入正确的资产ID和数量"));
        return;
      }
      setState(() => _isSubmitting = true);
      final result = await QccTxFlow.run(
        context: context,
        address: nowaddress,
        buildPayload: (wallet) async {
          final auth = AuthorizedPledge(to: _toController.text.trim(), tag: tag);
          final pledge = PledgeRules(
            address: wallet.address,
            assetId: assetId,
            amount: amount,
            actionType: PledgeActionType.lock,
            protocol: PledgetType.authorizedPledge,
            pledgeJson: jsonEncode(auth.toJson()),
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
          'protocol': PledgetType.authorizedPledge,
          'actionType': PledgeActionType.lock,
          'to': _toController.text.trim(),
          'tag': tag,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'status': 'LOCKED',
        });
        Tools.showToast(context, "✅ 授权已建立，凭证 txHash 已自动记录");
        _amountController.clear();
        _toController.clear();
        _tagController.clear();
        _loadMyAuthRecords();
      } else {
        LogObj.log("建立授权异常: ${result.error}");
        Tools.showToast(context, "错误: ${result.error}");
      }
    } else if (_mode == _Mode.revoke) {
      if (_selectedRevokeHash == null || _selectedRevokeHash!.isEmpty) {
        Tools.showToast(context, Tools.getTra("请选择要吊销的原授权记录"));
        return;
      }
      final record = _myAuthRecords.firstWhere((r) => r['txHash'] == _selectedRevokeHash);
      setState(() => _isSubmitting = true);
      final result = await QccTxFlow.run(
        context: context,
        address: nowaddress,
        buildPayload: (wallet) async {
          // 【关键】revokeHash 是 pledgeJson 里的嵌套字段，不是 PledgeRules
          // 顶层 credentialHash——严格照 PledgeUnlockTest.java doRevoke() 的
          // 字段位置写，不做"和普通质押统一"的简化。
          final revoke = AuthorizedPledge(
            to: (record['to'] ?? '').toString(),
            tag: (record['tag'] ?? '').toString(),
            revokeHash: _selectedRevokeHash,
          );
          final pledge = PledgeRules(
            address: wallet.address,
            assetId: (record['assetId'] ?? '').toString(),
            amount: (record['amount'] is int) ? record['amount'] : int.tryParse('${record['amount']}') ?? 0,
            actionType: PledgeActionType.unlock,
            protocol: PledgetType.authorizedPledge,
            pledgeJson: jsonEncode(revoke.toJson()),
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
        await PledgeFileStorage.updateStatus(_selectedRevokeHash!, 'UNLOCKED');
        Tools.showToast(context, "✅ 吊销已提交，鉴权将即时失效");
        _loadMyAuthRecords();
      } else {
        LogObj.log("吊销授权异常: ${result.error}");
        Tools.showToast(context, "错误: ${result.error}");
      }
    }
  }

  Future<void> _handleQuery() async {
    final address = _queryAddressController.text.trim();
    final tag = _queryTagController.text.trim();
    final hash = _queryHashController.text.trim();
    if (address.isEmpty || tag.isEmpty || hash.isEmpty) {
      Tools.showToast(context, Tools.getTra("请填写完整的 address / tag / hash 三要素"));
      return;
    }
    setState(() {
      _isQuerying = true;
      _queryResultText = null;
    });
    try {
      final url = "${QccExplorerService.baseUrl}/v1/pledge/$address?tag=$tag&hash=$hash";
      final resp = await http.get(Uri.parse(url));
      final outer = jsonDecode(resp.body);
      bool? qualified;
      bool? exists;
      if (outer is Map && outer['ok'] == true && outer['data'] is String) {
        try {
          final inner = jsonDecode(outer['data'] as String);
          if (inner is Map) {
            qualified = inner['qualified'] == true;
            exists = inner['exists'] == true;
          }
        } catch (_) {}
      }
      String text;
      if (qualified != null) {
        text = qualified ? "✅ qualified=true（鉴权有效）" : "❌ qualified=false（${exists == false ? '不存在/已吊销' : '不合格'}）";
      } else {
        text = "无法解析为标准鉴权结果，原始返回：\n${resp.body}";
      }
      if (!mounted) return;
      setState(() => _queryResultText = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _queryResultText = "查询失败: $e");
    } finally {
      if (mounted) setState(() => _isQuerying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 操作类型", Icons.rule_folder_outlined, _buildModeSelector()),
          const SizedBox(height: 16),
          if (_mode == _Mode.query) _buildQueryForm() else _buildEstablishOrRevokeForm(),
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
            Icon(icon, size: 16, color: Colors.deepOrange),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<_Mode>(
      segments: const <ButtonSegment<_Mode>>[
        ButtonSegment(value: _Mode.establish, label: Text("建立授权"), icon: Icon(Icons.add_moderator_outlined, size: 18)),
        ButtonSegment(value: _Mode.revoke, label: Text("吊销授权"), icon: Icon(Icons.remove_moderator_outlined, size: 18)),
        ButtonSegment(value: _Mode.query, label: Text("三要素查询"), icon: Icon(Icons.search, size: 18)),
      ],
      selected: <_Mode>{_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
      style: SegmentedButton.styleFrom(selectedBackgroundColor: Colors.deepOrange, selectedForegroundColor: Colors.white, side: BorderSide.none),
    );
  }

  Widget _buildEstablishOrRevokeForm() {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState(Icons.account_balance_wallet_outlined, "本机未导入任何钱包，无法进行授权质押操作。");
    }
    return Column(
      children: [
        _buildSectionCard("2. 发起地址(owner)", Icons.person_outline, _buildAddressPicker()),
        const SizedBox(height: 16),
        if (_mode == _Mode.establish)
          _buildSectionCard("3. 授权信息", Icons.badge_outlined, _buildEstablishFields())
        else
          _buildSectionCard("3. 选择要吊销的授权", Icons.receipt_long_outlined, _buildRevokeFields()),
        const SizedBox(height: 32),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildAddressPicker() {
    return DropdownButtonFormField<String>(
      value: nowaddress.isEmpty ? null : nowaddress,
      isExpanded: true,
      items: _localAddrs
          .map((a) => DropdownMenuItem(value: a, child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
          .toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => nowaddress = val);
          _loadMyAuthRecords();
        }
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildEstablishFields() {
    return Column(
      children: [
        TextField(
          controller: _toController,
          decoration: InputDecoration(labelText: Tools.getTra("被授权地址 to (留空=自我鉴权)"), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(labelText: Tools.getTra("授权标签 tag (如 node，可逗号分隔多个)"), border: const OutlineInputBorder()),
          // 【必须】提交按钮的可用状态依赖 _tagController.text，没有这个
          // onChanged 触发 setState 的话，输完 tag 按钮也不会变亮。
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _assetIdController,
          decoration: InputDecoration(labelText: Tools.getTra("资产ID (任意代币均可)"), border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          // 🐛 FIX：改成允许小数，用户按资产自身单位（如 QCC）填数量，
          // 不再要求自己换算成最小单位。
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          decoration: InputDecoration(labelText: Tools.getTra("质押数量 (${_assetIdController.text.trim().isEmpty ? 'QCC' : _assetIdController.text.trim()})"), border: const OutlineInputBorder()),
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

  Widget _buildRevokeFields() {
    if (_myAuthRecords.isEmpty) {
      return Text(
        "本机没有该地址发起过的、尚未吊销的授权质押记录（可能已全部吊销，或不是本机发起）。",
        style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedRevokeHash,
      isExpanded: true,
      items: _myAuthRecords
          .map((r) => DropdownMenuItem(
        value: r['txHash']?.toString(),
        child: Text(
          "tag=${r['tag']} · to=${_shortHash((r['to'] ?? '').toString())} · ${_shortHash(r['txHash']?.toString() ?? '')}",
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ))
          .toList(),
      onChanged: (val) => setState(() => _selectedRevokeHash = val),
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildQueryForm() {
    return Column(
      children: [
        _buildSectionCard(
          "鉴权三要素 (address + tag + hash)",
          Icons.vpn_key_outlined,
          Column(
            children: [
              TextField(controller: _queryAddressController, decoration: InputDecoration(labelText: Tools.getTra("被授权地址 (address)"), border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _queryTagController, decoration: InputDecoration(labelText: Tools.getTra("标签 (tag)"), border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _queryHashController, decoration: InputDecoration(labelText: Tools.getTra("授权凭证 hash"), border: const OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isQuerying ? null : _handleQuery,
                  icon: _isQuerying ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                  label: Trans("查询鉴权状态"),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange),
                ),
              ),
              if (_queryResultText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(_queryResultText!, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
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
    bool active = !_isSubmitting &&
        nowaddress.isNotEmpty &&
        (_mode == _Mode.establish ? _tagController.text.trim().isNotEmpty : (_selectedRevokeHash?.isNotEmpty ?? false));
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.deepOrange, Colors.orangeAccent]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans(_mode == _Mode.establish ? "确认建立授权" : "确认吊销授权", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}