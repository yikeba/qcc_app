
import 'dart:developer' as LogObj;
import '../../myasset/QccAssetService.dart';

class QccDexEngine {
  // 单例模式
  static final QccDexEngine _instance = QccDexEngine._internal();
  factory QccDexEngine() => _instance;
  QccDexEngine._internal();

  // 核心数据结构：Map<Symbol, DepthData> (例如: "QCC_USD": DepthData)
  final Map<String, DexDepthData> _depthMap = {};

  // 全量原始订单缓存 (供外部审查用)
  List<Map<String, dynamic>> _rawOpenOrders = [];

  // ✅ 自动识别什么是“计价资产 (稳定币)”
  bool _isQuoteAsset(String asset) {
    final upper = asset.toUpperCase();
    // 根据你的公链特性，包含这些字眼的通常作为计价基准 (可自行增删)
    return upper == 'USD' || upper == 'USDS' || upper == 'USDC' || upper == 'DAI';
  }

  // 获取特定交易对的盘口数据
  DexDepthData getDepth(String baseAsset, {String quoteAsset = "USDS"}) {
    String symbol = "${baseAsset.toUpperCase()}_${quoteAsset.toUpperCase()}";
    return _depthMap[symbol] ?? DexDepthData(asks: [], bids: []);
  }

  // ✅ 核心方法：清洗并合并深度
  void processRawOrders(List<Map<String, dynamic>> allOpenOrders) {
    _rawOpenOrders = allOpenOrders;
    _depthMap.clear();

    // 临时存储变更为：Map<Symbol, Map<Price, _DepthAggregator>>
    Map<String, Map<double, _DepthAggregator>> tempAsks = {};
    Map<String, Map<double, _DepthAggregator>> tempBids = {};

    for (var tx in allOpenOrders) {
      final logic = tx['matchLogic'];
      // 1. 过滤非交易单
      if (logic == null || (logic['rule'] != 'dex' && logic['rule'] != 'exchange')) continue;

      String lockedAsset = tx['assetId'].toString().toUpperCase();
      String targetAsset = logic['pairAssetId'].toString().toUpperCase();
      double rate = (logic['rate'] as num).toDouble();

      // 2. 动态获取真实数量，拒绝写死 / 10^9
      double rawAmount = (tx['amount'] as num).toDouble();
      double amount = QccAssetService().getHumanAmountNum(lockedAsset, rawAmount);

      if (rate <= 0 || amount <= 0) continue;

      // 3. 智能识别 Base 和 Quote 资产
      bool isLockedQuote = _isQuoteAsset(lockedAsset);
      bool isTargetQuote = _isQuoteAsset(targetAsset);

      // 异常拦截：如果两个都是稳定币，或者都不是稳定币，跳过
      if (isLockedQuote == isTargetQuote) {
        LogObj.log("跳过异常/非标准 DEX 对价交易: $lockedAsset -> $targetAsset");
        continue;
      }

      // 确定交易对标识 (Symbol)
      String baseAsset = isLockedQuote ? targetAsset : lockedAsset;
      String quoteAsset = isLockedQuote ? lockedAsset : targetAsset;
      String symbol = "${baseAsset}_${quoteAsset}";

      // ==== 4. 核心分类逻辑 (并处理价格档位) ====
      if (isTargetQuote) {
        // 📉 卖单 (Ask): 锁定代币 (Base)，换回稳定币 (Quote)
        double price = rate;
        double qty = amount;

        // 抹平极小浮点误差，按 6 位小数对齐价格档位
        price = double.parse(price.toStringAsFixed(6));

        tempAsks.putIfAbsent(symbol, () => {});
        tempAsks[symbol]!.putIfAbsent(price, () => _DepthAggregator());

        // 合并数量并保存原始订单
        tempAsks[symbol]![price]!.totalAmount += qty;
        tempAsks[symbol]![price]!.orders.add(tx);
      }
      else {
        // 📈 买单 (Bid): 锁定稳定币 (Quote)，换回代币 (Base)
        double price = 1.0 / rate;
        // 计算数量：锁定的稳定币数量 * rate = 目标代币数量
        double qty = amount * rate;

        price = double.parse(price.toStringAsFixed(6));

        tempBids.putIfAbsent(symbol, () => {});
        tempBids[symbol]!.putIfAbsent(price, () => _DepthAggregator());

        // 合并数量并保存原始订单
        tempBids[symbol]![price]!.totalAmount += qty;
        tempBids[symbol]![price]!.orders.add(tx);
      }
    }

    // ==== 5. 生成并排序盘口列表 ====
    Set<String> allSymbols = {...tempAsks.keys, ...tempBids.keys};

    for (String symbol in allSymbols) {
      // 卖盘处理：按价格从低到高排序
      List<DepthItem> asks = (tempAsks[symbol] ?? {}).entries.map((e) {
        // ✅ 按照时间戳给该价位下的订单排序 (先进先出 FIFO)
        e.value.orders.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
        return DepthItem(price: e.key, amount: e.value.totalAmount, rawOrders: e.value.orders);
      }).toList()..sort((a, b) => a.price.compareTo(b.price));

      // 买盘处理：按价格从高到低排序
      List<DepthItem> bids = (tempBids[symbol] ?? {}).entries.map((e) {
        // ✅ 按照时间戳给该价位下的订单排序 (先进先出 FIFO)
        e.value.orders.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
        return DepthItem(price: e.key, amount: e.value.totalAmount, rawOrders: e.value.orders);
      }).toList()..sort((a, b) => b.price.compareTo(a.price));

      _depthMap[symbol] = DexDepthData(asks: asks, bids: bids);
    }

    LogObj.log("盘口深度计算完成，共聚合 ${allSymbols.length} 个交易对。");
  }
}

// ─────────────────────────────────────────
// 内部辅助类：用于同一价格档位的聚合
// ─────────────────────────────────────────
class _DepthAggregator {
  double totalAmount = 0.0;
  List<Map<String, dynamic>> orders = [];
}

// ─────────────────────────────────────────
// 数据模型：盘口深度
// ─────────────────────────────────────────
class DexDepthData {
  final List<DepthItem> asks; // 卖盘
  final List<DepthItem> bids; // 买盘
  DexDepthData({required this.asks, required this.bids});
}

// ─────────────────────────────────────────
// 数据模型：单个深度档位 (包含原始订单引用)
// ─────────────────────────────────────────
class DepthItem {
  final double price;
  final double amount;
  final List<Map<String, dynamic>> rawOrders; // ✅ 保存合并前的原始订单列表

  DepthItem({
    required this.price,
    required this.amount,
    required this.rawOrders,
  });
}