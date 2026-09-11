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
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/rule/user/multiple/multicreat/MultiSigAddressStorage.dart';
import 'package:qcc_flutter/rule/user/multiple/MultiSigFileStorage.dart';
import 'package:qcc_flutter/rule/user/multiple/multicreat/MultiSigInitiatedPage.dart';
import 'package:qcc_flutter/rule/user/multiple/QccMultiSig.dart';
import 'WhitelistUpdateRule.dart';

/// 白名单提案——多签版。
///
/// 【本轮重做，回应你的反馈】"MultiSigWhitelistProposalWidget 不能读取所有
/// 资产啊，qcc 未来可能数万个资产，你只能读取本地钱包地址涉及的资产，
/// 比如多签应该是本地读取多签地址是否有资产显示"——原来是"选资产 -> 反过来
/// 匹配本地多签账户"，第一步的下拉框就已经是全网全量资产。现在改成"先选
/// 本机已导入的多签账户（本地读取，量级很小）-> 只展示该账户名下确实有
/// 发行过的资产"，具体见 _initialLoad()/_onSelectAccount() 的详细说明。
///
/// 选中账户+资产之后的流程不变，和 MultiSigAssetFreezeWidget.dart 的
/// _eligibleProposers/_pickProposer()/_buildProposerInfo() 套路完全一致：
/// 算出本机在该账户里实际持有私钥的成员地址 -> 允许手动选择提案发起人 ->
/// 批量粘贴/输入拟加白或减白的地址 -> QccTxFlow.run() 提交到 /v1/mtxrule。
///
/// ruleName 直接写死 "WhitelistUpdateRule"——见 WhitelistUpdateRule.dart
/// 文件头注释第2点，这是本次三个 Java 源码里唯一一处 ruleName 字面量的
/// 直接调用证据，比其它规则靠枚举反推更硬。
///
/// 【依赖需要你核实，和 QccWhitelistManagePage.dart 同样的问题】
/// a. 资产下拉目前没有按 isWhitelist 过滤（QccAsset.dart 真实字段未知）。
/// b. 没有"该地址是否已在白名单内"的查询展示（未拿到对应查询接口源码）。
/// c. "只展示相关资产"目前仍是靠一次全量 fetchAllAssets() 拉回来后本地
///    过滤实现的（没有找到"按发行地址查询资产"的专属接口），解决了显示
///    正确性问题，没有解决未来资产数万级时这一次全量请求本身的规模问题——
///    如果有按地址查询的接口/方法，请告诉我。
class MultiSigWhitelistProposalWidget extends StatefulWidget {
  const MultiSigWhitelistProposalWidget({super.key});

  @override
  State<MultiSigWhitelistProposalWidget> createState() => _MultiSigWhitelistProposalWidgetState();
}

class _MultiSigWhitelistProposalWidgetState extends State<MultiSigWhitelistProposalWidget> {
  // 【本轮重做，回应你的反馈】"MultiSigWhitelistProposalWidget 不能读取所有
  // 资产啊，qcc 未来可能数万个资产，你只能读取本地钱包地址涉及的资产，
  // 多签应该是本地读取多签地址是否有资产显示"——原来的流程是"选资产 ->
  // 反过来匹配本地多签账户"，这意味着第一步的资产下拉框就已经是全网全量
  // 资产，规模上完全不对。现在整个顺序倒过来：
  //   第一步. 先读本机已导入的全部多签账户（MultiSigAddressStorage，纯本地，
  //      不发网络请求）——这个集合天然就很小（一个用户不会导入几万个
  //      多签账户）。
  //   第二步. 只有本机多签账户集合非空，才去查一次资产列表，查回来立刻按
  //      "资产发行地址 ∈ 本机多签地址集合"过滤，构建
  //      多签地址 -> 该地址名下资产列表 的映射。
  //   第三步. 下拉框第一步选"本机多签账户"，第二步选"该账户名下的资产"——
  //      而且直接只展示"名下确实有资产"的多签账户，账户下没有资产的
  //      直接不出现在第一层下拉框里，不会让用户选了又发现没资产可选。
  //
  // 【仍需你确认，见 QccWhitelistManagePage.dart 同一段说明】没有找到
  // "按地址查询资产"的专属接口，第2步事实上还是一次 fetchAllAssets() 全量
  // 拉取后本地过滤——解决了"显示不相关资产"的正确性问题，没有解决"未来
  // 资产数万级时这一次全量请求"的规模问题。如果有按地址查询的接口/方法，
  // 请告诉我，我把这里换掉。
  List<MultiSigAccount> _localAccounts = []; // 本机全部多签账户（未过滤）
  Map<String, List<QccAsset>> _assetsByAccount = {}; // multiAddress -> 该账户名下资产
  List<MultiSigAccount> _accountsWithAssets = []; // 名下确实有资产的多签账户，供下拉选择

  MultiSigAccount? _selectedAccount;
  QccAsset? _selectedAsset;
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<String> _eligibleProposers = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  final _addressesController = TextEditingController();
  List<String> _parsedAddresses = [];

  String _op = WhitelistOp.add;

  List<QccAsset> get _assetsForSelectedAccount =>
      _selectedAccount == null ? [] : (_assetsByAccount[_selectedAccount!.multiAddress] ?? []);

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      final names = await QccStorage.getAllWalletNames();
      final localAccounts = await MultiSigAddressStorage.getAllAccounts();

      if (!mounted) return;

      if (localAccounts.isEmpty) {
        // 本机没有导入任何多签账户，压根不用查资产。
        setState(() {
          _walletNames = names;
          _localAccounts = [];
          _isLoading = false;
        });
        return;
      }

      final multiAddrSet = localAccounts.map((a) => a.multiAddress.toLowerCase()).toSet();
      List<QccAsset> allAssets = await QccAssetService().fetchAllAssets();

      final Map<String, List<QccAsset>> byAccount = {};
      for (final asset in allAssets) {
        final addrLower = asset.address.toLowerCase();
        if (multiAddrSet.contains(addrLower)) {
          // 找到对应的原始大小写 multiAddress 作为 key。
          final owner = localAccounts.firstWhere((a) => a.multiAddress.toLowerCase() == addrLower);
          byAccount.putIfAbsent(owner.multiAddress, () => []).add(asset);
        }
      }

      final accountsWithAssets = localAccounts.where((a) => (byAccount[a.multiAddress] ?? []).isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _walletNames = names;
        _localAccounts = localAccounts;
        _assetsByAccount = byAccount;
        _accountsWithAssets = accountsWithAssets;
        _isLoading = false;
      });

      if (accountsWithAssets.isNotEmpty) {
        _onSelectAccount(accountsWithAssets.first);
      }
    } catch (e) {
      LogObj.log("加载白名单提案页失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 选中"本机多签账户"后：刷新该账户名下的资产下拉（默认选第一个），
  /// 并重新计算本机在这个账户里持有私钥的成员地址（提案发起人候选）。
  void _onSelectAccount(MultiSigAccount account) {
    setState(() {
      _selectedAccount = account;
      final assets = _assetsByAccount[account.multiAddress] ?? [];
      _selectedAsset = assets.isNotEmpty ? assets.first : null;
    });
    _verifyWalletOwnership(account);
  }

  void _verifyWalletOwnership(MultiSigAccount account) {
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

  void _parseAddresses(String raw) {
    final parts = raw
        .split(RegExp(r'[\s,，;；\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    setState(() => _parsedAddresses = parts);
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
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
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

  Future<bool> _confirmDialog() async {
    final actionText = _op == WhitelistOp.add ? "加入白名单" : "移出白名单";
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _op == WhitelistOp.add ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Trans("二次确认"),
        ]),
        content: Text(
          "资产: ${_selectedAsset?.assetId}\n"
              "操作: $actionText\n"
              "地址数量: ${_parsedAddresses.length}\n"
              "多签账号: ${_selectedAccount?.multiAddress}\n"
              "门限: ${_selectedAccount?.threshold}\n\n"
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
    if (_selectedAsset == null || _selectedAccount == null) return;
    if (_parsedAddresses.isEmpty) {
      Tools.showToast(context, Tools.getTra("请至少输入一个地址"));
      return;
    }
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择提案发起人"));
      return;
    }

    final confirmed = await _confirmDialog();
    if (!confirmed) return;

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        WhitelistUpdateRule whitelistRule = WhitelistUpdateRule(
          assetId: _selectedAsset!.assetId,
          operator: wallet.address,
          op: _op,
          addresses: _parsedAddresses,
        );

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule";
        rule.ruleName = kWhitelistUpdateRuleName;
        rule.ruleJson = jsonEncode(whitelistRule.toJson());
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
        'ruleName': kWhitelistUpdateRuleName,
        'assetId': _selectedAsset!.assetId,
        'op': _op,
        'addresses': _parsedAddresses,
        'addressCount': _parsedAddresses.length,
        'multiAddress': _selectedAccount!.multiAddress,
        'owners': _selectedAccount!.owners,
        'threshold': _selectedAccount!.threshold,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'PENDING',
      });
      Tools.showToast(context, "✅ 白名单提案已发起");

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
      LogObj.log("白名单提案异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Trans("白名单提案(多签)"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _localAccounts.isEmpty
          ? _buildEmptyState(Icons.account_balance_outlined, "本机未导入任何多签账户，无法发起白名单提案。")
          : _accountsWithAssets.isEmpty
          ? _buildEmptyState(Icons.token_outlined, "本机导入的多签账户暂未发行任何资产。\n只有资产的发行多签账户才能发起白名单提案。")
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSectionCard("1. 选择多签账户 (本机已导入且有发行资产)", Icons.account_balance_outlined, _buildAccountDisplay()),
            const SizedBox(height: 16),
            _buildSectionCard("2. 选择该账户名下资产", Icons.token_outlined, _buildAssetDropdown()),
            const SizedBox(height: 16),
            _buildSectionCard("3. 操作类型", Icons.rule_folder_outlined, _buildOpSelector()),
            const SizedBox(height: 16),
            _buildSectionCard("4. 批量地址 (每行一个，或用逗号/空格分隔)", Icons.list_alt_outlined, _buildAddressInput()),
            const SizedBox(height: 16),
            _buildProposerInfo(),
            const SizedBox(height: 40),
            _buildSubmitButton(),
          ],
        ),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
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

  /// 第1步：选本机多签账户——只列出"名下确实有资产"的账户
  /// （_accountsWithAssets），而不是本机导入的全部多签账户。
  Widget _buildAccountDisplay() {
    return DropdownButtonFormField<MultiSigAccount>(
      value: _selectedAccount,
      isExpanded: true,
      hint: const Text("选择多签账号"),
      items: _accountsWithAssets
          .map((acc) => DropdownMenuItem(value: acc, child: Text(acc.multiAddress, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))))
          .toList(),
      onChanged: (val) {
        if (val != null) _onSelectAccount(val);
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  /// 第2步：选该账户名下的资产——只从 _assetsForSelectedAccount 里选，
  /// 不再是全网资产列表。
  Widget _buildAssetDropdown() {
    final assets = _assetsForSelectedAccount;
    return DropdownButtonFormField<QccAsset>(
      value: _selectedAsset,
      isExpanded: true,
      items: assets.map((a) => DropdownMenuItem(value: a, child: Text("${a.assetId} (Precision: ${a.precision})"))).toList(),
      onChanged: (val) {
        if (val != null) setState(() => _selectedAsset = val);
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildOpSelector() {
    return SegmentedButton<String>(
      segments: <ButtonSegment<String>>[
        ButtonSegment<String>(value: WhitelistOp.add, label: Trans("加入白名单"), icon: const Icon(Icons.person_add_alt_1_outlined, size: 18)),
        ButtonSegment<String>(value: WhitelistOp.remove, label: Trans("移出白名单"), icon: const Icon(Icons.person_remove_outlined, size: 18)),
      ],
      selected: <String>{_op},
      onSelectionChanged: (s) => setState(() => _op = s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: _op == WhitelistOp.add ? Colors.green : Colors.redAccent,
        selectedForegroundColor: Colors.white,
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildAddressInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _addressesController,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: "Q1...\nQ2...\n(每行一个地址，也可以逗号/空格分隔粘贴)",
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste, size: 18),
              onPressed: () async {
                var data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  _addressesController.text = data!.text!;
                  _parseAddresses(data.text!);
                }
              },
            ),
          ),
          onChanged: _parseAddresses,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.tag, size: 14, color: Colors.blueGrey.shade400),
          const SizedBox(width: 4),
          Text("已解析地址: ${_parsedAddresses.length} 个", style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600)),
        ]),
      ],
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
                        TextSpan(
                          text: nowaddress.isEmpty ? Tools.getTra("未选择") : nowaddress,
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            if (nick != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
              ),
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
    bool active = !_isSubmitting && nowaddress.isNotEmpty && _selectedAccount != null && _selectedAsset != null && _parsedAddresses.isNotEmpty;
    Color themeColor = _op == WhitelistOp.add ? Colors.green : Colors.redAccent;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? LinearGradient(colors: [themeColor, themeColor.withOpacity(0.8)]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans(_op == WhitelistOp.add ? "确认发起加白提案" : "确认发起减白提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}