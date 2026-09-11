import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../home/QccExplorerService.dart';
import '../../../procotol/RuleData.dart';
// 【本次修正，对应你指出的问题】原来这里签名走的是
// QccDataProtocol.encodeTransaction()——这个方法内部的真实签名代码整段被
// 注释掉了(见 QccDataProtocol.dart 第29-35行)，固定 return signature: ""，
// 也就是说之前这个页面提交的多签发行提案，签名字段自始至终是空字符串，
// 链上大概率会因为"签名校验失败"直接拒绝。QccTxFlow.run() 内部改用
// SignUtil.instance.signAndEncode()，这是本 session 里其它多签提案页面
// (MultiSigPledgeProposalWidget.dart 等)已经在用、经过验证的新签名方式，
// 这里换成同一套，不再自己手写 compute()/_signRuleTask()。
import '../../../procotol/QccTxFlow.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../user/multiple/QccMultiSig.dart';
import '../AssetFileStorage.dart';
import '../core/AssetMeta.dart';
import '../AssetMultiSigProposalPage.dart';

class MultiSigStableCoinIssueWidget extends StatefulWidget {
  const MultiSigStableCoinIssueWidget({super.key});

  @override
  State<MultiSigStableCoinIssueWidget> createState() => _MultiSigStableCoinIssueWidgetState();
}

class _MultiSigStableCoinIssueWidgetState extends State<MultiSigStableCoinIssueWidget> {
  final _formKey = GlobalKey<FormState>();
  final _assetIdController = TextEditingController();
  final _supplyController = TextEditingController(text: "100000"); // 默认10万
  final _precisionController = TextEditingController(text: "2");   // 默认精度2

  List<MultiSigAccount> _accounts = [];
  MultiSigAccount? _selectedAccount;
  Map<String, String> _walletNames = {};

  String _nowAddress = "";
  List<String> _eligibleProposers = [];
  bool _canSign = false;
  bool _isAssetIdAvailable = true;
  bool _isCheckingAsset = false;
  bool _isLoading = true;
  bool _mintable = true;   //允许增发
  bool _freezable = true;  //允许冻结
  // 【本次新增】允许销毁——稳定币发行默认开启(和 mintable/freezable 同一
  // 模式)，注意这跟 AssetMeta.dart 里 burnable 字段本身的类默认值 false
  // 不是一回事：那个 false 是"没有主动设置时"的兜底默认，这里是"稳定币
  // 发行表单"这个具体场景下，UI 初始勾选状态按你的要求给成 true。
  bool _burnable = true;

  Timer? _assetCheckDebounce;

  @override
  void initState() {
    super.initState();
    _loadMultiSigAccounts();
  }

  @override
  void dispose() {
    _assetCheckDebounce?.cancel();
    super.dispose();
  }

  // --- 载入本机全部多签账户(不再按"当前活跃钱包是否是成员"过滤)---
  // 【本次修改，对应你的要求1】原来这里只列出"当前活跃单签钱包恰好是成员"
  // 的多签账户，选择面很窄；现在改成本机全部多签账户都能选，具体能不能
  // 签名交给下面 _computeEligibleProposers() 在选定账户之后单独判断。
  void _loadMultiSigAccounts() async {
    final names = await QccStorage.getAllWalletNames();
    final list = await MultiSigAddressStorage.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _accounts = list;
      if (_accounts.isNotEmpty) {
        _selectedAccount = _accounts.first;
      } else {
        _isLoading = false;
      }
    });
    if (_selectedAccount != null) _computeEligibleProposers(_selectedAccount!);
  }

  /// 【本次新增，对应你的要求2】选定多签账户后，算出本机哪些单签地址属于
  /// 该账户的成员(owners ∩ 本机钱包)，供发起人下拉/弹出选择——和
  /// MultiSigPledgeProposalWidget.dart 的 _eligibleProposers/_pickProposer
  /// 套路完全一致，方便你对比审阅。
  void _computeEligibleProposers(MultiSigAccount account) {
    List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
    List<String> matched = localAddrs.where((a) => account.owners.contains(a)).toList();
    if (!mounted) return;
    setState(() {
      _eligibleProposers = matched;
      if (matched.isEmpty) {
        _nowAddress = "";
        _canSign = false;
      } else {
        final active = QccObj.activeWallet?.address;
        _nowAddress = (active != null && matched.contains(active)) ? active : matched.first;
        _canSign = true;
      }
      _isLoading = false;
    });
  }

  /// 【本次新增】发起人有多个候选时，弹出底部选择列表——同
  /// MultiSigPledgeProposalWidget.dart 的 _pickProposer()。
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
                    final bool isSelected = _nowAddress == addr;
                    final String? nick = _walletNames[addr];
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.green : Colors.grey),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(addr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onTap: () {
                        setState(() => _nowAddress = addr);
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


  /// 【本次新增，对应你的要求3】输入框每敲一个字符都会触发这个回调，之前
  /// 直接调 _checkAssetId 意味着每个字符都发一次整表查询请求——加 500ms
  /// 防抖，只在用户停止输入后才真正查一次，同时用户清空输入框时立刻把
  /// "可用"状态复位，避免残留上一次查询的结果。
  void _onAssetIdChanged(String v) {
    _assetCheckDebounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _isAssetIdAvailable = true);
      return;
    }
    _assetCheckDebounce = Timer(const Duration(milliseconds: 500), () => _checkAssetId(v.trim()));
  }

  /// 资产 ID 查重：GET 全量资产列表，本机比对是否已存在同名 assetId。
  Future<void> _checkAssetId(String assetId) async {
    if (assetId.isEmpty) return;
    setState(() => _isCheckingAsset = true);
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        List assets = jsonDecode(res['data']);
        bool exists = assets.any((a) => a['assetId'].toString().toUpperCase() == assetId.toUpperCase());
        if (!mounted) return;
        // 防抖之后仍要防"慢请求"：只有当前输入框内容还等于发起这次查询时
        // 的内容，才采纳结果——避免用户又改了字符之后，一个更早发出、更慢
        // 返回的请求把新输入的正确状态覆盖掉。
        if (_assetIdController.text.trim().toUpperCase() == assetId.toUpperCase()) {
          setState(() => _isAssetIdAvailable = !exists);
        }
      }
    } catch (e) {
      LogObj.log("资产查重失败: $e");
    } finally {
      if (mounted) setState(() => _isCheckingAsset = false);
    }
  }

  // 【本次修正，对应你指出"签名方式你没有修改"】原来这里手写
  // compute(_signRuleTask,...) -> QccDataProtocol.encodeTransaction()，而
  // encodeTransaction() 内部真正的签名调用整段被注释掉了(QccDataProtocol.dart
  // 29-35行)，固定返回 signature:""——也就是说这个页面之前提交的多签发行
  // 提案，签名字段自始至终是空字符串。现在改用 QccTxFlow.run()，内部走
  // SignUtil.instance.signAndEncode()，和本 session 里其它多签提案页面
  // (MultiSigPledgeProposalWidget.dart 等)用的是同一套已验证过的签名方式。
  // 副带的好处：密码框/loading 的显示顺序、try/catch 兜底也都统一交给
  // QccTxFlow.run() 处理，不用在这个函数里再重复维护。
  Future<void> _onIssueProposal() async {
    if (!_formKey.currentState!.validate() || !_canSign) return;

    int precision = int.parse(_precisionController.text);
    int supplyCount = int.parse(_supplyController.text);
    LogObj.log("提交稳定币提案:");
    LogObj.log("多签地址: ${_selectedAccount?.multiAddress}");

    // buildPayload 回调里才拿得到 rule.id(finalizeId() 之后才有)，供成功后
    // 跳转结果页使用——这里先在外层声明一个闭包变量接住它，和 QccTxFlow.dart
    // 文件头注释里说的"调用方可以在回调内部把它存到外层闭包变量里"是同一个
    // 用法。
    String finalizedRuleId = "";

    final result = await QccTxFlow.run(
      context: context,
      address: _nowAddress,
      buildPayload: (wallet) async {
        final multiAddr = _selectedAccount!.multiAddress;
        final assetId = _assetIdController.text;
        // 1. 构建模型
        AssetMeta meta = AssetMeta(assetId, multiAddr);
        meta.precision = precision;
        meta.mintable = _mintable;
        meta.freezable = _freezable;
        // 【本次新增，对应你的要求4】允许销毁——AssetMeta.dart 里这个字段
        // 类默认值是 false(对齐 Java 未显式赋值的 boolean 默认值)，但稳定币
        // 发行这个具体表单按你的要求把 UI 初始状态设成了默认允许(_burnable
        // 状态变量默认 true)，这里把用户在开关里的选择写进 meta。
        meta.burnable = _burnable;
        meta.type = "Stablecoin";  //.name;--重要稳定币标记
        meta.owner = multiAddr;
        // 2. 初始供应量换算 (int 对应 Java long)：输入10万，精度2，
        // Java端存10000000 (10万 * 10^2)
        meta.initialSupply = (supplyCount * pow(10, precision)).toInt();

        // 3. 构建 RuleData 容器
        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
        rule.ruleName = AssetType.AssetMeta.name;
        rule.ruleJson = jsonEncode(meta.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();
        finalizedRuleId = rule.id;

        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mtxrule",
    );

    if (!mounted) return;

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      resData['ruleName'] = AssetType.AssetMeta.name;
      await AssetFileStorage.saveAsset(resData);
      Tools.showToast(context, "✅ 资产发行规则已广播成功");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: finalizedRuleId)),
        );
      }
    } else {
      LogObj.log("多签稳定币发行提案失败: ${result.error}");
      Tools.showToast(context, "❌ ${result.error ?? "提案发布失败"}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签稳定币发行")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
      // 【本次新增，修复潜在崩溃】_accounts 为空时 _selectedAccount 会一直是
      // null——原文件在这种情况下仍然会往下渲染整个表单，其中
      // _buildMultiSigBalanceBar() 里 `_selectedAccount!.multiAddress` 是
      // 强制解包，遇到 null 会直接抛 null-check 异常崩溃(这是原上传文件就
      // 有的问题，不是这次改动引入的)。这里补一个空状态分支，本机没有任何
      // 多签账户时提前拦截，不再往下渲染依赖 _selectedAccount 的部件。
          : _accounts.isEmpty
          ? _buildEmptyAccountsState()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("1. 多签托管账户"),
              _buildMultiSigSelector(),
              // 1. 仅在多签选择下方显示多签余额
              _buildMultiSigBalanceBar(),

              const SizedBox(height: 20),
              _buildSectionTitle("2. 当前发起人 (单签)"),
              // 2. 发起人卡片，不显示余额
              _buildInitiatorBar(),

              const SizedBox(height: 24),
              _buildSectionTitle("3. 稳定币发行参数"),
              _buildAssetParams(),
              const SizedBox(height: 20),
              _buildSwitch("允许后续增发 (Mintable)", _mintable, (v) => setState(() => _mintable = v)),
              _buildSwitch("允许冻结逻辑 (Freezable)", _freezable, (v) => setState(() => _freezable = v)),
              // 【本次新增，对应你的要求4】稳定币发行默认允许销毁——注意
              // AssetMeta.dart 里 burnable 字段本身类默认值是 false(对齐
              // Java 未显式赋值的 boolean 默认)，这里 _burnable 这个 UI
              // 状态变量单独默认成 true，提交时会覆盖掉那个 false。
              _buildSwitch("允许销毁 (Burnable)", _burnable, (v) => setState(() => _burnable = v)),

              const SizedBox(height: 40),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 本机没有任何多签账户时的空状态提示——同 CommonPledgeWidget.dart 里
  /// _buildEmptyState() 的风格，避免继续往下渲染会崩溃的表单部件。
  Widget _buildEmptyAccountsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              "本机未创建任何多签账户，无法发起多签稳定币发行提案。",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String title, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      title: Trans(title, style: const TextStyle(fontSize: 14)),
      value: val,
      onChanged: onChanged,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildMultiSigSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MultiSigAccount>(
          value: _selectedAccount,
          isExpanded: true,
          items: _accounts.map((acc) => DropdownMenuItem(value: acc, child: Text(acc.multiAddress, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')))).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedAccount = val);
              _computeEligibleProposers(val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMultiSigBalanceBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 4),
          Text("多签账户余额: ", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          QccActiveWallet(_selectedAccount!.multiAddress, "QCC", fontSize: 12, fontColor: Colors.black54),
        ],
      ),
    );
  }

  /// 【本次改造，对应你的要求2】原来只是只读展示"当前活跃钱包是否恰好是
  /// 成员"，现在改成：该多签账户下所有"本机也持有私钥"的成员地址都可以
  /// 选(超过1个候选时可点击弹出列表切换)，并display备注名 + QCC 余额。
  Widget _buildInitiatorBar() {
    if (_eligibleProposers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.2))),
        child: const Row(
          children: [
            Icon(Icons.gpp_bad, size: 20, color: Colors.red),
            SizedBox(width: 10),
            Expanded(child: Text("本机没有属于该多签账户成员的地址，无法发起提案。", style: TextStyle(fontSize: 12))),
          ],
        ),
      );
    }

    final String? nick = _walletNames[_nowAddress];
    final bool canSwitch = _eligibleProposers.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickProposer : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified, size: 20, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_nowAddress, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
                    ],
                  ),
                  if (nick != null)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600))),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text("QCC 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        QccActiveWallet(_nowAddress, "QCC", fontSize: 12, fontColor: Colors.black87),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetParams() {
    return Column(
      children: [
        TextFormField(
          controller: _assetIdController,
          textCapitalization: TextCapitalization.characters,
          onChanged: _onAssetIdChanged,
          decoration: InputDecoration(
            labelText: "稳定币 ID (AssetID)",
            hintText: "如: QCCU, JPYC",
            suffixIcon: _isCheckingAsset ? const UnconstrainedBox(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : Icon(_isAssetIdAvailable ? Icons.check_circle : Icons.error, color: _isAssetIdAvailable ? Colors.green : Colors.red),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => v!.isEmpty ? "ID不能为空" : (!_isAssetIdAvailable ? "资产ID已存在" : null),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _supplyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: "初始发行量 (面值)",
                  hintText: "例如输入 100000",
                  border: OutlineInputBorder(),
                  helperText: "系统将根据精度自动计算链上总量", // 3. 说明
                  helperStyle: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _precisionController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: "精度 (0-9)", border: OutlineInputBorder()),
                validator: (v) {
                  int p = int.tryParse(v ?? "") ?? -1;
                  if (p < 0 || p > 9) return "0-9位";
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _canSign ? _onIssueProposal : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Trans("确认发起多签发行提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}