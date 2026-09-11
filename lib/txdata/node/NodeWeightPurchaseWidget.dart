import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/procotol/QccMatchLogic.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/qccwallet/AddressTool.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart' as server;
import 'package:qcc_flutter/home/QccScanner.dart';

/// 节点权重购买 —— 对应 TxNodeWeightTest.java：txType=open，matchLogic.rule=nodeweight。
///
/// 【协议要点，按 Java 测试文件核对】
/// 1. assetId 必须是 "QCC"（测试里 1d 专门验证 pairAssetId 为空会被拒），跟 Loan/Inherit
///    不同——那两个 assetId 是自由输入框，这里直接写死显示 "QCC"，不给用户改的入口，
///    避免提交一笔注定被拒的交易。
/// 2. tx.to = 被加权的节点地址，工厂对 nodeweight 注册了 usesTo=true，路由进 borrower 字段。
///    Java 测试原文明确"不做存在性校验，形成状态即可"——所以这里的地址校验只做**格式**
///    校验（AddressTool.isValidTransferAddress，跟 QccTransferPage.dart 收款地址用的是
///    同一个方法），不去校验这个地址是不是真的一个"节点"，格式对的普通地址一样能提交。
/// 3. matchLogic: pairAssetId=assetId("QCC")、rate=0、maxParticipants=1、remainingAmount=0、
///    maturityTime 不设置(默认0，nodeweight 不使用)。maturityTime 只有 rule=="inherit" 时
///    才会进签名串(参见继承那次踩过的坑)，nodeweight 这里恒为0、不受影响，不用担心同样的
///    签名问题。
/// 4. 最低购买 1 QCC（Java 测试 1a 专门验证 0.5 QCC 会被拒）——这里做了客户端预检查，
///    但最终以服务端校验为准，这只是提前拦一下明显会失败的提交，省一次网络往返。
/// 5. 【重要，务必在 UI 上让用户看清楚】这笔交易不可撤销、不可退款——Java 测试阶段5
///    专门验证了 cancel 一定被拒且不退款("NodeWeightProcess.onCancel() 一律拒绝，钱在
///    创建时就分出去了，退无可退")。提交按钮前加了一个二次确认弹窗，不能省。
///
/// 【本次范围，按你的要求】只做购买表单本身：1) from 地址选择+标记名称+余额；
/// 2) to 地址(节点地址) 自由粘贴+格式校验+多签地址配置入口。没有做"购买记录"查询页——
/// Java 测试文件自己说得很清楚"没有对外查询接口"，做了也是空中楼阁，等你后面有需要
/// 且服务端提供了查询接口再说。
///
/// ⚠️⚠️ 唯一没有实现的部分：「支持多签地址配置」——我在这个项目里只看到过
/// MultiSigTransferHubPage.dart 这个入口（在 QccTxManagerPage.dart 的"多签转账"里），
/// 没拿到过它内部到底怎么存储/列出多签地址（类名、方法名都不确定），瞎猜一个 API 名字
/// 大概率编译不过。下面 `_pickMultiSigAddress()` 先占好位置、按钮和交互逻辑都写好了，
/// 就等你把实际的多签地址列表接口（或者 MultiSigTransferHubPage.dart 源码）发我，
/// 一行函数体就能接上，不用改其它任何地方。
class NodeWeightPurchaseWidget extends StatefulWidget {
  const NodeWeightPurchaseWidget({super.key});

  @override
  State<NodeWeightPurchaseWidget> createState() => _NodeWeightPurchaseWidgetState();
}

class _NodeWeightPurchaseWidgetState extends State<NodeWeightPurchaseWidget> {
  static const String _assetId = "QCC"; // 协议写死，不给自由输入
  static const int _minAmountRaw = 1000000000; // 1 QCC，precision=9

  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _buyerAddress = "";

  final _nodeAddressController = TextEditingController();
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
        _buyerAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
  }

  Future<void> _onScanNodeAddress() async {
    String? scanResult = await QccScanner.scan(context);
    if (scanResult != null && scanResult.isNotEmpty) {
      if (scanResult.startsWith("QCC_SECURE_V2:")) {
        Tools.showToast(context, "这是备份数据，不是节点地址");
        return;
      }
      setState(() => _nodeAddressController.text = scanResult);
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _onPasteNodeAddress() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      Tools.showToast(context, "剪贴板为空");
      return;
    }
    setState(() => _nodeAddressController.text = text);
  }

  /// ⚠️ 待接入，见文件头说明——多签地址列表的实际接口还没拿到，先占位。
  Future<void> _pickMultiSigAddress() async {
    Tools.showToast(context, "多签地址选择功能待接入：需要提供多签地址列表接口");
    // TODO: 拿到实际接口后，改成类似下面这样，把选中结果写回 _nodeAddressController：
    // final picked = await Navigator.push<String>(context, MaterialPageRoute(
    //   builder: (_) => MultiSigAddressPickerPage(),
    // ));
    // if (picked != null && picked.isNotEmpty) {
    //   setState(() => _nodeAddressController.text = picked);
    // }
  }

  Future<void> _handleSubmit() async {
    if (_buyerAddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择购买地址"));
      return;
    }
    final nodeAddress = _nodeAddressController.text.trim();
    if (nodeAddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请输入节点地址"));
      return;
    }
    if (!AddressTool.isValidTransferAddress(nodeAddress)) {
      Tools.showToast(context, Tools.getTra("节点地址格式不正确"));
      return;
    }
    if (nodeAddress == _buyerAddress) {
      Tools.showToast(context, Tools.getTra("节点地址不能和购买地址相同"));
      return;
    }
    final amount = server.QccAssetService().getAmountRaw(_assetId, _amountController.text.trim());
    if (amount < _minAmountRaw) {
      Tools.showToast(context, Tools.getTra("最低购买 1 QCC"));
      return;
    }

    final confirmed = await _showConfirmDialog(nodeAddress, amount);
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: _buyerAddress,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = _assetId;
        tx.chain = "6666"; // 照既有几个交易 widget 硬编码，不擅自改
        tx.from = wallet.address;
        tx.to = nodeAddress; // ✅ 被加权的节点地址
        tx.amount = amount;
        tx.txType = "open";
        tx.memo = _memoController.text.trim().isEmpty ? "节点权重购买" : _memoController.text.trim();

        final logic = QccMatchLogic();
        logic.rule = "nodeweight";
        logic.pairAssetId = _assetId; // 按实际跑通代码：等于 assetId，不是空字符串
        logic.rate = 0;
        logic.maxParticipants = 1;
        // maturityTime 不设置，默认0——nodeweight 不使用，也不会进签名串。
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
      final pid = result.data?['txHash']?.toString() ?? "";
      _showSuccessDialog(pid);
      _nodeAddressController.clear();
      _amountController.clear();
      _memoController.clear();
    } else {
      LogObj.log("节点权重购买提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  Future<bool?> _showConfirmDialog(String nodeAddress, int amountRaw) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 22),
            SizedBox(width: 8),
            Text("请确认，不可撤销"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("购买金额: ${_formatAmount(amountRaw)} QCC", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text("节点地址: $nodeAddress", style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text(
              "权重购买提交后立即分账（不进入你或对方账户，直接分给利息池/系统），没有领取、没有取消、没有到期——买了就是买了，不能撤销、不能退款。",
              style: TextStyle(fontSize: 12, color: Colors.deepOrange),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("取消")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("确认购买")),
        ],
      ),
    );
  }

  void _showSuccessDialog(String pid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("购买已提交"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("这个 pid 是本次购买的交易凭证（没有查询/核销入口，留档即可）：", style: TextStyle(fontSize: 12)),
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

  // 假设 precision=9，跟本项目其它交易(质押/借贷/继承)统一的换算规则一致。
  String _formatAmount(int raw) {
    String s = (raw / 1000000000).toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState("本机未导入任何钱包，无法购买节点权重。");
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard("1. 购买地址(from)", Icons.person_outline, _buildBuyerPicker()),
          const SizedBox(height: 16),
          _buildSectionCard("2. 节点地址(to)", Icons.dns_outlined, _buildNodeAddressInput()),
          const SizedBox(height: 16),
          _buildSectionCard("3. 购买金额 (QCC)", Icons.token_outlined, _buildAmountInput()),
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
            Icon(icon, size: 16, color: const Color(0xFFBE123C)),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildBuyerPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _buyerAddress.isEmpty ? null : _buyerAddress,
          isExpanded: true,
          items: _localAddrs
              .map((a) => DropdownMenuItem(
                  value: a,
                  child: Text(_walletNames[a] != null ? "${_walletNames[a]} ($a)" : a,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _buyerAddress = val);
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        // 【需求】选择 from 地址时显示标记名称(上面下拉里已经带了)+余额。
        if (_buyerAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("可用余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(_buyerAddress, _assetId, fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNodeAddressInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nodeAddressController,
          maxLines: 2,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: Tools.getTra("粘贴或扫描节点钱包地址"),
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: "粘贴",
                  icon: const Icon(Icons.paste_outlined, size: 18),
                  onPressed: _onPasteNodeAddress,
                ),
                IconButton(
                  tooltip: "扫码",
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  onPressed: _onScanNodeAddress,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ⚠️ 多签地址配置入口，见文件头说明——实际存储/列表接口未确认，先占位可点但只弹提示。
        OutlinedButton.icon(
          onPressed: _pickMultiSigAddress,
          icon: const Icon(Icons.groups_2_outlined, size: 16),
          label: Text(Tools.getTra("从多签地址配置选择"), style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 38),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "节点地址不做存在性校验，只要格式正确就能提交——买给不存在的地址权重照样生效但永远不会被消费。",
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    return Column(
      children: [
        Row(
          children: [
            Text(_assetId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
            const SizedBox(width: 6),
            Text("（协议写死，购买资产固定为 QCC）", style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: const InputDecoration(labelText: "购买金额 (最低 1 QCC)", border: OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _buildMemoInput() {
    return TextField(
      controller: _memoController,
      decoration: InputDecoration(labelText: Tools.getTra("备注(默认: 节点权重购买)"), border: const OutlineInputBorder()),
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
    bool active = !_isSubmitting && _buyerAddress.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? const LinearGradient(colors: [Color(0xFFBE123C), Color(0xFFE11D48)]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认购买权重", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
