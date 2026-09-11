import 'dart:async';
import 'dart:convert';
import 'dart:developer' as LogObj;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../procotol/QccDataProtocol.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/QccTransactionData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../myasset/QccAssetService.dart';
import '../../myasset/QccAsset.dart'; // 引入资产模型
import '../../setting/AppTranslator.dart';
import '../../setting/QccPassDialog.dart';
import '../../toolviews/QccLoading.dart';
import '../../../procotol/QccMatchLogic.dart';
import 'QccDividendSuccessPage.dart';

class QccAssetDividendPage extends StatefulWidget {
  final String? initialBaseAsset;

  const QccAssetDividendPage({super.key, this.initialBaseAsset});

  @override
  State<QccAssetDividendPage> createState() => _QccAssetDividendPageState();
}

class _QccAssetDividendPageState extends State<QccAssetDividendPage> {
  String _fromAddress = "";

  // ✅ 核心配置
  String _baseAssetId = "ITTC";  // 权益资产 (Base)
  String _quoteAssetId = "USDS";  // 红利资产 (Quote)
  double _baseTotalSupply = 0.0; // 标的资产总发行量

  final TextEditingController _amountController = TextEditingController(); // 总预算
  final TextEditingController _rateController = TextEditingController();   // 每股派息
  final TextEditingController _memoController = TextEditingController();   // 备注

  double _myStableBalance = 0.0;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBaseAsset != null && widget.initialBaseAsset != "QCC") {
      _baseAssetId = widget.initialBaseAsset!;
    }
    _initAddress();
    _fetchAssetSupply(); // 初始化加载总量
  }

  void _initAddress() {
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      _fromAddress = QccObj.activeWallet?.address ?? wallets[0].address;
    }
  }

  // ✅ 核心逻辑 1：获取权益资产的全球总发行量 (用于换算)
  Future<void> _fetchAssetSupply() async {
    final assets = await QccAssetService().fetchAllAssets();
    final current = assets.firstWhere(
          (a) => a.assetId == _baseAssetId,
      //orElse: () => QccAsset(assetId: _baseAssetId, initialSupply: "0"),
    );

    if (mounted) {
      setState(() {
        _baseTotalSupply = QccAssetService().getHumanAmountNum(_baseAssetId, current.initialSupply);
      });
    }
  }


  // ✅ 核心逻辑 3：双向自动换算
  void _updateByAmount(String val) {
    if (_baseTotalSupply <= 0) return;
    double amount = double.tryParse(val) ?? 0;
    double rate = amount / _baseTotalSupply;
    _rateController.text = rate > 0 ? rate.toStringAsFixed(6) : "";
  }

  void _updateByRate(String val) {
    if (_baseTotalSupply <= 0) return;
    double rate = double.tryParse(val) ?? 0;
    double amount = rate * _baseTotalSupply;
    _amountController.text = amount > 0 ? amount.toStringAsFixed(4) : "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(title: const Trans("发布分红公告 (Open)"), centerTitle: true),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildSectionCard(
                title: "分红权限与资产对",
                child: Column(
                  children: [
                    _buildAddressSelector(),
                    const SizedBox(height: 16),
                    _rowAssetSelector("权益资产 (Base)", _baseAssetId, true),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                    _rowAssetSelector("红利资产 (Quote)", _quoteAssetId, false),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSectionCard(
                title: "派息精密换算",
                child: Column(
                  children: [
                    _buildSupplyInfo(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: _updateByRate,
                      decoration: _inputStyle("每股派息 (Rate)", "每 1 Token 分多少 $_quoteAssetId", Icons.auto_graph)
                          .copyWith(suffixText: "$_quoteAssetId/T"),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: _updateByAmount,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                      decoration: _inputStyle("总预算 (Total Pool)", "红利池注入总量", Icons.account_balance_wallet)
                          .copyWith(suffixText: _quoteAssetId),
                    ),
                    const SizedBox(height: 12),
                    _buildBalanceBar(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _memoController,
                      maxLength: 100,
                      maxLines: 2,
                      decoration: _inputStyle("分红备注", "记录本次分红的原因", Icons.campaign_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSubmitButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI 子组件 ---

  Widget _buildSupplyInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Trans("当前代币流通总量:", style: TextStyle(fontSize: 12, color: Colors.orange)),
          Text("$_baseTotalSupply $_baseAssetId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
        ],
      ),
    );
  }

  Widget _rowAssetSelector(String label, String currentId, bool isBase) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Trans(label, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold)),
            if (isBase && currentId == "QCC") const Text("⚠️ QCC不可分红", style: TextStyle(color: Colors.red, fontSize: 10)),
          ],
        ),
        isBase
            ? QccActiveWallet.onlyCoins(_fromAddress, currentId, color: Colors.blue, onAssetChanged: (v) {
          if (v == "QCC") { Tools.showToast(context, "QCC原生币不能作为分红标的"); return; }
          setState(() => _baseAssetId = v);
          _fetchAssetSupply(); // 切换资产同步总量
        })
            : QccActiveWallet.onlyStables(_fromAddress, currentId, color: Colors.green,onBalanceLoaded: (value){
               _myStableBalance=value.amount;
    },onAssetChanged: (v) {
          setState(() { _quoteAssetId = v; });
        }),
      ],
    );
  }

  // --- 核心提交逻辑 ---

  Future<void> _handleDividendSubmit() async {
    if (_fromAddress.isEmpty) return;
    if (_baseAssetId == "QCC") { Tools.showToast(context, "QCC原生币不能分红"); return; }

    double totalPool = double.tryParse(_amountController.text) ?? 0;
    double rate = double.tryParse(_rateController.text) ?? 0;

    if (totalPool <= 0 || totalPool > _myStableBalance) { Tools.showToast(context, "总预算无效或余额不足"); return; }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, _fromAddress, password);
      if (wallet == null) throw Exception("还原钱包失败");

      statusNotifier.value = TxStep.building;
      final tx = QccTransactionData();
      tx.assetId= _quoteAssetId;
      tx.from= _fromAddress;
      tx.to = "DIVIDEND_POOL_${DateTime.now().millisecondsSinceEpoch}";
      tx.amount = QccAssetService().getAmountRaw(_quoteAssetId, totalPool.toString());
      tx.txType = "open";
      tx.memo = _memoController.text;

      // ✅ MatchLogic 规则配置
      tx.matchLogic = QccMatchLogic(
        rule: "dividend",
        maxParticipants: 9999,
        rate: rate,
        remainingAmount: 0, // 此处的 rate 即为“每股分红”
      );
      tx.matchLogic!.pairAssetId = _baseAssetId;
      tx.finalizeId();

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask, {
        'payloadJson': jsonEncode(tx.toJson()),
        'privHex': wallet.privateKey!,
        'pubHex': wallet.pubkey!
      });

      statusNotifier.value = TxStep.submitting;
      final response = await http.post(Uri.parse("https://tx.qccio.com/v1/txm"), body: jsonEncode(packet.toJson()));

      if (Navigator.canPop(context)) Navigator.pop(context);

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        LogObj.log("分红交易返回$response");
        // ✅ 1. 严格判断共识状态
        if (resJson['status'] == 'ACCEPTED') {

          // ✅ 2. 构造标准化结果集 (统一用于存储和展示)
          // 包含：Hash凭证、权益资产、分红资产、金额、比例、存证备注及时间撮
          final dividendResult = {
            'id': resJson['txHash'] ?? tx.id, // 优先使用节点返回的 Hash
            'baseAssetId': _baseAssetId,
            'quoteAssetId': _quoteAssetId,
            'amount': tx.amount,
            'rate': rate.toString(),
            'memo': tx.memo,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'expireTime': DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
            'status': 'ACCEPTED',
          };
          // ✅ 3. 异步存入本地分红历史
          await QccStorage.addDividendOrder(_fromAddress, dividendResult);

          // ✅ 4. 路由跳转优化
          // 首先确保关闭 QccLoading 的弹窗
          if (Navigator.canPop(context)) Navigator.pop(context);

          // 使用 pushReplacement 替换当前输入页面，防止用户返回后重复提交
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => QccDividendSuccessPage(result: dividendResult,))
          );
        } else {
          // 状态非 ACCEPTED 处理
          if (Navigator.canPop(context)) Navigator.pop(context);
          Tools.showToast(context, "节点拒绝交易: ${resJson['msg'] ?? '共识未通过'}");
        }
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      Tools.showToast(context, "错误: $e");
    }
  }

  // --- 基础样式组件 (参考 DexMatchWidget) ---

  Widget _buildAddressSelector() {
    return InkWell(
      onTap: _showAddressPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.15))),
        child: Row(children: [
          const Icon(Icons.verified_user, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(_fromAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
          const Icon(Icons.unfold_more, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }

  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(context: context, builder: (context) => ListView(
      shrinkWrap: true,
      children: wallets.map((w) => ListTile(
        title: Text(w.address, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        onTap: () { setState(() => _fromAddress = w.address); Navigator.pop(context);  },
      )).toList(),
    ));
  }

  Widget _buildBalanceBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Trans("可用支付余额:", style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
          _isChecking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Text("$_myStableBalance $_quoteAssetId", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Trans(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: _handleDividendSubmit,
        child: const Trans("确认发布分红 (Open)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  InputDecoration _inputStyle(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: Colors.blueGrey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      filled: true, fillColor: Colors.white,
    );
  }

  static Future<QccPacket> _signTransactionTask(Map<String, String> data) async {
    return await QccDataProtocol.encodeTransaction(
      payloadJson: data['payloadJson']!, privateKeyHex: data['privHex']!, publicKeyHex: data['pubHex']!,
    );
  }
}