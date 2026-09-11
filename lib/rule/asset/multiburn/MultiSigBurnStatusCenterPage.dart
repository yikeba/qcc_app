/// 【新增】多签销毁状态中心——对应"多签销毁（提案/追随/中心）"这一组里的
/// "中心"。做法和 MultiSigFreezeStatusCenterPage.dart /
/// MultiSigMintStatusCenterPage.dart 完全一致，过滤条件是 ruleName ==
/// AssetBurnRule，展示字段是被销毁地址(targetAddress)+销毁数量(amount)。
///
/// 【依赖需要你核实，比另外两个中心多一层不确定性】另外两个中心（增发/
/// 冻结）背后发起提案的页面（MultiSigAssetMintWidget.dart /
/// MultiSigAssetFreezeWidget.dart）我这次都改过 saveTask 调用，确保本地
/// 记录带 ruleName/assetId/targetAddress 等字段。但 MultiSigAssetBurnWidget.
/// dart（多签销毁提案发起页）我没有拿到真实源码，不知道它现在的
/// saveTask 调用是不是也存了这些字段——如果它现在还是"原样存服务端返回"
/// 这种写法（这次会话里已经确认过好几个文件都是这个坑），这个中心页面
/// 可能读不到 assetId/targetAddress/owners/threshold，界面会显示成空白或
/// "--"。麻烦把 MultiSigAssetBurnWidget.dart 发我，我把它也按同样的方式
/// 修一遍（显式合并一份完整记录再 saveTask），这个中心才能稳定工作。
library;

import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/core/AssetMeta.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../user/multiple/MultiSigFileStorage.dart';
import '../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../user/multiple/multicreat/QccMultiSigService.dart';

class MultiSigBurnStatusCenterPage extends StatefulWidget {
  const MultiSigBurnStatusCenterPage({super.key});

  @override
  State<MultiSigBurnStatusCenterPage> createState() => _MultiSigBurnStatusCenterPageState();
}

class _MultiSigBurnStatusCenterPageState extends State<MultiSigBurnStatusCenterPage> {
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
        final bool isBurn = e['ruleName'] == AssetType.AssetBurnRule.name ||
            (e.containsKey('targetAddress') && e.containsKey('legalBasis'));
        if (!isBurn) continue;
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
    List<String> owners = List<String>.from(local['owners'] ?? []).map((e) => e.toString()).toList();
    int threshold = (local['threshold'] ?? 0) is int ? local['threshold'] : int.tryParse('${local['threshold']}') ?? 0;
    final bool finished = (live?.isConfirmed ?? false) || local['status'] == 'SUCCESS';
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
          isFinish: finished,
          type: MultiSigPageType.append,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("多签销毁状态中心"),
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
              ? Center(child: Trans("暂无多签销毁提案记录", style: const TextStyle(color: Colors.grey)))
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
    final String assetId = (local['assetId'] ?? '--').toString();
    final String target = (local['targetAddress'] ?? '--').toString();
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
                progressText = "已生效";
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
                    Icons.delete_forever_outlined,
                    color: finished ? Colors.green : Colors.teal,
                  ),
                  title: Text(
                    "$assetId · 销毁 $readableAmount",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    "目标: ${target.length > 16 ? '${target.substring(0, 8)}...${target.substring(target.length - 6)}' : target}  ·  Hash: ${hash.substring(0, 6)}...${hash.substring(hash.length - 6)}",
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey),
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
