import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/qccnodemap/qcc_geo_service.dart';
import 'QccNodeManager.dart';
import '../views/setting/AppTranslator.dart';
import 'QccNodeMapWidget.dart';
import 'QccProducerClusterWidget.dart';

/// 列表/地图共用的筛选：
/// - all  全部节点，按 当前出块 / 同步 / 未识别 分段显示
/// - sync 只看同步节点
/// 任何时刻只有一个生产者（当前出块者），不单设"生产"筛选。
/// "仅在线"是叠加开关（reachable && active）。
enum _NodeFilter { all, sync }

class QccNodeListWidget extends StatefulWidget {
  const QccNodeListWidget({super.key});

  @override
  State<QccNodeListWidget> createState() => _QccNodeListWidgetState();
}

class _QccNodeListWidgetState extends State<QccNodeListWidget>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  _NodeFilter _filter = _NodeFilter.all;
  bool _onlineOnly = false;
  final Map<String, GeoInfo?> _geoByIp = {};
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 切到"生产集群"tab 时隐藏顶部的节点筛选区，需要随 tab 切换重建
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await QccNodeManager.instance.init();
    // refreshNodes() 内部已经会 await 一轮探测 + 视图合并，这里不要再重复探测。
    await QccNodeManager.instance.refreshNodes(force: true);
    // 积分来自 /v1/producer，和生产集群 tab 共用缓存；失败不影响节点列表
    try {
      await QccProducerService.fetch();
    } catch (_) {}

    // 只查还没查过的 IP（GeoService 自己也有缓存，这里省掉无谓的 Future）
    final nodes = QccNodeManager.instance.nodes;
    await Future.wait(nodes.map((n) async {
      final key = IpUtils.stripBrackets(n.ip);
      if (_geoByIp.containsKey(key) && _geoByIp[key] != null) return;
      _geoByIp[key] = await GeoService.lookup(n.ip);
    }));

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _hideNode(QccNode n) async {
    await QccNodeManager.instance.hideNode(n.ip);
    if (mounted) setState(() {});
  }

  Future<void> _unhideNode(QccNode n) async {
    await QccNodeManager.instance.unhideNode(n.ip);
    if (mounted) setState(() {});
  }

  Future<bool> _confirmHide(QccNode n) async {
    final displayIp = IpUtils.displayIp(n.ip);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("隐藏该节点？"),
        content: Text("$displayIp 将不再显示在列表和地图中。\n如果它之后恢复可达，会自动重新显示；"
            "你也可以随时在“已隐藏节点”里手动恢复。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("隐藏"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showHiddenNodesSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final hidden = QccNodeManager.instance.hiddenNodes;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("已隐藏节点（${hidden.length}）",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (hidden.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text("暂无隐藏节点",
                            style: TextStyle(color: Colors.grey.shade600)),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: hidden.length,
                          itemBuilder: (_, i) {
                            final n = hidden[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  QccNodeRoleBadge(node: n),
                                  Expanded(
                                    child: Text(IpUtils.displayIp(n.ip),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              subtitle: Text(n.nodeId.isEmpty
                                  ? "高度 ${n.height}"
                                  : "${shortNodeId(n.nodeId)} · 高度 ${n.height}"),
                              trailing: TextButton(
                                onPressed: () async {
                                  await _unhideNode(n);
                                  setSheetState(() {});
                                },
                                child: const Text("恢复"),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 离线 → 灰；网络在线但本机连不上 → 蓝灰（不是故障，只是本机路由不通）；
  /// 可直连 → 按延迟绿/橙/红。
  Color _latencyColor(QccNode n) {
    if (!n.isOnline) return Colors.grey;
    if (!n.isDirect) return Colors.blueGrey;
    if (n.latencyMs < 150) return Colors.green;
    if (n.latencyMs < 400) return Colors.orange;
    return Colors.red;
  }

  static int _kindRank(QccNode n) =>
      n.isProducer ? 0 : (n.isSync ? 1 : 2);

  /// 过滤 + 排序：
  /// 类型（生产 → 同步 → 未识别）→ 当前出块者置顶 → 在线优先 → 高度降序
  /// → 延迟升序 → 原始顺序兜底（List.sort 不稳定，避免刷新时顺序乱跳）。
  List<QccNode> _filterAndSort(List<QccNode> nodes) {
    Iterable<QccNode> base = nodes;
    if (_filter == _NodeFilter.sync) {
      base = base.where((n) => n.isSync);
    }
    if (_onlineOnly) base = base.where((n) => n.isOnline);

    final indexed = base.toList().asMap().entries.toList();
    indexed.sort((a, b) {
      final x = a.value, y = b.value;
      var c = _kindRank(x).compareTo(_kindRank(y));
      if (c != 0) return c;
      if (x.isNowProducer != y.isNowProducer) return x.isNowProducer ? -1 : 1;
      if (x.isOnline != y.isOnline) return x.isOnline ? -1 : 1;
      if (x.isDirect != y.isDirect) return x.isDirect ? -1 : 1;
      c = y.height.compareTo(x.height);
      if (c != 0) return c;
      c = x.latencyMs.compareTo(y.latencyMs);
      if (c != 0) return c;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  void _copyIp(String ip) => _copyText(ip, "IP");

  void _copyText(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("已复制$label：$text"),
          duration: const Duration(seconds: 1)),
    );
  }

  /// 积分角标：#名次 积分；生产组 indigo、候选 blueGrey、负分红色
  Widget _heatChip(QccProducerRank r) {
    final c = r.heat < 0
        ? Colors.red.shade600
        : (r.isProducer ? Colors.indigo : Colors.blueGrey);
    return Tooltip(
      message: heatBreakdown(r) == null
          ? "积分 ${r.heat} · 第 ${r.rank} 名"
          : "积分 ${r.heat} = ${heatBreakdown(r)} · 第 ${r.rank} 名",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text("#${r.rank} · ${r.heat}分",
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: c)),
      ),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _statChip(String label, int online, int total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        "$label $online/$total",
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr = QccNodeManager.instance;
    final allNodes = mgr.visibleNodes;
    final nodes = _filterAndSort(allNodes);
    final net = mgr.network;
    final tip = mgr.tipHeight;

    final syncs = allNodes.where((n) => n.isSync).toList();
    final unknowns = allNodes.where((n) => n.kind == QccNodeKind.unknown).toList();
    int online(List<QccNode> l) => l.where((n) => n.isOnline).length;
    final direct = allNodes.where((n) => n.isDirect).length;
    final hiddenCount = mgr.hiddenNodes.length;

    return Scaffold(
      appBar: AppBar(
        title: const Trans("Qcc 测试网络节点"),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: "列表"),
            Tab(icon: Icon(Icons.map), text: "地图"),
            Tab(icon: Icon(Icons.leaderboard), text: "生产集群"),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tabController.index != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 网络摘要：高度 + 当前出块者 + 视图一致性
                  Text(
                    "网络高度 ${tip > 0 ? tip : '—'}",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.bolt, size: 14, color: Colors.amber.shade800),
                      const SizedBox(width: 2),
                      Expanded(
                        child: GestureDetector(
                          onLongPress: net.nowProducerId == null
                              ? null
                              : () => _copyText(net.nowProducerId!, "nodeId"),
                          child: Text(
                            "当前出块 ${net.nowProducerIp == null ? '—' : IpUtils.displayIp(net.nowProducerIp!)}"
                                "${net.nowProducerId == null ? '' : ' · ${shortNodeId(net.nowProducerId!)}'}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _statChip("同步在线", online(syncs), syncs.length, Colors.teal),
                      _statChip("本机可直连", direct, allNodes.length, Colors.indigo),
                      if (mgr.clientOffline)
                        _infoChip("本机网络异常", Colors.red)
                      else if (mgr.clientV6 == QccClientV6.no)
                        _infoChip("本机无 IPv6", Colors.blueGrey),
                      if (unknowns.isNotEmpty)
                        _statChip("未识别", online(unknowns), unknowns.length,
                            Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<_NodeFilter>(
                        segments: const [
                          ButtonSegment(value: _NodeFilter.all, label: Text("全部")),
                          ButtonSegment(value: _NodeFilter.sync, label: Text("同步")),
                        ],
                        selected: {_filter},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) =>
                            setState(() => _filter = s.first),
                      ),
                      FilterChip(
                        label: const Text("仅在线"),
                        selected: _onlineOnly,
                        onSelected: (v) => setState(() => _onlineOnly = v),
                      ),
                      if (hiddenCount > 0)
                        TextButton.icon(
                          onPressed: _showHiddenNodesSheet,
                          icon: const Icon(Icons.visibility_off, size: 16),
                          label: Text("已隐藏 $hiddenCount"),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(nodes),
                QccNodeMapWidget(nodes: nodes, geoByIp: _geoByIp),
                const QccProducerClusterWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "全部"筛选下在类型切换处插分段标题；其它筛选只有一种类型，不需要标题。
  List<Object> _withSectionHeaders(List<QccNode> nodes) {
    if (_filter != _NodeFilter.all) return nodes;
    final items = <Object>[];
    QccNodeKind? last;
    for (final n in nodes) {
      if (n.kind != last) {
        final group = nodes.where((x) => x.kind == n.kind).toList();
        final on = group.where((x) => x.isOnline).length;
        final title = switch (n.kind) {
          QccNodeKind.producer => "当前出块",
          QccNodeKind.sync => "同步节点",
          QccNodeKind.unknown => "未识别 / 其他链",
        };
        items.add("$title · $on/${group.length} 在线");
        last = n.kind;
      }
      items.add(n);
    }
    return items;
  }

  Widget _buildListTab(List<QccNode> nodes) {
    if (nodes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          // 用 ListView 包一层保留下拉刷新手势
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Text(
                  "暂无符合条件的节点，下拉刷新试试",
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final items = _withSectionHeaders(nodes);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          if (item is String) {
            return Padding(
              padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 14, 4, 6),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildNodeCard(item as QccNode),
          );
        },
      ),
    );
  }

  Widget _buildNodeCard(QccNode n) {
    final ipKey = IpUtils.stripBrackets(n.ip);
    final geo = _geoByIp[ipKey];
    final isV6 = IpUtils.isIPv6(n.ip);
    final displayIp = IpUtils.displayIp(n.ip);
    // 在生产者状态机名单里的节点（质押 ≥1 万），显示积分和名次
    final rank = QccProducerService.rankOf(n.nodeId);

    return Dismissible(
      key: ValueKey(n.ip),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmHide(n),
      onDismissed: (_) => _hideNode(n),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.visibility_off, color: Colors.white),
      ),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          // 当前出块者用琥珀色描边，一眼找到
          side: BorderSide(
            color: n.isNowProducer
                ? Colors.amber.shade600
                : Colors.grey.shade200,
            width: n.isNowProducer ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Text(geo?.flag ?? "🏳️", style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        QccNodeRoleBadge(node: n),
                        if (rank != null) _heatChip(rank),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isV6 ? "IPv6" : "IPv4",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Tooltip(
                            message: n.nodeId.isEmpty
                                ? displayIp
                                : "$displayIp\n${n.nodeId}",
                            child: GestureDetector(
                              onLongPress: () => _copyIp(displayIp),
                              child: Text(
                                displayIp,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                        children: [
                          TextSpan(
                              text:
                              "${geo?.displayName ?? '定位中...'} · 高度 ${n.height < 0 ? '未同步' : n.height}"),
                          // 同步节点常态落后 1，>2 才标橙提醒
                          if (n.lag > 0)
                            TextSpan(
                              text: " · 落后 ${n.lag}",
                              style: n.lag > 2
                                  ? TextStyle(
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w600)
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    // nodeId 行：缩写显示，长按复制完整 nodeId。
                    // IPv6 节点的出口地址（remoteIp）与自报地址不同时一并显示，仅供参考。
                    if (n.nodeId.isNotEmpty || n.hasAltRemote) ...[
                      const SizedBox(height: 2),
                      GestureDetector(
                        onLongPress: n.nodeId.isEmpty
                            ? null
                            : () => _copyText(n.nodeId, "nodeId"),
                        child: Text(
                          [
                            if (n.nodeId.isNotEmpty) shortNodeId(n.nodeId),
                            if (n.hasAltRemote) "出口 ${n.remoteIp}",
                          ].join(" · "),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _latencyColor(n).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 实心点 = 本机可直连；空心点 = 网络在线但本机连不上；灰 = 离线
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: (n.isDirect || !n.isOnline)
                            ? _latencyColor(n)
                            : Colors.transparent,
                        border: Border.all(color: _latencyColor(n), width: 1.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      n.isDirect
                          ? "${n.latencyMs}ms"
                          : (n.isOnline
                          ? QccNodeManager.instance.unreachableReason(n)
                          : "离线"),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _latencyColor(n),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}