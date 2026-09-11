import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../utile/QccStorage.dart';
import '../../utile/LogObj.dart';
import '../../home/QccExplorerService.dart';
import 'QccAsset.dart';

class QccAssetService {
  // ✅ 1. 定义私有静态实例
  static final QccAssetService _instance = QccAssetService._internal();

  // ✅ 2. 工厂构造函数，返回唯一实例
  factory QccAssetService() => _instance;

  // ✅ 3. 私有构造函数
  QccAssetService._internal();

  static String baseUrl = "${QccExplorerService.baseUrl}/v1";
  static const String _followKey = "followed_asset_objects_v2";

  // ✅ 4. 实例成员：保存关注的完整资产对象
  List<QccAsset> followAsset = [];
  bool _isInitialized = false;

  /// ✅ 唯一实例初始化方法
  /// 余额组件启动时调用：await QccAssetService().initFollowAssets();
  Future<void> initFollowAssets() async {
    if (_isInitialized) return; // 防止重复初始化

    try {
      // 这里的 getStringListAsync 是基于 SharedPreferences 的异步读取
      List<String>? jsonList = await QccStorage.getStringListAsync(_followKey);

      if (jsonList != null && jsonList.isNotEmpty) {
        followAsset = jsonList.map((s) => QccAsset.fromJson(jsonDecode(s))).toList();
        LogObj.log("✅ [Service] 唯一实例已从本地恢复 ${followAsset.length} 个资产");
      } else {
        // 默认关注主币 QCC
        followAsset = [
          QccAsset(assetId: 'QCC', type: 'COIN', precision: 9, isFollowing: true,address: 'Q9999...')
        ];
        await saveFollowStatus(followAsset);
      }
      _isInitialized = true;
    } catch (e) {
      LogObj.log("❌ [Service] 初始化失败: $e");
    }
  }

  /// ✅ 存储资产对象数组
  Future<void> saveFollowStatus(List<QccAsset> allAssets) async {
    // 过滤出已关注的
    followAsset = allAssets.where((a) => a.isFollowing).toList();

    // 序列化
    List<String> jsonList = followAsset.map((a) => jsonEncode(a.toJson())).toList();

    LogObj.log("💾 [Service] 正在同步本地存储，数量: ${jsonList.length}");
    await QccStorage.saveStringList(_followKey, jsonList);
  }


  /// ✅ 核心转换方法：将人类可读金额转换为 QCC 状态机识别的 int (Java long)
  /// [assetId] 资产代码（如 USDA）
  /// [humanAmount] 用户输入的金额（支持 String, double, num）
  int getAmountRaw(String assetId, dynamic humanAmount) {
    // 1. 从关注列表中查找该资产对象
    final asset = followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      // 兜底：如果未关注，默认按 9 位精度处理（即 10^8）
      orElse: () => QccAsset(assetId: assetId, type: 'COIN', precision: 9, isFollowing: true,address: 'Q9999...'),
    );

    // 2. 解析输入金额为 double
    double amount = 0.0;
    if (humanAmount is String) {
      amount = double.tryParse(humanAmount) ?? 0.0;
    } else if (humanAmount is num) {
      amount = humanAmount.toDouble();
    }

    // 3. ✅ 核心修正逻辑：
    // 如果 precision 为 4，乘数是 1000 (10^3)
    // 如果 precision 为 9，乘数是 100,000,000 (10^8)
    // 公式：multiplier = 10 ^ (precision - 1)
    int exponent = asset.precision;
    if (exponent < 0) exponent = 0; // 安全保护

    num multiplier = pow(10, exponent);

    LogObj.log("计算转账金额 - 资产: $assetId, 精度设定: ${asset.precision}, 乘数: ${multiplier.toInt()}");

    // 4. 执行计算并四舍五入，最后转为 int (Java long)
    // 使用 round() 处理 1.1 * 1000 这种浮点数微差，确保转为最接近的整数
    return (amount * multiplier).round().toInt();
  }


  /// ✅ 核心转换方法：将 QCC 状态机识别的 int (原始金额) 转换为人类可读金额
  /// [assetId] 资产代码（用于查找精度）
  /// [rawAmount] 原始金额（Java long / Dart int）
  /// [showFull] 是否显示全量不限制小数位的字符串，默认 false（会进行格式化）
  String getHumanAmount(String assetId, dynamic rawAmount, {bool showFull = false}) {
    // 1. 获取资产对象以确定精度
    // 逻辑参考你提供的 getAmountRaw 逻辑
    final asset = followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      // 兜底：如果未找到，默认按 9 位精度处理
      orElse: () => QccAsset(assetId: assetId, type: 'COIN', precision: 9, isFollowing: true,address: 'Q9999...'),
    );

    if (rawAmount == null) return "0";

    // 2. 转换输入值为 BigInt 或 double 处理
    num amountValue = 0;
    if (rawAmount is String) {
      amountValue = num.tryParse(rawAmount) ?? 0;
    } else if (rawAmount is num) {
      amountValue = rawAmount;
    }
    // 3. 计算除数 (10 ^ precision)
    // 注意：你之前的 multiplier 逻辑是 pow(10, precision)，这里保持一致
    num divider = pow(10, asset.precision);
    // 4. 执行除法
    double result = amountValue / divider;
    return result.toStringAsFixed(asset.precision).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");

  }


  /// ✅ 核心转换方法：将 QCC 状态机识别的 int (原始金额) 转换为人类可读金额
  /// [assetId] 资产代码（用于查找精度）
  /// [rawAmount] 原始金额（Java long / Dart int）
  /// [showFull] 是否显示全量不限制小数位的字符串，默认 false（会进行格式化）
  double getHumanAmountNum(String assetId, dynamic rawAmount, {bool showFull = false}) {
    // 1. 获取资产对象以确定精度
    // 逻辑参考你提供的 getAmountRaw 逻辑
    final asset = followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      // 兜底：如果未找到，默认按 9 位精度处理
      orElse: () => QccAsset(assetId: assetId, type: 'COIN', precision: 9, isFollowing: true,address: 'Q9999...'),
    );

    if (rawAmount == null) return 0;
    // 2. 转换输入值为 BigInt 或 double 处理
    num amountValue = 0;
    if (rawAmount is String) {
      amountValue = num.tryParse(rawAmount) ?? 0;
    } else if (rawAmount is num) {
      amountValue = rawAmount;
    }
    // 3. 计算除数 (10 ^ precision)
    // 注意：你之前的 multiplier 逻辑是 pow(10, precision)，这里保持一致
    num divider = pow(10, asset.precision);
    // 4. 执行除法
    double result = amountValue / divider;
    return result;

  }

  int getAmountString(String assetId, dynamic humanAmount) {
    // 1. 从关注列表中查找该资产对象
    final asset = followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      // 兜底：如果未关注，默认按 9 位精度处理（即 10^8）
      orElse: () => QccAsset(assetId: assetId, type: 'COIN', precision: 9, isFollowing: true, address: 'Q9999...'),
    );
    // 2. 解析输入金额为 double
    double amount = 0.0;
    if (humanAmount is String) {
      amount = double.tryParse(humanAmount) ?? 0.0;
    } else if (humanAmount is num) {
      amount = humanAmount.toDouble();
    }
    int exponent = asset.precision;
    if (exponent < 0) exponent = 0; // 安全保护
    num multiplier = pow(10, exponent);

    LogObj.log("计算转账金额 - 资产: $assetId, 精度设定: ${asset.precision}, 乘数: ${multiplier.toInt()}");
    // 4. 执行计算并四舍五入，最后转为 int (Java long)
    // 使用 round() 处理 1.1 * 1000 这种浮点数微差，确保转为最接近的整数
    return (amount / multiplier).round().toInt();
  }


  /// 获取全量资产并同步关注状态
  Future<List<QccAsset>> fetchStablecoinAssets() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/asset"));
      if (response.statusCode == 200) {
        final Map<String, dynamic> raw = jsonDecode(response.body);
        if (raw['ok'] == true && raw['data'] != null) {
          final List<dynamic> assetData = jsonDecode(raw['data']);
          final followedIds = followAsset.map((e) => e.assetId.toUpperCase()).toSet();

          return assetData.map((item) {
            final asset = QccAsset.fromJson(item);
            LogObj.log("服务器读取资产参数$item");
            asset.isFollowing = followedIds.contains(asset.assetId.toUpperCase());
            return asset;
          }).toList();
        }
      }
    } catch (e) {
      LogObj.log("❌ [Service] 获取全量资产异常: $e");
    }
    return [];
  }

  /// 获取全量资产并同步关注状态
  Future<List<QccAsset>> fetchAllAssets() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/asset"));
      if (response.statusCode == 200) {
        final Map<String, dynamic> raw = jsonDecode(response.body);
        if (raw['ok'] == true && raw['data'] != null) {
          final List<dynamic> assetData = jsonDecode(raw['data']);
          // 确保本地数据已就绪
         // if (!_isInitialized) await initFollowAssets();
          final followedIds = followAsset.map((e) => e.assetId.toUpperCase()).toSet();

          return assetData.map((item) {
            final asset = QccAsset.fromJson(item);
            LogObj.log("服务器读取资产参数$item");
            asset.isFollowing = followedIds.contains(asset.assetId.toUpperCase());
            return asset;
          }).toList();
        }
      }
    } catch (e) {
      LogObj.log("❌ [Service] 获取全量资产异常: $e");
    }
    return [];
  }
}