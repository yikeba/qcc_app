/// 【新增】多签增发状态中心——对应"多签增发（提案/追随/中心）"这一组里的
/// "中心"。做法和 MultiSigFreezeStatusCenterPage.dart 完全一致，只是过滤
/// 条件换成 ruleName == AssetMintRule，展示字段换成接收多签地址(receiver)+
/// 增发数量(amount)。
///
/// 【依赖，已顺带修复】本地记录来自 MultiSigFileStorage，由
/// MultiSigAssetMintWidget._handleMintSubmit() 发起成功后写入——原来那处
/// 代码是 `MultiSigFileStorage.saveTask(resData)` 直接存服务端原始返回，
/// 不保证带 assetId/receiver/amount/owners/threshold 这些字段。这次顺带把
/// 那处也改成了显式合并一份完整记录再保存（和 MultiSigAssetFreezeWidget.dart
/// 那次同一个修法），这个中心页面才有稳定的数据可读。
///
/// 【假设，需要你核实】本文件放在和 MultiSigAssetMintWidget.dart /
/// AssetMintFollowSignWidget.dart 同一个文件夹下，import 相对路径按这两个
/// 文件已确认的深度推出来的。
library;

import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../../user/multiple/MultiSigFileStorage.dart';
import '../../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../../user/multiple/multicreat/QccMultiSigService.dart';
import '../../core/AssetMeta.dart';

class MultiSigMintStatusCenterPage extends StatefulWidget {
  const MultiSigMintStatusCenterPage({super.key});

  @override
  State<MultiSigMintStatusCenterPage> createState() => _MultiSigMintStatusCenterPageState();
}

class _MultiSigMintStatusCenterPageState extends State<MultiSigMintStatusCenterPage> {
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
        // 只认增发记录：按 ruleName 过滤；老记录万一缺这个字段，用
        // receiver 存在这个特征兜底识别（转账/冻结记录都不会有这个字段）。
        final bool isMint = e['ruleName'] == AssetType.AssetMintRule.name || e.containsKey('receiver');
        if (!isMint) continue;
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
        title: Trans("多签增发状态中心"),
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
              ? Center(child: Trans("暂无多签增发提案记录", style: const TextStyle(color: Colors.grey)))
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
    final String receiver = (local['receiver'] ?? local['multiAddress'] ?? '--').toString();
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
                    Icons.add_chart_outlined,
                    color: finished ? Colors.green : Colors.deepPurple,
                  ),
                  title: Text(
                    "$assetId · 增发 $readableAmount",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    "接收: ${receiver.length > 16 ? '${receiver.substring(0, 8)}...${receiver.substring(receiver.length - 6)}' : receiver}  ·  Hash: ${hash.substring(0, 6)}...${hash.substring(hash.length - 6)}",
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
