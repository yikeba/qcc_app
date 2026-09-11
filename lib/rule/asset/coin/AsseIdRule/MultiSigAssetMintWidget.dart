import 'dart:convert';
import 'dart:math';
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
import '../../../../views/setting/AppTranslator.dart';
import '../../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../../user/multiple/MultiSigFileStorage.dart';
import '../../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../../user/multiple/QccMultiSig.dart';
import '../../core/AssetMeta.dart';
import '../../core/AssetMintRule.dart';

/// 多签资产增发 —— 本轮按你的 5 点要求整体重做：
/// 1. 选择资产：改成直接查 /v1/asset（和资产查重、MultiSigTokenIssueWidget
///    的 _checkAssetId 同一个接口），一次性拿到 owner/type/precision/
///    mintable/initialSupply 全字段，不再依赖 QccAssetService().fetchAllAssets()
///    返回的 QccAsset 模型是否带 mintable/initialSupply（这两个字段之前在
///    本项目里没有任何地方读取过，无法确认该模型是否带、带的话是否新鲜）。
///    这里额外做了两层过滤：type==COIN（见第2点）、mintable==true——避免
///    选中一个根本没开增发权限的资产，交给公链拒绝才发现。
/// 2. 标签：这个页面对应 AssetMintRule + AssetMetaType.COIN，标的是"代币"，
///    不是稳定币（稳定币是另一套菜单/另一个 Widget）。原标题"稳定币增发
///    铸造"写错了，改成"代币增发铸造"，并把候选资产过滤为 COIN 类型。
/// 3. 资产选择后：先用该资产 owner 地址匹配本机已导入的多签账户（同原逻辑
///    _matchLocalMultiSig），再从匹配到的账户里找出本机持有私钥的全部
///    成员地址，允许手动选择提案发起人（同 MultiSigTokenIssueWidget.dart
///    的 _eligibleProposers/_pickProposer 套路），展示昵称 + QCC 余额。
/// 4. 增发面值配置下方新增"现有链上发行总量"——从 /v1/asset 里该资产的
///    initialSupply 换算显示，发起人增发前不用切出去查浏览器就能看到现状。
/// 5. 铸造来源（原"铸造证明"）输入长度从 200 收紧到 128 字符。
///
/// 【顺带修复，超出本次 5 点要求但同一类问题】原来的签名提交走
/// QccDataProtocol.encodeTransaction（该方法内部签名逻辑被注释掉，
/// signature 恒为空字符串——本 session 里 QccBurnPage.dart / 各发行页面
/// 都踩过同一个坑），现在统一改走 QccTxFlow.run()，和其余已修复的发行/
/// 增发/跟签页面保持一致，不会再单独漏掉某一步。
class MultiSigAssetMintWidget extends StatefulWidget {
  const MultiSigAssetMintWidget({super.key});

  @override
  State<MultiSigAssetMintWidget> createState() => _MultiSigAssetMintWidgetState();
}

class _MultiSigAssetMintWidgetState extends State<MultiSigAssetMintWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _proofController = TextEditingController();

  List<QccAsset> _mintableAssets = [];
  QccAsset? _selectedAsset;
  // 【新增】assetId -> 现有链上发行总量（原始整数，未按精度换算），随资产
  // 列表一次性从 /v1/asset 取回，选中资产切换时直接查表，不用再发一次请求。
  Map<String, int> _supplyRawByAssetId = {};

  List<MultiSigAccount> _matchedAccounts = [];
  MultiSigAccount? _selectedAccount;

  // 【新增】选中的多签账户里，本机实际持有私钥的持有人地址——用于"提案
  // 发起人可选择"，命名和做法对齐 MultiSigTokenIssueWidget.dart。
  List<String> _eligibleProposers = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      final names = await QccStorage.getAllWalletNames();
      List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
      final allMultiAccounts = await MultiSigAddressStorage.getAllAccounts();

      // 本机持有私钥、且是其成员之一的多签账户地址集合——只在这个范围内
      // 挑资产，不然下拉框会塞满全链跟自己毫无关系的资产。
      Set<String> myMultiAddrs = allMultiAccounts
          .where((acc) => acc.owners.any((o) => localAddrs.contains(o)))
          .map((acc) => acc.multiAddress.toLowerCase())
          .toSet();

      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
      List<QccAsset> mintable = [];
      Map<String, int> supplyMap = {};
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        List raw = jsonDecode(res['data']);
        for (final item in raw) {
          final owner = (item['owner'] ?? '').toString();
          final type = (item['type'] ?? '').toString();
          final bool isMintable = item['mintable'] == true;
          if (type == AssetMetaType.COIN.name &&
              isMintable &&
              myMultiAddrs.contains(owner.toLowerCase())) {
            final assetId = item['assetId'].toString();
            mintable.add(QccAsset(
              assetId: assetId,
              type: type,
              precision: int.tryParse(item['precision'].toString()) ?? 9,
              address: owner,
            ));
            supplyMap[assetId] = int.tryParse(item['initialSupply'].toString()) ?? 0;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _walletNames = names;
        _mintableAssets = mintable;
        _supplyRawByAssetId = supplyMap;
        if (_mintableAssets.isNotEmpty) {
          _selectedAsset = _mintableAssets.first;
        }
        _isLoading = false;
      });

      if (_selectedAsset != null) {
        await _matchLocalMultiSig(_selectedAsset!.address);
      }
    } catch (e) {
      LogObj.log("加载资产失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _matchLocalMultiSig(String issuerAddress) async {
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

  // 校验权限：匹配本地私钥，并给出全部可选的发起人地址。
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
      builder: (ctx) => AlertDialog(
        title: Trans("无权增发资产"),
        content: Text("本地未找到该资产的发行多签账号：\n$addr\n\n请先导入该多签账号再进行操作。"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Trans("确定"))],
      ),
    );
  }

  /// 提案发起人选择弹层——列出本机在该多签账户里持有私钥的全部地址，展示
  /// 昵称，选中后 _buildProposerInfo() 会显示对应的 QCC 余额。
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

  /// 把 initialSupply 原始整数按精度换算成可读的小数字符串，仅用于展示，
  /// 不参与任何提交逻辑，所以直接用 BigInt 做除法/取余，避免精度损失。
  String _formatSupply(int raw, int precision) {
    if (precision <= 0) return raw.toString();
    final divisor = BigInt.from(10).pow(precision);
    final bigRaw = BigInt.from(raw);
    final whole = bigRaw ~/ divisor;
    final frac = (bigRaw % divisor).abs();
    final fracStr = frac.toString().padLeft(precision, '0');
    return "$whole.$fracStr";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // 【修改】原来是"稳定币增发铸造"——这个页面走的是 AssetMintRule +
      // AssetMetaType.COIN，对标"代币"资产，不是稳定币。
      appBar: AppBar(title: Trans("代币增发铸造"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mintableAssets.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildSection("1. 选择目标资产", _buildAssetDropdown()),
              const SizedBox(height: 16),

              if (_selectedAsset != null) _buildAssetInfoCard(),
              const SizedBox(height: 16),

              _buildSection("2. 发行多签账号", _buildAccountSelector()),
              _buildMultiSigBalanceBar(),
              const SizedBox(height: 16),

              _buildSection("3. 提案发起人", _buildProposerInfo()),
              const SizedBox(height: 16),

              _buildSection("4. 增发面值配置", _buildAmountInput()),
              const SizedBox(height: 16),

              // 【修改】原"铸造证明"限200字，改名"铸造来源"，限128字。
              _buildSection("5. 铸造来源 (可选，限128字)", _buildProofInput()),
              const SizedBox(height: 16),

              _buildStatusBanner(),

              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Trans(
          "当前钱包没有可增发的多签代币资产\n（需同时满足：代币类型、mintable=true、且本机持有该多签账户至少一名成员的私钥）",
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildAssetDropdown() {
    return DropdownButtonFormField<QccAsset>(
      initialValue: _selectedAsset,
      isExpanded: true,
      items: _mintableAssets.map((a) => DropdownMenuItem(
          value: a,
          child: Text("${a.assetId} (精度:${a.precision})")
      )).toList(),
      onChanged: (val) {
        if (val == null) return;
        setState(() => _selectedAsset = val);
        _matchLocalMultiSig(val.address);
      },
      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }

  Widget _buildAssetInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoItem("类型", "代币 (${_selectedAsset!.type})"),
          _infoItem("精度", _selectedAsset!.precision.toString()),
          _infoItem("状态", "可增发"),
        ],
      ),
    );
  }

  // --- UI: 多签账户选择器 ---
  Widget _buildAccountSelector() {
    return DropdownButtonFormField<MultiSigAccount>(
      initialValue: _selectedAccount,
      isExpanded: true,
      hint: Text(_matchedAccounts.isEmpty ? "无匹配多签账号" : "选择多签账号"),
      items: _matchedAccounts.map((acc) => DropdownMenuItem(
          value: acc,
          child: Text(acc.multiAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))
      )).toList(),
      onChanged: (val) {
        if (val == null) return;
        setState(() => _selectedAccount = val);
        _verifyWalletOwnership(val);
      },
      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }

  /// 【新增】多签发行源地址的 QCC 余额——和 MultiSigTokenIssueWidget.dart
  /// 的 _buildMultiSigBalanceBar() 是同一套展示逻辑。
  Widget _buildMultiSigBalanceBar() {
    if (_selectedAccount == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, bottom: 8),
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

  /// 【新增】提案发起人信息——支持点击切换（本机持有私钥的成员不止一个时），
  /// 显示昵称 + QCC 余额。做法对齐 MultiSigTokenIssueWidget.dart。
  Widget _buildProposerInfo() {
    String? nick = _walletNames[nowaddress];
    bool canSwitch = _eligibleProposers.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickProposer : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
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

  Widget _buildAmountInput() {
    int precision = _selectedAsset?.precision ?? 0;
    int displayAmount = int.tryParse(_amountController.text) ?? 0;
    int rawTotal = (displayAmount * pow(10, precision)).toInt();
    int? currentRaw = _selectedAsset == null ? null : _supplyRawByAssetId[_selectedAsset!.assetId];

    return Column(
      children: [
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: "拟增发面值", border: OutlineInputBorder(), hintText: "请输入整数"),
          onChanged: (v) => setState(() {}),
          validator: (v) => v!.isEmpty ? "金额不能为空" : null,
        ),
        const SizedBox(height: 8),
        // 【新增】现有资产总链上发行额度——从 /v1/asset 的 initialSupply
        // 按精度换算展示，增发前先看一眼现状。
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            currentRaw == null
                ? "现有链上发行总量: 未知"
                : "现有链上发行总量: ${_formatSupply(currentRaw, precision)}",
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text("本次增发 initialSupply 增加(原始值): $rawTotal",
              style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // 【修改】原"铸造证明"字段收紧为"铸造来源"，maxLength 从 200 改为 128。
  Widget _buildProofInput() {
    return TextFormField(
      controller: _proofController,
      maxLength: 128,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: Tools.getTra("铸造来源"),
        hintText: Tools.getTra("例如：根据审计报告或外部存单生成的增发凭证"),
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
        counterStyle: const TextStyle(fontSize: 10),
      ),
    );
  }

  /// 【新增】本机不持有该多签账户任何成员私钥时的提示——原来这种情况下
  /// nowaddress 会被清空，但没有任何界面文案说明原因，用户只会看到提交
  /// 按钮变灰，不知道为什么。
  Widget _buildStatusBanner() {
    if (_selectedAccount == null) return const SizedBox.shrink();
    if (_eligibleProposers.isNotEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.gpp_bad, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Trans(
              "本机没有该多签账户任何成员的私钥，无法发起增发提案",
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = !_isSubmitting &&
        _selectedAsset != null &&
        _selectedAccount != null &&
        _eligibleProposers.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: active ? _handleMintSubmit : null,
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: _isSubmitting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Trans("确认发起多签增发提案"),
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _infoItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- 核心逻辑：统一走 QccTxFlow.run() ---
  // 【重构】原来这里手抄了一遍"密码 -> loading -> 还原钱包 -> 构建 RuleData ->
  // compute 签名 -> 提交 -> 解析返回"全流程，且签名走的是已确认损坏的
  // QccDataProtocol.encodeTransaction（signature 恒为空）。现在改成统一走
  // QccTxFlow.run()，和其余已修复的发行/增发/跟签页面共用同一处实现。
  Future<void> _handleMintSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null || _selectedAccount == null) return;

    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择提案发起人"));
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        int precision = _selectedAsset!.precision;
        int amountRaw = (int.parse(_amountController.text) * pow(10, precision)).toInt();

        final mintRule = AssetMintRule(
          assetId: _selectedAsset!.assetId,
          amount: amountRaw,
          receiver: _selectedAccount!.multiAddress,
          proof: _proofController.text.trim().isEmpty ? null : _proofController.text.trim(),
        );

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
        rule.ruleName = AssetType.AssetMintRule.name;
        rule.ruleJson = jsonEncode(mintRule.toJson());
        // 对应 Java：ruleAppendJson = ""，必须显式写入——toSign() 的签名
        // 原文也包含这个字段。
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
      await MultiSigFileStorage.saveTask(resData);
      Tools.showToast(context, "✅ 增发提案已发起");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MultiSigInitiatedPage(
              txHash: resData['txHash'],
              type: MultiSigPageType.append, // 借用转账展示页逻辑
              owners: _selectedAccount!.owners,
              threshold: _selectedAccount!.threshold,
            ),
          ),
        );
      }
    } else {
      LogObj.log("多签增发异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }
}