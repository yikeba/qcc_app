/// 【新增】多签冻结状态中心——对应你要的第3点"增加一个多签冻结状态中心"。
///
/// 和单签那边的 QccFreezeHistoryPage（读 AssetFreezeStorage 本地记录）不是
/// 同一个数据源：多签冻结/解冻走的是 /v1/mtxrule 多签规则流程，本地记录在
/// MultiSigAssetFreezeWidget._handleFreezeSubmit() 成功后写进
/// MultiSigFileStorage（和多签资产增发、多签转账共用同一个本地存储），
/// 这里只按 ruleName == AssetFreezeRule 过滤出冻结/解冻这一类，不会和
/// 增发/转账的记录混在一起——延续本次会话"追随签署时不会选错功能"这个
/// 大原则。
///
/// 展示字段（资产/目标地址/冻结还是解冻/owners/threshold）以本地记录为准
/// （MultiSigAssetFreezeWidget 发起成功那一刻就已经完整存下），只用
/// QccMultiSigService.fetchTaskWithLocalFallback() 去查一次"当前签了几个/
/// 是否已生效"这个会变化的状态——和 MultiSigTransferHistoryPage.dart 同一个
/// 做法。
///
/// 【假设，需要你核实，和其它几个新文件同一处】本文件放在和
/// MultiSigAssetFreezeWidget.dart / MultiSigAssetFreezeFollowSignWidget.dart
/// 同一个文件夹下，import 相对路径是按这三个文件互相的深度关系推出来的。
library;

import 'package:flutter/material.dart';

import '../../../user/multiple/MultiSigFileStorage.dart';
import '../../../user/multiple/multicreat/MultiSigInitiatedPage.dart';
import '../../../user/multiple/multicreat/QccMultiSigService.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../core/AssetMeta.dart';

class MultiSigFreezeStatusCenterPage extends StatefulWidget {
  const MultiSigFreezeStatusCenterPage({super.key});

  @override
  State<MultiSigFreezeStatusCenterPage> createState() => _MultiSigFreezeStatusCenterPageState();
}

class _MultiSigFreezeStatusCenterPageState extends State<MultiSigFreezeStatusCenterPage> {
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
        // 只认冻结/解冻记录：按 ruleName 过滤（MultiSigAssetFreezeWidget
        // 发起成功时已经写了这个字段）；老记录万一缺这个字段，用
        // targetAddress + freeze 同时存在这个特征兜底识别。
        final bool isFreeze = e['ruleName'] == AssetType.AssetFreezeRule.name ||
            (e.containsKey('targetAddress') && e.containsKey('freeze'));
        if (!isFreeze) continue;
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
          // 冻结/解冻是规则提案，不是转账，借用 append 的展示逻辑，和
          // MultiSigAssetMintWidget.dart / MultiSigAssetFreezeWidget.dart
          // 提交成功后跳转的类型保持一致。
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
        title: Trans("多签冻结状态中心"),
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
              ? Center(child: Trans("暂无多签冻结/解冻提案记录", style: const TextStyle(color: Colors.grey)))
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
    final bool freeze = local['freeze'] == true;
    final String target = (local['targetAddress'] ?? '--').toString();

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
                    freeze ? Icons.ac_unit : Icons.wb_sunny_outlined,
                    color: finished ? (freeze ? Colors.blueGrey : Colors.green) : Colors.orange,
                  ),
                  title: Text(
                    "$assetId · ${freeze ? '冻结' : '解冻'}",
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
