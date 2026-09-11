import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:http/http.dart' as http;

/// 借贷状态查询 —— 对应 TxLoanTest.java 的 queryLoanByHash/queryLoanByAddress。
///
/// 【查询接口地址，⚠️ 仍需你确认路径本身，但 base 已更有把握】
/// Java 侧两个查询都是 demoUtil.poolurl + "/v1/loan/?hash=xxx" 或
/// ".../v1/loan/?address=xxx"（这是实际代码，注意 TxLoanTest.java 文件头部的
/// 说明注释里写的是另一个猜测路径 "/v1/loanaddress/?address="，和它自己的代码
/// 对不上——我按实际跑的代码来，即两个查询用同一个路径 /v1/loan/，只是参数名
/// 不同）。base 用 QccExplorerService.baseUrl，这一点现在有更强依据了——
/// 你给的 QccTransferPage.dart(普通转账真实页面)里提交 /v1/txm 用的也是
/// "${QccExplorerService.baseUrl}/v1/txm"，不是 tx.qccio.com，说明这个域名
/// 同时承担提交和查询，和这里的假设一致。如果 /v1/loan 具体路径不对，告诉我
/// 改一下即可。
///
/// 【撤销/核销入口位置】按 QccTxManagerPage.dart 自己的设计注释——
/// "撤销不设独立入口——由「交易明细」进入详情后判断并执行(cancel/cancelloan)"，
/// 核销按钮放在详情弹窗里：只有当前选中地址 == 该笔借贷 owner 且状态为
/// ACTIVE 时才显示，对应 TxLoanCancelTest.java(cancelloan 只能由 owner 发起)。
class LoanStatusWidget extends StatefulWidget {
  const LoanStatusWidget({super.key});

  @override
  State<LoanStatusWidget> createState() => _LoanStatusWidgetState();
}

class _LoanStatusWidgetState extends State<LoanStatusWidget> {
  static final String _base = QccExplorerService.baseUrl;

  final _hashController = TextEditingController();
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _queryAddress = "";

  bool _byHash = false; // false=按本机地址查询(默认)，true=按 txHash 查询
  bool _isLoading = false;
  String? _errorMsg;
  List<Map<String, dynamic>> _loans = [];

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
        _queryAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
    if (_queryAddress.isNotEmpty) _runQuery();
  }

  Future<void> _runQuery() async {
    final String param = _byHash ? _hashController.text.trim() : _queryAddress;
    if (param.isEmpty) {
      Tools.showToast(context, Tools.getTra(_byHash ? "请输入 txHash" : "请选择本机地址"));
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _loans = [];
    });
    try {
      final String url = _byHash ? "$_base/v1/loan/?hash=$param" : "$_base/v1/loan/?address=$param";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        setState(() => _errorMsg = "网络通讯异常: ${response.statusCode}");
        return;
      }
      final Map<String, dynamic> result = jsonDecode(response.body);
      if (result['ok'] != true) {
        setState(() => _errorMsg = "查询失败");
        return;
      }
      final String? dataStr = result['data']?.toString();
      if (dataStr == null || dataStr.isEmpty) {
        setState(() => _loans = []);
        return;
      }
      final String trimmed = dataStr.trim();
      final List<Map<String, dynamic>> parsed = [];
      if (trimmed.startsWith('[')) {
        final List<dynamic> arr = jsonDecode(dataStr);
        for (final item in arr) {
          parsed.add(Map<String, dynamic>.from(item as Map));
        }
      } else {
        parsed.add(Map<String, dynamic>.from(jsonDecode(dataStr) as Map));
      }
      if (!mounted) return;
      setState(() => _loans = parsed);
    } catch (e) {
      LogObj.log("借贷状态查询出错: $e");
      setState(() => _errorMsg = "查询出错: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancelLoan(Map<String, dynamic> loan) async {
    final String pid = (loan['pid'] ?? '').toString();
    final String owner = (loan['owner'] ?? '').toString();
    final String borrower = (loan['borrower'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("核销该笔借贷"),
        content: Text(
          "核销无资金转移，仅把这笔欠款从账本上抹掉——本金留在借款人手里，出借人不会拿回任何东西，"
              "只能由出借人(owner)发起。\npid: $pid",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("确认核销")),
        ],
      ),
    );
    if (ok != true) return;

    final result = await QccTxFlow.run(
      context: context,
      address: owner,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = "QCC";
        tx.chain = "6666"; // 照 QccTransferPage.dart 硬编码，不擅自改
        tx.from = wallet.address;
        // fromdev 用默认构造函数里已经设好的值，不手动覆盖。
        tx.to = borrower;
        // 【按 TxLoanCancelTest.java 的说明文字，不是它的代码】onCancelLoan
        // 不读 amount 字段，这里填 0，语义上更清楚"这笔交易本身不代表资金移动"
        // (该 Java 文件的代码里实际把它设成了 principal，和自己的注释矛盾，
        // 但因为服务端不读这个字段，填哪个数值都不影响结果，这里选更清楚的 0)。
        tx.amount = 0;
        tx.txType = "cancelloan";
        tx.matcHash = pid;
        tx.memo = "借贷核销";
        tx.finalizeId();
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    if (result.cancelled) return;
    if (result.success) {
      Tools.showToast(context, "✅ 核销已提交");
      Navigator.of(context).pop(); // 关闭详情弹窗
      _runQuery();
    } else {
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  void _showDetail(Map<String, dynamic> loan) {
    final String pid = (loan['pid'] ?? '').toString();
    final String owner = (loan['owner'] ?? '').toString();
    final String borrower = (loan['borrower'] ?? '').toString();
    final String state = (loan['state'] ?? '').toString();
    final int currentAmount = ((loan['currentAmount'] ?? 0) as num).toInt();
    final int repaid = ((loan['repaid'] ?? 0) as num).toInt();
    final bool iAmOwner = _localAddrs.contains(owner);
    final bool canCancel = iAmOwner && state.toUpperCase() == 'ACTIVE';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Trans("借贷明细"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row("pid", pid, mono: true),
                _row("状态", state),
                _row("出借人(owner)", _nameFor(owner)),
                _row("借款人(borrower)", _nameFor(borrower)),
                _row("剩余欠款 currentAmount", _formatAmount(currentAmount)),
                _row("已还 repaid", _formatAmount(repaid)),
              ],
            ),
          ),
          actions: [
            if (canCancel)
              TextButton(
                onPressed: () => _handleCancelLoan(loan),
                child: const Text("核销借贷", style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text("关闭")),
          ],
        );
      },
    );
  }

  String _nameFor(String addr) {
    final nick = _walletNames[addr];
    return nick != null ? "$nick ($addr)" : addr;
  }

  // 🐛 FIX：currentAmount/repaid 是查询接口返回的最小单位数值（精度对齐
  // TxLoanTest.java 的 PRECISION=1_000_000_000），原来直接显示这个原始数字，
  // 现在换算成人类可读的 QCC 数量。
  String _formatAmount(dynamic raw) {
    if (raw == null) return '-';
    final n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null) return raw.toString();
    String s = (n / 1000000000).toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: Colors.black87, fontFamily: mono ? 'monospace' : null),
          children: [
            TextSpan(text: "$label：", style: const TextStyle(color: Colors.black54, fontFamily: null)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Trans("按本机地址"), icon: const Icon(Icons.account_balance_wallet_outlined, size: 16)),
                  ButtonSegment<bool>(value: true, label: Trans("按 txHash"), icon: const Icon(Icons.tag, size: 16)),
                ],
                selected: <bool>{_byHash},
                onSelectionChanged: (s) => setState(() => _byHash = s.first),
                style: SegmentedButton.styleFrom(selectedBackgroundColor: Colors.teal, selectedForegroundColor: Colors.white, side: BorderSide.none),
              ),
              const SizedBox(height: 12),
              if (_byHash)
                TextField(
                  controller: _hashController,
                  decoration: InputDecoration(
                    labelText: Tools.getTra("放款交易 txHash(PID)"),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _runQuery),
                  ),
                  onSubmitted: (_) => _runQuery(),
                )
              else if (_localAddrs.isEmpty)
                Text("本机未导入任何钱包。", style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              else
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _queryAddress.isEmpty ? null : _queryAddress,
                        isExpanded: true,
                        items: _localAddrs
                            .map((a) => DropdownMenuItem(value: a, child: Text(_nameFor(a), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _queryAddress = val);
                            _runQuery();
                          }
                        },
                        decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _runQuery),
                  ],
                ),
            ],
          ),
        ),
        if (_errorMsg != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text("当前没有查到活跃借贷记录。", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _loans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildLoanTile(_loans[i]),
    );
  }

  Widget _buildLoanTile(Map<String, dynamic> loan) {
    final String pid = (loan['pid'] ?? '').toString();
    final String owner = (loan['owner'] ?? '').toString();
    final String borrower = (loan['borrower'] ?? '').toString();
    final String state = (loan['state'] ?? '').toString();
    final int currentAmount = ((loan['currentAmount'] ?? 0) as num).toInt();
    final int repaid = ((loan['repaid'] ?? 0) as num).toInt();
    final bool iAmOwner = _localAddrs.contains(owner);
    final bool iAmBorrower = _localAddrs.contains(borrower);

    return InkWell(
      onTap: () => _showDetail(loan),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statePill(state),
                const SizedBox(width: 8),
                if (iAmOwner) _rolePill("我是出借人", Colors.blue),
                if (iAmBorrower) _rolePill("我是借款人", Colors.orange),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Text("剩余欠款: ${_formatAmount(currentAmount)}  ·  已还: ${_formatAmount(repaid)}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 6),
            Text("借款人: ${_nameFor(borrower)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text("出借人: ${_nameFor(owner)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text("pid: $pid", style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _statePill(String state) {
    final bool active = state.toUpperCase() == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: (active ? Colors.green : Colors.grey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(state.isEmpty ? "-" : state, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.green.shade700 : Colors.grey.shade700)),
    );
  }

  Widget _rolePill(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}