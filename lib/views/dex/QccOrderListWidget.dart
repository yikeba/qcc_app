import 'dart:developer' as LogObj;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/dex/win/QccWinTransactionPage.dart';

import '../../utile/Tools.dart';
import '../myasset/QccAssetService.dart';
import '../setting/AppTranslator.dart';
import '../../procotol/QccMatchLogic.dart';
import 'QccOpenDataManager.dart';

class OpenOrderListView extends StatefulWidget {
  final QccMatchType type;
  const OpenOrderListView({super.key, required this.type});

  @override
  State<OpenOrderListView> createState() => _OpenOrderListViewState();
}

class _OpenOrderListViewState extends State<OpenOrderListView> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await QccOpenDataManager.syncFromNetwork();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final orders = QccOpenDataManager.getOrdersByType(widget.type);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _isLoading && orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
          ? _buildEmptyView()
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return QccOrderCard(
            orderData: orders[index],
            onTap: () => _showWinDetail(orders[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyView() {
    return ListView( // 必须用 ListView 才能支持下拉刷新
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        const Center(child: Trans("暂无此类挂单，下拉刷新")),
      ],
    );
  }

  void _showWinDetail(Map<String, dynamic> order) {
   /* showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    //  builder: (context) => QccWinDetailSheet(order: order),
      builder: (context) => QccWinTransactionPage(initialHash: order["hash"],)
    );*/
    LogObj.log("选择交易hash ${order["id"]},完成win,读取order$order ");
    Navigator.push(context, MaterialPageRoute(builder: (context) => QccWinTransactionPage(initialHash: order["id"],)));

  }
}


class QccWinDetailSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  const QccWinDetailSheet({super.key, required this.order});

  @override
  State<QccWinDetailSheet> createState() => _QccWinDetailSheetState();
}

class _QccWinDetailSheetState extends State<QccWinDetailSheet> {
  final TextEditingController _buyAmountController = TextEditingController();
  double _payEstimated = 0.0; // 预估支付金额

  @override
  Widget build(BuildContext context) {
    final logic = widget.order['matchLogic'];
    final String rule = logic['rule'];
    final String sellAsset = widget.order['assetId'];
    final String buyAsset = logic['pairAssetId'] ?? "USDS";
    final double rate = (logic['rate'] as num).toDouble();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, // 避开键盘
        left: 20, right: 20, top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          _buildHeader(rule, sellAsset),
          const Divider(height: 30),

          // 详情展示
          _rowInfo("发起地址", widget.order['from']),
          _rowInfo("订单备注", widget.order['memo'] ?? "N/A"),
          _rowInfo("撮合汇率", "1 $sellAsset = $rate $buyAsset", valueColor: Colors.blue),

          const SizedBox(height: 20),

          // ✅ 交互区：如果是 DEX，需要输入买入数量
          if (rule == 'dex' || rule == 'exchange') ...[
            const Trans("买入数量", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _buyAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: "输入拟购买的 $sellAsset 数量",
                suffixText: sellAsset,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) {
                double val = double.tryParse(v) ?? 0;
                setState(() => _payEstimated = val * rate);
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Trans("预估支付:"),
                  Text("$_payEstimated $buyAsset", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ),
          ] else ...[
            // 红包或空投逻辑
            _rowInfo("剩余份数", "${logic['remainingAmount'] ?? 0} / ${logic['maxParticipants']}"),
          ],

          const SizedBox(height: 30),

          // 确认按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => _handleConfirmWin(rule, buyAsset, rate),
              child: const Trans("确认碰撞交易 (Win)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildHeader(String rule, String asset) {
    return Row(
      children: [
        CircleAvatar(backgroundColor: Colors.blue.withOpacity(0.1), child: Icon(Icons.shopping_cart_outlined, color: Colors.blue)),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("参与 $asset 撮合", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("类型: ${rule.toUpperCase()}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _rowInfo(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 20),
          Expanded(child: Text(value, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: valueColor))),
        ],
      ),
    );
  }

  // ✅ 核心：发起 Win 交易逻辑
  void _handleConfirmWin(String rule, String buyAssetId, double rate) {
    double buyQty = double.tryParse(_buyAmountController.text) ?? 0;
    if ((rule == 'dex') && buyQty <= 0) {
      Tools.showToast(context, "请输入买入数量");
      return;
    }

    Navigator.pop(context); // 先关详情页

    // 调用之前我们讨论过的 _performWinTransaction 逻辑
    // 这里会进入：还原钱包 -> 获取支付资产金额 -> 签名 -> 广播
    // 传递参数给父级或直接在此处执行
  }
}

class QccOrderCard extends StatelessWidget {
  final Map<String, dynamic> orderData;
  final VoidCallback onTap;

  const QccOrderCard({
    super.key,
    required this.orderData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 解析内部嵌套的 matchLogic
    final logic = orderData['matchLogic'] ?? {};
    final String rule = logic['rule'] ?? "unknown";
    final String assetId = orderData['assetId'] ?? "Unknown";

    // 这里的 Precision 处理建议调用你的 AssetUtil
    //final double amount = (orderData['amount'] ?? 0) / 1000000000.0;

    double amount=QccAssetService().getHumanAmountNum(assetId, orderData['amount'] );
    LogObj.log("计算收到出售资产$assetId,资产数量:${orderData["amount"]},最终计算显示数量：$amount");
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：类型标签与资产 ID
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTypeBadge(rule),
                  Text(
                    assetId,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 第二行：核心描述 (Memo)
              Text(
                orderData['memo'] ?? "无备注信息",
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(height: 24),

              // 第三行：交易细节 (根据类型差异化显示)
              _buildOrderDetail(rule, logic, amount, assetId),

              const SizedBox(height: 12),

              // 第四行：底部 Hash 缩略与时间
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Hash: ${orderData['id'].toString().substring(0, 8)}...",
                    style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ 根据 QccMatchType 渲染不同的详情布局
  Widget _buildOrderDetail(String rule, Map logic, double amount, String assetId) {
    if (rule == 'dex' || rule == 'exchange') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _infoColumn("出售数量", "$amount $assetId"),
          _infoColumn("汇率", "1 : ${logic['rate']}"),
          _infoColumn("对价资产", "${logic['pairAssetId'] ?? 'USD'}"),
        ],
      );
    } else {
      // 红包或分红模式
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _infoColumn("投放总量", "$amount $assetId"),
          _infoColumn("最大份数", "${logic['maxParticipants'] ?? 0} 份"),
          _infoColumn("剩余", "${logic['remainingAmount'] ?? 0}"),
        ],
      );
    }
  }



  // ✅ 状态标签美化
  Widget _buildTypeBadge(String rule) {
    Color color = Colors.grey;
    String label = rule.toUpperCase();

    if (rule == 'dex' || rule == 'exchange') {
      color = Colors.teal;
      label = "DEX 现货";
    } else if (rule == 'random') {
      color = Colors.orange;
      label = "随机红包";
    } else if (rule == 'fixed') {
      color = Colors.blue;
      label = "固定空投";
    } else if (rule == 'dividend') {
      color = Colors.purple;
      label = "持币分红";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
  // 在 QccOpenMarketPage 的 AppBar 下方增加一个筛选栏
  Widget _buildAssetFilterBar() {
    return Container(
      height: 50,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(label: const Text("全部"), onSelected: (_) {}),
          const SizedBox(width: 8),
          FilterChip(label: const Text("QCC 交易区"), onSelected: (_) {}),
          const SizedBox(width: 8),
          FilterChip(label: const Text("稳定币区"), onSelected: (_) {}),
        ],
      ),
    );
  }
}


class QccOrderRow extends StatelessWidget {
  late final Map<String, dynamic> orderData;
  late final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logic = orderData['matchLogic'] ?? {};
    final double rate = (logic['rate'] as num?)?.toDouble() ?? 0.0;
    final String assetId = orderData['assetId'] ?? "";
    final String pairId = logic['pairAssetId'] ?? "USDS";
    final double amount = (orderData['amount'] ?? 0) / 1000000000.0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            // 1. 价格/汇率 (突出显示)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$rate", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("汇率 ($pairId)", style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ),
            // 2. 数量
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$amount", style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text("数量 ($assetId)", style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ),
            // 3. 操作按钮 (买入)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(60, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: onTap,
              child: const Trans("买入"),
            ),
          ],
        ),
      ),
    );
  }
}

class QccOpenOrder {
  final String id;           // 交易 Hash
  final String assetId;      // 出售的资产 (如 MCZX)
  final String from;         // 发起人地址
  final int amount;          // 总挂单数量
  final int timestamp;       // 挂单时间
  final String memo;         // 备注（项目名称/融资说明）
  final String txType;       // 交易类型 (open)

  // 撮合逻辑详情
  final String rule;         // exchange (DEX), random, fixed
  final double rate;         // 汇率
  final int maxParticipants; // 最大份数
  final int remainingAmount; // 剩余可交易数量

  QccOpenOrder.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        assetId = map['assetId'],
        from = map['from'],
        amount = map['amount'],
        timestamp = map['timestamp'],
        memo = map['memo'] ?? "",
        txType = map['txType'],
        rule = map['matchLogic']['rule'],
        rate = (map['matchLogic']['rate'] as num).toDouble(),
        maxParticipants = map['matchLogic']['maxParticipants'],
        remainingAmount = map['matchLogic']['remainingAmount'] ?? 0;
}