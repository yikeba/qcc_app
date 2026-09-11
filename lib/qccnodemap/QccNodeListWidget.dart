import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/qccnodemap/qcc_geo_service.dart';
import 'QccNodeManager.dart';
import '../views/setting/AppTranslator.dart';
import 'QccNodeMapWidget.dart';
/// 列表筛选模式，对应服务端 API 的两种查询语义：
/// - all    → GET /v1/node            （全量，含历史离线节点）
/// - active → GET /v1/node?active=true（仅活跃节点）
///
/// 这个筛选是"列表"和"地图"两个 tab 共用的——切全部/活跃时，地图上的点
/// 也会跟着变，两个 tab 看的是同一份已过滤数据，只是换了个展示方式。
enum _NodeFilter { all, active }

class QccNodeListWidget extends StatefulWidget {
  const QccNodeListWidget({super.key});

  @override
  State<QccNodeListWidget> createState() => _QccNodeListWidgetState();
}

class _QccNodeListWidgetState extends State<QccNodeListWidget>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  _NodeFilter _filter = _NodeFilter.all;
  final Map<String, GeoInfo?> _geoByIp = {};
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    // 【修复】这里以前刷新完还会自己再 await 一次 probeAll()，但
    // refreshNodes() 内部本来就会做一轮探测——两次探测撞在一起时，
    // 后面这次会被 QccNodeManager 的重入保护直接短路、瞬间返回（并
    // 没有真的等到探测结果），导致这里提前认为"刷新完了"，实际探测
    // 结果还没落地就把 loading 关掉、把旧数据渲染出去了，多刷新几次
    // 之后"X/Y 在线"的统计和列表里实际显示的节点就会对不上。现在
    // QccNodeManager.refreshNodes() 已经会老老实实等探测完成再返回，
    // 这里不需要也不应该再重复探测一次。
    await QccNodeManager.instance.refreshNodes(force: true);

    // 并发查地理位置，避免 N 个节点串行等待
    // 用去掉方括号后的地址做 key，和下面 build() 里取值时保持一致，
    // 避免 "[::1]" 与 "::1" 被当成两个不同的 key。
    // 注意这里用全量 nodes（含本地隐藏的），不只是 visibleNodes——
    // 隐藏的节点如果之后自动恢复显示，地理位置缓存已经提前准备好了；
    // 地图 tab 用的经纬度也是从这份缓存里取，不需要单独再查一次。
    final nodes = QccNodeManager.instance.nodes;
    await Future.wait(nodes.map((n) async {
      final key = IpUtils.stripBrackets(n.ip);
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
        // 用 StatefulBuilder 让面板里"恢复"之后能立刻刷新自己，
        // 不用等外层 setState 触发的重建。
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
                              title: Text(IpUtils.displayIp(n.ip)),
                              subtitle: Text("高度 ${n.height}"),
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

  Color _latencyColor(QccNode n) {
    if (!n.reachable) return Colors.grey;
    if (n.latencyMs < 150) return Colors.green;
    if (n.latencyMs < 400) return Colors.orange;
    return Colors.red;
  }

  /// 按当前选中的筛选模式过滤 + 排序节点，对应服务端 API 的两种视图：
  ///
  /// - 全部（对应不带参数的 GET /v1/node）：不过滤，排序保持原来的规则——
  ///   在线（reachable && active）排前面，离线排后面；同为在线时按延迟从
  ///   低到高排；延迟也相同（或同为离线）时按原始顺序，不然 List.sort
  ///   不保证稳定，离线节点之间会在每次刷新时顺序乱跳。
  ///
  /// - 活跃（对应 GET /v1/node?active=true）：只保留 active == true 的
  ///   节点。但光看 active 不够——active 是节点自己上报、来自 /v1/qccnode
  ///   返回的"最近有心跳"状态，是它对自己的判断，可能过时或者跟本地探测
  ///   结果对不上（比如节点自己觉得在线，但客户端这边实际连不通；节点刚
  ///   启动时，各节点看到的即时状态本来也会有几秒的不一致）。本地已经对
  ///   每个节点做过真实探测（probeAll → reachable/latencyMs），这份判断
  ///   更可信，所以活跃 tab 额外叠加 reachable 条件：本地探测显示离线的
  ///   节点，即使自称 active，也不算进"活跃"里。
  ///   这里直接用本地已缓存的数据过滤，不需要额外再发一次带参数的请求。
  ///   活跃列表按 height 从高到低排——height 越高（区块越新）排越前面；
  ///   height 相同时按延迟从低到高；最后按原始顺序兜底，保证稳定排序。
  List<QccNode> _filterAndSort(List<QccNode> nodes, _NodeFilter filter) {
    final base = filter == _NodeFilter.active
        ? nodes.where((n) => n.active && n.reachable).toList()
        : nodes;

    final indexed = base.asMap().entries.toList();
    indexed.sort((a, b) {
      if (filter == _NodeFilter.active) {
        final heightCmp = b.value.height.compareTo(a.value.height); // 高度越高越靠前
        if (heightCmp != 0) return heightCmp;
        final latencyCmp = a.value.latencyMs.compareTo(b.value.latencyMs);
        if (latencyCmp != 0) return latencyCmp;
        return a.key.compareTo(b.key);
      } else {
        final aOnline = a.value.reachable && a.value.active;
        final bOnline = b.value.reachable && b.value.active;
        if (aOnline != bOnline) return aOnline ? -1 : 1;
        final latencyCmp = a.value.latencyMs.compareTo(b.value.latencyMs);
        if (latencyCmp != 0) return latencyCmp;
        return a.key.compareTo(b.key);
      }
    });
    return indexed.map((e) => e.value).toList();
  }

  void _copyIp(String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("已复制：$ip"), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // allNodes：本地手动隐藏的节点已被排除，用于顶部“X / Y 在线”整体统计
    // （不随筛选 tab 变化，方便用户随时看到整体网络健康状况）。
    // nodes：按当前筛选模式过滤 + 排序后的节点——列表 tab 和地图 tab
    // 共用同一份，切"全部/活跃"时两个 tab 会同步变化。
    final allNodes = QccNodeManager.instance.visibleNodes;
    final nodes = _filterAndSort(allNodes, _filter);
    final onlineCount = allNodes.where((n) => n.reachable && n.active).length;
    final hiddenCount = QccNodeManager.instance.hiddenNodes.length;

    return Scaffold(
      appBar: AppBar(
        title: const Trans("Qcc 测试网络节点"), // 假设 Trans 是你的翻译组件
        actions: [
          // 刷新按钮挪到 AppBar 上：列表/地图两个 tab 共用，不用各自再放一个。
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
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "节点状态  $onlineCount / ${allNodes.length} 在线",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 全部 / 活跃 切换：对应 API 的两种查询语义（见 _filterAndSort 注释）。
                    // 列表和地图 tab 共用这一个筛选。
                    SegmentedButton<_NodeFilter>(
                      segments: const [
                        ButtonSegment(
                          value: _NodeFilter.all,
                          label: Text("全部"),
                          icon: Icon(Icons.list_alt, size: 16),
                        ),
                        ButtonSegment(
                          value: _NodeFilter.active,
                          label: Text("活跃"),
                          icon: Icon(Icons.bolt, size: 16),
                        ),
                      ],
                      selected: {_filter},
                      showSelectedIcon: false,
                      onSelectionChanged: (selected) {
                        setState(() => _filter = selected.first);
                      },
                    ),
                    // 隐藏节点入口：只有存在隐藏节点时才显示，避免界面常驻一个
                    // 用不上的按钮。点开是一个可以手动"恢复"的列表。
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListTab(List<QccNode> nodes) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: nodes.isEmpty
          ? ListView(
        // 用 ListView 包一层（而不是直接 Center）是为了保留
        // 下拉刷新手势——活跃列表暂时为空时，用户仍然可以
        // 下拉重新探测，不然空状态下 RefreshIndicator 收不到
        // 手势会显得像是"卡住了"。
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Text(
                _filter == _NodeFilter.active
                    ? "暂无活跃节点，下拉刷新试试"
                    : "暂无节点数据，下拉刷新试试",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      )
          : ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: nodes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final n = nodes[i];
          final ipKey = IpUtils.stripBrackets(n.ip);
          final geo = _geoByIp[ipKey];
          final isV6 = IpUtils.isIPv6(n.ip);
          final displayIp = IpUtils.displayIp(n.ip);
          // 左滑可以本地隐藏这个节点（删掉过期不用的节点，不影响
          // 后台继续探测——它恢复可达后会自动重新显示，见
          // QccNodeManager._doProbeAll）。用节点 ip 做 key，
          // 保证同一个节点在列表重排后依然对应同一个 Dismissible。
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Text(
                      geo?.flag ?? "🏳️",
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // IPv4 / IPv6 角标：一眼区分节点地址类型
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: (isV6 ? Colors.blue : Colors.teal)
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isV6 ? "IPv6" : "IPv4",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isV6
                                        ? Colors.blue.shade700
                                        : Colors.teal.shade700,
                                  ),
                                ),
                              ),
                              // IPv6 地址可能很长且没有空格断点，这里单行显示 +
                              // 省略号，用 Tooltip 展示完整地址、长按复制。
                              Expanded(
                                child: Tooltip(
                                  message: displayIp,
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
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              children: [
                                TextSpan(
                                    text:
                                    "${geo?.displayName ?? '定位中...'} · 高度 "),
                                // 活跃 tab 下，高度是排序依据，加粗突出显示。
                                TextSpan(
                                  text: "${n.height}",
                                  style: _filter == _NodeFilter.active
                                      ? const TextStyle(
                                      fontWeight: FontWeight.w700)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _latencyColor(n).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _latencyColor(n),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            n.reachable ? "${n.latencyMs}ms" : "离线",
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
        },
      ),
    );
  }
}