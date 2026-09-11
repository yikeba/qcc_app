import 'dart:async';
import 'dart:convert';
import 'dart:developer' as LogObj;
import 'package:flutter/material.dart';

// 【本次修正，对应你的要求"1.修改签名方式按照新方案"】原来这里手写
// compute(_signTransactionTask,...) -> QccDataProtocol.encodeTransaction()——
// encodeTransaction() 内部真正的签名调用整段被注释掉了，固定 return
// signature:""，之前这个页面提交的挂单交易签名字段自始至终是空字符串。
// 现在改用 QccTxFlow.run()，内部走 SignUtil.instance.signAndEncode()，和
// TxMatchDexTest.java 里 sendTx() 的做法完全对应：单独用 WalletSigner.sign()
// 对 toSign() 签名，再覆盖 encodeData() 生成的空签名。
import '../../../procotol/QccTxFlow.dart';
import '../../../procotol/QccTransactionData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';
import '../util/DexUtil.dart' as DexUtil;
import '../../../procotol/QccMatchLogic.dart';
import '../QccOpenDataManager.dart';
import 'QccTxSuccessWidget.dart';


class DexMatchWidget extends StatefulWidget {
  const DexMatchWidget({super.key});

  @override
  State<DexMatchWidget> createState() => _QccCreateMatchWidgetState();
}

class _QccCreateMatchWidgetState extends State<DexMatchWidget> {
  String _fromAddress = "";

  // 【本次新增，对应你的要求"3.地址选择地方需要增加名称显示"】本机钱包备注名，
  // 和其它已经做过地址选择的页面(MultiSigStableCoinIssueWidget.dart 等)同款
  // 用法——地址列表本身还是 QccObj.readWallets()，这里只是额外查一份地址->
  // 备注名的映射，用于选择弹窗里展示。
  Map<String, String> _walletNames = {};

  // ✅ 交易方向，默认为买入
  DexUtil.TradeDirection _direction = DexUtil.TradeDirection.buy;

  // ✅ 核心资产对 (Trading Pair)
  String _baseAssetId = "QCC";   // 标的资产 (想要交易的币，如 QCC)
  String _quoteAssetId = "USDS";  // 计价资产 (用来支付的稳定币，如 USDS)

  final TextEditingController _amountController = TextEditingController(); // 数量
  final TextEditingController _rateController = TextEditingController();   // 价格
  final TextEditingController _countController = TextEditingController();  // 拆单份数
  final TextEditingController _noteController = TextEditingController();   // 备注

  double _estimatedTotal = 0.0; // 预估总额 (Price * Amount)

  // ✅ 3. 声明一个后台轮询定时器
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      _fromAddress = wallets[0].address;
    }
    _countController.text = "10"; // 默认允许拆分为 10 笔成交
    // ✅ 4. 启动 8 秒定时轮询，静默刷新后台数据
    _startBackgroundPolling();
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  // ✅ 启动后台静默轮询的方法
  void _startBackgroundPolling() {
    // 首次进入时先立刻拉取一次
    //QccOpenDataManager.syncFromNetwork();
    // 然每隔 8 秒循环拉取
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      LogObj.log("⏰ 触发 8 秒定时轮询: 同步后台盘口数据...");
      QccOpenDataManager.syncFromNetwork();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _amountController.dispose();
    _rateController.dispose();
    _countController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // 动态计算预估总额
  void _updateTotal() {
    double price = double.tryParse(_rateController.text) ?? 0.0;
    double amount = double.tryParse(_amountController.text) ?? 0.0;
    setState(() {
      _estimatedTotal = price * amount;
    });
  }

  /// 地址选择器。【本次重写，对应你的要求"3.地址选择地方需要增加名称显示"】
  /// 原来每一行只显示地址本身，现在加上备注名(_walletNames[address])——没有
  /// 备注名时退回显示"未命名钱包"，不留空白；顺手也加了每个地址的 QCC 余额，
  /// 和这个页面其它地方(QccActiveWallet.onlyCoins/onlyStables)、以及本 session
  /// 其它已经做过地址选择的页面(MultiSigStableCoinIssueWidget.dart 的
  /// _pickProposer() 等)保持同一个视觉套路。
  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // 【本次修正，修复你反馈的 RenderFlex overflow】原来没设
      // isScrollControlled:true 时，底部弹窗被系统限制在一个偏小的固定高度
      // 内，而里面的 Column 本身不会滚动——加了备注名+余额之后每一行变高，
      // 弹窗内容总高度一超过那个固定高度就会溢出。isScrollControlled:true
      // 让弹窗高度可以按内容动态变化(不再是那个偏小的固定比例)，下面再用
      // ConstrainedBox 兜底一个最大高度、并把列表包一层 Flexible，钱包数量
      // 多到仍然超过屏幕时就走列表内部滚动，而不是让 Column 溢出。
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
                        leading: CircleAvatar(backgroundColor: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.grey[100], child: Icon(Icons.wallet, color: isSelected ? Colors.blue : Colors.grey)),
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
      appBar: AppBar(title: const Trans("现货挂单交易"), centerTitle: true),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              // 1. 买卖切换器
              _buildDirectionToggle(),

              // 2. 基础配置：交易账户与资产对
              _buildSectionCard(
                title: "交易对配置",
                child: Column(
                  children: [
                    _buildAddressSelector(),
                    const SizedBox(height: 10),
                    // 交易对配置 (Base / Quote)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Trans("标的资产 (Base)"),
                        QccActiveWallet.onlyCoins(
                            _fromAddress,
                            _baseAssetId,
                            color: Colors.blueGrey,
                            onAssetChanged: (v) => setState(() {
                              _baseAssetId = v;
                              _updateTotal(); // 切换资产时刷新后缀
                            })
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
                            onAssetChanged: (v) => setState(() {
                              _quoteAssetId = v;
                              _updateTotal(); // 切换资产时刷新后缀
                            })
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 3. 交易参数
              _buildSectionCard(
                title: "订单参数",
                child: Column(
                  children: [
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
                    const SizedBox(height: 8),

                    // ✅ 恢复：最大拆单数输入框
                    TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      decoration: _inputStyle("最大拆单数", "允许被吃单的最大笔数 (如: 10)", Icons.format_list_numbered),
                    ),
                    const SizedBox(height: 10),
                    // 动态计算总额展示
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Trans(_direction == DexUtil.TradeDirection.buy ? "预计支付总额:" : "预计获得总额:", style: const TextStyle(color: Colors.blueGrey)),
                          Text("${_estimatedTotal.toStringAsFixed(2)} $_quoteAssetId", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
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
    // 【本次新增，对应你的要求"3.地址选择地方需要增加名称显示"】折叠状态下也
    // 带上备注名，不用非得点开底部弹窗才能看到是哪个钱包。
    final String? nick = _walletNames[_fromAddress];
    return InkWell(
      onTap: _showAddressPicker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wallet, size: 20, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: _fromAddress.isEmpty
                  ? const Text("请选择发送地址", style: TextStyle(fontSize: 13))
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (nick != null) Text(nick, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue)),
                  Text(_fromAddress, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool isBuy = _direction == DexUtil.TradeDirection.buy;
    Color btnColor = isBuy ? Colors.green : Colors.redAccent;

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
            Trans(isBuy ? "确认买入" : "确认卖出", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ✅ 核心逻辑：纯粹的 DEX 上链计算
  Future<void> _handleOpenSubmit() async {
    if (_fromAddress.isEmpty) { Tools.showToast(context, "请选择发送地址"); return; }
    if (_baseAssetId == _quoteAssetId) { Tools.showToast(context, "标的资产不能与计价资产相同"); return; }

    double qty = double.tryParse(_amountController.text) ?? 0;
    if (qty <= 0) { Tools.showToast(context, "请输入有效交易数量"); return; }

    double price = double.tryParse(_rateController.text) ?? 0;
    if (price <= 0) { Tools.showToast(context, "必须设置有效价格"); return; }


    // 确定最终的底层锁仓逻辑
    String finalLockedAssetId;
    String finalTargetAssetId;
    String finalAmountStr;
    double finalRate;

    if (_direction == DexUtil.TradeDirection.sell) {
      // 🔴 卖单 (Sell): 锁定 Base，换回 Quote
      finalLockedAssetId = _baseAssetId;
      finalTargetAssetId = _quoteAssetId;
      finalAmountStr = qty.toStringAsFixed(8); // 锁定数量 = 用户输入的 Base 数量
      finalRate = price;// 链上汇率 = 价格 (1 Base 换多少 Quote)
      // ── 汇率精度校验 ──────────────────────────────────────────
      // 卖单：rate = price，锁定 base，精度对齐 quote 资产
      // 买单：rate = 1/price，锁定 quote，精度对齐 base 资产
      final rateError = _direction == DexUtil.TradeDirection.sell
          ? validateRatePrecision(price,2 )
          : validateRatePrecision(1.0 / price, 9);

      if (rateError != null) {
        Tools.showToast(context, rateError);
        return;
      }


    } else {
      // 🟢 买单 (Buy): 锁定 Quote，换回 Base
      finalLockedAssetId = _quoteAssetId;
      finalTargetAssetId = _baseAssetId;
      // 锁定数量 = 用户输入的 Base 数量 * 价格 (预估总额)
      finalAmountStr = _estimatedTotal.toStringAsFixed(8);
      // 链上汇率 = 倒数 (1 Quote 换多少 Base)
      finalRate = 1.0 / price;
    }

    // buildPayload 回调里构建好的 tx 需要在成功之后存本地挂单记录
    // (QccStorage.saveDexOrder)，这里先在外层声明闭包变量接住它——和
    // MultiSigStableCoinIssueWidget.dart 里 finalizedRuleId 的用法一个道理。
    QccTransactionData? builtTx;

    // 【本次修正，对应你的要求"1.修改签名方式按照新方案"】原来这里是手写
    // 密码框->QccLoading.show()->QccStorage.restoreWallet()->
    // compute(_signTransactionTask,...)->http.post 一整套，和本 session 其它
    // 页面改之前是同一个 bug 模式：encodeTransaction() 内部签名被注释掉，
    // packet.signature 恒为空字符串。现在统一走 QccTxFlow.run()。
    final result = await QccTxFlow.run(
      context: context,
      address: _fromAddress,
      buildPayload: (wallet) async {
        // 构造 Transaction Data
        final tx = QccTransactionData();
        tx.assetId = finalLockedAssetId;
        tx.from = _fromAddress;
        tx.to = "DEX_POOL_${DateTime.now().millisecondsSinceEpoch}";
        tx.amount = QccAssetService().getAmountRaw(finalLockedAssetId, finalAmountStr);
        tx.txType = "open";
        tx.memo = _noteController.text;
        // 【本次修正，对应你的要求"2.对比java优化"里发现的问题】原来这里完全
        // 没有设置 tx.chain——对照 TxMatchDexTest.java 逐字段核对后发现的真实
        // bug：Java 每一笔 TransactionData(openTx/winTx/topUp tx) 都显式执行
        // `tx.chain = tx.getChain();`，而 chain 会参与 toSign()/getPayloadForHash()
        // 签名计算，留空等于用空字符串去签名、也会把 chain:null 发给服务端，
        // 大概率被服务端按"链ID不匹配/缺失"直接拒绝。这里补上，取值按本
        // session 其它已验证页面(QccTransferPage.dart / LoanIssueWidget.dart
        // 等)统一硬编码的 "6666"，不要在这里自行改成别的值。
        tx.chain = "6666";
        // ✅ DEX 模式的底层 MatchLogic 组装
        tx.matchLogic = QccMatchLogic(
          rule: "dex", // 固定为 dex 模式
          maxParticipants: int.tryParse(_countController.text) ?? 1, // 读取用户输入
          rate: finalRate, remainingAmount: 0,
        );
        tx.matchLogic!.pairAssetId = finalTargetAssetId; // 设置目标对价资产
        tx.finalizeId();
        builtTx = tx;
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/txm",
    );

    if (!mounted) return;

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      LogObj.log("返回dex交易内容：$resData");
      if (builtTx != null) {
        await QccStorage.saveDexOrder(_fromAddress, builtTx!.toJson()); //保存我的挂单交易单
      }
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => QccTxSuccessWidget(response: resData),
      );
      if (mounted) Navigator.pop(context);
    } else {
      LogObj.log("dex挂单异常: ${result.error}");
      Tools.showToast(context, "操作失败: ${result.error}");
    }
  }


  /// 校验 rate 的小数位数是否超过资产精度
  /// 等价于 Java 的 BigDecimal(Double.toString(rate)).stripTrailingZeros().scale()
  /// 返回 null 表示合法，返回错误字符串表示不合法
  static String? validateRatePrecision(double rate, int precision) {
    if (rate <= 0) {
      return 'error rate > 0';
    }
    // ⚠️ 必须用 toString() 转字符串再处理，避免 double 二进制误差
    // 0.099.toString() → "0.099"（正确）
    // 直接用 double 运算会产生 0.09900000000000000...（错误）
    final str = rate.toString(); // e.g. "0.099"

    // 处理科学计数法（极小数 Dart 会输出 "1e-7" 形式）
    if (str.contains('e') || str.contains('E')) {
      // 科学计数法直接用 BigDecimal 等价逻辑解析指数
      final parts = str.toLowerCase().split('e');
      final exp = int.parse(parts[1]);
      final mantissaScale = parts[0].contains('.')
          ? parts[0].split('.')[1].length
          : 0;
      final actualScale = (mantissaScale - exp).clamp(0, 999);
      if (actualScale > precision) {
        return 'error rate [$rate] Precision $actualScale bits, '
            'exceeding the asset\'s allowed precision $precision bits.';
      }
      return null;
    }

    // 普通小数：取小数点后内容，去掉末尾 0（stripTrailingZeros 等价）
    final dotIndex = str.indexOf('.');
    if (dotIndex == -1) return null; // 整数，scale = 0

    final decimals = str
        .substring(dotIndex + 1)
        .replaceAll(RegExp(r'0+$'), ''); // 去末尾零
    final actualScale = decimals.length;

    if (actualScale > precision) {
      return 'error rate [$rate] Precision $actualScale bits, '
          'exceeding the asset\'s allowed precision $precision bits.';
    }
    return null;
  }
}