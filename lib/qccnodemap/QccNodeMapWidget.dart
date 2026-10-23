import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'QccNodeManager.dart';
import 'qcc_geo_service.dart';

/// nodeId 缩写：Qcc 地址 34 位，展示首 6 + 尾 6，完整值靠复制/tooltip。
String shortNodeId(String id) =>
    id.length > 16 ? "${id.substring(0, 6)}…${id.substring(id.length - 6)}" : id;

/// 节点角色角标：列表页和地图详情面板共用。
/// 出块中（当前生产者）> 生产 > 同步 > 未识别。
class QccNodeRoleBadge extends StatelessWidget {
  final QccNode node;
  const QccNodeRoleBadge({super.key, required this.node});

  static Color colorOf(QccNode n) {
    if (n.foreign) return Colors.deepOrange;
    if (n.isNowProducer) return Colors.amber.shade800;
    switch (n.kind) {
      case QccNodeKind.producer:
        return Colors.indigo;
      case QccNodeKind.sync:
        return Colors.teal;
      case QccNodeKind.unknown:
        return Colors.grey;
    }
  }

  static String labelOf(QccNode n) {
    if (n.foreign) return "其他链";
    if (n.isNowProducer) return "出块中";
    switch (n.kind) {
      case QccNodeKind.producer:
        return "生产";
      case QccNodeKind.sync:
        return "同步";
      case QccNodeKind.unknown:
        return "未识别";
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colorOf(node);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (node.isNowProducer)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.bolt, size: 11, color: c),
            ),
          Text(
            labelOf(node),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

/// 按"城市"把节点聚合成一个点（经纬度保留 1 位小数，约 11km 一格）。
/// 生产/同步区分：
/// - 格子里有生产者 → 圆角方块；含当前出块者 → 琥珀色粗边框
/// - 只有同步节点   → 圆形
/// - 全部离线       → 灰色
/// 另外按同步节点的 upstreamIps 画"同步节点 → 所挂生产者"的连线，
/// 直接看出每个生产者带了哪些同步节点、分布在哪。
class _CityGroup {
  final String label;
  final latlong.LatLng point;
  final List<QccNode> nodes = [];

  _CityGroup({required this.label, required this.point});

  int get onlineCount => nodes.where((n) => n.isOnline).length;
  int get directCount => nodes.where((n) => n.isOnline && n.isDirect).length;
  int get producerCount => nodes.where((n) => n.isProducer).length;
  int get syncCount => nodes.where((n) => n.isSync).length;
  bool get hasNowProducer => nodes.any((n) => n.isNowProducer);
}

class QccNodeMapWidget extends StatelessWidget {
  /// 已按当前筛选（全部/生产/同步、仅在线）过滤好的节点列表，跟列表 tab 同一份。
  final List<QccNode> nodes;

  /// 复用列表页已查好的地理位置缓存（key 是去掉方括号后的地址）。
  final Map<String, GeoInfo?> geoByIp;

  const QccNodeMapWidget({
    super.key,
    required this.nodes,
    required this.geoByIp,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, _CityGroup>{};
    final groupKeyByIp = <String, String>{};

    for (final n in nodes) {
      final geo = geoByIp[IpUtils.stripBrackets(n.ip)];
      if (geo == null || !geo.hasLocation) continue; // 本地网络/没查到，跳过
      final key =
          "${geo.latitude!.toStringAsFixed(1)}_${geo.longitude!.toStringAsFixed(1)}";
      groups
          .putIfAbsent(
        key,
            () => _CityGroup(
          label: geo.displayName,
          point: latlong.LatLng(geo.latitude!, geo.longitude!),
        ),
      )
          .nodes
          .add(n);
      groupKeyByIp[n.ip] = key;
    }

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "暂无节点定位信息，请稍等或下拉刷新列表页试试",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final lines = _buildUpstreamLines(groups, groupKeyByIp);
    final center = groups.values
        .firstWhere((g) => g.hasNowProducer, orElse: () => groups.values.first)
        .point;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 2,
        minZoom: 1.5,
        maxZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.qcc.qcc_flutter',
          maxZoom: 19,
        ),
        if (lines.isNotEmpty) PolylineLayer(polylines: lines),
        MarkerLayer(
          markers: groups.values.map((g) => _buildMarker(context, g)).toList(),
        ),
        const Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: _MapLegend(),
          ),
        ),
        RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  /// 同步节点 → 上游生产者 的连线，按城市对去重。
  /// 两端必须都在当前筛选结果里（比如切到"同步"筛选时生产者不在，就不画线）。
  /// 跨 180° 经线的连线会走"远的那一边"，节点少时不处理。
  List<Polyline> _buildUpstreamLines(
      Map<String, _CityGroup> groups, Map<String, String> groupKeyByIp) {
    final byIp = {for (final n in nodes) n.ip: n};
    final drawn = <String, bool>{}; // 城市对 → 是否有在线链路
    for (final n in nodes) {
      if (!n.isSync) continue;
      final from = groupKeyByIp[n.ip];
      if (from == null) continue;
      for (final up in n.upstreamIps) {
        final upNode = byIp[up];
        final to = groupKeyByIp[up];
        if (upNode == null || to == null || to == from) continue;
        final pair = from.compareTo(to) < 0 ? "$from|$to" : "$to|$from";
        final online = n.isOnline && upNode.isOnline;
        drawn[pair] = (drawn[pair] ?? false) || online;
      }
    }
    return drawn.entries.map((e) {
      final ends = e.key.split('|');
      return Polyline(
        points: [groups[ends[0]]!.point, groups[ends[1]]!.point],
        color: e.value
            ? Colors.indigo.withOpacity(0.5)
            : Colors.grey.withOpacity(0.35),
        strokeWidth: 1.6,
      );
    }).toList();
  }

  Marker _buildMarker(BuildContext context, _CityGroup g) {
    final hasOnline = g.onlineCount > 0;
    final isProducerSite = g.producerCount > 0;
    final Color base = !hasOnline
        ? Colors.grey
        : (isProducerSite ? Colors.indigo : Colors.teal);
    // 网络在线、但这个城市没有一个节点本机能直连（典型：在无 IPv6 的地方看
    // IPv6 家庭节点）→ 空心标记：节点是活的，只是本机路由不通，不画成离线。
    final hollow = hasOnline && g.directCount == 0;
    final Color fill = hollow ? Colors.white : base;
    final Color textColor = hollow ? base : Colors.white;
    final countText = g.nodes.length > 99 ? "99+" : "${g.nodes.length}";

    return Marker(
      point: g.point,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _showCitySheet(context, g),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            shape: isProducerSite ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isProducerSite ? BorderRadius.circular(10) : null,
            border: Border.all(
              color: g.hasNowProducer
                  ? Colors.amber.shade600
                  : (hollow ? base : Colors.white),
              width: g.hasNowProducer ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            countText,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _showCitySheet(BuildContext context, _CityGroup g) {
    // 详情里：当前出块者 → 生产者 → 同步节点；同类在线优先、高度降序
    int rank(QccNode n) => n.isNowProducer ? 0 : (n.isProducer ? 1 : (n.isSync ? 2 : 3));
    final sorted = List<QccNode>.from(g.nodes)
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return b.height.compareTo(a.height);
      });

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${g.label} · ${g.nodes.length} 个节点（${g.onlineCount} 在线）",
                style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                g.hasNowProducer
                    ? "含当前出块节点 · 同步 ${g.syncCount}"
                    : "同步 ${g.syncCount}",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final n = sorted[i];
                    final parts = <String>[];
                    if (n.nodeId.isNotEmpty) parts.add(shortNodeId(n.nodeId));
                    parts.add("高度 ${n.height}");
                    if (n.lag > 0) parts.add("落后 ${n.lag}");
                    parts.add(n.isDirect
                        ? "${n.latencyMs}ms"
                        : (n.isOnline
                        ? QccNodeManager.instance.unreachableReason(n)
                        : "离线"));
                    if (n.hasAltRemote) parts.add("出口 ${n.remoteIp}");
                    if (n.isSync && n.upstreamIps.isNotEmpty) {
                      parts.add(
                          "上游 ${n.upstreamIps.map(IpUtils.displayIp).join(', ')}");
                    }
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      // 实心绿 = 可直连；空心 = 网络在线但本机连不上；灰 = 离线
                      leading: Icon(
                        n.isOnline && !n.isDirect
                            ? Icons.circle_outlined
                            : Icons.circle,
                        size: 10,
                        color: !n.isOnline
                            ? Colors.grey
                            : (n.isDirect ? Colors.green : Colors.blueGrey),
                      ),
                      title: Row(
                        children: [
                          QccNodeRoleBadge(node: n),
                          Expanded(
                            child: Text(
                              IpUtils.displayIp(n.ip),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(parts.join(" · ")),
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
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  Widget _row(Widget icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, height: 16, child: icon),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  Widget _shape(Color c, {bool square = false, Color? border}) => Container(
    decoration: BoxDecoration(
      color: c,
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(4) : null,
      border: border == null ? null : Border.all(color: border, width: 2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(_shape(Colors.indigo, square: true, border: Colors.amber.shade600),
              "当前出块"),
          _row(_shape(Colors.teal), "同步节点"),
          _row(_shape(Colors.white, border: Colors.teal), "在线·本机不可直连"),
          _row(_shape(Colors.grey), "离线"),
        ],
      ),
    );
  }
}