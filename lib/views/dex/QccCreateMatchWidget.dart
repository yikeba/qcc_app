import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/rule/asset/core/AssetMeta.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../procotol/QccDataProtocol.dart';
import '../../procotol/QccPacket.dart';
import '../../procotol/QccTransactionData.dart';
import '../../qccwallet/QccActiveWallet.dart';
import '../../qccwallet/QccWallet.dart';
import '../../utile/QccObj.dart';
import '../../utile/QccStorage.dart';
import '../../utile/Tools.dart';
import '../myasset/QccAssetService.dart';
import '../setting/AppTranslator.dart';
import '../setting/QccPassDialog.dart';
import '../toolviews/QccLoading.dart';
import 'util/DexUtil.dart' as DexUtil;
import '../../procotol/QccMatchLogic.dart';
import 'package:http/http.dart' as http;
import 'package:convert/convert.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
import '../../qccwallet/QccLibOqsSigner.dart';

import 'trade/QccTxSuccessWidget.dart';

class QccCreateMatchWidget extends StatefulWidget {
  const QccCreateMatchWidget({super.key});

  @override
  State<QccCreateMatchWidget> createState() => _QccCreateMatchWidgetState();
}

class _QccCreateMatchWidgetState extends State<QccCreateMatchWidget> {
  String _fromAddress = "";
  QccMatchType _selectedType = QccMatchType.dex;

  // ✅ 交易方向，默认为买入
  DexUtil.TradeDirection _direction = DexUtil.TradeDirection.buy;

  // ✅ 重新定义核心资产对 (Trading Pair)
  String _baseAssetId = "QCC";   // 标的资产 (想要交易的币，如 QCC, MCZX)
  String _quoteAssetId = "USDS"; // 计价资产 (用来支付的稳定币，如 USDT)

  final TextEditingController _amountController = TextEditingController(); // 数量
  final TextEditingController _rateController = TextEditingController();   // 价格
  final TextEditingController _countController = TextEditingController();  // 份数 (普通撮合用)
  final TextEditingController _noteController = TextEditingController();   // 备注

  double _estimatedTotal = 0.0; // 预估总额 (Price * Amount)

  @override
  void initState() {
    super.initState();
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      _fromAddress = wallets[0].address;
    }
    _countController.text = "1"; // 默认1份
  }

  // 动态计算预估总额
  void _updateTotal() {
    double price = double.tryParse(_rateController.text) ?? 0.0;
    double amount = double.tryParse(_amountController.text) ?? 0.0;
    setState(() {
      _estimatedTotal = price * amount;
    });
  }

  // 稳定币选择器
  void _showStableAssetPicker() {
    final allFollowed = QccAssetService().followAsset;
    final List<dynamic> stableAssets = allFollowed.where((a) => a.type == AssetMetaType.Stablecoin.name).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 15),
              const Trans("选择计价资产 (稳定币)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(),
              if (stableAssets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Trans("未发现已关注的稳定币", style: TextStyle(color: Colors.grey))),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: stableAssets.length,
                    itemBuilder: (context, index) {
                      final asset = stableAssets[index];
                      return ListTile(
                        leading: const CircleAvatar(backgroundColor: Color(0xFFE0F2F1), child: Icon(Icons.monetization_on, color: Colors.teal, size: 20)),
                        title: Text(asset.assetId, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: asset.assetId == _quoteAssetId ? const Icon(Icons.check, color: Colors.teal) : null,
                        onTap: () {
                          setState(() => _quoteAssetId = asset.assetId);
                          Navigator.pop(context);
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

  // 地址选择器
  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Trans("选择发送地址", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ListView.separated(
              shrinkWrap: true,
              itemCount: wallets.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final w = wallets[index];
                bool isSelected = w.address == _fromAddress;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: isSelected ? Colors.blue.withOpacity(0.1) : Colors.grey[100], child: Icon(Icons.wallet, color: isSelected ? Colors.blue : Colors.grey)),
                  title: Text(w.address, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                  onTap: () {
                    setState(() => _fromAddress = w.address);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 通用输入框样式
  InputDecoration _inputStyle(String label, String hint, IconData icon) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: Colors.blueGrey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blue, width: 2)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(title: const Trans("现货交易"), centerTitle: true),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
          child: Column(
            children: [
              // 1. DEX 专属：买卖切换器
              if (_selectedType == QccMatchType.dex) _buildDirectionToggle(),

              // 2. 基础配置
              _buildSectionCard(
                title: "交易账户与资产对",
                child: Column(
                  children: [
                    _buildAddressSelector(),
                    const SizedBox(height: 12),

                    // 交易对配置 (Base / Quote)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Trans("标的资产 (Base)"),
                        QccActiveWallet.onlyCoins(
                            _fromAddress,
                            _baseAssetId,
                            color: Colors.blueGrey,
                            onAssetChanged: (v) => setState(() => _baseAssetId = v)
                        ),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Trans("计价资产 (Quote)"),
                        QccActiveWallet.onlyStables(
                            _fromAddress,
                            _quoteAssetId,
                            color: Colors.blueGrey,
                            onAssetChanged: (v) => setState(() =>_quoteAssetId = v)
                        ),
                        /*  ActionChip(
                          avatar: const Icon(Icons.monetization_on, size: 16, color: Colors.teal),
                          label: Text(_quoteAssetId, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          backgroundColor: Colors.teal.withOpacity(0.1),
                          onPressed: _showStableAssetPicker,
                        ),*/
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 3. 交易参数
              _buildSectionCard(
                title: "订单参数",
                child: Column(
                  children: [
                    DropdownButtonFormField<QccMatchType>(
                      value: _selectedType,
                      decoration: _inputStyle("撮合模式", "请选择类型", Icons.layers_outlined),
                      items: QccMatchType.values.map((e) => DropdownMenuItem(value: e, child: Trans(e.label))).toList(),
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                    const SizedBox(height: 12),

                    // ✅ DEX 模式的表单
                    if (_selectedType == QccMatchType.dex) ...[
                      TextField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputStyle("挂单价格", "1 $_baseAssetId = ?", Icons.price_change).copyWith(suffixText: _quoteAssetId),
                        onChanged: (_) => _updateTotal(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputStyle("交易数量", "想要交易的 $_baseAssetId 数量", Icons.account_balance).copyWith(suffixText: _baseAssetId),
                        onChanged: (_) => _updateTotal(),
                      ),
                      const SizedBox(height: 12),

                      // 动态计算总额展示
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Trans(_direction == DexUtil.TradeDirection.buy ? "预计支付总额:" : "预计获得总额:", style: const TextStyle(color: Colors.blueGrey)),
                            Text("${_estimatedTotal.toStringAsFixed(2)} $_quoteAssetId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                          ],
                        ),
                      ),
                    ]
                    // 普通红包/分红模式的表单
                    else ...[
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputStyle("投放总量", "总计 $_baseAssetId", Icons.account_balance).copyWith(suffixText: _baseAssetId),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _countController,
                        keyboardType: TextInputType.number,
                        decoration: _inputStyle("最大份数", "允许成交的最大笔数", Icons.format_list_numbered),
                      ),
                    ],

                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLength: 100,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: _inputStyle("交易说明", "简单描述此交易 (可选)", Icons.edit_note_rounded),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              _buildSubmitButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 买卖切换按钮 UI
  Widget _buildDirectionToggle() {
    bool isBuy = _direction == DexUtil.TradeDirection.buy;
    return Container(
      margin: const EdgeInsets.only(bottom:16),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _direction = DexUtil.TradeDirection.buy),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isBuy ? Colors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isBuy ? [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8)] : [],
                ),
                child: Center(child: Text("买入 (Buy)", style: TextStyle(fontWeight: FontWeight.bold, color: isBuy ? Colors.white : Colors.grey.shade600))),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _direction = DexUtil.TradeDirection.sell),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !isBuy ? Colors.redAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !isBuy ? [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 8)] : [],
                ),
                child: Center(child: Text("卖出 (Sell)", style: TextStyle(fontWeight: FontWeight.bold, color: !isBuy ? Colors.white : Colors.grey.shade600))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 基础卡片包装
  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Trans(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildAddressSelector() {
    return InkWell(
      onTap: _showAddressPicker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wallet, size: 20, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(_fromAddress.isEmpty ? "请选择发送地址" : _fromAddress, style: const TextStyle(fontSize: 13, fontFamily: 'monospace'))),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool isBuy = _direction == DexUtil.TradeDirection.buy && _selectedType == QccMatchType.dex;
    Color btnColor = _selectedType != QccMatchType.dex ? Colors.blue : (isBuy ? Colors.green : Colors.redAccent);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          elevation: 4,
          shadowColor: btnColor.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _handleOpenSubmit,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sensors, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Trans(_selectedType == QccMatchType.dex ? (isBuy ? "确认买入" : "确认卖出") : "确认广播交易",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ✅ 核心逻辑：数据转换与上链
  Future<void> _handleOpenSubmit() async {
    if (_fromAddress.isEmpty) { Tools.showToast(context, "请选择发送地址"); return; }

    double qty = double.tryParse(_amountController.text) ?? 0;
    if (qty <= 0) { Tools.showToast(context, "请输入有效交易数量"); return; }

    // ====== DEX 模式的核心转换 ======
    String finalLockedAssetId = _baseAssetId;   // 链上实际锁定的资产
    String finalTargetAssetId = _quoteAssetId;  // 链上想要换回的资产
    String finalAmountStr = _amountController.text; // 链上锁定的数量
    double finalRate = 0.0;                     // 链上的撮合汇率

    if (_selectedType == QccMatchType.dex) {
      if (_baseAssetId == _quoteAssetId) { Tools.showToast(context, "标的资产不能与计价资产相同"); return; }

      double price = double.tryParse(_rateController.text) ?? 0;
      if (price <= 0) { Tools.showToast(context, "DEX模式必须设置有效价格"); return; }

      if (_direction == DexUtil.TradeDirection.sell) {
        // 🔴 卖单逻辑 (Sell): 锁定 Base，换回 Quote
        finalLockedAssetId = _baseAssetId;
        finalTargetAssetId = _quoteAssetId;
        finalAmountStr = qty.toStringAsFixed(8); // 锁定数量 = 用户输入的 Base 数量
        finalRate = price;                       // 链上汇率 = 价格 (1 Base 换多少 Quote)
      } else {
        // 🟢 买单逻辑 (Buy): 锁定 Quote，换回 Base
        finalLockedAssetId = _quoteAssetId;
        finalTargetAssetId = _baseAssetId;
        // 锁定数量 = 用户输入的 Base 数量 * 价格 (预估总额)
        finalAmountStr = _estimatedTotal.toStringAsFixed(8);
        // 链上汇率 = 倒数 (1 Quote 换多少 Base)
        finalRate = 1.0 / price;
      }
    }

    // 2. 获取密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    // 3. 准备钱包
    String? encryptedData = await QccStorage.getRawData(_fromAddress);
    if (encryptedData == null) { Tools.showToast(context, "找不到钱包私钥数据"); return; }

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 原写法：成功路径先 pop loading，后续 throw 时 catch 再 pop 一次，弹掉的是当前页面
    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    try {
      statusNotifier.value = TxStep.restoring;

      QccWallet? wallet=await QccStorage.restoreWallet(context,_fromAddress,password);
      if (wallet == null || wallet.address != _fromAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      statusNotifier.value = TxStep.building;

      // ✅ 构造 Transaction Data
      final tx = QccTransactionData();
      tx.assetId=finalLockedAssetId;
      tx.from= _fromAddress;
      tx.to = "DEX_POOL_${DateTime.now().millisecondsSinceEpoch}";
      tx.amount = QccAssetService().getAmountRaw(finalLockedAssetId, finalAmountStr); // 注意传入正确的资产ID算精度
      tx.txType = "open";
      tx.memo = _noteController.text;

      // ✅ 构造 MatchLogic
      final logic = QccMatchLogic(
        rule: _selectedType.name,
        maxParticipants: int.tryParse(_countController.text) ?? 1,
        rate: 0,
        remainingAmount: 0,
      );
      if (_selectedType == QccMatchType.dex) {
        logic.rate = finalRate;
        logic.pairAssetId = finalTargetAssetId;
      }
      LogObj.log("open 交易 汇率订单:$finalRate   对应资产:$finalTargetAssetId");
      tx.matchLogic = logic;
      tx.finalizeId();

      // 🐛 原来直接调 QccDataProtocol.encodeTransaction()，它内部的签名是旧逻辑
      // （SingleSigTokenIssueWidget 里记录过：signature 恒为空 → Invalid Signature）。
      // 改为和 QccTransferPage 一致：对 tx.toSign() 做 ML-DSA 签名后覆盖 packet.signature。
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask, {
        'tx': tx,
        'privHex': wallet.privateKey!,
        'pubHex': wallet.pubkey!,
      });

      // 原来写死 https://tx.qccio.com，统一走 baseUrl（转账 /v1/txm 已在 baseUrl 实测通过）
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/txm"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      closeLoading();
      LogObj.log("Open 交易返回: ${response.body}");
      // 原来只看 HTTP 200 就弹成功页；现在必须 code==ACCEPTED 且带 txHash
      final String txHash = QccTxStatusService.parseAcceptedTxHash(response);
      final Map<String, dynamic> result = Map<String, dynamic>.from(jsonDecode(response.body) as Map);

      if (!mounted) return;
      final bool isDex = _selectedType == QccMatchType.dex;
      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: isDex ? "挂单已上链" : "交易已上链",
          details: [
            Text(isDex
                ? "${_direction == DexUtil.TradeDirection.buy ? '买入' : '卖出'} ${_amountController.text} $_baseAssetId"
                : "投放 ${_amountController.text} $_baseAssetId"),
            if (isDex) Text("价格：${_rateController.text} $_quoteAssetId", style: const TextStyle(fontSize: 12)),
            Text("锁定：$finalAmountStr $finalLockedAssetId", style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          footer: "挂单上链后才会出现在盘口、才能被他人成交。",
        ),
      );

      if (!mounted) return;
      if (st?.state == TxChainState.confirmed) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => QccTxSuccessWidget(response: {
            ...result,
            'chainStatus': 'confirmed',
            if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
          }),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "挂单上链失败：${st!.message ?? '未知原因'}，资产未被锁定");
      } else {
        Tools.showToast(context, "挂单已受理，尚未确认上链，请稍后在「我的交易」中查看");
      }
    } catch (e) {
      closeLoading();
      if (mounted) Tools.showToast(context, "操作失败: ${e.toString()}");
    }
  }

  /// 子线程签名 —— 与 QccTransferPage._signTransactionTask 同一写法：
  /// 对 tx.toSign() 单独签名并覆盖 packet.signature。
  static Future<QccPacket> _signTransactionTask(Map<String, dynamic> data) async {
    final QccTransactionData tx = data['tx'];
    final Uint8List sig = QccLibOqsSigner.sign(data['privHex'], tx.toSign());
    final QccPacket qp = await QccDataProtocol.encodeTransaction(
      payloadJson: jsonEncode(tx.toJson()),
      privateKeyHex: data['privHex']!,
      publicKeyHex: data['pubHex']!,
    );
    qp.signature = hex.encode(sig);
    return qp;
  }
}