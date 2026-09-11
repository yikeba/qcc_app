import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../procotol/MultiTransactionData.dart';
import '../../../procotol/QccDataProtocol.dart';
import '../../../procotol/QccPacket.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/myasset/QccAsset.dart';
import '../../../views/myasset/QccAssetService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../user/multiple/MultiSigFileStorage.dart';
import '../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../user/multiple/QccMultiSig.dart';

class MultiSigAssetBurnWidget extends StatefulWidget {
  const MultiSigAssetBurnWidget({super.key});

  @override
  State<MultiSigAssetBurnWidget> createState() => _MultiSigAssetBurnWidgetState();
}

class _MultiSigAssetBurnWidgetState extends State<MultiSigAssetBurnWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  // 【核心】：根据您提供的日志，QCC 系统销毁/发行黑洞地址
  final String _systemBurnAddress = "Q999999999999999999999999999999999";

  List<QccAsset> _assets = [];
  QccAsset? _selectedAsset;

  List<MultiSigAccount> _accounts = [];
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
      // 1. 加载所有资产
      List<QccAsset> assetList = await QccAssetService().fetchAllAssets();
      // 2. 加载本地多签账号
      final multiAccounts = await MultiSigAddressStorage.getAllAccounts();

      setState(() {
        _assets = assetList;
        _accounts = multiAccounts;

        if (_assets.isNotEmpty) {
          _selectedAsset = _assets.firstWhere((a) => a.assetId == "USDQ", orElse: () => _assets.first);
        }
        if (_accounts.isNotEmpty) {
          _selectedAccount = _accounts.first;
          _verifySignerPermission(_selectedAccount!);
        }
        _isLoading = false;
      });
    } catch (e) {
      LogObj.log("加载销毁页面数据失败: $e");
    }
  }

  void _verifySignerPermission(MultiSigAccount account) {
    String? activeAddr = QccObj.activeWallet?.address;
    if (activeAddr == null) return;
    bool exists = account.owners.contains(activeAddr);
    setState(() {
      _nowAddress = exists ? activeAddr : "活跃钱包非多签成员";
      _canSign = exists;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBFA), // 浅红警示背景
      appBar: AppBar(
        title: Trans("资产销毁 (Burn)"),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildWarningHeader(),
              const SizedBox(height: 16),
              _buildCard("1. 支出多签账号", _buildAccountSelector()),
              const SizedBox(height: 16),
              _buildCard("2. 销毁资产与金额", _buildAssetAndAmount()),
              const SizedBox(height: 16),
              _buildCard("3. 销毁说明 (Memo)", _buildMemoInput()),
              const SizedBox(height: 24),
              _buildSignerStatus(),
              const SizedBox(height: 40),
              _buildBurnSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: const [
          Icon(Icons.dangerous, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "注意：销毁操作会将资产转入系统黑洞地址。一旦确认，资产将从流通总量中永久移除，无法找回！",
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildAccountSelector() {
    return DropdownButtonFormField<MultiSigAccount>(
      value: _selectedAccount,
      isExpanded: true,
      items: _accounts.map((acc) => DropdownMenuItem(value: acc, child: Text(acc.multiAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAccount = val);
          _verifySignerPermission(val);
        }
      },
      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
    );
  }

  Widget _buildAssetAndAmount() {
    int precision = _selectedAsset?.precision ?? 0;
    double displayAmt = double.tryParse(_amountController.text) ?? 0;
    int rawTotal = (displayAmt * pow(10, precision)).toInt();

    return Column(
      children: [
        DropdownButtonFormField<QccAsset>(
          value: _selectedAsset,
          decoration: const InputDecoration(labelText: "选择销毁资产", border: OutlineInputBorder()),
          items: _assets.map((a) => DropdownMenuItem(value: a, child: Text("${a.assetId} (Precision: ${a.precision})"))).toList(),
          onChanged: (val) => setState(() => _selectedAsset = val),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: "销毁数量",
            suffixText: _selectedAsset?.assetId,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() {}),
          validator: (v) => v!.isEmpty ? "请输入金额" : null,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_selectedAccount != null && _selectedAsset != null)
              Expanded(child: Row(
                children: [
                  const Text("可用: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  QccActiveWallet(_selectedAccount!.multiAddress, _selectedAsset!.assetId, fontSize: 11.0, fontColor: Colors.redAccent),
                ],
              )),
            Text("链上扣除: $rawTotal", style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildMemoInput() {
    return TextFormField(
      controller: _memoController,
      maxLines: 2,
      maxLength: 100,
      decoration: const InputDecoration(
        hintText: "选填：记录本次销毁的原因（如：储备金调整、回购等）",
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildSignerStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _canSign ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (_canSign ? Colors.green : Colors.red).withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(_canSign ? Icons.verified : Icons.gpp_bad, size: 20, color: _canSign ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text("提案人: $_nowAddress", style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _buildBurnSubmitButton() {
    bool active = _canSign && _selectedAccount != null && _selectedAsset != null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: active ? _handleBurnSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Trans("发起多签销毁提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- 核心逻辑 ---

  void _handleBurnSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // 二次确认，防止手滑
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("最终销毁确认"),
        content: Text("确定将 ${_amountController.text} ${_selectedAsset!.assetId} 发往黑洞地址吗？此操作无法撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("确定销毁", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet=await QccStorage.restoreWallet(context,_nowAddress,password);
      if (wallet == null || wallet.address !=_nowAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }
    /*  String? encryptedData = await QccStorage.getRawData(_nowAddress);
      if (encryptedData == null) throw "找不到该账户的本地私钥数据";
      final wallet = await compute(QccStorage.restoreWalletTask, {'rawData': encryptedData, 'password': password});
      if (wallet == null) throw "密码错误";*/

      statusNotifier.value = TxStep.building;
      int rawAmount = (double.parse(_amountController.text) * pow(10, _selectedAsset!.precision)).toInt();

      // 构建销毁数据（本质是转账给黑洞）
      final mudata = MultiTransactionData();
      mudata.from=wallet.address;
      mudata.fromMulti= _selectedAccount!.multiAddress;
      mudata.to= _systemBurnAddress; // 👈 锁定黑洞地址
      mudata.amount=rawAmount;
      mudata.assetId = _selectedAsset!.assetId;
      mudata.memo = _memoController.text;
      mudata.txType = "pay"; // 使用转账类型
      mudata.finalizeId();
      mudata.mutxHash = mudata.id;

      statusNotifier.value = TxStep.signing;

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask, {
        'payloadJson': jsonEncode(mudata.toJson()),
        'privHex': wallet.privateKey!,
        'pubHex': wallet.pubkey!
      });

      statusNotifier.value = TxStep.submitting;
      String url = "https://tx.qccio.com/v1/mutxbaseData";
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);

      Map<String, dynamic> resData = jsonDecode(response.body);
      if (resData['status'] == 'ACCEPTED' || resData['ok'] == true) {
        await MultiSigFileStorage.saveTask(resData);
        Tools.showToast(context, "✅ 销毁提案已成功发起");

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => MultiSigInitiatedPage(
          txHash: resData['txHash'],
          type: MultiSigPageType.transfer,
          owners: _selectedAccount!.owners,
          threshold: _selectedAccount!.threshold,
        )));
      } else {
        throw resData['msg'] ?? "广播失败";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      Tools.showToast(context, "错误: $e");
    }
  }



  static Future<QccPacket> _signTransactionTask(Map<String, String> data) async {
    return await QccDataProtocol.encodeTransaction(
      payloadJson: data['payloadJson']!,
      privateKeyHex: data['privHex']!,
      publicKeyHex: data['pubHex']!,
    );
  }
}