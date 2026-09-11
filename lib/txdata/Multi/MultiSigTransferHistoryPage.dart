/// 【新增】多签转账明细页——对应「多签转账」菜单里新增的第三个入口
/// (多签转账提案 / 多签转账签署 / 多签转账明细)。
///
/// 数据来源：MultiSigFileStorage 里由 QccMultiSigTransferPage._handleInitiate()
/// 发起成功后写入的记录（type == 'transfer'，字段：txHash/multiAddress/
/// assetId/amount/to/from/owners/threshold/timestamp/status）。这里只按
/// type == 'transfer' 过滤，不会把"资产规则"类的多签记录（QccMultiSigCenterPage
/// 那边混着展示的另一类）混进来——这正是你要单独拆一个"转账明细"入口的目的：
/// 避免追随签署时选错功能、也避免转账和资产规则的记录混在一起分不清。
///
/// 展示字段以本地记录（local）为准（to/amount/assetId/owners/threshold 这些
/// 在发起那一刻就已经完整、权威地存下来了），只用 QccMultiSigService
/// .fetchTaskWithLocalFallback() 去查一次"当前是否已经签署完成/签了几个"这个
/// 会变化的状态——这样即使 mtxquery 查不到（换节点/内存过期）也不会导致
/// 明细本身（转给谁、多少钱）显示不出来。
///
/// 【假设，需要你核实】本文件放在和 QccMultiSigTransferPage.dart /
/// QccFollowTransactionPage.dart 同一个文件夹下（也就是 QccTxManagerPage.dart
/// 里 `import 'Multi/QccMultiSigTransferPage.dart'` 对应的 Multi/ 目录），
/// 所以下面这些 import 的相对路径前缀（../../）直接照抄了
/// QccMultiSigTransferPage.dart 里已经验证过的那一套。如果实际项目里这个
/// 新文件被你放到了别的目录，麻烦告诉我一声，我把相对路径改一下。
library;

import 'package:flutter/material.dart';
import 'package:qcc_flutter/txdata/tx/QccTransaction.dart';

import '../../rule/user/multiple/MultiSigFileStorage.dart';
import '../../rule/user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../rule/user/multiple/multicreat/QccMultiSigService.dart';
import '../tx/TransferSuccessPage.dart';
import '../../utile/Tools.dart';
import '../../views/myasset/QccAssetService.dart';
import '../../views/setting/AppTranslator.dart';

class MultiSigTransferHistoryPage extends StatefulWidget {
  const MultiSigTransferHistoryPage({super.key});

  @override
  State<MultiSigTransferHistoryPage> createState() => _MultiSigTransferHistoryPageState();
}

class _MultiSigTransferHistoryPageState extends State<MultiSigTransferHistoryPage> {
  bool _isInit = true;
  List<String> _hashes = [];
  Map<String, Map<String, dynamic>> _localRecords = {};
  final Map<String, Future<MultiSigTaskWrapper?>> _liveFutures = {};

  @override
  void initState() {
    super.initState();
    _handleRefresh();
  }

  Future<void> _handleRefresh() async {
    try {
      final List<dynamic> tasks = await MultiSigFileStorage.getAllTasks();
      final Map<String, Map<String, dynamic>> byHash = {};
      for (final e in tasks) {
        if (e is! Map) continue;
        // 只认转账记录：优先看 type 字段（QccMultiSigTransferPage 发起时写的
        // 就是 'transfer'），老记录万一没有这个字段，用 fromMulti/to 同时
        // 存在这个特征兜底识别，避免历史数据被漏掉。
        final bool isTransfer = e['type'] == 'transfer' ||
            (e['to'] != null && (e['multiAddress'] != null || e['from'] != null));
        if (!isTransfer) continue;
        final String h = (e['txHash'] ?? '').toString().trim();
        if (h.length > 10) byHash[h] = Map<String, dynamic>.from(e);
      }
      if (mounted) {
        setState(() {
          _localRecords = byHash;
          _hashes = byHash.keys.toList().reversed.toList();
          _liveFutures.clear();
          _isInit = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isInit = false);
    }
  }

  Future<void> _handleDelete(String hash) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("移除记录"),
        content: Trans("是否从本地列表中移除此条记录？（不会影响链上数据）"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Trans("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Trans("确定", style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await MultiSigFileStorage.deleteTask(hash);
    if (mounted) {
      setState(() {
        _hashes.remove(hash);
        _localRecords.remove(hash);
        _liveFutures.remove(hash);
      });
      Tools.showToast(context, "已移除");
    }
  }

  void _onTapItem(String hash, MultiSigTaskWrapper? live) {
    final Map<String, dynamic> local = _localRecords[hash] ?? {};
    final String assetId = (local['assetId'] ?? 'QCC').toString();
    final String? to = local['to']?.toString();
    final String? from = local['from']?.toString();
    final dynamic rawAmount = local['amount'];

    final bool finished = (live?.isConfirmed ?? false) || local['status'] == 'SUCCESS';

    if (finished) {
      final QccTransaction txData = QccTransaction(
        from: from ?? '',
        to: to ?? '',
        amount: QccAssetService().getHumanAmountNum(assetId, rawAmount),
        assetId: assetId,
        txHash: hash,
        type: "multitransaction",
        timestamp: (local['timestamp'] ?? DateTime.now().millisecondsSinceEpoch) as int,
        status: '',
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TransferSuccessPage(transaction: txData)),
      );
      return;
    }

    // 未完成：owners/threshold 优先用这次实时查到的（更贴近当前真实签署
    // 进度），查不到时用本地记录发起时存的那一份兜底。
    List<String> owners = List<String>.from(local['owners'] ?? []).map((e) => e.toString()).toList();
    int threshold = (local['threshold'] ?? 0) is int ? local['threshold'] : int.tryParse('${local['threshold']}') ?? 0;
    List<String>? signedOwners;
    if (live != null && !live.isConfirmed) {
      final liveOwners = List<String>.from(live.data['owners'] ?? []).map((e) => e.toString()).toList();
      if (liveOwners.isNotEmpty) owners = liveOwners;
      final liveThreshold = live.data['threshold'];
      if (liveThreshold is int && liveThreshold > 0) threshold = liveThreshold;
      signedOwners = live.signedOwners.toSet().toList();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiSigInitiatedPage(
          txHash: hash,
          owners: owners,
          threshold: threshold,
          signedOwners: signedOwners,
          isFinish: false,
          type: MultiSigPageType.transfer,
          toAddress: to,
          amount: QccAssetService().getHumanAmount(assetId, rawAmount),
          assetId: assetId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("多签转账明细"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.blueAccent), onPressed: _handleRefresh),
        ],
      ),
      body: _isInit
          ? const Center(child: CircularProgressIndicator())
          : _hashes.isEmpty
              ? Center(child: Trans("暂无多签转账记录", style: const TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _hashes.length,
                    itemBuilder: (context, index) => _buildItem(_hashes[index]),
                  ),
                ),
    );
  }

  Widget _buildItem(String hash) {
    final Map<String, dynamic> local = _localRecords[hash] ?? {};
    final String assetId = (local['assetId'] ?? 'QCC').toString();
    final String to = (local['to'] ?? '--').toString();
    final String readableAmount = QccAssetService().getHumanAmount(assetId, local['amount']);

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
          onPressed: () => _handleDelete(hash),
        ),
        Expanded(
          child: FutureBuilder<MultiSigTaskWrapper?>(
            future: _liveFutures.putIfAbsent(
                hash, () => QccMultiSigService.fetchTaskWithLocalFallback(hash, local)),
            builder: (context, snapshot) {
              final bool loading = snapshot.connectionState == ConnectionState.waiting;
              final MultiSigTaskWrapper? live = snapshot.data;
              final bool finished = (live?.isConfirmed ?? false) || local['status'] == 'SUCCESS';

              String progressText;
              if (finished) {
                progressText = "已完成";
              } else if (loading) {
                progressText = "查询中...";
              } else if (live != null) {
                final int threshold = (local['threshold'] ?? 0) is int
                    ? local['threshold']
                    : int.tryParse('${local['threshold']}') ?? 0;
                final int current = live.data['currentCount'] is int
                    ? live.data['currentCount']
                    : live.signedOwners.toSet().length;
                progressText = "$current / $threshold";
              } else {
                progressText = "待签署";
              }

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Icon(
                    finished ? Icons.check_circle : Icons.hourglass_bottom,
                    color: finished ? Colors.green : Colors.blueAccent,
                  ),
                  title: Text(
                    "→ ${to.length > 16 ? '${to.substring(0, 8)}...${to.substring(to.length - 6)}' : to}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    "$readableAmount $assetId  ·  Hash: ${hash.substring(0, 6)}...${hash.substring(hash.length - 6)}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: finished
                      ? const Icon(Icons.done_all, color: Colors.green)
                      : Text(progressText, style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                  onTap: () => _onTapItem(hash, live),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
