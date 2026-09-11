import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../../home/QccExplorerService.dart';
import '../../../../procotol/QccTxFlow.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../utile/QccObj.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/myasset/QccAsset.dart';
import '../../../../views/myasset/QccAssetService.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../../user/multiple/MultiSigFileStorage.dart';
import '../../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../../user/multiple/QccMultiSig.dart';
import '../AssetFreezeRule.dart';
import '../../core/AssetMeta.dart';

/// 多签资产冻结/解冻提案——本轮按你的 4 点要求整体重做：
///
/// 1.【新增签署地址】原代码 _verifySignerPermission() 直接把
///    QccObj.activeWallet!.address 当成签署人，如果活跃钱包根本不是这个
///    多签账户的成员，_nowAddress 会被塞进一句中文提示（"活跃钱包非该多签
///    成员"）当地址用，_handleFreezeSubmit 拿这个"地址"去 QccStorage.
///    restoreWallet 必然失败，而且用户完全没有机会换一个真正有权限的本地
///    地址去发起——这是原代码本来就没法用的一个硬伤。现在改成和
///    MultiSigAssetMintWidget.dart 一致的 _eligibleProposers/_pickProposer()/
///    _buildProposerInfo() 套路：选中多签账号后，算出本机在这个账户里
///    实际持有私钥的全部地址，允许手动选择提案发起人，展示昵称 + QCC 余额。
/// 2.【查询地址是否已经被冻结】目标地址输入框新增 onChanged 联动查询——
///    复用 QccFreezePage.dart 里已经按 AssetFrozenContext.java 源码核实过的
///    GET /v1/assetFrozen?address={address}&asset={assetId} 接口
///    （注意参数名是 asset，不是 assetId；返回信封是
///    {ok, kind, data:{status:"FROZEN"|"NORMAL"}}），发起解冻前先看一眼
///    这个地址现在到底是不是真的处于冻结状态，避免签一个没有意义的提案。
/// 3.【多签冻结状态中心】新增 MultiSigFreezeStatusCenterPage.dart（同目录），
///    展示本机发起过的多签冻结/解冻提案列表及签署进度——和单签那边的
///    QccFreezeHistoryPage（读 AssetFreezeStorage）不是同一个数据源，这里
///    读的是 MultiSigFileStorage（多签提案通用的本地记录），因为冻结提案
///    走的是 /v1/mtxrule 多签流程，不是单签的 /v1/rule。
/// 4.【多签冻结追随签署】新增 MultiSigAssetFreezeFollowSignWidget.dart
///    （同目录）——粘贴 Hash 查询冻结/解冻提案摘要并追加签署，做法对齐
///    AssetMintFollowSignWidget.dart，只是把 ruleJson 换成 AssetFreezeRule
///    专属的 assetId/targetAddress/freeze/expiry 四个字段。
///
/// 【顺带修复，同一类问题】
/// a. rule.ruleName 原来写的是字面量 "AssetFreeze"——按 QccFreezePage.dart
///    （已用你贴的 Java 源码/既有约定核实过）单签冻结用的是
///    AssetType.AssetFreezeRule.name（即 "AssetFreezeRule"，对应 Java 类名），
///    多签走的是同一套规则模型，ruleName 必须和单签一致，否则公链那边按
///    ruleName 分发规则解析器时会找不到对应的处理器。这里改成
///    AssetType.AssetFreezeRule.name。
/// b. 签名提交原来走 compute + QccDataProtocol.encodeTransaction（该方法
///    内部签名逻辑被注释掉，signature 恒为空字符串——本 session 里其它
///    页面都踩过的同一个坑），现在统一改走 QccTxFlow.run()。
/// c. MultiSigFileStorage.saveTask(resData) 原来直接存服务端原始返回，不
///    保证带 assetId/targetAddress/freeze/owners/threshold 这些本地展示
///    需要的字段（这几个字段服务端 ACK 是否回传不确定）。现在改成显式
///    合并一份完整记录再保存，新增的状态中心页面才有数据可读。
/// d. MultiSigInitiatedPage 的 type 原来传的是 MultiSigPageType.transfer——
///    这是个规则提案（冻结），不是转账，按 MultiSigAssetMintWidget.dart
///    的同类修法改成 MultiSigPageType.append（借用它的展示逻辑）。
///
/// 【依赖需要你核实】按这份文件自己原有的相对 import 深度推算，
/// AssetMeta.dart 在这里的路径是 '../../core/AssetMeta.dart'；如果实际路径
/// 不同，编译会直接报错，麻烦告诉我真实位置。
class MultiSigAssetFreezeWidget extends StatefulWidget {
  const MultiSigAssetFreezeWidget({super.key});

  @override
  State<MultiSigAssetFreezeWidget> createState() => _MultiSigAssetFreezeWidgetState();
}

enum FreezeAction { freeze, unfreeze }

class _MultiSigAssetFreezeWidgetState extends State<MultiSigAssetFreezeWidget> {
  final _formKey = GlobalKey<FormState>();
  final _targetAddressController = TextEditingController();

  List<QccAsset> _freezableAssets = [];
  QccAsset? _selectedAsset;

  List<MultiSigAccount> _matchedAccounts = [];
  MultiSigAccount? _selectedAccount;

  bool _isLoading = true;
  bool _isSubmitting = false;

  // 【新增，替换原来的 _nowAddress/_canSign】选中多签账户里，本机实际
  // 持有私钥的成员地址——用于"提案发起人可选择"，命名和做法对齐
  // MultiSigAssetMintWidget.dart。
  List<String> _eligibleProposers = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  // 【新增】目标地址在当前选中资产下的冻结状态：null=未知/未查询，
  // true=已冻结，false=未冻结。做法对齐 QccFreezePage.dart。
  bool? _targetFrozen;
  bool _isCheckingFrozen = false;

  // 操作状态：默认为冻结
  FreezeAction _currentAction = FreezeAction.freeze;

  @override
  void initState() {
    super.initState();
    _initialLoadFlow();
  }

  Future<void> _initialLoadFlow() async {
    try {
      final names = await QccStorage.getAllWalletNames();
      List<QccAsset> assets = await QccAssetService().fetchAllAssets();
      List<QccAsset> filtered = assets.where((a) => a.address.startsWith('M') == true).toList();

      if (!mounted) return;
      setState(() {
        _walletNames = names;
        _freezableAssets = filtered;
        _isLoading = false;
      });

      if (_freezableAssets.isNotEmpty) {
        setState(() => _selectedAsset = _freezableAssets.first);
        await _matchIssuerToLocalMultiSig(_selectedAsset!.address);
      }
    } catch (e) {
      LogObj.log("加载冻结流程失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _matchIssuerToLocalMultiSig(String issuerAddress) async {
    final allMultiAccounts = await MultiSigAddressStorage.getAllAccounts();
    List<MultiSigAccount> matched = allMultiAccounts
        .where((acc) => acc.multiAddress.toLowerCase() == issuerAddress.toLowerCase())
        .toList();

    if (!mounted) return;
    setState(() {
      _matchedAccounts = matched;
      _selectedAccount = matched.isNotEmpty ? matched.first : null;
    });

    if (matched.isEmpty) {
      setState(() {
        _eligibleProposers = [];
        nowaddress = "";
      });
      _showNoPermissionDialog(issuerAddress);
    } else {
      _verifyWalletOwnership(_selectedAccount!);
    }
  }

  /// 【重写，见文件头部第1点】原来的 _verifySignerPermission 只会强行认定
  /// QccObj.activeWallet 是签署人，现在改成算出本机全部可用地址，交给
  /// 用户在 _pickProposer() 里手动选。
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

  void _showNoPermissionDialog(String addr) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.warning, color: Colors.orange), const SizedBox(width: 8), Trans("权限受限")]),
        content: Text("本地未找到该资产的发行多签账号：\n\n$addr\n\n您无法发起冻结/解冻提案。"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Trans("确定"))],
      ),
    );
  }

  /// 【新增，见文件头部第2点】查询目标地址在当前选中资产下是否已处于
  /// 冻结状态——和 QccFreezePage.dart 的 _checkFrozenStatus 完全一致。
  Future<void> _checkFrozenStatus(String address) async {
    if (address.isEmpty || _selectedAsset == null) {
      if (mounted) setState(() => _targetFrozen = null);
      return;
    }
    setState(() {
      _isCheckingFrozen = true;
      _targetFrozen = null;
    });
    try {
      final assetId = _selectedAsset!.assetId;
      final resp = await http.get(Uri.parse(
          "${QccExplorerService.baseUrl}/v1/assetFrozen?address=$address&asset=$assetId"));
      if (resp.statusCode == 200) {
        final res = jsonDecode(resp.body);
        if (res['ok'] == true) {
          final data = res['data'];
          final String? status = data is Map ? data['status']?.toString() : null;
          if (mounted) setState(() => _targetFrozen = status == 'FROZEN');
        } else {
          LogObj.log("查询地址冻结状态失败: ${res['error']}");
          if (mounted) setState(() => _targetFrozen = null);
        }
      }
    } catch (e) {
      LogObj.log("查询地址冻结状态失败: $e");
      if (mounted) setState(() => _targetFrozen = null);
    } finally {
      if (mounted) setState(() => _isCheckingFrozen = false);
    }
  }

  /// 提案发起人选择弹层——列出本机在该多签账户里持有私钥的全部地址，
  /// 展示昵称，选中后 _buildProposerInfo() 会显示对应的 QCC 余额。
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Trans("资产冻结/解冻管理"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildActionSelector(),
              const SizedBox(height: 16),
              _buildSectionCard("1. 选择目标资产", Icons.token_outlined, _buildAssetDropdown()),
              const SizedBox(height: 16),
              if (_selectedAsset != null) _buildAssetInfoChip(),
              const SizedBox(height: 16),
              _buildSectionCard("2. 发行多签账号 (自动匹配)", Icons.account_balance_outlined, _buildAccountDisplay()),
              const SizedBox(height: 16),
              _buildSectionCard("3. 目标地址 (Target Address)", Icons.person_pin_circle_outlined, _buildTargetAddressInput()),
              // 【新增，见文件头部第2点】目标地址冻结状态查询结果
              _buildFrozenStatusRow(),
              // 【新增，本轮要求】和单签 QccFreezePage.dart 一样，输入目标
              // 地址后展示该地址在当前选中资产下的余额，做法与
              // _buildTargetBalanceRow() 完全一致。
              _buildTargetBalanceRow(),
              const SizedBox(height: 16),
              // 【替换】原来的 _buildSignerStatusCard() 只显示一句话，现在
              // 换成可点击切换的提案发起人信息卡（昵称+QCC余额）。
              _buildProposerInfo(),
              const SizedBox(height: 40),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: SegmentedButton<FreezeAction>(
        segments: <ButtonSegment<FreezeAction>>[
          ButtonSegment<FreezeAction>(
            value: FreezeAction.freeze,
            label: Trans("冻结资产"),
            icon: const Icon(Icons.lock_outline, size: 18),
          ),
          ButtonSegment<FreezeAction>(
            value: FreezeAction.unfreeze,
            label: Trans("解冻资产"),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
          ),
        ],
        selected: <FreezeAction>{_currentAction},
        onSelectionChanged: (Set<FreezeAction> newSelection) {
          setState(() {
            _currentAction = newSelection.first;
          });
        },
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: _currentAction == FreezeAction.freeze ? Colors.redAccent : Colors.green,
          selectedForegroundColor: Colors.white,
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Widget child) {
    Color themeColor = _currentAction == FreezeAction.freeze ? Colors.redAccent : Colors.green;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: themeColor),
              const SizedBox(width: 8),
              Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildAssetDropdown() {
    return DropdownButtonFormField<QccAsset>(
      value: _selectedAsset,
      isExpanded: true,
      items: _freezableAssets.map((a) => DropdownMenuItem(value: a, child: Text("${a.assetId} (Precision: ${a.precision})"))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAsset = val);
          _matchIssuerToLocalMultiSig(val.address);
          // 【新增】换资产后，之前查到的目标地址冻结状态是针对旧资产的，
          // 需要重新查一次。
          _checkFrozenStatus(_targetAddressController.text.trim());
        }
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildAssetInfoChip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoItem("类型", _selectedAsset!.type),
          _infoItem("精度", _selectedAsset!.precision.toString()),
          _infoItem("限制功能", "可管控", color: Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildAccountDisplay() {
    return DropdownButtonFormField<MultiSigAccount>(
      initialValue: _selectedAccount,
      isExpanded: true,
      hint: Text(_matchedAccounts.isEmpty ? "无匹配多签账号" : "选择多签账号"),
      items: _matchedAccounts.map((acc) => DropdownMenuItem(value: acc, child: Text(acc.multiAddress, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAccount = val);
          _verifyWalletOwnership(val);
        }
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildTargetAddressInput() {
    String actionText = _currentAction == FreezeAction.freeze ? "冻结" : "解冻";
    return TextFormField(
      controller: _targetAddressController,
      decoration: InputDecoration(
        labelText: "拟${actionText}的目标地址",
        hintText: "Q1...",
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person_search, size: 20),
        suffixIcon: IconButton(icon: const Icon(Icons.paste, size: 18), onPressed: () async {
          var data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data != null) {
            _targetAddressController.text = data.text!;
            _checkFrozenStatus(data.text!.trim());
          }
        }),
      ),
      // 【新增】地址变动时自动查一次冻结状态。
      onChanged: (v) => _checkFrozenStatus(v.trim()),
      validator: (v) => (v == null || v.isEmpty) ? "请输入地址" : null,
    );
  }

  /// 【新增，见文件头部第2点】目标地址冻结状态查询结果展示。
  Widget _buildFrozenStatusRow() {
    if (_targetAddressController.text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (_isCheckingFrozen)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(
              _targetFrozen == null ? Icons.help_outline : (_targetFrozen! ? Icons.ac_unit : Icons.wb_sunny_outlined),
              size: 14,
              color: _targetFrozen == null ? Colors.grey : (_targetFrozen! ? Colors.blueGrey : Colors.green),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _isCheckingFrozen
                  ? "正在查询该地址冻结状态..."
                  : (_targetFrozen == null
                  ? "该地址当前冻结状态未知（查询失败或接口无返回）"
                  : (_targetFrozen! ? "该地址在此资产下当前已处于冻结状态" : "该地址在此资产下当前未被冻结")),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  /// 【新增，本轮要求："在多签冻结提案，也需要优化和单签一样，在输入冻结
  /// 地址时候，显示地址对应的资产的余额"】目标地址在当前选中资产下的余额
  /// 展示——和 QccFreezePage.dart 的 _buildTargetBalanceRow() 完全一致，
  /// 复用已经 import 的 QccActiveWallet（本文件第10行），不需要新增依赖。
  Widget _buildTargetBalanceRow() {
    final target = _targetAddressController.text.trim();
    if (target.isEmpty || _selectedAsset == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
          const SizedBox(width: 4),
          Text("该地址 ${_selectedAsset!.assetId} 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          QccActiveWallet(target, _selectedAsset!.assetId, fontSize: 12, fontColor: Colors.black87),
        ],
      ),
    );
  }

  /// 【替换，见文件头部第1点】提案发起人信息卡：本机没有成员地址时红色
  /// 提示；否则展示当前选中地址的昵称 + QCC 余额，多于1个可选地址时可
  /// 点击切换，做法对齐 MultiSigAssetMintWidget.dart 的 _buildProposerInfo。
  Widget _buildProposerInfo() {
    if (_selectedAccount != null && _eligibleProposers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
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
        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
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
    Color themeColor = _currentAction == FreezeAction.freeze ? Colors.redAccent : Colors.green;
    bool active = !_isSubmitting && nowaddress.isNotEmpty && _selectedAccount != null && _selectedAsset != null;
    String actionText = _currentAction == FreezeAction.freeze ? "冻结" : "解冻";

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? LinearGradient(colors: [themeColor, themeColor.withValues(alpha: 0.8)]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleFreezeSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起${actionText}提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _infoItem(String label, String val, {Color color = Colors.black}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // --- 核心逻辑：统一走 QccTxFlow.run()，见文件头部第 b 点 ---
  Future<void> _handleFreezeSubmit() async {
    if (!_formKey.currentState!.validate() || _selectedAsset == null || _selectedAccount == null) return;
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择提案发起人"));
      return;
    }

    String targetAddr = _targetAddressController.text.trim();

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        // 1. 构建模型 (expiry 固定为 0，代表永久直至手动撤销)
        AssetFreezeRule freezeRule = AssetFreezeRule(
          assetId: _selectedAsset!.assetId,
          targetAddress: targetAddr,
          freeze: _currentAction == FreezeAction.freeze,
          expiry: 0,
        );
        // 2. 构建 RuleData 容器
        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule";
        // 【修复，见文件头部第 a 点】原来写的是字面量 "AssetFreeze"，必须
        // 和单签冻结（QccFreezePage.dart）一样用 "AssetFreezeRule"，否则
        // 公链按 ruleName 分发规则解析器时会找不到处理器。
        rule.ruleName = AssetType.AssetFreezeRule.name;
        rule.ruleJson = jsonEncode(freezeRule.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result.cancelled) return;
    if (result.success) {
      final resData = result.data!;
      await MultiSigFileStorage.saveTask({
        ...resData,
        'ruleName': AssetType.AssetFreezeRule.name,
        'assetId': _selectedAsset!.assetId,
        'targetAddress': targetAddr,
        'freeze': _currentAction == FreezeAction.freeze,
        'multiAddress': _selectedAccount!.multiAddress,
        'owners': _selectedAccount!.owners,
        'threshold': _selectedAccount!.threshold,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'PENDING',
      });
      Tools.showToast(context, "✅ 提案已发起");

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MultiSigInitiatedPage(
            txHash: resData['txHash']?.toString() ?? "",
            // 【修复，见文件头部第 d 点】这是规则提案（冻结），不是转账，
            // 借用 append 的展示逻辑，和 MultiSigAssetMintWidget.dart 一致。
            type: MultiSigPageType.append,
            owners: _selectedAccount!.owners,
            threshold: _selectedAccount!.threshold,
          ),
        ),
      );
    } else {
      LogObj.log("多签冻结提案异常: ${result.data}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }
}