import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/procotol/QccMatchLogic.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart' as server;

/// 借款(放款) —— 对应 TxLoanTest.java 步骤1：lender -> borrower 发起借贷放款。
/// txType=loan，matchLogic.rule=loan，amount=本金。
///
/// 【和 CommonPledgeWidget 的界面风格保持一致】卡片分区 + 地址下拉 + 资产/
/// 数量输入 + 底部大提交按钮，复用同样的视觉语言，方便你对比审阅。
///
/// 【已按你确认的结论改为 QccTransactionData】借贷在 Java 端就是用
/// TransactionData 实现的(txType=loan/repay/cancelloan)，不需要单独的
/// LoanTransactionData——之前那份草稿已废弃，请从你本机删除，不要再使用。
/// 这里改成直接用你发我的 QccTransactionData.dart(对应 TransactionData.java)，
/// toSign()/getPayloadForHash() 都已经和 Java 源码逐字核对过。
///
/// fromdev 不用手动赋值——QccTransactionData() 默认构造函数已经把它固定
/// 设成了项目里的开发者/推广地址，直接用默认值即可。
///
/// submitUrl 改成了 "${QccExplorerService.baseUrl}/v1/txm"（不是
/// tx.qccio.com）——这是照你给的 QccTransferPage.dart(普通转账，已经在跑
/// 的真实页面)里 `String url = "${QccExplorerService.baseUrl}/v1/txm";`
/// 照抄来的，比我之前的猜测更可靠。
///
/// 【⚠️ 仍需你确认】QccMatchLogic 的真实构造方式——QccTransactionData.dart
/// 自己的注释也说这个类"本次没有拿到最新内容"，这里假设它有默认构造函数
/// + 可写字段(pairAssetId/rate/maxParticipants/rule/remainingAmount)，如果
/// 实际是别的构造方式(比如只有具名构造函数)，编译会报错，把 QccMatchLogic.dart
/// 发我改一下就行。
class LoanIssueWidget extends StatefulWidget {
  const LoanIssueWidget({super.key});

  @override
  State<LoanIssueWidget> createState() => _LoanIssueWidgetState();
}

class _LoanIssueWidgetState extends State<LoanIssueWidget> {
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _lenderAddress = "";

  final _assetIdController = TextEditingController(text: "QCC");
  final _borrowerController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final names = await QccStorage.getAllWalletNames();
    final addrs = QccObj.readWallets().map((e) => e.address).toSet().toList();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localAddrs = addrs;
      if (addrs.isNotEmpty) {
        final active = QccObj.activeWallet?.address;
        _lenderAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (_lenderAddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择出借地址"));
      return;
    }
    final assetId = _assetIdController.text.trim();
    if (assetId.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入资产ID"));
      return;
    }
    final borrower = _borrowerController.text.trim();
    if (borrower.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入借款人地址"));
      return;
    }
    if (borrower == _lenderAddress) {
      Tools.showToast(context, Tools.getTra("借款人地址不能和出借地址相同"));
      return;
    }
    // 🐛 FIX：原来直接把用户输入当"最小单位"整数提交（int.tryParse），跟
    // TxLoanTest.java 的 principal = 1000L * PRECISION 对不上——填"1000"实际
    // 会提交 1000 个最小单位而不是 1000 QCC。改成跟 QccTransferPage.dart /
    // CommonPledgeWidget.dart 一致，用 getAmountRaw() 按资产精度换算。
    final amount = server.QccAssetService().getAmountRaw(assetId, _amountController.text.trim());
    if (amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的借款本金"));
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: _lenderAddress,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = assetId;
        // 【照抄 QccTransferPage.dart】它也是硬编码 "6666"，没有按环境切换，
        // 这里保持一致，不擅自改成 kDebugMode 判断。
        tx.chain = "6666";
        tx.from = wallet.address;
        // fromdev 保留默认构造函数里已经设好的值，不手动覆盖。
        tx.to = borrower;
        tx.amount = amount;
        tx.txType = "loan";
        tx.memo = _memoController.text.trim().isEmpty ? "借贷放款" : _memoController.text.trim();

        final logic = QccMatchLogic();
        logic.rule = "loan";
        logic.pairAssetId = assetId;
        logic.maxParticipants = 1;
        tx.matchLogic = logic;

        tx.finalizeId();
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final txHash = result.data?['txHash']?.toString() ?? "";
      _showSuccessDialog(txHash);
      _borrowerController.clear();
      _amountController.clear();
      _memoController.clear();
    } else {
      LogObj.log("借贷放款提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  void _showSuccessDialog(String pid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("放款已提交"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("这个 pid 就是后续查询/还款/核销要用到的借贷凭证：", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: SelectableText(pid, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("确定"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState("本机未导入任何钱包，无法发起借贷。");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 出借地址(from)", Icons.person_outline, _buildLenderPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("2. 借款人地址(to)", Icons.person_pin_circle_outlined, _buildBorrowerInput()),
          const SizedBox(height: 16),
          _buildSectionCard("3. 资产与本金", Icons.token_outlined, _buildAssetAmountInput()),
          const SizedBox(height: 16),
          _buildSectionCard("4. 备注(可选)", Icons.notes_outlined, _buildMemoInput()),
          const SizedBox(height: 32),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.teal),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildLenderPicker() {
    return DropdownButtonFormField<String>(
      value: _lenderAddress.isEmpty ? null : _lenderAddress,
      isExpanded: true,
      items: _localAddrs
          .map((a) => DropdownMenuItem(value: a, child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
          .toList(),
      onChanged: (val) {
        if (val != null) setState(() => _lenderAddress = val);
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildBorrowerInput() {
    return TextField(
      controller: _borrowerController,
      decoration: InputDecoration(labelText: Tools.getTra("借款人钱包地址"), border: const OutlineInputBorder()),
    );
  }

  Widget _buildAssetAmountInput() {
    return Column(
      children: [
        TextField(
          controller: _assetIdController,
          decoration: InputDecoration(labelText: Tools.getTra("资产ID (如 QCC)"), border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          // 🐛 FIX：允许小数，按资产单位（如 QCC）填写，不再要求换算成最小单位。
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: InputDecoration(
            labelText: Tools.getTra("借款本金 (${_assetIdController.text.trim().isEmpty ? 'QCC' : _assetIdController.text.trim()})"),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_lenderAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("出借地址余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(_lenderAddress, _assetIdController.text.trim().isEmpty ? "QCC" : _assetIdController.text.trim(), fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMemoInput() {
    return TextField(
      controller: _memoController,
      decoration: InputDecoration(labelText: Tools.getTra("备注(默认: 借贷放款)"), border: const OutlineInputBorder()),
    );
  }

  Widget _buildEmptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = !_isSubmitting && _lenderAddress.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.teal, Colors.tealAccent]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起借款", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}