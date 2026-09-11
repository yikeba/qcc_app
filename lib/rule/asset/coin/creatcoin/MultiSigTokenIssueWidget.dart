import 'dart:convert';
import 'dart:developer' as LogObj;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../../procotol/QccTxFlow.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../utile/QccObj.dart';
import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../home/QccExplorerService.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../../user/multiple/QccMultiSig.dart';
import '../../AssetFileStorage.dart';
import '../../core/AssetMeta.dart';
import '../../AssetMultiSigProposalPage.dart';


class MultiSigTokenIssueWidget extends StatefulWidget {
  const MultiSigTokenIssueWidget({super.key});

  @override
  State<MultiSigTokenIssueWidget> createState() => _MultiSigTokenIssueWidgetState();
}

class _MultiSigTokenIssueWidgetState extends State<MultiSigTokenIssueWidget> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _supplyController = TextEditingController();
  final _precisionController = TextEditingController(text: "9");
  bool _mintable = true;
  bool _freezable = true;
  // 【新增】对应 AssetMeta.java 的 burnable 字段，和单签发行表单同一处理。
  bool _burnable = false;
  bool _isSubmitting = false;

  // 【新增】资产 ID 查重状态——命名和判断逻辑对齐
  // SingleSigTokenIssueWidget.dart / MultiSigStableCoinIssueWidget.dart 的
  // _isAssetIdAvailable/_isCheckingAsset。
  bool _isAssetIdAvailable = true;
  bool _isCheckingAsset = false;

  List<MultiSigAccount> _accounts = [];
  MultiSigAccount? _selectedAccount;
  String nowaddress="";

  // 【新增】选中的多签账户里，本机实际持有私钥的那些持有人地址——用于
  // "提案发起人可选择"。原来 nowaddress 只会自动取活跃钱包（且必须恰好是
  // 该多签成员之一），不是活跃钱包就直接清空，用户没有任何手动选择的余地。
  List<String> _eligibleProposers = [];
  // 【新增】地址 -> 本地钱包昵称映射，用于提案发起人展示名称
  // （照搬 QccCreateMultiSigPage.dart 里 _walletNames 的做法）。
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _loadMultiSigAccounts();
  }

  // --- 核心逻辑：安全载入并校验签名权 ---
  Future<void> _loadMultiSigAccounts() async {
    String? currentWalletAddr = QccObj.activeWallet?.address;
    if (currentWalletAddr == null) return;

    final names = await QccStorage.getAllWalletNames();
    final list = await MultiSigAddressStorage.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      // 这里的逻辑就是你说的：只选出包含当前单签地址的多签账户
      _accounts = list.where((acc) => acc.owners.contains(currentWalletAddr)).toList();
      if (_accounts.isNotEmpty) {
        _selectedAccount = _accounts.first;
      }
    });
    if (_selectedAccount != null) {
      _verifyWalletOwnership(_selectedAccount!);
    }
  }


  // 校验权限：匹配本地私钥，并给出全部可选的发起人地址
  // 【修复】原来匹配不到活跃钱包就直接把 nowaddress 清空，用户唯一的出路是
  // 去别处切换活跃钱包——现在只要本机持有私钥的成员不止一个，就默认选第一个
  // 并允许用户在 _buildProposerInfo() 里手动切换。
  void _verifyWalletOwnership(MultiSigAccount account) {
    List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
    List<String> matched = localAddrs.where((a) => account.owners.contains(a)).toList();
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

  /// 【新增】提案发起人选择弹层——列出本机在该多签账户里持有私钥的全部
  /// 地址，展示昵称，选中后 _buildProposerInfo() 会显示对应的 QCC 余额。
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

  /// 【新增】资产 ID 查重：和单签发行/多签稳定币发行走同一个 GET /v1/asset
  /// 接口，本地按 assetId 大小写不敏感过滤已注册资产列表。
  Future<void> _checkAssetId(String assetId) async {
    if (assetId.isEmpty) {
      setState(() => _isAssetIdAvailable = true);
      return;
    }
    setState(() => _isCheckingAsset = true);
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        List assets = jsonDecode(res['data']);
        bool exists = assets.any((a) => a['assetId'].toString().toUpperCase() == assetId.toUpperCase());
        setState(() => _isAssetIdAvailable = !exists);
      }
    } catch (e) {
      LogObj.log("资产查重失败: $e");
    } finally {
      if (mounted) setState(() => _isCheckingAsset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Trans("多签资产发行"),
        backgroundColor: Colors.orange[600],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 多签源选择
              _buildAccountPicker(),
              // 【新增】多签地址 QCC 余额
              _buildMultiSigBalanceBar(),
              const SizedBox(height: 20),

              // 【修改】资产代码输入改成带查重的专用输入框
              _buildAssetIdInput(),
              // 2. 新增：本地单签发起人显示 [根据你的最新要求新增]
              const SizedBox(height: 12),
              _buildProposerInfo(),

              Row(
                children: [
                  Expanded(child: _buildInput("精度 (2-9)", _precisionController, "最大9位", isNum: true)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildInput("发行总量 (Supply)", _supplyController, "输入整数", isNum: true)),
                ],
              ),

              _buildSwitch("允许后续增发 (Mintable)", _mintable, (v) => setState(() => _mintable = v)),
              _buildSwitch("允许冻结逻辑 (Freezable)", _freezable, (v) => setState(() => _freezable = v)),
              _buildSwitch("允许销毁逻辑 (Burnable)", _burnable, (v) => setState(() => _burnable = v)),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || _selectedAccount == null) ? null : () => _handleSubmit(),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Trans("发起多签发行提案"),
                ),
              ),
              if (_selectedAccount == null && _accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Trans("当前钱包无任何多签资产管理权限", style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 【新增】多签发行源地址的 QCC 余额——和 MultiSigStableCoinIssueWidget.dart
  /// 的 _buildMultiSigBalanceBar() 是同一套展示逻辑。
  Widget _buildMultiSigBalanceBar() {
    if (_selectedAccount == null) return const SizedBox.shrink();
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

  // 显示当前单签发起人信息
  // 【修改】原来只是纯展示 nowaddress，现在：1. 支持点击切换发起人（本机
  // 持有私钥的成员不止一个时）；2. 显示发起人昵称；3. 显示发起人 QCC 余额。
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

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // 【新增】资产 ID 已被注册则直接拦截，不进入后续提交流程。
    if (!_isAssetIdAvailable) {
      Tools.showToast(context, "该资产代码已被注册，请更换");
      return;
    }

    int p = int.tryParse(_precisionController.text) ?? 9;
    if (p > 9 || p < 0) {
      Tools.showToast(context, "精度必须在 0-9 之间");
      return;
    }

    // 校验 long 溢出逻辑
    try {
      BigInt baseSupply = BigInt.parse(_supplyController.text);
      BigInt totalValue = baseSupply * BigInt.from(10).pow(p);
      if (totalValue > BigInt.parse("9223372036854775807")) {
        Tools.showToast(context, "发行总量超过 long 类型限制");
        return;
      }
    } catch (e) {
      Tools.showToast(context, "数据格式错误");
      return;
    }
    _processIssue(p);

  }

  // 【重构】原来这里手抄了一遍"密码->loading->还原钱包->构建RuleData->
  // 签名->提交->解析返回"全流程——你这次报的"没弹loading"就是这份手抄漏了
  // 一行。现在改成统一走 QccTxFlow.run()，这类步骤从今往后只有一处实现，
  // 不会再出现"这个页面漏了某一步"的问题。
  Future<void> _processIssue(int precision) async {
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择提案发起人"));
      return;
    }
    setState(() => _isSubmitting = true);

    // rule.id 要留到提交成功后跳转结果页用，在 buildPayload 回调里拼好后
    // 存到这个外层变量里。
    String? proposedRuleId;

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        final multiAddr = _selectedAccount!.multiAddress;
        // 1. 构建模型
        AssetMeta meta = AssetMeta(_idController.text.trim(), multiAddr);
        meta.precision = precision;
        meta.mintable = _mintable;
        meta.freezable = _freezable;
        meta.burnable = _burnable;
        meta.type = "COIN";

        // 2. 初始供应量换算 (int 对应 Java long)
        int supplyCount = int.parse(_supplyController.text);
        meta.initialSupply = (supplyCount * pow(10, precision)).toInt();

        // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
        rule.ruleName = AssetType.AssetMeta.name;
        rule.ruleJson = jsonEncode(meta.toJson());
        // 对应 Java：ruleAppendJson = ""，必须显式写入。
        rule.ruleAppendJson = "";
        rule.finalizeId();
        proposedRuleId = rule.id;

        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      resData['ruleName'] = AssetType.AssetMeta.name;
      await AssetFileStorage.saveAsset(resData);
      Tools.showToast(context, "✅ 资产发行规则已广播成功");
      // 跳转至结果页
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: proposedRuleId!)),
        );
      }
    } else {
      LogObj.log("多签发行资产异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  // --- UI: 多签账户选择器 ---
  Widget _buildAccountPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MultiSigAccount>(
          value: _selectedAccount,
          isExpanded: true,
          hint: Trans("请选择多签发行源"),
          items: _accounts.map((acc) {
            return DropdownMenuItem(
              value: acc,
              child: Text(acc.multiAddress,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            );
          }).toList(),
          // 【修复】原来切换多签账户后完全没有重新校验签名权/刷新可选发起人，
          // 导致切换账户后 nowaddress/_eligibleProposers 还停留在上一个账户
          // 的结果上。现在切换账户时重新走一遍 _verifyWalletOwnership。
          onChanged: (val) {
            if (val == null) return;
            setState(() => _selectedAccount = val);
            _verifyWalletOwnership(val);
          },
        ),
      ),
    );
  }

  /// 【新增】资产代码输入框：onChanged 触发查重，suffixIcon 展示
  /// 查询中/可用/已占用三种状态，和 SingleSigTokenIssueWidget.dart /
  /// MultiSigStableCoinIssueWidget.dart 的写法保持一致。
  Widget _buildAssetIdInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _idController,
        textCapitalization: TextCapitalization.characters,
        onChanged: _checkAssetId,
        decoration: InputDecoration(
          labelText: Tools.getTra("资产代码 (assetId)"),
          hintText: "如: QCC_USDT",
          border: const OutlineInputBorder(),
          suffixIcon: _isCheckingAsset
              ? const UnconstrainedBox(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(_isAssetIdAvailable ? Icons.check_circle : Icons.error, color: _isAssetIdAvailable ? Colors.green : Colors.red),
        ),
        validator: (v) => v!.isEmpty ? Tools.getTra("不能为空") : (!_isAssetIdAvailable ? "资产代码已存在" : null),
      ),
    );
  }

  // 修改后的 _buildInput 方法
  Widget _buildInput(String label, TextEditingController ctrl, String hint, {bool isNum = false, bool isUpperCase = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        // 控制大写
        textCapitalization: isUpperCase ? TextCapitalization.characters : TextCapitalization.none,
        inputFormatters: isUpperCase ? [UpperCaseTextFormatter()] : [],
        decoration: InputDecoration(
          labelText: Tools.getTra(label),
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => v!.isEmpty ? Tools.getTra("不能为空") : null,
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
}

// 在类外部添加这个辅助类
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}