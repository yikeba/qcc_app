import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccWallet.dart';
// 【修复，重要】原来直接调 QccDataProtocol.encodeTransaction，内部签名逻辑
// 被注释掉（signature 恒为 ""）——这正是"Invalid Signature"被拒的原因，
// 和其它资产发行 Widget 是同一个坑。改成统一走 SignUtil。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/myasset/QccAsset.dart';
import '../../../views/myasset/QccAssetService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../user/multiple/MultiSigFileStorage.dart';
import '../user/multiple/QccMultiSig.dart';
import '../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import 'core/AssetMeta.dart';
import 'core/AssetMintRule.dart';





class MultiSigAssetMintWidget extends StatefulWidget {
  const MultiSigAssetMintWidget({super.key});

  @override
  State<MultiSigAssetMintWidget> createState() => _MultiSigAssetMintWidgetState();
}

class _MultiSigAssetMintWidgetState extends State<MultiSigAssetMintWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _proofController = TextEditingController(); // 👉 新增：铸造证明控制器

 // List<QccAsset> _allAssets = [];
  List<QccAsset> _mintableAssets = [];
  QccAsset? _selectedAsset;

  List<MultiSigAccount> _matchedAccounts = [];
  MultiSigAccount? _selectedAccount;

  String _nowAddress = "";
  bool _canSign = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      List<QccAsset> assets = await QccAssetService().fetchAllAssets();
      List<QccAsset> mintable = assets.where((a) => a.address.startsWith('M')).toList();

      setState(() {
       // _allAssets = assets;
        _mintableAssets = mintable;
        if (_mintableAssets.isNotEmpty) {
          _selectedAsset = _mintableAssets.first;
          _matchLocalMultiSig(_selectedAsset!.address);
        }
        _isLoading = false;
      });
    } catch (e) {
      LogObj.log("加载资产失败: $e");
    }
  }

  Future<void> _matchLocalMultiSig(String issuerAddress) async {
    final allMultiAccounts = await MultiSigAddressStorage.getAllAccounts();
    List<MultiSigAccount> matched = allMultiAccounts.where((acc) =>
    acc.multiAddress.toLowerCase() == issuerAddress.toLowerCase()).toList();

    setState(() {
      _matchedAccounts = matched;
      if (_matchedAccounts.isEmpty) {
        _selectedAccount = null;
        _canSign = false;
        _showNoPermissionDialog(issuerAddress);
      } else {
        _selectedAccount = _matchedAccounts.first;
        _verifySignerPermission(_selectedAccount!);
      }
    });
  }

  void _verifySignerPermission(MultiSigAccount account) {
    String? activeAddr = QccObj.activeWallet?.address;
    if (activeAddr == null) return;
    bool exists = account.owners.contains(activeAddr);

    setState(() {
      if (exists) {
        _nowAddress = activeAddr;
        _canSign = true;
      } else {
        _nowAddress = "活跃钱包非多签成员";
        _canSign = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("稳定币增发铸造"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
              const SizedBox(height: 16),

              _buildSection("3. 增发面值配置", _buildAmountInput()),
              const SizedBox(height: 16),

              // 👉 新增：铸造证明输入（限制200字符）
              _buildSection("4. 铸造证明 (可选)", _buildProofInput()),
              const SizedBox(height: 16),

              _buildSignerCard(),

              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetDropdown() {
    return DropdownButtonFormField<QccAsset>(
      value: _selectedAsset,
      isExpanded: true,
      items: _mintableAssets.map((a) => DropdownMenuItem(
          value: a,
          child: Text("${a.assetId} (精度:${a.precision})")
      )).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAsset = val);
          _matchLocalMultiSig(val.address);
        }
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
          _infoItem("类型", _selectedAsset!.type),
          _infoItem("精度", _selectedAsset!.precision.toString()),
          _infoItem("状态", "可增发"),
        ],
      ),
    );
  }

  Widget _buildAccountSelector() {
    return DropdownButtonFormField<MultiSigAccount>(
      value: _selectedAccount,
      isExpanded: true,
      hint: Text(_matchedAccounts.isEmpty ? "无匹配多签账号" : "选择多签账号"),
      items: _matchedAccounts.map((acc) => DropdownMenuItem(
          value: acc,
          child: Text(acc.multiAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))
      )).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAccount = val);
          _verifySignerPermission(val);
        }
      },
      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }

  Widget _buildAmountInput() {
    int precision = _selectedAsset?.precision ?? 0;
    int displayAmount = int.tryParse(_amountController.text) ?? 0;
    int rawTotal = (displayAmount * pow(10, precision)).toInt();

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
        Align(
          alignment: Alignment.centerRight,
          child: Text("链上 initialSupply 增加: $rawTotal",
              style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // 👉 新增：证明输入框实现
  Widget _buildProofInput() {
    return TextFormField(
      controller: _proofController,
      maxLength: 200, // 👉 限制200字符
      maxLines: 3,
      decoration: InputDecoration(
        labelText: Tools.getTra("铸造证明/来源说明"),
        hintText: Tools.getTra("例如：根据审计报告或外部存单生成的增发凭证"),
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
        counterStyle: const TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _buildSignerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _canSign ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _canSign ? Colors.green : Colors.red, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(_canSign ? Icons.verified : Icons.gpp_bad, size: 18, color: _canSign ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text("当前签署人: $_nowAddress", style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = _canSign && _selectedAccount != null && _selectedAsset != null;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: active ? _handleMintSubmit : null,
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
        ),
        child: Trans("确认发起多签增发提案"),
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

  // --- 核心逻辑补全 ---
  void _handleMintSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    // 1. 验证密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);
    try {
      // 2. 还原钱包
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet=await QccStorage.restoreWallet(context,_nowAddress,password);
      if (wallet == null || wallet.address !=_nowAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      // 3. 构建 AssetMintRule (Java 对标)
      statusNotifier.value = TxStep.building;
      int precision = _selectedAsset!.precision;
      int amountRaw = (int.parse(_amountController.text) * pow(10, precision)).toInt();

      final mintRule = AssetMintRule(
        assetId: _selectedAsset!.assetId,
        amount: amountRaw,
        receiver: _selectedAccount!.multiAddress,
        proof: _proofController.text.trim().isEmpty ? null : _proofController.text.trim(),
      );

      // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
      RuleData rule = RuleData();
      rule.from =  wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      rule.ruleName = AssetType.AssetMintRule.name;   ///AssetMintRule
      rule.ruleJson=jsonEncode(mintRule.toJson());
      // 【修复，重要】对应 Java：ruleAppendJson = ""，必须显式写入——toSign()
      // 的签名原文也包含这个字段，原代码完全没有设置这一行。
      rule.ruleAppendJson = "";
      // 计算 TxHash (finalizeId)
      rule.finalizeId();
      // 5. 签名与广播——统一走 SignUtil.signAndEncode()
      statusNotifier.value = TxStep.signing;

      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rule.toSign(),
        payloadJson: jsonEncode(rule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("https://tx.qccio.com/v1/mtxrule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context); // 关闭 loading
      LogObj.log( "✅ 增发提案发起，返回内容${response.body}");
      if (response.statusCode == 200) {
        Map<String, dynamic> resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED') {
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          await MultiSigFileStorage.saveTask(resData);

          if (!mounted) return;
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
        } else {
          throw resData['msg'] ?? "提交失败";
        }
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      Tools.showToast(context, "错误: $e");
    }
  }
}
