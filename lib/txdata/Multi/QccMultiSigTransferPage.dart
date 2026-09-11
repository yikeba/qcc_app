import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../home/QccScanner.dart';
import '../../procotol/MultiTransactionData.dart';
import '../../procotol/QccTxFlow.dart';
import '../../qccwallet/QccActiveWallet.dart';
import '../../utile/QccObj.dart';
import '../../utile/QccStorage.dart';
import '../../utile/Tools.dart';
import '../../views/myasset/QccAsset.dart';
import '../../views/myasset/QccAssetService.dart';
import '../../views/setting/AppTranslator.dart';
import '../../rule/user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../rule/user/multiple/MultiSigFileStorage.dart';
import '../../rule/user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../rule/user/multiple/QccMultiSig.dart';

/// 发起多签转账。
///
/// 本轮按你的要求重做：
/// 1. 支持选择多签地址、显示与选择资产类型——多签账户选择器 + 资产类型
///    继续复用 QccActiveWallet 自带的资产切换弹层（点击余额旁边的资产
///    标签即可切换 assetId，onAssetChanged 回调同步 _selectedAsset），
///    删掉了原来完全没被调用、并且用法本身也是错的
///    _buildAssetSelector()（重复功能，属于死代码）。同时把原来注释掉的
///    "可用余额"展示补回来（原代码调用了一个 QccActiveWallet 根本没有的
///    .buildBalanceWidget() 方法，编译不会过，所以被注释掉了）。
/// 2. 可选择多签对应的单签地址——原来的做法是"自动把 QccObj.activeWallet
///    这个全局活跃钱包换掉"，一个转账页面的选择会全局影响 App 其它地方
///    对"当前钱包"的判断，属于意外的副作用。现在改成和
///    MultiSigTokenIssueWidget.dart 同一套"提案发起人"模式：只在这个页面
///    内部记录 nowaddress，可点击切换，显示昵称+QCC余额，不再动
///    QccObj.activeWallet。
/// 3. 生成多签提案本地状态明细——原代码 `MultiSigFileStorage.saveTask(resData)`
///    是在还没解析出 innerData 之前调用的，而 resData 顶层往往没有 txHash
///    （只在 innerData['id'] 里），saveTask 内部一判空就直接跳过，根本没
///    存上；现在先解析完 innerData，再拼一份字段完整的本地记录
///    （txHash/multiAddress/assetId/amount/to/from/owners/threshold/
///    timestamp/status）传给 saveTask。
/// 4. 签名采用新版——统一改走 QccTxFlow.run()，不再用 compute +
///    QccDataProtocol.encodeTransaction（本 session 里其它页面都确认过
///    这个方法的签名逻辑被注释掉，signature 恒为空）。
///
/// 【需要你核实的一处假设】MultiTransactionData 这个类我手上没有源码，
/// 按这个项目里另外两个协议类 RuleData / QccTransactionData 的一贯设计
/// （toJson() 给传输用的完整信封，toSign() 单独给出规范化签名原文，两者
/// 彻底解耦），这里假设 MultiTransactionData 也有一个 toSign() 方法。
/// 如果实际类里没有这个方法，或者字段名/拼接方式不同，麻烦把
/// MultiTransactionData.dart 发我核对，我只需要改 buildPayload 回调里
/// `toSign: mudata.toSign()` 这一行，不影响其它部分。
class QccMultiSigTransferPage extends StatefulWidget {
  final MultiSigAccount? initialAccount;
  const QccMultiSigTransferPage({super.key, this.initialAccount});

  @override
  State<QccMultiSigTransferPage> createState() => _QccMultiSigTransferPageState();
}

class _QccMultiSigTransferPageState extends State<QccMultiSigTransferPage> {
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  List<MultiSigAccount> _accounts = [];
  MultiSigAccount? _selectedAccount;

  List<QccAsset> _assets = [];
  QccAsset? _selectedAsset;

  bool _isLoading = true;
  bool _isProcessing = false;

  // 【新增】本机在选中多签账户里持有私钥的地址（可选的提案发起人）+
  // 昵称映射 + 当前选中的发起人地址。不再需要 _canSign（用
  // nowaddress.isNotEmpty 直接判断即可）。
  List<String> _eligibleProposers = [];
  Map<String, String> _walletNames = {};
  String nowaddress = "";

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final names = await QccStorage.getAllWalletNames();
    if (mounted) setState(() => _walletNames = names);

    // 1. 获取本地多签列表
    await _loadAvailableAccounts();
    // 2. 加载关注的资产列表
    List<QccAsset> assetList = await QccAssetService().fetchAllAssets();
    if (mounted && assetList.isNotEmpty) {
      setState(() {
        _assets = assetList;
        _selectedAsset = _assets.first;
      });
    }
  }

  Future<void> _loadAvailableAccounts() async {
    final list = await MultiSigAddressStorage.getAllAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      if (widget.initialAccount != null) {
        _selectedAccount = widget.initialAccount;
      } else if (_accounts.isNotEmpty) {
        _selectedAccount = _accounts.first;
      }
      _isLoading = false;
    });

    if (_selectedAccount != null) {
      _verifyWalletOwnership(_selectedAccount!);
    }
  }

  /// 【重构】不再自动切换/弹窗确认切换全局活跃钱包，只在本页面内部算出
  /// 可选的发起人地址列表，交给用户在 _pickProposer() 里手动选。
  void _verifyWalletOwnership(MultiSigAccount account) {
    List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
    List<String> matched = localAddrs.where((a) => account.owners.contains(a)).toList();
    setState(() {
      _eligibleProposers = matched;
      if (matched.isEmpty) {
        nowaddress = "";
      } else if (matched.contains(QccObj.activeWallet?.address)) {
        nowaddress = QccObj.activeWallet!.address;
      } else {
        nowaddress = matched.first;
      }
    });
  }

  /// 【新增】提案发起人选择弹层——列出本机在该多签账户里持有私钥的全部
  /// 地址，展示昵称，选中后 _buildProposerInfo() 显示对应的 QCC 余额。
  void _pickProposer() {
    if (_eligibleProposers.length <= 1) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Trans("选择提案发起人", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _eligibleProposers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final addr = _eligibleProposers[i];
                    final bool isSelected = nowaddress == addr;
                    final String? nick = _walletNames[addr];
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(addr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onTap: () {
                        setState(() => nowaddress = addr);
                        Navigator.pop(sheetContext);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Trans("发起多签交易"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- 第一组：账户信息卡片 ---
            _buildCard(
              title: "付款信息",
              icon: Icons.account_balance_wallet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel("选择付款多签账户"),
                  _buildAccountSelector(),
                  const SizedBox(height: 16),
                  _buildLabel("选择资产类型"),
                  QccActiveWallet(
                    _selectedAccount?.multiAddress ?? "",
                    _selectedAsset?.assetId ?? "QCC",
                    fontColor: Colors.lightBlue,
                    onAssetChanged: (value) {
                      setState(() {
                        _selectedAsset = _assets.firstWhere(
                              (asset) => asset.assetId == value,
                          orElse: () => _selectedAsset ?? _assets.first,
                        );
                        LogObj.log("资产已切换为对象: ${_selectedAsset?.assetId}, 精度: ${_selectedAsset?.precision}");
                      });
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- 第二组：提案发起人 ---
            _buildCard(
              title: "提案发起人",
              icon: Icons.badge_outlined,
              child: _buildProposerInfo(),
            ),

            const SizedBox(height: 16),

            // --- 第三组：转账明细卡片 ---
            _buildCard(
              title: "转账详情",
              icon: Icons.send_rounded,
              child: Column(
                children: [
                  TextField(
                    controller: _toController,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: Tools.getTra("接收地址 (To)"),
                      prefixIcon: const Icon(Icons.call_received, size: 20),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.content_paste, size: 20),
                            onPressed: _paste,
                            tooltip: "粘贴",
                          ),
                          IconButton(
                            icon: const Icon(Icons.document_scanner_outlined, color: Colors.blue),
                            onPressed: _onAddressScan,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAmountField(),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --- 发送按钮 ---
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddressScan() async {
    String? scanResult = await QccScanner.scan(context);
    if (scanResult != null && scanResult.isNotEmpty) {
      if (scanResult.startsWith("QCC_SECURE_V2:")) {
        Tools.showToast(context, "这是备份数据，请在地址管理中使用扫码恢复");
        return;
      }
      setState(() {
        _toController.text = scanResult;
      });
      HapticFeedback.lightImpact();
    }
  }

  // 美观的卡片封装
  Widget _buildCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 32),
          child,
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool canSign = nowaddress.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: canSign && !_isProcessing
            ? const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)])
            : null,
      ),
      child: ElevatedButton(
        onPressed: (_isProcessing || !canSign) ? null : _handleInitiate,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isProcessing
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans(canSign ? "确认并签名发送" : "无签名权限"),
      ),
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: Tools.getTra("转账金额"),
            prefixIcon: const Icon(Icons.attach_money, size: 20),
            suffixText: _selectedAsset?.assetId.toUpperCase() ?? "QCC",
          ),
        ),
        const SizedBox(height: 8),
        // 【修复】原来这段是注释掉的死代码——调用了 QccActiveWallet 根本
        // 没有的 .buildBalanceWidget() 方法，编译不过。现在用正确的方式
        // （直接把 QccActiveWallet 当组件用）把"可用余额"展示补回来。
        if (_selectedAccount != null && _selectedAsset != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance, size: 12, color: Colors.green),
                const SizedBox(width: 4),
                Trans("可用余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                QccActiveWallet(
                  _selectedAccount!.multiAddress,
                  _selectedAsset!.assetId,
                  fontSize: 12.0,
                  fontColor: Colors.green,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 【重构，替代原来的 _buildSignerStatusCard】展示当前选中的提案发起
  /// 地址——支持点击切换（本机持有私钥的成员不止一个时），显示昵称 + QCC
  /// 余额，做法对齐 MultiSigTokenIssueWidget.dart 的 _buildProposerInfo()。
  Widget _buildProposerInfo() {
    if (nowaddress.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.warning_rounded, size: 18, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Trans("本机没有该多签账户任何成员的私钥，无法发起转账提案",
                  style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    String? nick = _walletNames[nowaddress];
    bool canSwitch = _eligibleProposers.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickProposer : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nowaddress, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
                ),
                if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            if (nick != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 24),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text("QCC 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  QccActiveWallet(nowaddress, "QCC", fontSize: 12, fontColor: Colors.black87),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Trans(text, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
  );

  Widget _buildAccountSelector() {
    return DropdownButtonFormField<MultiSigAccount>(
      initialValue: _selectedAccount,
      isExpanded: true,
      items: _accounts.map((acc) => DropdownMenuItem(
        value: acc,
        child: Text(acc.multiAddress, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
      )).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedAccount = val);
          _verifyWalletOwnership(val);
        }
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }

  void _paste() async {
    var data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() => _toController.text = data.text!);
    }
  }

  // 【重构】统一走 QccTxFlow.run()，不再手抄"密码->loading->还原钱包->
  // compute签名->提交->解析返回"全流程，签名也不再走已确认损坏的
  // compute + QccDataProtocol.encodeTransaction。
  Future<void> _handleInitiate() async {
    if (nowaddress.isEmpty) {
      Tools.showToast(context, "无签名权限");
      return;
    }
    if (_selectedAccount == null || _selectedAsset == null) {
      Tools.showToast(context, "参数不完整");
      return;
    }
    String toAddr = _toController.text.trim();
    String amountStr = _amountController.text.trim();
    if (toAddr.isEmpty || amountStr.isEmpty) {
      Tools.showToast(context, "请完善地址和金额");
      return;
    }

    setState(() => _isProcessing = true);

    int amount = QccAssetService().getAmountRaw(_selectedAsset!.assetId, amountStr);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        final mudata = MultiTransactionData();
        mudata.from = wallet.address;
        mudata.fromMulti = _selectedAccount!.multiAddress;
        mudata.to = toAddr;
        mudata.amount = amount;
        mudata.assetId = _selectedAsset!.assetId;
        mudata.txType = "pay";
        mudata.finalizeId();
        // 发起提案本身没有"上一个要跟随的哈希"，约定自引用（和
        // QccFollowTransactionPage.dart 里 mutxHash 指向被跟随的原始
        // 提案哈希是同一套字段，跟原逻辑保持一致）。
        mudata.mutxHash = mudata.id;
        // 【假设，见文件顶部说明】按 RuleData/QccTransactionData 的一贯
        // 设计，这里假设 MultiTransactionData 也有 toSign()。
        return QccSignPayload(toSign: mudata.toSign(), payloadJson: jsonEncode(mudata.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mutxbaseData",
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      LogObj.log("发起多签转账返回$resData");
      Map<String, dynamic> innerData = {};
      if (resData['data'] is String) {
        innerData = jsonDecode(resData['data']);
      } else {
        innerData = resData['data'] ?? {};
      }
      final String finalHash = (resData['txHash'] ?? innerData['id'] ?? '').toString();
      final String finalAssetId = innerData['assetId']?.toString() ?? _selectedAsset!.assetId;
      final String finalAmount = (innerData['amount'] ?? amount).toString();

      // 【新增，对应"生成多签提案本地状态明细"】字段齐全的本地记录，
      // 不再是原样存一份可能缺 txHash 的 resData。
      await MultiSigFileStorage.saveTask({
        'txHash': finalHash,
        'type': 'transfer',
        'multiAddress': _selectedAccount!.multiAddress,
        'assetId': finalAssetId,
        'amount': finalAmount,
        'to': innerData['to']?.toString() ?? toAddr,
        'from': result.wallet!.address,
        'owners': _selectedAccount!.owners,
        'threshold': _selectedAccount!.threshold,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'PENDING',
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MultiSigInitiatedPage(
            txHash: finalHash,
            type: MultiSigPageType.transfer,
            owners: _selectedAccount!.owners,
            threshold: _selectedAccount!.threshold,
            assetId: finalAssetId,
            amount: finalAmount,
            toAddress: toAddr,
          ),
        ),
      );
    } else {
      LogObj.log("多签转账异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }
}