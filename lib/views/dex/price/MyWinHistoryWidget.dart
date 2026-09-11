import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../setting/AppTranslator.dart';

class MyWinHistoryWidget extends StatefulWidget {
  const MyWinHistoryWidget({super.key});

  @override
  State<MyWinHistoryWidget> createState() => _MyWinHistoryWidgetState();
}

class _MyWinHistoryWidgetState extends State<MyWinHistoryWidget> {
  String _fromAddress = ""; // ✅ 当前选择的查询地址
  List<Map<String, dynamic>> _winOrders = [];
  bool _isLoading = true;

  // 【本次新增，对应你的要求"1.地址有名称显示、余额 2.选择地址的时候有名称
  // 余额"】和 MyDexOrdersWidget.dart 同款用法——本机钱包备注名映射，用于
  // 折叠头部和选择弹窗里展示。
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _initAddress();
    _loadWins();
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  // ✅ 初始化地址逻辑
  void _initAddress() {
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      // 优先取当前激活钱包，没有则取第一个
      _fromAddress = QccObj.activeWallet?.address ?? wallets[0].address;
    }
  }

  // ✅ 根据指定地址加载 Win 历史
  Future<void> _loadWins() async {
    if (_fromAddress.isEmpty) return;

    setState(() => _isLoading = true);

    // 从本地持久化库读取该地址对应的 win 订单
    final data = await QccStorage.getWinOrders(_fromAddress);

    if (mounted) {
      setState(() {
        _winOrders = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ✅ 1. 地址切换头部 (保持和挂单页一致)
        _buildAddressHeader(),

        // ✅ 2. 列表内容
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _winOrders.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
            onRefresh: _loadWins,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: _winOrders.length,
              itemBuilder: (context, index) => _buildWinCard(_winOrders[index]),
            ),
          ),
        ),
      ],
    );
  }

  /// 【本次重写，对应你的要求"1.地址有名称显示、余额"】原来折叠头部只显示
  /// 地址本身，现在加上备注名(没有则"未命名钱包")和 QCC 余额，和
  /// MyDexOrdersWidget.dart 保持同一套写法。
  Widget _buildAddressHeader() {
    final String? nick = _walletNames[_fromAddress];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: _showAddressPicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.blue),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 【本次重写，对应你的要求"2.选择地址的时候有名称余额"】原来的
  /// showModalBottomSheet 没设 isScrollControlled，弹窗高度是系统给的偏小
  /// 固定值；每一行只显示地址本身。现在加上 isScrollControlled + 高度约束 +
  /// Flexible(避免和 DexMatchWidget.dart 那次一样的溢出 bug)，每一行加上
  /// 备注名和 QCC 余额。
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
                        _loadWins(); // 切换地址后重新加载
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

  Widget _buildWinCard(Map<String, dynamic> win) {
    String time = DateFormat('MM-dd HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(win['timestamp'] ?? 0)
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade100)
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.swap_vert, color: Colors.green, size: 22),
        ),
        title: Text(
          "获得 ${win['obtainedAmount']} ${win['targetAssetId']}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("支付 ${win['humanAmount']} ${win['assetId']}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              const SizedBox(height: 4),
              Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        /*onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => QccWinDetailWidget(txHash: win['id'])));
        },*/
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history_toggle_off, size: 60, color: Colors.grey.shade200),
        const SizedBox(height: 16),
        const Trans("该地址暂无成交历史", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 40), // 留白防止顶到头
      ],
    ),
  );
}