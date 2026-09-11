import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/RuleData.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import '../../procotol/PledgeRules.dart';
import '../../procotol/PledgetType.dart';
import '../../views/myasset/QccAssetService.dart' as server;
import 'util/PledgeFileStorage.dart';


/// 普通质押（自我信托）——对应 PledgeCommonTest.java。
/// 质押人 = 受益人 = 自己，不挂 tag、不授权给第三方，protocol 固定传空
/// 字符串 ""（不属于 PledgetType 枚举任何一个值）。
///
/// - lock：钱包 -amount，质押池 +amount，返回的 txHash 就是将来解押必须
///   带上的 credentialHash——本页在 lock 成功后自动把这个 txHash 存进
///   PledgeFileStorage，解押时直接从"本机记录"里选，不需要用户手抄 hash。
/// - unlock：credentialHash 必须是原 lock 交易的 txHash（PledgeRules 顶层
///   字段），服务端凭这个 hash 找到原始质押记录退款；非本人无法解押。
///
/// 🐛 FIX：金额输入框之前直接把用户输入的数字当"最小单位"整数提交
/// （`int.tryParse(_amountController.text.trim())`），跟 QccTransferPage.dart
/// 转账页面的处理方式不一致——转账页面用 `server.QccAssetService().getAmountRaw()`
/// 把用户填的 QCC 小数换算成最小单位再提交。质押页面漏了这一步，导致用户
/// 填"150"（以为是150 QCC）实际提交的是150个最小单位（=0.00000015 QCC），
/// 扣款相对巨额余额小到肉眼看不出来，表现得像"质押没扣钱"。这次改成和转账页面
/// 一致，输入框改成允许小数、按 QCC 为单位输入，提交前用 getAmountRaw() 换算。
class CommonPledgeWidget extends StatefulWidget {
  const CommonPledgeWidget({super.key});

  @override
  State<CommonPledgeWidget> createState() => _CommonPledgeWidgetState();
}

class _CommonPledgeWidgetState extends State<CommonPledgeWidget> {
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  final _assetIdController = TextEditingController(text: "QCC");
  final _amountController = TextEditingController();

  bool _isLock = true; // true=发起质押(lock)，false=解押(unlock)
  bool _isSubmitting = false;

  List<Map<String, dynamic>> _myLockRecords = [];
  String? _selectedCredentialHash;

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
    // 只列"普通质押(protocol=='')、还没标记解押、和当前 assetId 一致"的
    // lock 记录，供解押时选择。
    final assetId = _assetIdController.text.trim();
    final matched = all
        .where((t) =>
    (t['protocol'] ?? '') == '' &&
        (t['actionType'] ?? '') == PledgeActionType.lock &&
        (t['assetId'] ?? '') == assetId &&
        (t['status'] ?? '') != 'UNLOCKED')
        .toList();
    if (!mounted) return;
    setState(() {
      _myLockRecords = matched;
      _selectedCredentialHash = matched.isNotEmpty ? matched.first['txHash']?.toString() : null;
    });
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
    // 🐛 FIX：改成和 QccTransferPage.dart 一样，用 getAmountRaw() 把用户填的
    // QCC 小数换算成链上最小单位整数，不再让用户自己心算 ×10^precision。
    final amount = server.QccAssetService().getAmountRaw(assetId, _amountController.text.trim());
    if (amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的质押数量"));
      return;
    }
    if (!_isLock && (_selectedCredentialHash == null || _selectedCredentialHash!.isEmpty)) {
      Tools.showToast(context, Tools.getTra("请选择要解押的原质押记录"));
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
          protocol: "",
          // 🐛 FIX：这行之前被注释掉了，导致 unlock 请求永远不带 credentialHash，
          // 服务端 buildKey() 找不到原始质押记录，解押会一直失败。
          credentialHash: _isLock ? null : _selectedCredentialHash,
        );

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "PledgeRule";
        rule.ruleName = "PledgeRule";
        rule.ruleJson = jsonEncode(pledge.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();
        LogObj.log("质押提交整个json：${rule.toJson()}");
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/rule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final txHash = result.data?['txHash']?.toString() ?? "";
      if (_isLock) {
        await PledgeFileStorage.saveTask({
          'txHash': txHash,
          'address': nowaddress,
          'assetId': assetId,
          'amount': amount, // 存的是换算后的最小单位，跟提交给链上的值保持一致
          'protocol': PledgetType.plain,
          'actionType': PledgeActionType.lock,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'status': 'LOCKED',
        });
        Tools.showToast(context, "✅ 普通质押已提交，txHash 已自动记录，解押时可直接选择");
      } else {
        await PledgeFileStorage.updateStatus(_selectedCredentialHash!, 'UNLOCKED');
        Tools.showToast(context, "✅ 解押已提交");
      }
      _amountController.clear();
      _loadMyLockRecords();
    } else {
      LogObj.log("普通质押提交异常: ${result.error}");
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
          _buildSectionCard("2. 质押地址(=受益地址)", Icons.person_outline, _buildAddressPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("3. 资产与数量", Icons.token_outlined, _buildAssetAmountInput()),
          if (!_isLock) ...[
            const SizedBox(height: 16),
            _buildSectionCard("4. 选择要解押的原质押记录", Icons.receipt_long_outlined, _buildRecordPicker()),
          ],
          const SizedBox(height: 32),
          _buildSubmitButton(),
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
            Icon(icon, size: 16, color: Colors.indigo),
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
        ButtonSegment<bool>(value: true, label: Trans("发起质押(lock)"), icon: const Icon(Icons.lock_outline, size: 18)),
        ButtonSegment<bool>(value: false, label: Trans("解押(unlock)"), icon: const Icon(Icons.lock_open_outlined, size: 18)),
      ],
      selected: <bool>{_isLock},
      onSelectionChanged: (s) {
        setState(() => _isLock = s.first);
        _loadMyLockRecords();
      },
      style: SegmentedButton.styleFrom(selectedBackgroundColor: Colors.indigo, selectedForegroundColor: Colors.white, side: BorderSide.none),
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
          setState(() => nowaddress = val);
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
          enabled: _isLock, // 解押时资产由所选记录决定，不允许再改
          decoration: InputDecoration(labelText: Tools.getTra("资产ID (如 QCC / ITLT)"), border: const OutlineInputBorder()),
          onChanged: (_) => _loadMyLockRecords(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          // 🐛 FIX：改成允许小数，和 QccTransferPage.dart 一致——用户按 QCC 为单位
          // 填数量，不再要求自己换算成最小单位。
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

  Widget _buildRecordPicker() {
    if (_myLockRecords.isEmpty) {
      return Text(
        "本机没有该地址+该资产的普通质押记录（可能已全部解押，或本次质押不是在本机发起的——若属于后者，请手动联系管理员核实原始 txHash）。",
        style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedCredentialHash,
      isExpanded: true,
      items: _myLockRecords
          .map((r) => DropdownMenuItem(
        value: r['txHash']?.toString(),
        // ⚠️ TODO：r['amount'] 存的是最小单位原始整数，这里直接显示会跟输入框
        // 现在改成的"按 QCC 展示"不一致。QccAssetService 里如果有对应的
        // "最小单位 → 展示值"反向换算方法（getAmountRaw 的反函数），麻烦告诉我
        // 具体方法名，我把这里也换算成 QCC 展示；我手头没有 QccAssetService.dart
        // 源码，不敢瞎猜方法名。
        child: Text(
          "金额 ${r['amount']} (最小单位) · ${_shortHash(r['txHash']?.toString() ?? '')}",
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ))
          .toList(),
      onChanged: (val) => setState(() => _selectedCredentialHash = val),
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
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
    bool active = !_isSubmitting && nowaddress.isNotEmpty && (_isLock || (_selectedCredentialHash?.isNotEmpty ?? false));
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.indigo, Colors.indigoAccent]) : null,
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