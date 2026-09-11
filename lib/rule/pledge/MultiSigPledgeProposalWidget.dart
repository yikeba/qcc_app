import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/RuleData.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/rule/user/multiple/multicreat/MultiSigAddressStorage.dart';
import 'package:qcc_flutter/rule/user/multiple/MultiSigFileStorage.dart';
import 'package:qcc_flutter/rule/user/multiple/multicreat/MultiSigInitiatedPage.dart';
import 'package:qcc_flutter/rule/user/multiple/QccMultiSig.dart';

import '../../procotol/PledgeRules.dart';
import '../../procotol/PledgetType.dart';
/// 质押提案——多签版。
///
/// 【范围限定，如实标注】6个 Java 测试文件里，唯一演示多签质押流程的是
/// PledgeFollowTest.java，且只用了 protocol=StablecoinPledege（稳定币质押）
/// 这一种类型，多签地址直接作为 pledge.address（受益方=多签账户本身）。
/// 普通质押/超级节点质押/授权质押这三种在测试文件里全部只出现在单签
/// 场景（PledgeCommonTest / PledgeNodeTest / PledgeSignNodeTest /
/// PledgeAuthorizedTest 的 owner 都是单个钱包），没有证据表明它们支持多签
/// 提案——本页因此只做 StablecoinPledege 这一种，不臆测其它三种也能走
/// 多签流程。如果协议上其实都支持，请告诉我，我再补齐。
///
/// 和白名单提案不同的一点：质押不要求这个多签账户"发行过"任何资产，
/// 任何有余额的多签账户都能质押，所以这里不需要"先查资产再过滤账户"这套
/// 白名单页面才有的复杂流程，直接列出本机全部多签账户即可（本地读取，
/// 量级天然很小）。
///
/// 流程：选本机多签账户 -> 输入资产ID+数量 -> 算出本机在该账户里的
/// 提案发起人候选(和 MultiSigAssetFreezeWidget.dart 的
/// _eligibleProposers/_pickProposer 套路一致) -> QccTxFlow 提交
/// /v1/mtxrule -> 存 MultiSigFileStorage -> 跳转 MultiSigInitiatedPage。
class MultiSigPledgeProposalWidget extends StatefulWidget {
  const MultiSigPledgeProposalWidget({super.key});

  @override
  State<MultiSigPledgeProposalWidget> createState() => _MultiSigPledgeProposalWidgetState();
}

class _MultiSigPledgeProposalWidgetState extends State<MultiSigPledgeProposalWidget> {
  List<MultiSigAccount> _localAccounts = [];
  MultiSigAccount? _selectedAccount;
  bool _isLoading = true;
  bool _isSubmitting = false;

  final _assetIdController = TextEditingController(text: "QCC");
  final _amountController = TextEditingController();

  List<String> _eligibleProposers = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final names = await QccStorage.getAllWalletNames();
    final accounts = await MultiSigAddressStorage.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localAccounts = accounts;
      _isLoading = false;
    });
    if (accounts.isNotEmpty) _onSelectAccount(accounts.first);
  }

  void _onSelectAccount(MultiSigAccount account) {
    setState(() => _selectedAccount = account);
    List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
    List<String> matched = localAddrs.where((a) => account.owners.contains(a)).toList();
    if (!mounted) return;
    setState(() {
      _eligibleProposers = matched;
      if (matched.isEmpty) {
        nowaddress = "";
      } else if (matched.contains(QccObj.activeWallet?.address)) {
        nowaddress = QccObj.activeWallet!.address;
      } else {
        nowaddress = matched.first;
      }
    });
  }

  void _pickProposer() {
    if (_eligibleProposers.length <= 1) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Trans("选择提案发起人", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _eligibleProposers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final addr = _eligibleProposers[i];
                    final bool isSelected = nowaddress == addr;
                    final String? nick = _walletNames[addr];
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.green : Colors.grey),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(addr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onTap: () {
                        setState(() => nowaddress = addr);
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmDialog(int amount, String assetId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("二次确认"),
        content: Text(
          "多签账号: ${_selectedAccount?.multiAddress}\n"
              "门限: ${_selectedAccount?.threshold}\n"
              "资产: $assetId\n数量: $amount\n"
              "类型: 稳定币质押(StablecoinPledege)\n\n"
              "提交后需要其余签署人共同签署满足门限才会生效。",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("确认发起")),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _handleSubmit() async {
    if (_selectedAccount == null) return;
    final assetId = _assetIdController.text.trim();
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (assetId.isEmpty || amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的资产ID和数量"));
      return;
    }
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择提案发起人"));
      return;
    }

    final confirmed = await _confirmDialog(amount, assetId);
    if (!confirmed) return;

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        final pledge = PledgeRules(
          address: _selectedAccount!.multiAddress,
          assetId: assetId,
          amount: amount,
          actionType: PledgeActionType.lock,
          protocol: PledgetType.stablecoinPledege,
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
      submitUrl: "https://tx.qccio.com/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      await MultiSigFileStorage.saveTask({
        ...resData,
        'ruleName': "PledgeRule",
        'protocol': PledgetType.stablecoinPledege,
        'assetId': assetId,
        'amount': amount,
        'multiAddress': _selectedAccount!.multiAddress,
        'owners': _selectedAccount!.owners,
        'threshold': _selectedAccount!.threshold,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'PENDING',
      });
      Tools.showToast(context, "✅ 质押提案已发起");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MultiSigInitiatedPage(
            txHash: resData['txHash']?.toString() ?? "",
            type: MultiSigPageType.append,
            owners: _selectedAccount!.owners,
            threshold: _selectedAccount!.threshold,
          ),
        ),
      );
    } else {
      LogObj.log("质押提案异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Trans("质押提案(多签)"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _localAccounts.isEmpty
          ? _buildEmptyState(Icons.account_balance_outlined, "本机未导入任何多签账户，无法发起质押提案。")
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoBanner(),
            const SizedBox(height: 16),
            _buildSectionCard("1. 选择多签账户", Icons.account_balance_outlined, _buildAccountDropdown()),
            const SizedBox(height: 16),
            _buildSectionCard("2. 资产与数量", Icons.token_outlined, _buildAssetAmountInput()),
            const SizedBox(height: 16),
            _buildMultiSigBalanceCard(),
            const SizedBox(height: 16),
            _buildProposerInfo(),
            const SizedBox(height: 40),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(child: Text("目前多签质押仅确认支持「稳定币质押」类型，其余质押类型的多签支持情况未经测试验证。", style: TextStyle(fontSize: 11, color: Colors.blueGrey))),
        ],
      ),
    );
  }

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

  Widget _buildSectionCard(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildAccountDropdown() {
    return DropdownButtonFormField<MultiSigAccount>(
      value: _selectedAccount,
      isExpanded: true,
      items: _localAccounts
          .map((acc) => DropdownMenuItem(value: acc, child: Text(acc.multiAddress, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))))
          .toList(),
      onChanged: (val) {
        if (val != null) _onSelectAccount(val);
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildAssetAmountInput() {
    return Column(
      children: [
        TextField(
          controller: _assetIdController,
          decoration: InputDecoration(labelText: Tools.getTra("资产ID"), border: const OutlineInputBorder()),
          // 【本次新增】资产ID改了要能实时刷新下面的多签账户余额展示。
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: Tools.getTra("质押数量 (最小单位)"), border: const OutlineInputBorder())),
      ],
    );
  }

  /// 【本次新增】多签账户(=质押发起时锁定资金的账户)的资产余额——
  /// 之前只显示"提案发起人"个人钱包的 QCC 余额，但真正会被扣款的是
  /// _selectedAccount.multiAddress 这个多签账户，不是发起人自己的钱包，
  /// 提交前理应先看一眼这个账户里够不够质押数量，所以单独加一张卡片，
  /// 跟随"资产ID"输入框实时切换要看哪个资产的余额。
  Widget _buildMultiSigBalanceCard() {
    if (_selectedAccount == null) return const SizedBox.shrink();
    final String assetId = _assetIdController.text.trim().isEmpty ? "QCC" : _assetIdController.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined, size: 14, color: Colors.deepPurple),
              const SizedBox(width: 6),
              Text(Tools.getTra("多签账户余额"), style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text("$assetId: ", style: const TextStyle(fontSize: 12, color: Colors.black54)),
              QccActiveWallet(_selectedAccount!.multiAddress, assetId, fontSize: 13, fontColor: Colors.black87),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedAccount!.multiAddress,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProposerInfo() {
    if (_selectedAccount != null && _eligibleProposers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.gpp_bad, size: 20, color: Colors.red),
            SizedBox(width: 10),
            Expanded(child: Text("本机没有属于该多签账户成员的地址，无法发起提案。", style: TextStyle(fontSize: 12))),
          ],
        ),
      );
    }

    String? nick = _walletNames[nowaddress];
    bool canSwitch = _eligibleProposers.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickProposer : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      text: "${Tools.getTra("提案发起人")}: ",
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                      children: [
                        TextSpan(text: nowaddress.isEmpty ? Tools.getTra("未选择") : nowaddress, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ),
                if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            if (nick != null)
              Padding(padding: const EdgeInsets.only(top: 4, left: 24), child: Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600))),
            if (nowaddress.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 24),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text("QCC 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    QccActiveWallet(nowaddress, "QCC", fontSize: 12, fontColor: Colors.black87),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = !_isSubmitting && nowaddress.isNotEmpty && _selectedAccount != null;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.deepPurple, Colors.purpleAccent]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起质押提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}