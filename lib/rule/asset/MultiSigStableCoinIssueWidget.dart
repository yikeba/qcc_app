import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

import '../../../home/QccExplorerService.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
// 【修复，重要】原来直接调 QccDataProtocol.encodeTransaction，内部签名逻辑
// 被注释掉（signature 恒为 ""）——这正是"Invalid Signature"被拒的原因，
// 和其它资产发行 Widget 是同一个坑。改成统一走 SignUtil。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../user/multiple/QccMultiSig.dart';
import '../user/multiple/multicreat/MultiSigAddressStorage.dart';
import 'AssetFileStorage.dart';
import 'AssetMultiSigProposalPage.dart';
import 'core/AssetMeta.dart';


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

  String _nowAddress = "";
  bool _canSign = false;
  bool _isAssetIdAvailable = true;
  bool _isCheckingAsset = false;
  bool _isLoading = true;
  bool _mintable = true;   //允许增发
  bool _freezable = true;  //允许冻结
  // 【新增】对应 AssetMeta.java 的 burnable 字段——发行时一次性声明，默认
  // 不开启，事后无法追溯补授权，和单签/多签代币发行表单同一处理。
  bool _burnable = false;
  // 【新增】原来这个 Widget 完全没有防重复提交的状态，_onIssueProposal()
  // 也没有包住任何 try/catch——一旦钱包恢复失败或网络异常，Loading 弹窗会
  // 永久卡住且抛出未捕获异常。加一个 _isSubmitting 驱动按钮 Loading 态，
  // 并把整个提交流程包进 try/catch/finally。
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMultiSigAccounts();
  }

  // --- 核心逻辑：安全载入并校验签名权 ---
  void _loadMultiSigAccounts() {
    // 严格按照您的蓝本写法
    String? currentWalletAddr = QccObj.activeWallet!.address;
    if (currentWalletAddr == null) return;

    MultiSigAddressStorage.getAllAccounts().then((list) {
      if (mounted) {
        setState(() {
          // 逻辑：只选出包含当前单签地址的多签账户
          _accounts = list.where((acc) =>
              acc.owners.any((owner) => owner == currentWalletAddr)).toList();

          if (_accounts.isNotEmpty) {
            _selectedAccount = _accounts.first;
            _verifyWalletOwnership(_selectedAccount!);
          } else {
            _isLoading = false;
          }
        });
      }
    });
  }

  // 校验权限：匹配本地私钥
  void _verifyWalletOwnership(MultiSigAccount account) {
    List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
    List<String> matched = localAddrs.where((a) =>
        account.owners.any((owner) => owner == a)).toList();

    if (matched.isEmpty) {
      setState(() {
        _nowAddress = "";
        _canSign = false;
        _isLoading = false;
      });
    } else {
      String? activeAddr = QccObj.activeWallet!.address;
      if (activeAddr != null && matched.contains(activeAddr)) {
        setState(() {
          _nowAddress = activeAddr;
          _canSign = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _nowAddress = "";
          _canSign = false;
          _isLoading = false;
        });
      }
    }
  }


  /// 资产 ID 查重
  Future<void> _checkAssetId(String assetId) async {
    if (assetId.isEmpty) return;
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
      setState(() => _isCheckingAsset = false);
    }
  }

  Future<void> _onIssueProposal() async {
    if (!_formKey.currentState!.validate() || !_canSign) return;

    int precision = int.parse(_precisionController.text);
    int displaySupply = int.parse(_supplyController.text);
    // 3. 计算逻辑：输入10万，精度2，Java端存10000000 (10万 * 10^2)
    int rawInitialSupply = displaySupply * pow(10, precision).toInt();
    LogObj.log("提交稳定币提案:");
    LogObj.log("多签地址: ${_selectedAccount?.multiAddress}");
    LogObj.log("Java Long Total: $rawInitialSupply");

    // 【修复，重要】原来是先 QccLoading.show() 再弹密码框——如果用户在密码框
    // 点了取消，函数直接 return，Loading 弹窗永远不会被关闭。改成先拿到
    // 密码、确认要继续了，才展示 Loading（和其它发行 Widget 的顺序一致）。
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      setState(() => _isSubmitting = true);
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, _nowAddress, password);
      if (wallet == null || wallet.address != _nowAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      statusNotifier.value = TxStep.building;
      final multiAddr = _selectedAccount!.multiAddress;
      final assetId = _assetIdController.text;
      // 1. 构建模型
      AssetMeta meta = AssetMeta(assetId, multiAddr);
      meta.precision = precision;
      meta.mintable = _mintable;
      meta.freezable = _freezable;
      meta.burnable = _burnable;
      meta.type = "Stablecoin"; //.name;--重要稳定币标记
      meta.owner = _selectedAccount!.multiAddress;
      // 2. 初始供应量换算 (int 对应 Java long)
      int supplyCount = int.parse(_supplyController.text);
      meta.initialSupply = (supplyCount * pow(10, precision)).toInt();

      // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
      RuleData rule = RuleData();
      rule.from = wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      rule.ruleName = AssetType.AssetMeta.name;
      rule.ruleJson = jsonEncode(meta.toJson());
      // 【修复，重要】对应 Java：ruleAppendJson = ""，必须显式写入——toSign()
      // 的签名原文也包含这个字段，原代码完全没有设置这一行。
      rule.ruleAppendJson = "";
      // 计算 TxHash (finalizeId)
      rule.finalizeId();

      // 3. 签名——统一走 SignUtil.signAndEncode()
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rule.toSign(),
        payloadJson: jsonEncode(rule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 4. POST 至多签提案池
      statusNotifier.value = TxStep.submitting;
      String url = "https://tx.qccio.com/v1/mtxrule";
      var response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("多签发行资产返回:${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          resData['ruleName'] = AssetType.AssetMeta.name;
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          await AssetFileStorage.saveAsset(resData);
          Tools.showToast(context, "✅ 资产发行规则已广播成功");
          // 7. 跳转至结果页
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: rule.id,)),
            );
          }
        } else {
          throw resData['msg'] ?? "提案发布失败";
        }
      } else {
        throw "网络通讯异常: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("稳定币发行异常: $e");
      Tools.showToast(context, "发行失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签稳定币发行")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
              _buildSwitch("允许销毁逻辑 (Burnable)", _burnable, (v) => setState(() => _burnable = v)),

              const SizedBox(height: 40),
              _buildSubmitButton(),
            ],
          ),
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
              _verifyWalletOwnership(val);
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

  Widget _buildInitiatorBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _canSign ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _canSign ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_canSign ? Icons.verified : Icons.gpp_bad, size: 20, color: _canSign ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nowAddress.isEmpty ? "无签署权限" : _nowAddress, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                Text(_canSign ? "活跃钱包匹配：拥有签名提案权" : "当前单签钱包不在多签成员列表中", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetParams() {
    return Column(
      children: [
        TextFormField(
          controller: _assetIdController,
          textCapitalization: TextCapitalization.characters,
          onChanged: _checkAssetId,
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
        onPressed: (_canSign && !_isSubmitting) ? _onIssueProposal : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起多签发行提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
