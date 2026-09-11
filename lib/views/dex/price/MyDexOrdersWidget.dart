import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccStorage.dart';
import '../../setting/AppTranslator.dart';
import '../QccOpenDataManager.dart';
import 'QccOrderWinDetailWidget.dart';

class MyDexOrdersWidget extends StatefulWidget {
  const MyDexOrdersWidget({super.key});

  @override
  State<MyDexOrdersWidget> createState() => _MyDexOrdersWidgetState();
}

class _MyDexOrdersWidgetState extends State<MyDexOrdersWidget> {
  String _fromAddress = "";
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  Timer? _heartbeatTimer;

  // 【本次新增，对应你的要求"1.地址有名称显示、余额 2.选择地址的时候有名称
  // 余额"】本机钱包备注名，和 DexMatchWidget.dart/QccWinTransactionPage.dart
  // 同款用法——地址列表还是 QccObj.readWallets()，这里只是额外查一份地址->
  // 备注名映射，用于折叠头部和选择弹窗里展示。
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _initAddress();
    _loadLocalOrders();
    _loadWalletNames();
    // ✅ 启动 10s 自动同步心跳
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) => _syncOrdersRealtimeStatus());
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _initAddress() {
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      _fromAddress = QccObj.activeWallet?.address ?? wallets[0].address;
    }
  }

  Future<void> _loadLocalOrders() async {
    if (_fromAddress.isEmpty) return;
    setState(() => _isLoading = true);
    _orders = await QccStorage.getDexOrders(_fromAddress);
    setState(() => _isLoading = false);
  }

  // ✅ 核心对账逻辑：双源同步 (状态机 + 历史明细)
  Future<Map<String, dynamic>?> _syncOrderFully(String address, Map<String, dynamic> localOrder) async {
    String hash = localOrder['id'];

    // 1. 尝试同步活跃状态机
    var updated = await QccOpenDataManager.syncOpenHashStatus(address, hash);

    // 2. 如果活跃状态机查不到了（返回 null），说明单据已结项，进入历史明细反演
    if (updated == null) {
      LogObj.log("订单 $hash 已从状态机移除，尝试通过历史明细反演状态...");
      final winList = await QccOpenDataManager.getWinHashTx(hash);

      if (winList.isNotEmpty) {
        // 使用明细重算进度
        final stats = _recalculateFromWins(localOrder, winList);

        // 更新本地对象状态
        localOrder['filledProgress'] = (stats['progress']! * 100).toInt();
        localOrder['filledAmount'] = stats['spent']!.toStringAsFixed(4);

        // 如果进度达到 100% 或已有明细但状态机已删，标记为 filled
        localOrder['localStatus'] = stats['progress']! >= 0.999 ? 'filled' : 'closed';

        // 持久化到本地存储
        List<Map<String, dynamic>> currentAll = await QccStorage.getDexOrders(address);
        int idx = currentAll.indexWhere((e) => e['id'] == hash);
        if (idx != -1) {
          currentAll[idx] = localOrder;
          await QccStorage.saveAllDexOrders(address, currentAll);
        }
        return localOrder;
      }
    }
    return updated;
  }

  // 辅助方法：通过 Win 明细重算
  Map<String, double> _recalculateFromWins(Map<String, dynamic> order, List<dynamic> winList) {
    String lid = order['assetId'];
    double rate = (order['matchLogic']?['rate'] as num?)?.toDouble() ?? 0.0;
    double originalHuman = QccAssetService().getHumanAmountNum(lid, order['amount']);

    double spentHuman = 0.0;
    for (var win in winList) {
      spentHuman += QccAssetService().getHumanAmountNum(win['assetId'], win['amount']);
    }

    double progress = originalHuman > 0 ? (spentHuman / originalHuman) : 0;
    return {"spent": spentHuman, "progress": progress > 1.0 ? 1.0 : progress};
  }

  // ✅ 10秒一次的心跳，调用全量同步
  Future<void> _syncOrdersRealtimeStatus() async {
    if (_fromAddress.isEmpty || _orders.isEmpty) return;

    List<int> activeIndexes = [];
    List<Future<Map<String, dynamic>?>> tasks = [];

    for (int i = 0; i < _orders.length; i++) {
      // 只有 "open" 状态的才需要心跳同步
      if (_orders[i]['localStatus'] == 'open' || _orders[i]['localStatus'] == null) {
        activeIndexes.add(i);
        tasks.add(_syncOrderFully(_fromAddress, _orders[i]));
      }
    }

    if (tasks.isEmpty) return;
    final results = await Future.wait(tasks);

    bool needsRepaint = false;
    for (int j = 0; j < results.length; j++) {
      if (results[j] != null) {
        // 强制创建新 Map 引用以确保 UI 刷新
        _orders[activeIndexes[j]] = Map<String, dynamic>.from(results[j]!);
        needsRepaint = true;
      }
    }

    if (needsRepaint && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    /*return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(title: const Trans("现货挂单管理"), centerTitle: true, elevation: 0),
      body: Column(
        children: [_buildAddressHeader(), Expanded(child: _isLoading ? _loading() : _orders.isEmpty ? _buildEmpty() : _buildList())],
      ),
    );*/
    return  Column(
      children: [_buildAddressHeader(), Expanded(child: _isLoading ? _loading() : _orders.isEmpty ? _buildEmpty() : _buildList())],

    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadLocalOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    bool isBuy = order['assetId'].toString().toUpperCase().contains("USDS");
    Color sideColor = isBuy ? Colors.green : Colors.redAccent;

    double chainRate = double.tryParse(order['matchLogic']?['rate']?.toString() ?? "0") ?? 0;
    double usdPrice = isBuy ? (chainRate > 0 ? 1.0 / chainRate : 0) : chainRate;
    String token = isBuy ? (order['matchLogic']?['pairAssetId'] ?? "QCC") : order['assetId'];
    String stable = isBuy ? order['assetId'] : (order['matchLogic']?['pairAssetId'] ?? "USDS");

    double rawAmountHuman = QccAssetService().getHumanAmountNum(order["assetId"], order['amount']);
    double tokenTotal = isBuy ? (rawAmountHuman * chainRate) : rawAmountHuman;

    // 计算成交额 (Obtained)
    double filledHuman = double.tryParse(order['filledAmount']?.toString() ?? "0") ?? 0;
    double obtainedTotal = isBuy ? filledHuman : (filledHuman * chainRate);

    String status = order['localStatus'] ?? 'open';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _sideTag(isBuy ? "买入" : "卖出", sideColor),
                    const SizedBox(width: 8),
                    Text("$token / $stable", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                _buildStatusBadge(status),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                _dataBox("价格($stable)", usdPrice.toStringAsFixed(4)),
                _dataBox("委托量($token)", tokenTotal.toStringAsFixed(2)),
                _dataBox("成交额($stable)", obtainedTotal.toStringAsFixed(2)),
              ],
            ),
            const SizedBox(height: 16),
            _buildTradeSection(order),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Hash: ${order['id'].substring(0, 10)}...", style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
                Row(
                  children: [
                    _iconBtn(Icons.receipt_long, "明细", Colors.blue, () => _showTradeDetail(order)),
                    if (status == 'open') ...[
                      const SizedBox(width: 40),
                      _iconBtn(Icons.cancel_outlined, "取消", Colors.blueGrey, () => _handleCancel(order)),
                    ],
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;
    switch (status) {
      case 'filled': color = Colors.green; text = "已完成"; break;
      case 'cancelled': color = Colors.grey; text = "已撤销"; break;
      case 'expired': color = Colors.orange; text = "已过期"; break;
      default: color = Colors.blue; text = "撮合中";
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTradeSection(Map<String, dynamic> order) {
    int progress = order['filledProgress'] ?? 0;
    Color pColor = (order['localStatus'] == 'filled') ? Colors.green : Colors.blue;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("成交进度", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
              Text("$progress %", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pColor)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: progress / 100, minHeight: 3, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(pColor)),
          ),
        ],
      ),
    );
  }

  // --- 小组件 ---
  Widget _sideTag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _dataBox(String label, String value) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), const SizedBox(height: 4), Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))],
  ));

  Widget _iconBtn(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Row(children: [Icon(icon, size: 22, color: color), const SizedBox(width: 5), Text(label, style: TextStyle(fontSize: 12, color: color))]),
  );

  /// 【本次重写，对应你的要求"1.地址有名称显示、余额"】原来折叠头部只显示
  /// 地址本身，现在加上备注名(没有则"未命名钱包")和 QCC 余额。
  Widget _buildAddressHeader() {
    final String? nick = _walletNames[_fromAddress];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: _showAddressPicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet, size: 20, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(nick ?? "未命名钱包", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_fromAddress, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 11, color: Colors.blueGrey),
                        const SizedBox(width: 3),
                        QccActiveWallet(_fromAddress, "QCC", fontSize: 11, fontColor: Colors.black54),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.unfold_more, size: 18, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  /// 【本次重写，对应你的要求"2.选择地址的时候有名称余额"】原来的
  /// showModalBottomSheet 没设 isScrollControlled，弹窗高度是系统给的偏小
  /// 固定值；每一行只显示地址本身。现在加上 isScrollControlled + 高度约束 +
  /// Flexible(避免钱包多、行变高之后溢出——同 DexMatchWidget.dart 修过的
  /// 那个溢出 bug 的处理方式)，每一行加上备注名和 QCC 余额。
  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Trans("切换查询地址", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: wallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final w = wallets[index];
                    bool isSelected = w.address == _fromAddress;
                    final String? nick = _walletNames[w.address];
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.wallet, color: isSelected ? Colors.blue : Colors.grey),
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
                      onTap: () {
                        setState(() => _fromAddress = w.address);
                        Navigator.pop(context);
                        _loadLocalOrders();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTradeDetail(Map<String, dynamic> order) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => QccOrderWinDetailWidget(order: order)));
  }

  void _handleCancel(Map<String, dynamic> order) { /* 撤单逻辑 */ }
  Widget _loading() => const Center(child: CircularProgressIndicator(strokeWidth: 2));
  Widget _buildEmpty() => const Center(child: Text("暂无活跃挂单"));
}