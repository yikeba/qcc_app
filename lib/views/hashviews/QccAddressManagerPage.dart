import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../setting/AppTranslator.dart';
import 'GasRecord.dart';
import 'QccDataMeta.dart';
import 'QccDetailPage.dart';
import '../../home/QccExplorerService.dart';

class QccAddressManagerPage extends StatefulWidget {
  final String address;
  final int initialTabIndex;

  const QccAddressManagerPage({super.key, required this.address, this.initialTabIndex = 0});

  @override
  State<QccAddressManagerPage> createState() => _QccAddressManagerPageState();
}

class _QccAddressManagerPageState extends State<QccAddressManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  List<QccDataMeta> _transactions = [];
  List<QccDataMeta> _dataEntries = [];
  List<GasRecord>   _gasRecords  = []; // ← 改用 GasRecord

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final results = await Future.wait([
      QccExplorerService.fetchAddressHashes(widget.address),
      // fetchGasDetails 现在返回 GasRecordPage，调用方解包 .records
      QccExplorerService.fetchGasDetails(widget.address),
    ]);

    final List<String>      hashes  = results[0] as List<String>;
    final GasRecordPage     gasPage = results[1] as GasRecordPage; // ← 新类型

    final detailResults = await Future.wait(
      hashes.map((h) => QccExplorerService.fetchDetail(h)),
    );

    if (!mounted) return;
    setState(() {
      _transactions = detailResults.where((e) => e.entryType == QccEntryType.transaction).toList();
      _dataEntries  = detailResults.where((e) => e.entryType == QccEntryType.data).toList();
      _gasRecords   = gasPage.records; // ← 直接用 GasRecord 列表
      _isLoading    = false;
    });

    LogObj.log('数据加载完成：交易(${_transactions.length}), ''存证(${_dataEntries.length}), Gas(${_gasRecords.length})');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Trans('资产详情'),
            Text(
              widget.address,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal, fontFamily: 'monospace'),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue.shade800,
          labelColor: Colors.blue.shade800,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: '交易轨迹 (${_transactions.length})'),
            Tab(text: '存证数据 (${_dataEntries.length})'),
            Tab(text: 'Gas 明细 (${_gasRecords.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildList(_transactions, Icons.swap_horiz, Colors.orange),
          _buildList(_dataEntries, Icons.description, Colors.blue),
          _buildGasList(),
        ],
      ),
    );
  }

  // 通用列表（交易 & 存证）
  Widget _buildList(List<QccDataMeta> items, IconData icon, Color color) {
    if (items.isEmpty) return const Center(child: Trans('暂无记录'));

    return ListView.separated(
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Hash: ${item.metaHash.substring(0, 16)}...',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (c) => QccDetailPage(meta: item)),
          ),
        );
      },
    );
  }

  // Gas 专属列表（使用 GasRecord 字段）
  Widget _buildGasList() {
    if (_gasRecords.isEmpty) return const Center(child: Trans('暂无手续费记录'));

    return ListView.separated(
      itemCount: _gasRecords.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, index) {
        final r = _gasRecords[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.withOpacity(0.1),
            child: const Icon(Icons.local_gas_station, color: Colors.green, size: 20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // txType 标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _txTypeColor(r.txType).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.txTypeLabel,
                  style: TextStyle(fontSize: 11, color: _txTypeColor(r.txType), fontWeight: FontWeight.w600),
                ),
              ),
              // Gas 费用，永远是 QCC 原生币
              Text(
                '-${r.gasFormatted} QCC',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 转账金额
                Row(
                  children: [
                    const Icon(Icons.arrow_forward, size: 11, color: Colors.grey),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        // amount 单位是交易资产(assetId)，不是 gas 单位
                        '${r.amountFormatted} ${r.assetId}  →  ${_shortAddr(r.to)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // txId + 时间
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TxID: ${r.txId.substring(0, 16)}...',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      r.timeStr,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // nodeId（出块节点）
                Text(
                  '节点: ${_shortAddr(r.nodeId)}',
                  style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right, size: 16),
          onTap: () => _showGasDetail(context, r),
        );
      },
    );
  }

  // Gas 详情弹窗
  void _showGasDetail(BuildContext context, GasRecord r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_gas_station, color: Colors.green),
                const SizedBox(width: 8),
                Text('Gas 详情', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(height: 24),
            _detailRow('类型',         r.txTypeLabel),
            // gas / leaderUnits / systemIncome / devReward 固定 QCC 原生币
            _detailRow('手续费',       '${r.gasFormatted} QCC'),
            // amount 是交易资产，单位用 assetId
            _detailRow('转账金额',     '${r.amountFormatted} ${r.assetId}'),
            _detailRow('支付方',       r.payer),
            _detailRow('收款方',       r.to),
            _detailRow('出块节点',     r.nodeId),
            _detailRow('Leader 分成', '${(r.leaderUnits / 1e9).toStringAsFixed(9)} QCC'),
            _detailRow('系统收入',     '${(r.systemIncome / 1e9).toStringAsFixed(9)} QCC'),
            if (r.devReward > 0) ...[
              _detailRow('开发者奖励', '${(r.devReward / 1e9).toStringAsFixed(9)} QCC'),
              _detailRow('开发者地址', r.devAddress ?? '--'),
            ],
            _detailRow('交易 ID',     r.txId),
            _detailRow('容器 Hash',   r.containerHash),
            _detailRow('时间',        r.timeStr),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // 地址缩短显示
  String _shortAddr(String addr) {
    if (addr.length <= 20) return addr;
    return '${addr.substring(0, 10)}...${addr.substring(addr.length - 6)}';
  }

  // txType 对应颜色
  Color _txTypeColor(String txType) {
    switch (txType) {
      case 'WIN':         return Colors.amber.shade700;
      case 'RULE_USER':   return Colors.purple;
      case 'RULE_ASSET':  return Colors.indigo;
      case 'ENTITY_DATA': return Colors.teal;
      case 'NORMAL':
      default:            return Colors.green.shade700;
    }
  }
}