import 'dart:async'; // ✅ 引入 async 以支持 TimeoutException
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../procotol/QccTxFlow.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
import '../../../procotol/QccTransactionData.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../home/QccExplorerService.dart';
import '../../setting/AppTranslator.dart';
import '../QccOpenDataManager.dart';
import 'QccWinSuccessSheet.dart';

class QccWinTransactionPage extends StatefulWidget {
  /// 可以从列表页或扫码页面传入的初始 Hash
  final String? initialHash;

  const QccWinTransactionPage({super.key, this.initialHash});

  @override
  State<QccWinTransactionPage> createState() => _QccWinTransactionPageState();
}

class _QccWinTransactionPageState extends State<QccWinTransactionPage> {
  final TextEditingController _hashController = TextEditingController();
  final TextEditingController _buyAmountController = TextEditingController();

  bool _isLoading = false;
  Map<String, dynamic>? _orderData;
  double _payEstimated = 0.0;
  String _errorMessage = "";

  // 【本次新增，对应你的要求"选择钱包地址的时候显示名称"】原来这个页面从头到
  // 尾直接用 QccObj.activeWallet!.address(还是强制解包，activeWallet 为
  // null 时会直接崩)，完全没有地址选择的能力。照 DexMatchWidget.dart 刚加过
  // 的 _fromAddress/_walletNames/地址选择弹窗套路加上，让用户可以选择用哪个
  // 本机地址去吃单，弹窗里带备注名+余额。
  String _fromAddress = "";
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      final active = QccObj.activeWallet?.address;
      _fromAddress = (active != null && wallets.any((w) => w.address == active)) ? active : wallets.first.address;
    }
    _loadWalletNames();
    if (widget.initialHash != null && widget.initialHash!.isNotEmpty) {
      _hashController.text = widget.initialHash!;
      _fetchOrderData(widget.initialHash!);
    }
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  /// 地址选择弹窗——和 DexMatchWidget.dart 里 _showAddressPicker() 同款
  /// (isScrollControlled + ConstrainedBox + Flexible，避免多地址时弹窗溢出)。
  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                const Trans("选择发送地址", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: wallets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final w = wallets[index];
                      bool isSelected = w.address == _fromAddress;
                      final String? nick = _walletNames[w.address];
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: isSelected ? Colors.blue.withOpacity(0.1) : Colors.grey[100], child: Icon(Icons.wallet, color: isSelected ? Colors.blue : Colors.grey)),
                        title: Text(nick ?? "未命名钱包", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(w.address, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet_outlined, size: 11, color: Colors.blueGrey),
                                  const SizedBox(width: 3),
                                  QccActiveWallet(w.address, "QCC", fontSize: 11, fontColor: Colors.black54),
                                ],
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                        onTap: () {
                          setState(() => _fromAddress = w.address);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 折叠状态下的地址选择条——同 DexMatchWidget.dart 的 _buildAddressSelector()。
  Widget _buildFromAddressSelector() {
    final String? nick = _walletNames[_fromAddress];
    return InkWell(
      onTap: _showAddressPicker,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wallet, size: 18, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: _fromAddress.isEmpty
                  ? const Text("请选择发送地址", style: TextStyle(fontSize: 13))
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nick ?? "未命名钱包", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue)),
                  Text(_fromAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  // ✅ 核心优化：合并 opentx 和 openhash 实时数据
  Future<void> _fetchOrderData(String hash) async {
    if (hash.trim().isEmpty) {
      Tools.showToast(context, "请输入交易哈希");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _orderData = null; // 清空旧数据
    });

    try {
      // 1. 获取静态交易数据 (opentx)
      final txResponse = await http.get(Uri.parse(QccExplorerService.baseUrl+"/v1/opentx/${hash.trim()}")).timeout(const Duration(seconds: 3));

      if (txResponse.statusCode != 200) {
        throw Exception("节点网络异常");
      }

      final resJson = jsonDecode(txResponse.body);
      if (resJson['ok'] != true || resJson['data'] == null) {
        throw Exception("未找到有效的 Open 交易信息");
      }

      final Map<String, dynamic> txData = jsonDecode(resJson['data']);

      // 2. ✅ 获取动态状态机数据 (openhash)，确认订单死活和最新余额
      try {
        final stateRes = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/openhash/${hash.trim()}")).timeout(const Duration(seconds: 3));
        if (stateRes.statusCode == 200) {
          Map stateResJson = jsonDecode(stateRes.body);
          LogObj.log("领取分红hash 返回数据: $stateResJson");
          if (stateResJson.isEmpty) {
            throw Exception("该订单已交易结束或被撤销");
          }
          if (stateResJson['ok'] != true || stateResJson['data'] == null) {
            throw Exception("该订单已交易结束或被撤销");
          }

          final stateData = jsonDecode(stateResJson['data']);
          double currentAmt = (stateData['currentAmount'] as num?)?.toDouble() ?? 0.0;

          // 拦截失效订单
          if (stateData['state'] != 'ACTIVE' || stateData['isExpired'] == true || currentAmt <= 0) {
            throw Exception("该订单已失效或已被抢光");
          }

          // 将最新的金额和剩余份数覆盖到 UI 数据中
          txData['amount'] = currentAmt;
          if (stateData['remainingParts'] != null && txData['matchLogic'] != null) {
            txData['matchLogic']['remainingAmount'] = stateData['remainingParts'];
          }
        }
      } on TimeoutException catch (_) {
        throw Exception("查询订单实时状态超时，请稍后再试");
      }

      // 3. 赋值更新 UI
      setState(() {
        _orderData = txData;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
      LogObj.log("获取交易详情异常: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Trans("对价Hash去中心化交易"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHashInputArea(),
              const SizedBox(height: 20),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_errorMessage.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),

              if (_orderData != null && !_isLoading)
                _buildOrderDetailsPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHashInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
      ),
      child: TextField(
        controller: _hashController,
        decoration: InputDecoration(
          hintText: "输入 Open 交易 Hash...",
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.blueGrey),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
            onPressed: () => _fetchOrderData(_hashController.text),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onSubmitted: _fetchOrderData,
      ),
    );
  }

  Widget _buildOrderDetailsPanel() {
    final logic = _orderData!['matchLogic'];
    final String rule = logic['rule'] ?? 'unknown';
    final String sellAsset = _orderData!['assetId'];
    final String buyAsset = logic['pairAssetId'] ?? "USDS";
    final double rate = (logic['rate'] as num?)?.toDouble() ?? 0.0;

    double amount = QccAssetService().getHumanAmountNum(sellAsset, _orderData!['amount']);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(rule, sellAsset, amount),
          const Divider(height: 30),
          _buildMakerRow(_orderData!['from']?.toString() ?? ""),
          _rowInfo("订单备注", _orderData!['memo'] ?? "无"),
          if (rule == 'dex' || rule == 'exchange')
            _rowInfo("设定汇率", "1 $sellAsset = $rate $buyAsset", valueColor: Colors.blue),

          const SizedBox(height: 24),

          _buildActionForm(rule, sellAsset, buyAsset, rate, logic),

          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () => _handleConfirmWin(rule, buyAsset, rate),
              child: const Trans("签名广播交易", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String rule, String asset, double amount) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: const Icon(Icons.handshake, color: Colors.blue),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("获取 $amount $asset", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text("交易模型: ${rule.toUpperCase()}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionForm(String rule, String sellAsset, String buyAsset, double rate, Map logic) {
    double maxAmount = QccAssetService().getHumanAmountNum(sellAsset, _orderData!['amount']);

    if (rule == 'dex' || rule == 'exchange') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QccActiveWallet.onlyStables(_fromAddress, buyAsset),
          const SizedBox(height: 10),
          const Trans("当前钱包地址:"),
          const SizedBox(height: 5),
          // 【本次改造，对应你的要求"选择钱包地址的时候显示名称"】原来是一行
          // 纯文本、不能换、也不显示名称——现在换成 DexMatchWidget.dart 同款
          // 的可点击选择条，显示备注名(没有则"未命名钱包")，点击弹出
          // _showAddressPicker()。
          _buildFromAddressSelector(),
          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Trans("输入交易数量", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("最大可获取: $maxAmount $sellAsset", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _buyAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: "请输入数量...",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blue)),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sellAsset, style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        backgroundColor: Colors.blue.withOpacity(0.1),
                      ),
                      onPressed: () {
                        // 【本次修正，同一个精度问题】原来这里只截到 4 位小数——
                        // 点"全部"时 _payEstimated 是按截断前的完整 maxAmount
                        // 算的，但提交时 _handleConfirmWin() 是重新从这个文本框
                        // 解析 buyQty，两边就对不上了(尤其 QCC 是 9 位精度资产，
                        // 4 位小数会截掉后面 5 位)。改成和 DexMatchWidget.dart
                        // 同一套 8 位小数的写法，把截断误差降到可忽略范围，并让
                        // 文本框里的值和 _payEstimated 的计算来源保持一致。
                        _buyAmountController.text = maxAmount.toStringAsFixed(8);
                        setState(() => _payEstimated = maxAmount * rate);
                      },
                      child: const Trans("全部", style: TextStyle(color: Colors.blue, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
            onChanged: (v) {
              double val = double.tryParse(v) ?? 0;
              setState(() => _payEstimated = val * rate);
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Trans("预估需支付:"),
                // 【本次修正，同一个精度问题】_payEstimated 是 double 乘法结果，
                // 直接用字符串插值会把二进制浮点噪声也显示出来(比如
                // "12.340000000000002")，改成和签名那里一致的 8 位定点格式。
                Text("${_payEstimated.toStringAsFixed(8)} $buyAsset", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800, fontSize: 16)),
              ],
            ),
          ),
        ],
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            _rowInfo("最大参与份数", "${logic['maxParticipants'] ?? 0} 份"),
            const SizedBox(height: 8),
            _rowInfo("剩余可用名额", "${logic['remainingAmount'] ?? 0} 份", valueColor: Colors.green),
          ],
        ),
      );
    }
  }

  Widget _rowInfo(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: valueColor ?? Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// 【本次新增，对应你的要求"交易记录对应显示名称（如对手地址没有名称无需
  /// 显示）"】发起人(Maker)是对手方地址——本机通讯录里查到备注名就在地址上方
  /// 加一行名称，查不到就什么都不加、只显示原来的地址(不像地址选择弹窗那样
  /// 退回显示"未命名钱包"占位文字，这里按你的原话"无需显示"处理)。
  Widget _buildMakerRow(String address) {
    final String? nick = _walletNames[address];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Trans("发起人 (Maker)", style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (nick != null) Text(nick, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text(
                  address,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 执行 Win 交易构建与签名
  Future<void> _handleConfirmWin(String rule, String buyAssetId, double rate) async {
    if (_orderData == null) return;

    double buyQty = double.tryParse(_buyAmountController.text) ?? 0;
    String sellAsset = _orderData!['assetId'];
    final String openHash = _orderData!['id'];

    if (widget.initialHash != null && widget.initialHash!.isNotEmpty) {
      if (openHash != widget.initialHash) {
        Tools.showToast(context, "请检查交易hash错误");
        return;
      }
    }
    LogObj.log("执行win hash:$openHash");
    if (_fromAddress == _orderData!['from']) {
      Tools.showToast(context, "现货交易地址和购买地址不能一致");
      return;
    }

    // 基础本地校验
    if (rule == 'dex' || rule == 'exchange') {
      if (buyQty <= 0) {
        Tools.showToast(context, "请输入有效的买入数量");
        return;
      }
      double localMax = QccAssetService().getHumanAmountNum(sellAsset, _orderData!['amount']);
      if (buyQty > localMax) {
        Tools.showToast(context, "交易数量不能超过挂单当前剩余量");
        return;
      }
    }

    // =======================================================
    // ✅ 核心优化：防踩坑 Pre-Check！下单前进行最后一次探针核对
    // =======================================================
    try {
      final stateRes = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/openhash/$openHash")).timeout(const Duration(seconds: 2));
      if (stateRes.statusCode == 200) {
        final stateResJson = jsonDecode(stateRes.body);
        if (stateResJson['ok'] != true || stateResJson['data'] == null) {
          Tools.showToast(context, "下手慢了！该订单已经交易结束");
          setState(() => _orderData = null); // 清空失效数据
          return;
        }

        final stateData = jsonDecode(stateResJson['data']);
        double realCurrentAmt = (stateData['currentAmount'] as num?)?.toDouble() ?? 0.0;

        if (stateData['state'] != 'ACTIVE' || stateData['isExpired'] == true || realCurrentAmt <= 0) {
          Tools.showToast(context, "该订单已失效，无法继续交易");
          setState(() => _orderData = null);
          return;
        }

        // 核实抢单期间，余额是否被别人买走了一部分
        double realMaxAmount = QccAssetService().getHumanAmountNum(sellAsset, realCurrentAmt);
        if (buyQty > realMaxAmount) {
          Tools.showToast(context, "余量不足！当前仅剩: $realMaxAmount $sellAsset，请修改数量");
          // 自动同步页面上显示的最新数量
          setState(() => _orderData!['amount'] = realCurrentAmt);
          return;
        }
      }
    } on TimeoutException catch (_) {
      Tools.showToast(context, "核对订单实时状态超时，请稍后重试");
      return;
    } catch (e) {
      Tools.showToast(context, "状态核对异常");
      return;
    }

    // 通过了严苛的 Pre-Check，正式呼出密码框——密码框/loading 顺序、
    // try/catch 兜底现在都交给 QccTxFlow.run() 统一处理。
    // buildPayload 里构建好的 tx 需要在成功之后存本地成交记录，先在外层
    // 声明闭包变量接住(和 DexMatchWidget.dart 里 builtTx 用法一致)。
    QccTransactionData? builtTx;

    final result = await QccTxFlow.run(
      context: context,
      address: _fromAddress,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = buyAssetId;
        tx.from = wallet.address;
        tx.to = _orderData!['from']?.toString() ?? "";
        tx.amount = QccAssetService().getAmountRaw(buyAssetId, _payEstimated.toStringAsFixed(8));
        tx.txType = "win";
        tx.matcHash = openHash;
        tx.chain = "6666";
        tx.memo="";
        tx.finalizeId();
        builtTx = tx;
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      // 原来写死 https://tx.qccio.com，统一走 baseUrl
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    LogObj.log("现货win交易数据返回：${result.data}");
    if (result.cancelled) return;

    final String? winTxHash = _acceptedTxHash(result);
    if (winTxHash != null && builtTx != null) {
      final Map<String, dynamic> resJson = Map<String, dynamic>.from(result.data ?? {});
      final tx = builtTx!;

      // 🐛 本地扣减必须与盘口缓存同单位：缓存里是 openhash 的 currentAmount
      // （挂单锁定资产 sellAsset 的链上最小单位），原来传的是界面数量 buyQty，
      // QCC 下差了 10^9 倍，扣减几乎不生效。
      // 释放时机跟随这笔 Win 自己的链上结果，不再固定 10 秒。
      final double deductRaw =
      QccAssetService().getAmountRaw(sellAsset, buyQty.toStringAsFixed(8)).toDouble();
      QccOpenDataManager.addLocalDeduction(openHash, deductRaw, winTxHash: winTxHash);
      // ✅ 核心：构建 Win 订单快照并保存
      final winOrderSnapshot = {
        'id': tx.id, // 这笔 Win 交易的 Hash
        'matcHash': openHash, // 碰撞的 Open Hash
        'assetId': buyAssetId, // 支付的资产
        'targetAssetId': sellAsset, // 获得的资产
        'amount': tx.amount.toString(), // 支付的原始数量
        'humanAmount': _payEstimated.toStringAsFixed(8), // 支付的人读数量（和签名用的定点字符串保持一致，避免浮点噪声存进本地记录）
        'obtainedAmount': buyQty.toString(), // 获得的资产数量
        'rate': rate,
        'from': tx.from,
        'to': _orderData!['from'], // 挂单发起人
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'localStatus': 'pending', // 初始状态为等待上链
        'memo': _orderData!['memo'] ?? "DEX Trade",
      };

      await QccStorage.addWinOrder(tx.from!, winOrderSnapshot);
      LogObj.log("✅ Win 订单已保存至本地历史");
      if (!mounted) return;

      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: winTxHash,
          confirmedTitle: "成交已上链",
          details: [
            Text("获得：${buyQty.toStringAsFixed(8)} $sellAsset", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("支付：${_payEstimated.toStringAsFixed(8)} $buyAssetId", style: const TextStyle(fontSize: 12)),
            Text("对手挂单：${openHash.length > 12 ? '${openHash.substring(0, 6)}...${openHash.substring(openHash.length - 6)}' : openHash}",
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
          ],
          footer: "上链前资产尚未完成交割；若上链失败，本次支付不会扣除。",
        ),
      );
      if (!mounted) return;

      if (st?.state == TxChainState.confirmed) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          backgroundColor: Colors.transparent,
          builder: (_) => QccWinSuccessSheet(responseData: {
            ...resJson,
            'txHash': winTxHash,
            'data': jsonEncode(tx.toJson()), // 新响应不含 data，用本地交易补上
            'chainStatus': 'confirmed',
          }),
        );
        _fetchOrderData(openHash); // 刷新挂单剩余量
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "成交上链失败：${st!.message ?? '未知原因'}，本次支付未扣除");
        _fetchOrderData(openHash);
      } else {
        Tools.showToast(context, "成交已受理，尚未确认上链，请稍后在「我的交易」中查看");
      }
    } else {
      LogObj.log("Win 交易出错: ${result.error}");
      Tools.showToast(context, "操作失败: ${result.error}");
    }
  }

  /// 同 DexMatchWidget._acceptedTxHash：以 code 为准兜底判断受理。
  static String? _acceptedTxHash(dynamic result) {
    final Map? d = result.data is Map ? result.data as Map : null;
    if (d == null) return null;
    final code = (d['code'] ?? d['status'] ?? '').toString().toUpperCase();
    final h = d['txHash']?.toString() ?? '';
    if ((result.success == true || code == 'ACCEPTED') && h.isNotEmpty) return h;
    return null;
  }
}