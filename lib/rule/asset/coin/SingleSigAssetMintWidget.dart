import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/rule/asset/AssetMintSuccessPage.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccWallet.dart';
// 统一走 SignUtil 签名，不再直接调 QccDataProtocol.encodeTransaction
// （该方法签名逻辑被注释掉，signature 恒为 "" ——同一个坑，参见
// SingleSigTokenIssueWidget.dart / MultiSigAssetMintWidget.dart 的修复说明）。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/myasset/QccAsset.dart';
import '../../../views/myasset/QccAssetService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../core/AssetMeta.dart';
import '../core/AssetMintRule.dart';

/// 单签资产增发 Widget —— 对标 Java TxRuleITIAAssetFullFlow 中单签发行
/// 之后的增发流程（AssetMintRule + ruleType=AsseIdRule，走 /v1/rule 单签
/// 接口），字段/UI 布局参考已修复的 MultiSigAssetMintWidget.dart，但去掉
/// 多签账号匹配环节，改为直接校验"当前钱包地址 == 该资产的 owner"。
class SingleSigAssetMintWidget extends StatefulWidget {
  const SingleSigAssetMintWidget({super.key});

  @override
  State<SingleSigAssetMintWidget> createState() => _SingleSigAssetMintWidgetState();
}

class _SingleSigAssetMintWidgetState extends State<SingleSigAssetMintWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _proofController = TextEditingController();

  List<QccAsset> _mintableAssets = [];
  QccAsset? _selectedAsset;

  String _nowAddress = "";
  bool _canSign = false;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      String? activeAddr = QccObj.activeWallet?.address;
      _nowAddress = activeAddr ?? "";
      List<QccAsset> assets = await QccAssetService().fetchAllAssets();
      // 单签发行的资产：owner 地址不以 'M' 开头（'M' 前缀留给多签地址），
      // 且必须是当前活跃钱包本人发行的资产才允许在这里增发。
      List<QccAsset> mintable = assets.where((a) =>
      !a.address.startsWith('M') &&
          activeAddr != null &&
          a.address.toLowerCase() == activeAddr.toLowerCase()
      ).toList();

      setState(() {
        _mintableAssets = mintable;
        if (_mintableAssets.isNotEmpty) {
          _selectedAsset = _mintableAssets.first;
        }
        _canSign = activeAddr != null && _mintableAssets.isNotEmpty;
        _isLoading = false;
      });

      if (activeAddr != null && mintable.isEmpty && mounted) {
        _showNoAssetDialog();
      }
    } catch (e) {
      LogObj.log("加载资产失败: $e");
      setState(() => _isLoading = false);
    }
  }

  void _showNoAssetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("无可增发资产"),
        content: Text("当前活跃钱包 ($_nowAddress) 名下未找到可增发的单签资产。"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Trans("确定"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("单签资产增发"), centerTitle: true),
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

              _buildSection("2. 增发面值配置", _buildAmountInput()),
              const SizedBox(height: 16),

              _buildSection("3. 铸造证明 (可选)", _buildProofInput()),
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
      hint: Text(_mintableAssets.isEmpty ? "无可增发资产" : "选择资产"),
      items: _mintableAssets.map((a) => DropdownMenuItem(
          value: a,
          child: Text("${a.assetId} (精度:${a.precision})")
      )).toList(),
      onChanged: (val) {
        if (val != null) setState(() => _selectedAsset = val);
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

  Widget _buildProofInput() {
    return TextFormField(
      controller: _proofController,
      maxLength: 200,
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
          Expanded(child: Text("当前签署人: ${_nowAddress.isEmpty ? '未选择钱包' : _nowAddress}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = _canSign && _selectedAsset != null && !_isSubmitting;
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
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起单签增发"),
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

  // --- 核心逻辑 ---
  void _handleMintSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    // 1. 验证密码——先弹密码框，再显示 loading，避免"取消密码框后 loading
    // 转圈圈卡死"的问题（同 MultiSigStableCoinIssueWidget.dart 的修复）。
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    setState(() => _isSubmitting = true);
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      // 2. 还原钱包
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, _nowAddress, password);
      if (wallet == null || wallet.address != _nowAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 3. 构建 AssetMintRule (对标 Java AssetMintRule)
      statusNotifier.value = TxStep.building;
      int precision = _selectedAsset!.precision;
      int amountRaw = (int.parse(_amountController.text) * pow(10, precision)).toInt();

      final mintRule = AssetMintRule(
        assetId: _selectedAsset!.assetId,
        amount: amountRaw,
        receiver: wallet.address,
        proof: _proofController.text.trim().isEmpty ? null : _proofController.text.trim(),
      );

      // 4. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
      RuleData rule = RuleData();
      rule.from = wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      rule.ruleName = AssetType.AssetMintRule.name;
      rule.ruleJson = jsonEncode(mintRule.toJson());
      // 对应 Java：ruleAppendJson = ""，必须显式写入——toSign() 的签名原文
      // 也包含这个字段。
      rule.ruleAppendJson = "";
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
        Uri.parse("https://tx.qccio.com/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context); // 关闭 loading
      LogObj.log("单签增发返回: ${response.body}");

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          resData['ruleName'] = AssetType.AssetMintRule.name;
          await SignUtil.instance.markSubmitted(wallet.address);
          Tools.showToast(context, "✅ 增发规则已广播成功");
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AssetMintSuccessPage(ruleData: resData)),
            );
          }
        } else {
          throw resData['msg'] ?? "公链拒绝了该增发请求";
        }
      } else {
        throw "网络通讯异常: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("单签增发错误: $e");
      Tools.showToast(context, "增发失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
