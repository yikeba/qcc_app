import 'dart:convert';
import 'package:http/http.dart' as http;

/// IPv4 / IPv6 相关的小工具函数。
///
/// 从 QccNodeListWidget.dart 挪到这个单独的文件里：这个文件里的地理位置查询
/// 逻辑现在同时给列表页（QccNodeListWidget）和地图页（QccNodeMapWidget）用，
/// 两个页面是不同的 Dart 文件，Dart 里带下划线前缀的类只能在同一个文件内可见，
/// 所以把公用的部分单独拆出来、去掉下划线前缀，两边 import 这一个文件即可，
/// 不用互相复制一份、也不用互相 import 对方的私有类。
///
/// 说明：为了不引入 dart:io（Flutter Web 上不可用），这里用简单的字符串/正则判断，
/// 没有做完整的 RFC 4291 校验，只覆盖列表展示 & GeoIP 查询所需的场景：
/// 1. 识别 IPv6（含 "::" 简写、全展开、IPv4 映射地址 ::ffff:a.b.c.d 等）。
/// 2. 去掉 "[ip]:port" 或 "[ip]" 这种带方括号的写法，取出纯地址部分。
/// 3. 判断是否是回环 / 链路本地 / 唯一本地(ULA) / 私网地址——这类地址查公网 GeoIP
///    没有意义（会一直超时或返回失败），直接标记为"本地网络"，不用发请求。
class IpUtils {
  /// 形如 "[2001:db8::1]" 或 "[2001:db8::1]:8080" 时，取出方括号内的地址；
  /// 否则原样返回（去掉首尾空白）。
  static String stripBrackets(String ip) {
    final trimmed = ip.trim();
    final m = RegExp(r'^\[([^\]]+)\]').firstMatch(trimmed);
    return m != null ? m.group(1)! : trimmed;
  }

  static bool isIPv6(String ip) => stripBrackets(ip).contains(':');

  /// 展示用：过长的 IPv6 地址不做处理，交给 UI 层用省略号 + 长按复制解决；
  /// 这里只是统一去掉可能残留的方括号，避免列表里出现 "[::1]" 这种半成品。
  static String displayIp(String ip) => stripBrackets(ip);

  static bool _isIPv4Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      nums.add(n);
    }
    if (nums[0] == 127) return true; // 127.0.0.0/8 回环
    if (nums[0] == 10) return true; // 10.0.0.0/8
    if (nums[0] == 192 && nums[1] == 168) return true; // 192.168.0.0/16
    if (nums[0] == 172 && nums[1] >= 16 && nums[1] <= 31) return true; // 172.16.0.0/12
    if (nums[0] == 169 && nums[1] == 254) return true; // 169.254.0.0/16 链路本地
    return false;
  }

  /// 回环 / 链路本地(fe80::/10) / 唯一本地地址(fc00::/7) / IPv4 映射地址等。
  static bool _isIPv6Local(String ip) {
    final lower = ip.toLowerCase();
    if (lower == '::1') return true; // 回环
    if (lower.startsWith('fe80:') || lower.startsWith('fe80::')) return true; // 链路本地
    if (lower.startsWith('fc') || lower.startsWith('fd')) return true; // fc00::/7 唯一本地
    // IPv4 映射/兼容地址（::ffff:a.b.c.d、::a.b.c.d）：按内嵌的 IPv4 判断
    final v4Embedded = RegExp(r'(?:^::ffff:|^::)(\d{1,3}(?:\.\d{1,3}){3})$')
        .firstMatch(lower);
    if (v4Embedded != null) return _isIPv4Private(v4Embedded.group(1)!);
    return false;
  }

  /// 是否是无需（也不该）查公网 GeoIP 的本地/私网地址。
  static bool isLocalOrPrivate(String ip) {
    final addr = stripBrackets(ip);
    return addr.contains(':') ? _isIPv6Local(addr) : _isIPv4Private(addr);
  }
}

/// IP -> 地理位置 的查询与缓存。
///
/// 假设：用 https://ipwho.is/{ip} 做地理位置查询——免费、走 HTTPS、不需要 key，
/// 但有速率限制（免费额度约每月 1 万次），如果你们节点数会扩到几十上百个，
/// 或者对第三方出网有合规顾虑（IP 信息发给了第三方服务商），建议换成自建的
/// GeoIP 库（比如内置 MaxMind GeoLite2 数据库离线查）而不是每次都调外部接口。
/// 这里做了内存缓存，同一个 IP 只查一次。
///
/// IPv6 支持说明：ipwho.is 本身同时支持 IPv4 / IPv6 查询，这里做了两点适配：
/// 1. 用 Uri(pathSegments: ...) 而不是手工拼字符串来生成请求地址，避免 IPv6
///    地址里的 "::" 在字符串拼接时被误处理；
/// 2. 回环 / 链路本地 / 唯一本地(ULA) / 私网 等地址直接判为"本地网络"，不发请求
///    （这类地址查公网 GeoIP 库本来就查不到，还会浪费一次限额、多等一次超时）。
///
/// 【新增】除了国家信息，这里额外解析 city / latitude / longitude——
/// 列表页不需要这两个字段，用不用无所谓；地图页（QccNodeMapWidget）需要
/// 经纬度才能把节点标在地图城市位置上，所以顺手在这一次请求里带出来，
/// 不需要再为地图单独多发一次请求。
class GeoService {
  static final Map<String, GeoInfo?> _cache = {};

  static const _localInfo = GeoInfo(
    countryCode: '',
    countryName: '本地网络',
    isLocal: true,
  );

  static Future<GeoInfo?> lookup(String rawIp) async {
    final ip = IpUtils.stripBrackets(rawIp);
    if (_cache.containsKey(ip)) return _cache[ip];

    if (IpUtils.isLocalOrPrivate(ip)) {
      _cache[ip] = _localInfo;
      return _localInfo;
    }

    try {
      final uri = Uri(
        scheme: 'https',
        host: 'ipwho.is',
        pathSegments: [ip],
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['success'] == true) {
          final info = GeoInfo(
            countryCode: (data['country_code'] ?? '') as String,
            countryName: (data['country'] ?? '未知') as String,
            city: data['city'] as String?,
            latitude: (data['latitude'] as num?)?.toDouble(),
            longitude: (data['longitude'] as num?)?.toDouble(),
          );
          _cache[ip] = info;
          return info;
        }
      }
    } catch (_) {}
    _cache[ip] = null;
    return null;
  }
}

class GeoInfo {
  final String countryCode; // 例如 "US"
  final String countryName; // 例如 "United States"
  final bool isLocal;
  final String? city; // 例如 "Los Angeles"；本地网络/查询失败时为 null
  final double? latitude; // 地图标点用；本地网络/查询失败时为 null
  final double? longitude;

  const GeoInfo({
    required this.countryCode,
    required this.countryName,
    this.isLocal = false,
    this.city,
    this.latitude,
    this.longitude,
  });

  /// 是否有可用于地图标点的经纬度（本地网络/查询失败都没有，地图上跳过不画）。
  bool get hasLocation => latitude != null && longitude != null;

  /// ISO 国家代码转国旗 emoji（区域指示符号 Unicode 技巧，不需要图片资源）
  /// 注意：部分低版本 Android / 部分 OEM 字体不渲染国旗 emoji，会显示成两个字母，
  /// 如果你们目标用户里这类机型占比高，建议换成打包的国旗图片资源而不是 emoji。
  String get flag {
    if (isLocal) return "🏠";
    if (countryCode.length != 2) return "🏳️";
    final base = 0x1F1E6;
    final chars = countryCode.toUpperCase().codeUnits
        .map((c) => base + (c - 'A'.codeUnitAt(0)));
    return String.fromCharCodes(chars);
  }

  /// 展示用地名："城市, 国家"；city 缺失时（比如没查到、或就是没有该字段）
  /// 退化成只显示国家名，供地图气泡/详情面板使用。
  String get displayName =>
      (city == null || city!.isEmpty) ? countryName : "$city, $countryName";
}
