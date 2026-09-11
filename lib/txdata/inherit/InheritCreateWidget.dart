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

import 'InheritConfirmPage.dart';

/// 创建信托(继承) —— 对应 TxMatchInheritTest.java 的 submitInheritOpen()：
/// txType=open，matchLogic.rule=inherit，继承人地址在 tx.to（不在 matchLogic
/// 里，MatchProcessFactory 对 inherit 注册了 usesTo=true）。
///
/// 【风格对齐】跟 LoanIssueWidget.dart 是同一套写法：地址下拉 + 余额显示 +
/// getAmountRaw() 精度换算 + QccTxFlow.run() 提交，方便你对比审阅。
///
/// ⚠️⚠️⚠️ 高风险项，正式使用前务必确认，不是"能不能编译"的问题，是"签名对不对得上"
/// 的问题：
///
/// 1.【最关键】MatchLogic.maturityTime 这个字段——Java 测试文件自己说得很明白：
///    "条件字节：只有 rule==inherit 时才出现在 toBytes() 和签名串里"，并且
///    "⚠️ 前置条件：服务端必须已应用 toSignFragment() 改造，否则本测试签出来的
///    串和服务端算的对不上，所有交易会直接验签失败"。这句话描述的是【服务端】
///    的前置条件，但客户端（也就是你的 QccTransactionData.dart）的 toSign()
///    实现同样需要知道"rule==inherit 时要把 maturityTime 编进签名串"这条规则，
///    不然这边签的串和链上重新计算的对不上，一样会被拒。你之前给 LoanIssueWidget
///    核对签名时用的是"借贷"场景（matchLogic 只有 rule/pairAssetId/maxParticipants
///    三个字段），并不确定当时核对的版本是否已经把 maturityTime 这个继承专属字段
///    也覆盖进去了。这是本次唯一一处我建议你先用小额本金实测一次"创建信托"，
///    看会不会被拒（Invalid Signature），再大范围使用的地方。
/// 2. QccMatchLogic 是否已经有 maturityTime 这个可写字段——如果没有，
///    下面 `logic.maturityTime = maturityTime;` 这一行会直接编译不过。
/// 3. matchLogic.pairAssetId 的取值——Java 测试文件里代码注释写的是"正常应为空"，
///    但实际跑通的阶段2(创建信托A/B，真正成功的那两笔)传的参数是
///    `ASSET_PRINCIPAL`("QCC")，不是空字符串；文件里阶段1的负向用例 1f 专门
///    测了"pairAssetId 为空"，而且断言它必须被拒绝——这俩明显对不上（"正常应为空"
///    的注释和"传空会被拒"的测试用例矛盾）。本文件按【实际跑通的代码】走，
///    即 pairAssetId = assetId（跟 loan 的写法一致），不是空字符串。建议你也
///    顺手把 Java 测试文件里那处注释改一下，避免以后又被这个矛盾误导。
class InheritCreateWidget extends StatefulWidget {
  const InheritCreateWidget({super.key});

  @override
  State<InheritCreateWidget> createState() => _InheritCreateWidgetState();
}

class _InheritCreateWidgetState extends State<InheritCreateWidget> {
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _testatorAddress = "";

  final _assetIdController = TextEditingController(text: "QCC");
  final _heirController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  // 默认到期时间：30天后。测试文件里生产默认 minLeadMs=7天，太近会被拒，
  // 这里给一个明显更远的默认值，避免一上来就踩"到期时间过近"这条负向用例。
  DateTime _maturityDateTime = DateTime.now().add(const Duration(days: 30));

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
        _testatorAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
  }

  Future<void> _pickMaturityDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _maturityDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 50)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_maturityDateTime),
    );
    if (time == null) return;
    setState(() {
      _maturityDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _handleSubmit() async {
    if (_testatorAddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择委托人地址"));
      return;
    }
    final assetId = _assetIdController.text.trim();
    if (assetId.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入资产ID"));
      return;
    }
    final heir = _heirController.text.trim();
    if (heir.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入继承人地址"));
      return;
    }
    if (heir == _testatorAddress) {
      Tools.showToast(context, Tools.getTra("继承人地址不能和委托人地址相同"));
      return;
    }
    final amount = server.QccAssetService().getAmountRaw(assetId, _amountController.text.trim());
    if (amount <= 0) {
      Tools.showToast(context, Tools.getTra("请输入正确的本金数量"));
      return;
    }
    final maturityTime = _maturityDateTime.millisecondsSinceEpoch;
    if (maturityTime <= DateTime.now().millisecondsSinceEpoch) {
      Tools.showToast(context, Tools.getTra("到期时间必须晚于当前时间"));
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: _testatorAddress,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = assetId;
        tx.chain = "6666"; // 照 LoanIssueWidget/QccTransferPage.dart 硬编码，不擅自改
        tx.from = wallet.address;
        tx.to = heir; // ✅ 继承人地址在这里，不在 matchLogic 里
        tx.amount = amount;
        tx.txType = "open";
        tx.memo = _memoController.text.trim().isEmpty ? "创建继承信托" : _memoController.text.trim();

        final logic = QccMatchLogic();
        logic.rule = "inherit";
        // ⚠️ 见文件头注释3：按实际跑通的 Java 代码，这里传 assetId，不是空字符串。
        logic.pairAssetId = assetId;
        logic.rate = 0;
        logic.maxParticipants = 1;
        // ⚠️ 见文件头注释1/2：maturityTime 是本文件风险最高的一处，字段是否
        // 存在、toSign() 有没有覆盖到这个条件字节，都还没有实测验证过。
        logic.maturityTime = maturityTime;
        tx.matchLogic = logic;

        tx.finalizeId();
        // 🔍 诊断日志：跟 QccTransferPage.dart 的 `LogObj.log("发起签名内容:${tx.toSign()}");`
        // 保持同样的打法。这笔交易失败到底是不是 maturityTime 签名分歧导致的，
        // 光看 Dart 代码猜不出来——把这行 toSign() 的完整字符串跟服务端实际计算出来的
        // 那份（麻烦让后端也在验签前打一行同样的日志）逐字符 diff 一下，一眼就能看出来
        // 到底差在哪一段，不用再来回猜测。
        LogObj.log("创建信托-发起签名内容:${tx.toSign()}");
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final pid = result.data?['txHash']?.toString() ?? "";
      final testator = _testatorAddress;
      final heirAddr = heir;
      final submittedAssetId = assetId;
      final submittedAmount = amount;
      final submittedMaturity = maturityTime;
      _heirController.clear();
      _amountController.clear();
      _memoController.clear();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InheritConfirmPage(
            pid: pid,
            testator: testator,
            heir: heirAddr,
            assetId: submittedAssetId,
            amountRaw: submittedAmount,
            maturityTimeMs: submittedMaturity,
          ),
        ),
      );
    } else {
      LogObj.log("创建信托提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState("本机未导入任何钱包，无法创建信托。");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 委托人地址(from)", Icons.person_outline, _buildTestatorPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("2. 继承人地址(to)", Icons.family_restroom_outlined, _buildHeirInput()),
          const SizedBox(height: 16),
          _buildSectionCard("3. 资产与本金", Icons.token_outlined, _buildAssetAmountInput()),
          const SizedBox(height: 16),
          _buildSectionCard("4. 到期时间(maturityTime)", Icons.schedule_outlined, _buildMaturityPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("5. 备注(可选)", Icons.notes_outlined, _buildMemoInput()),
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
            Icon(icon, size: 16, color: const Color(0xFFB08900)),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildTestatorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _testatorAddress.isEmpty ? null : _testatorAddress,
          isExpanded: true,
          items: _localAddrs
              .map((a) => DropdownMenuItem(value: a, child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _testatorAddress = val);
          },
          decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
        // 【需求】选择 from 地址时显示 from 余额。
        if (_testatorAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("委托人余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(_testatorAddress, _assetIdController.text.trim().isEmpty ? "QCC" : _assetIdController.text.trim(), fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeirInput() {
    return TextField(
      controller: _heirController,
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(labelText: Tools.getTra("继承人钱包地址"), border: const OutlineInputBorder()),
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: InputDecoration(
            labelText: Tools.getTra("本金数量 (${_assetIdController.text.trim().isEmpty ? 'QCC' : _assetIdController.text.trim()})"),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildMaturityPicker() {
    final bool tooSoon = _maturityDateTime.difference(DateTime.now()).inDays < 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _pickMaturityDateTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(_formatDateTime(_maturityDateTime), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(Tools.getTra("点击修改"), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ),
        if (tooSoon) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "距现在不到7天，链上默认最短提前量可能更长（测试环境常配成很短，正式环境不确定），提交可能会被拒。",
                    style: TextStyle(fontSize: 11, color: Colors.deepOrange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMemoInput() {
    return TextField(
      controller: _memoController,
      decoration: InputDecoration(labelText: Tools.getTra("备注(默认: 创建继承信托)"), border: const OutlineInputBorder()),
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
    bool active = !_isSubmitting && _testatorAddress.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Color(0xFFB08900), Color(0xFFD4A72C)]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认创建继承", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}