import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'QccNodeManager.dart';
import 'qcc_geo_service.dart';

/// 按"城市"把节点聚合成一个点：同一个城市（GeoService 查询给出的经纬度，
/// 四舍五入到约 11km 精度后落在同一格）无论有多少个节点，地图上只画一个
/// 标记，标记上直接显示节点数量；点开看这个城市具体有哪些节点、在线情况。
///
/// 为什么按城市分组、而不是接一个按屏幕距离动态聚合的 marker cluster 插件：
/// 一是不用再多引入一个包、多担心版本兼容；二是节点的 GeoIP 定位本来就是
/// "城市"粒度（不是精确门牌号），同一城市的多个节点本来经纬度就相同，天然
/// 会落在同一个点上——按城市分组已经能覆盖"未来节点非常多"的场景。如果
/// 以后同一个城市也堆到几十上百个、觉得气泡数字不够看，可以再引入
/// flutter_map_marker_cluster 做屏幕距离聚合，跟这里的城市分组不冲突，
/// 到时候把 MarkerLayer 换成 MarkerClusterLayerWidget 就行。
class _CityGroup {
  final String label; // 例如 "Los Angeles, United States"
  final latlong.LatLng point;
  final List<QccNode> nodes;

  _CityGroup({required this.label, required this.point, required this.nodes});

  int get onlineCount => nodes.where((n) => n.reachable && n.active).length;
}

class QccNodeMapWidget extends StatelessWidget {
  /// 已经按当前筛选模式（全部/活跃）过滤好的节点列表——地图跟列表看的是
  /// 同一份数据，切"全部/活跃"时地图上的点也会跟着变。
  final List<QccNode> nodes;

  /// 复用 QccNodeListWidget 里已经查好的地理位置缓存（key 是去掉方括号后的
  /// 地址），避免地图页再对同一批 IP 重新查一次地理位置接口。
  final Map<String, GeoInfo?> geoByIp;

  const QccNodeMapWidget({
    super.key,
    required this.nodes,
    required this.geoByIp,
  });

  List<_CityGroup> _groupByCity() {
    final Map<String, _CityGroup> groups = {};
    for (final n in nodes) {
      final key = IpUtils.stripBrackets(n.ip);
      final geo = geoByIp[key];
      if (geo == null || !geo.hasLocation) continue; // 本地网络/还没查到/查询失败，跳过不画

      final point = latlong.LatLng(geo.latitude!, geo.longitude!);
      // 分组 key：经纬度保留 1 位小数（约 11km），同一城市的节点几乎总会
      // 落进同一格；理论上两个不同城市可能巧合落进同一格，概率很低，暂不处理。
      final groupKey =
          "${geo.latitude!.toStringAsFixed(1)}_${geo.longitude!.toStringAsFixed(1)}";

      final existing = groups[groupKey];
      if (existing != null) {
        existing.nodes.add(n);
      } else {
        groups[groupKey] =
            _CityGroup(label: geo.displayName, point: point, nodes: [n]);
      }
    }
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByCity();

    if (groups.isEmpty) {
      // 地理位置查询是异步的（GeoService.lookup），刚打开地图 tab 时经常会
      // 命中这个空态；提示语指向"稍等/下拉刷新"，别让人以为地图坏了。
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

    return FlutterMap(
      options: MapOptions(
        initialCenter: groups.first.point,
        initialZoom: 2,
        minZoom: 1.5,
        maxZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // OSM 公共瓦片服务的使用政策要求带上能识别应用的 User-Agent，
          // 换成你们真实的包名（跟 AndroidManifest.xml / Info.plist 里的一致）。
          // 节点数/用户量大了之后，公共瓦片服务器可能会限流，到时候考虑换成
          // 付费瓦片服务（Mapbox / MapTiler 等）或自建瓦片服务器。
          userAgentPackageName: 'com.qcc.qcc_flutter',
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: groups.map((g) => _buildMarker(context, g)).toList(),
        ),
        // OSM 的瓦片使用政策要求在地图上保留可见的版权归属文字，这个不能删；
        // 但 RichAttributionWidget 默认还会额外显示 flutter_map 自己的 logo
        // 图标（跟 OSM 版权无关，纯粹是这个库自己的品牌展示），有些工程的
        // 资源打包方式下找不到那张图会直接抛 "Unable to load asset" 异常。
        // 这里显式关掉，只保留真正必须的文字版权。
        RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  Marker _buildMarker(BuildContext context, _CityGroup g) {
    final hasOnline = g.onlineCount > 0;
    final color = hasOnline ? Colors.green : Colors.grey;
    // 节点数超过 2 位数时气泡撑不下，简单截断成 "99+"，避免文字溢出气泡。
    final countText = g.nodes.length > 99 ? "99+" : "${g.nodes.length}";

    return Marker(
      point: g.point,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _showCitySheet(context, g),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
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
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _showCitySheet(BuildContext context, _CityGroup g) {
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
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: g.nodes.length,
                  itemBuilder: (_, i) {
                    final n = g.nodes[i];
                    final online = n.reachable && n.active;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.circle,
                        size: 10,
                        color: online ? Colors.green : Colors.grey,
                      ),
                      title: Text(IpUtils.displayIp(n.ip)),
                      subtitle: Text("高度 ${n.height}"
                          "${n.reachable ? ' · ${n.latencyMs}ms' : ' · 离线'}"),
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