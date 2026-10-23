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
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';

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
    // 只列"普通质押(protocol=='')、已上链锁定(LOCKED)、和当前 assetId 一致"的
    // lock 记录，供解押时选择。
    // 状态流转：PENDING(受理) → LOCKED(上链) / FAILED；解押：LOCKED → UNLOCKING → UNLOCKED
    // PENDING / FAILED / UNLOCKING 都不可再解押（未上链的质押解押必被拒；
    // UNLOCKING 已在途，再提交一次会重复）。旧记录无此状态体系时 status 为 'LOCKED'。
    final assetId = _assetIdController.text.trim();
    final matched = all
        .where((t) =>
    (t['protocol'] ?? '') == '' &&
        (t['actionType'] ?? '') == PledgeActionType.lock &&
        (t['assetId'] ?? '') == assetId &&
        (t['status'] ?? 'LOCKED') == 'LOCKED')
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

    final bool isLock = _isLock; // 提交过程中锁定，避免中途切换 Tab
    final String from = nowaddress;
    final String? credentialHash = _selectedCredentialHash;
    String? builtRuleId; // 本地 finalizeId() 结果，QccTxFlow 误判失败时作 txHash 兜底

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
        builtRuleId = rule.id;
        LogObj.log("质押提交整个json：${rule.toJson()}");
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      // 原来写死 https://tx.qccio.com，统一走 baseUrl
      submitUrl: "${QccExplorerService.baseUrl}/v1/rule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    final String? txHash = _acceptedTxHash(result, builtRuleId);
    if (txHash == null) {
      LogObj.log("普通质押提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
      return;
    }

    // ---- 受理：先落本地状态（受理 ≠ 上链） ----
    // lock 的 txHash 就是将来解押要用的 credentialHash，受理当下就必须存下来；
    // 原来只在 result.success 时存，而 QccTxFlow 把受理误判为失败，
    // 导致 lock 已上链、本机却没有记录，从界面上再也无法解押。
    if (isLock) {
      await PledgeFileStorage.saveTask({
        'txHash': txHash,
        'address': from,
        'assetId': assetId,
        'amount': amount, // 换算后的最小单位，与链上一致
        'protocol': PledgetType.plain,
        'actionType': PledgeActionType.lock,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'PENDING',
      });
    } else {
      // 解押在途：从可解押列表移除，防止重复提交；上链失败再恢复为 LOCKED
      await PledgeFileStorage.updateStatus(credentialHash!, 'UNLOCKING');
    }
    _amountController.clear();
    _loadMyLockRecords();
    if (!mounted) return;

    final String humanAmount = server.QccAssetService().getHumanAmount(assetId, amount.toString());
    final TxChainStatus? st = await showDialog<TxChainStatus?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QccTxConfirmDialog(
        txHash: txHash,
        confirmedTitle: isLock ? "质押已上链" : "解押已上链",
        details: [
          Text("${isLock ? '质押' : '解押'}：$humanAmount $assetId", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("地址：${_walletNames[from] ?? ''} ${_shortHash(from)}", style: const TextStyle(fontSize: 12)),
          if (!isLock) Text("原质押：${_shortHash(credentialHash!)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ],
        footer: isLock ? "上链后资产才被锁定；txHash 已自动记录，解押时可直接选择。" : "上链后资产才会退回到质押地址。",
        onFinal: (s) async {
          final bool ok = s.state == TxChainState.confirmed;
          if (isLock) {
            await PledgeFileStorage.updateStatus(txHash, ok ? 'LOCKED' : 'FAILED');
          } else {
            await PledgeFileStorage.updateStatus(credentialHash!, ok ? 'UNLOCKED' : 'LOCKED');
          }
          if (mounted) _loadMyLockRecords();
        },
      ),
    );
    if (!mounted) return;

    if (st?.state == TxChainState.confirmed) {
      Tools.showToast(context, isLock ? "✅ 质押已上链，资产已锁定" : "✅ 解押已上链，资产已退回");
    } else if (st?.state == TxChainState.failed) {
      Tools.showToast(context,
          isLock ? "质押上链失败：${st!.message ?? '未知原因'}，资产未被锁定" : "解押上链失败：${st!.message ?? '未知原因'}，质押仍有效");
    } else {
      Tools.showToast(context, "交易已受理，尚未确认上链，请稍后在「我的记录」中查看");
    }
  }

  /// 从 QccTxFlow 结果取出已受理的 txHash（与 DexMatchWidget 同一兜底）。
  /// 【临时兜底，根治在 QccTxFlow】QccTxFlow 把受理响应判成失败、data 为空，
  /// 服务端 msg 落在 error 里："Transaction accepted, query by txHash for final result"。
  /// 此时用本地 finalizeId() 的 rule.id 作为 txHash（日志里 id 与 toSign 末段一致）。
  static String? _acceptedTxHash(dynamic result, String? localId) {
    final Map? d = result.data is Map ? result.data as Map : null;
    if (d != null) {
      final code = (d['code'] ?? d['status'] ?? '').toString().toUpperCase();
      final h = d['txHash']?.toString() ?? '';
      if ((result.success == true || code == 'ACCEPTED') && h.isNotEmpty) return h;
    }
    final String err = (result.error ?? '').toString().toLowerCase();
    if (err.contains('transaction accepted') && localId != null && localId.isNotEmpty) return localId;
    return null;
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
        // r['amount'] 是最小单位，用 getHumanAmount 换算展示（质押管理页、DEX 页已在用）
        child: Text(
          "${server.QccAssetService().getHumanAmount((r['assetId'] ?? 'QCC').toString(), r['amount'].toString())} "
              "${r['assetId'] ?? ''} · ${_shortHash(r['txHash']?.toString() ?? '')}",
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