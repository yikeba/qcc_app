import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart' as server;
import 'package:http/http.dart' as http;

/// 还款 —— 对应 TxLoanTest.java 步骤2(doRepay)：borrower -> lender 还款，
/// 支持部分多次还款(txType=repay，matcHash=放款交易 pid)。
///
/// 【设计取舍】不用本机存储记录 pid，而是选好"借款人地址"之后实时查询
/// "这个地址名下有哪些活跃借贷"(GET /v1/loan/?address=)，从查询结果里选——
/// 这样即使这笔借贷是在别的设备上发起的，只要查询接口能查到，这里照样能还款，
/// 不依赖"当初是不是在本机点的借款"。查询接口地址的假设和 LoanStatusWidget.dart
/// 完全一致，见该文件头部说明。
///
/// 【已按你确认的结论改为 QccTransactionData】同 LoanIssueWidget.dart，
/// 不再用已废弃的 LoanTransactionData，submitUrl 也改成
/// "${QccExplorerService.baseUrl}/v1/txm"（照 QccTransferPage.dart 抄的）。
class LoanRepayWidget extends StatefulWidget {
  const LoanRepayWidget({super.key});

  @override
  State<LoanRepayWidget> createState() => _LoanRepayWidgetState();
}

class _LoanRepayWidgetState extends State<LoanRepayWidget> {
  static final String _base = QccExplorerService.baseUrl;

  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _borrowerAddress = "";

  bool _isLoadingLoans = false;
  List<Map<String, dynamic>> _activeLoans = [];
  Map<String, dynamic>? _selectedLoan;

  final _amountController = TextEditingController();
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
        _borrowerAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
    if (_borrowerAddress.isNotEmpty) _loadActiveLoans();
  }

  Future<void> _loadActiveLoans() async {
    if (_borrowerAddress.isEmpty) return;
    setState(() {
      _isLoadingLoans = true;
      _activeLoans = [];
      _selectedLoan = null;
    });
    try {
      final response = await http.get(Uri.parse("$_base/v1/loan/?address=$_borrowerAddress"));
      if (response.statusCode != 200) return;
      final Map<String, dynamic> result = jsonDecode(response.body);
      if (result['ok'] != true) return;
      final String? dataStr = result['data']?.toString();
      if (dataStr == null || dataStr.isEmpty) return;

      final List<Map<String, dynamic>> parsed = [];
      final String trimmed = dataStr.trim();
      if (trimmed.startsWith('[')) {
        final List<dynamic> arr = jsonDecode(dataStr);
        for (final item in arr) {
          parsed.add(Map<String, dynamic>.from(item as Map));
        }
      } else {
        parsed.add(Map<String, dynamic>.from(jsonDecode(dataStr) as Map));
      }
      // 只保留"我是借款人(borrower)"的活跃借贷——查询接口可能会把我作为
      // 出借人(owner)参与的记录也一起返回，出借人不能对自己发起还款交易。
      final mine = parsed.where((l) => (l['borrower'] ?? '').toString() == _borrowerAddress).toList();
      if (!mounted) return;
      setState(() {
        _activeLoans = mine;
        _selectedLoan = mine.isNotEmpty ? mine.first : null;
      });
    } catch (e) {
      LogObj.log("查询活跃借贷失败: $e");
    } finally {
      if (mounted) setState(() => _isLoadingLoans = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_selectedLoan == null) {
      Tools.showToast(context, Tools.getTra("请选择要还款的借贷"));
      return;
    }
    final int currentAmount = ((_selectedLoan!['currentAmount'] ?? 0) as num).toInt();
    // 🐛 FIX：跟 LoanIssueWidget 一样，原来直接把输入当最小单位整数用
    // （int.tryParse），改成用 getAmountRaw() 按资产精度换算。这里固定按
    // "QCC"换算——跟 tx.assetId 硬编码 "QCC" 保持一致（如果这笔借贷实际是
    // 别的资产，需要你确认查询接口能不能把 assetId 也返回，目前 Java 测试
    // 的 printLoanDetail() 没有输出这个字段，widget 这边也就没法按真实资产
    // 换算，先按现状硬编码 QCC，跟其余提交逻辑保持一致）。
    final amount = server.QccAssetService().getAmountRaw("QCC", _amountController.text.trim());
    if (amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的还款金额"));
      return;
    }
    if (amount > currentAmount) {
      Tools.showToast(context, Tools.getTra("还款金额不能超过剩余欠款"));
      return;
    }

    final String pid = (_selectedLoan!['pid'] ?? '').toString();
    final String owner = (_selectedLoan!['owner'] ?? '').toString();

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: _borrowerAddress,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = "QCC";
        tx.chain = "6666"; // 照 QccTransferPage.dart 硬编码，不擅自改
        tx.from = wallet.address;
        // fromdev 用默认构造函数里已经设好的值，不手动覆盖。
        tx.to = owner;
        tx.amount = amount;
        tx.txType = "repay";
        tx.matcHash = pid;
        tx.memo = "借贷还款";
        tx.finalizeId();
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      Tools.showToast(context, "✅ 还款已提交");
      _amountController.clear();
      _loadActiveLoans();
    } else {
      LogObj.log("借贷还款提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  String _nameFor(String addr) {
    final nick = _walletNames[addr];
    return nick != null ? "$nick ($addr)" : addr;
  }

  // 🐛 FIX：查询接口返回的 currentAmount/repaid 是最小单位（跟 TxLoanTest.java
  // 的 PRECISION=1_000_000_000 一致），原来直接把这串数字显示给用户看，
  // 现在换算成人类可读的 QCC 数量再显示。
  String _formatAmount(dynamic raw) {
    if (raw == null) return '-';
    final n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null) return raw.toString();
    String s = (n / 1000000000).toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState("本机未导入任何钱包，无法还款。");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 借款人地址(from)", Icons.person_outline, _buildBorrowerPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("2. 选择要还的借贷", Icons.receipt_long_outlined, _buildLoanPicker()),
          if (_selectedLoan != null) ...[
            const SizedBox(height: 16),
            _buildSectionCard("3. 还款金额", Icons.payments_outlined, _buildAmountInput()),
          ],
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
            Icon(icon, size: 16, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildBorrowerPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _borrowerAddress.isEmpty ? null : _borrowerAddress,
          isExpanded: true,
          items: _localAddrs
              .map((a) => DropdownMenuItem(value: a, child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _borrowerAddress = val);
              _loadActiveLoans();
            }
          },
          decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
        // 🐛 FIX（需求：选 from 地址时要显示 from 余额）：原来这里没有显示
        // 还款账户(borrower/from)自己的余额，跟 LoanIssueWidget 里出借地址
        // 有余额显示不对称——补上，按当前硬编码提交用的 "QCC" 资产显示。
        if (_borrowerAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("当前余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(_borrowerAddress, "QCC", fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLoanPicker() {
    if (_isLoadingLoans) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()));
    }
    if (_activeLoans.isEmpty) {
      return Text(
        "该地址名下查不到活跃借贷(可能已结清/已核销，或还没有以这个地址作为借款人的放款记录)。",
        style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
      );
    }
    return Column(
      children: _activeLoans.map((loan) {
        final String pid = (loan['pid'] ?? '').toString();
        final int currentAmount = ((loan['currentAmount'] ?? 0) as num).toInt();
        final int repaid = ((loan['repaid'] ?? 0) as num).toInt();
        final String owner = (loan['owner'] ?? '').toString();
        final bool selected = _selectedLoan != null && (_selectedLoan!['pid'] ?? '') == pid;
        return InkWell(
          onTap: () => setState(() => _selectedLoan = loan),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? Colors.orange.withOpacity(0.08) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? Colors.orange : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("剩余欠款: ${_formatAmount(currentAmount)}  ·  已还: ${_formatAmount(repaid)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text("出借人: ${_nameFor(owner)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text("pid: $pid", style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAmountInput() {
    final int currentAmount = ((_selectedLoan!['currentAmount'] ?? 0) as num).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _amountController,
          // 🐛 FIX：允许小数，按 QCC 为单位填写，不再要求换算成最小单位；
          // 提示文字里的"剩余欠款"也换算成人类可读数值。
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: InputDecoration(labelText: Tools.getTra("还款金额 (QCC，剩余欠款 ${_formatAmount(currentAmount)})"), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 6),
        TextButton(
          // 🐛 FIX：一键填入也要填人类可读值（跟输入框现在期望的单位一致），
          // 不能再填原始最小单位整数，否则会被 getAmountRaw() 再放大一次。
          onPressed: () => setState(() => _amountController.text = _formatAmount(currentAmount)),
          child: Text(Tools.getTra("一键填入全部剩余欠款"), style: const TextStyle(fontSize: 12)),
        ),
      ],
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
    bool active = !_isSubmitting && _selectedLoan != null;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Colors.orange, Colors.deepOrangeAccent]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认还款", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}