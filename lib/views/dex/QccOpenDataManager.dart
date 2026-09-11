import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../utile/QccStorage.dart';
import '../../home/QccExplorerService.dart';
import '../../procotol/QccMatchLogic.dart';
import 'package:qcc_flutter/utile/QccHttp.dart';

class QccOpenDataManager {
  // 内存缓存：Map<交易哈希, 交易详情Map>
  static final Map<String, Map<String, dynamic>> _orderCache = {};
  static final ValueNotifier<int> marketUpdateNotifier = ValueNotifier(0);

  // ✅ 你的极简思路变体：本地刚刚发生、尚未被网络确认的扣款金额
  static final Map<String, double> _localPendingDeductions = {};
  static List<String> errhash=[];

// ✅ Win 成功后调用这个方法记账，并自带 10 秒倒计时销毁
  static void addLocalDeduction(String hash, double amount) {
    // 1. 累加本地记账
    _localPendingDeductions[hash] = (_localPendingDeductions[hash] ?? 0.0) + amount;
    LogObj.log("乐观更新：本地记录 [$hash] 扣除 $amount");

    // 2. ✅ 设置 10 秒延迟清理 (TTL)
    Future.delayed(const Duration(seconds: 10), () {
      if (_localPendingDeductions.containsKey(hash)) {
        // 10秒后，认为量子链节点已经绝对打包完毕，删除本地记账
        _localPendingDeductions.remove(hash);
        LogObj.log("乐观更新过期：释放 [$hash] 的本地记账，交由服务器接管");

        // 3. (可选) 触发一次静默的单条 Hash 刷新，强行用服务器最新状态覆盖本地缓存
        _syncSingleOrder(hash).then((_) {
          // 如果你的架构需要通知 UI 刷新，可以在这里触发
          // 比如你在上一轮如果用了 ValueNotifier，这里可以 value++
        });
      }
    });
  }
  // 全局同步方法
  static Future<void> syncFromNetwork() async {
    try {
      // 1. 获取当前所有活跃的 Open Hash 列表 (改用封装好的 QccHttp)
      final response = await QccHttp.get("${QccExplorerService.baseUrl}/v1/open");

      if (response.statusCode != 200) return;

      final Map<String, dynamic> rootJson = jsonDecode(response.body);
      // 注意：这里需要确保解析层级正确
      final List<dynamic> serverHashes = jsonDecode(rootJson['data']);

      // ✅ 关键改动 1：强制清理。只要服务器列表里没有，本地缓存必须立刻灰飞烟灭
      _orderCache.removeWhere((hash, data) => !serverHashes.contains(hash));
      //清理已经失败的或交易完成hash
      // ✅ 修正 1：防止内存泄漏！如果服务器终于把这个废弃的 Hash 删了，黑名单也跟着释放
     // errhash.removeWhere((hash) => !serverHashes.contains(hash));
      // 2. 双重保险：将黑名单中的 Hash 从展示缓存中彻底清除
    //  _orderCache.removeWhere((hash, data) => errhash.contains(hash));
      // 3. 构建并发同步任务
      List<Future<void> Function()> tasks = [];
      for (String hash in serverHashes) {
        if(errhash.contains(hash)) continue;
        tasks.add(() => _syncSingleOrder(hash));
      }
      // 使用分批并发执行，防止瞬时并发过高
      await QccHttp.runInBatches(tasks, batchSize: 5);

    } catch (e) {
      LogObj.log("同步撮合大厅数据失败: $e");
    }
  }

  // 处理单个 Hash 的核心逻辑
  static Future<void> _syncSingleOrder(String hash) async {
    String _url = "";
    try {
      // A. 静态数据兜底
      if (!_orderCache.containsKey(hash)) {
        _url = "${QccExplorerService.baseUrl}/v1/opentx/$hash";
        final txRes = await QccHttp.get(_url);

        if (txRes.statusCode == 200) {
          final resJson = jsonDecode(txRes.body);
          if (resJson['ok'] == true && resJson['data'] != null) {
            _orderCache[hash] = jsonDecode(resJson['data']);
            marketUpdateNotifier.value++;
          }
        } else {
          return;
        }
      }

      // B. 动态状态覆盖 (拉取 openhash)
      _url = "${QccExplorerService.baseUrl}/v1/openhash/$hash";
      final stateRes = await QccHttp.get(_url);

      if (stateRes.statusCode == 200) {
        final stateResJson = jsonDecode(stateRes.body);

        // ✅ 关键改动 2：如果接口返回 ok: false 或 data 为空，说明该单据在状态机已不存在
        if (stateResJson['ok'] != true || stateResJson['data'] == null) {
          _orderCache.remove(hash);
          LogObj.log("订单 [$hash] 状态机已结项，执行清理");
          return;
        }

        final stateData = jsonDecode(stateResJson['data']);
        if (_orderCache.containsKey(hash)) {
          // ✅ 关键改动 3：状态判定拦截
          // 如果状态不是 ACTIVE，或者 currentAmount <= 0，或者已经过期
          double currentAmt = (stateData['currentAmount'] as num?)?.toDouble() ?? 0.0;
          if (stateData['state'] != 'ACTIVE' || stateData['isExpired'] == true || currentAmt <= 0) {
            _orderCache.remove(hash);
          //  LogObj.log("订单 [$hash] 已无效(金额:$currentAmt,状态:${stateData['state']})，执行清理");
            errhash.add(hash);
            return;
          }
          // 核心映射：同步最新数量
          _orderCache[hash]!['amount'] = currentAmt;
          // 同步剩余份数
          if (stateData['remainingParts'] != null && _orderCache[hash]!['matchLogic'] != null) {
            _orderCache[hash]!['matchLogic']['remainingAmount'] = stateData['remainingParts'];
          }
        }
      }
    } on TimeoutException catch (_) {
      // ✅ 关键改动 4：如果 openhash 连续超时，且我们处于“激进模式”，可以考虑在这里也清理
      // 但保守起见，超时通常选择保留，除非连续多次失败
      LogObj.log("状态更新超时 [Hash: $hash]");
      _orderCache.remove(hash);
      errhash.add(hash);
    } catch (e) {
      LogObj.log("同步单个订单异常 [$hash]: $e");
    }
  }

  static List<Map<String, dynamic>> getOrdersByType(QccMatchType type) {
    return _orderCache.values.where((tx) {
      String hash = tx['id'];

      // 1. 获取网络上真实的数量
      double amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;

      // ✅ 2. 减去我们本地刚刚买走的数量 (这就是你黑名单逻辑的精髓)
      double pendingDeduct = _localPendingDeductions[hash] ?? 0.0;
      double finalAmt = amt - pendingDeduct;

      // 如果减完之后没了，就不显示了
      if (finalAmt <= 0) return false;

      // ⚠️ 把扣减后的数量塞回去给 UI 显示
      tx['amount'] = finalAmt;

      // 3. 原有的类型过滤逻辑
      String rule = "";
      try {
        rule = tx['matchLogic']['rule'];
        if (type == QccMatchType.dex) return rule == "dex" || rule == "exchange";
        return rule == type.name;
      } catch (e) {
        rule = tx['type'] ?? "";
        if (type == QccMatchType.dex) return rule == "dex" || rule == "exchange";
        return rule == type.name;
      }
    }).toList();
  }

  /// ✅ 获取指定挂单的碰撞(Win)明细
  static Future<List<dynamic>> getWinHashTx(String hash) async {
    try {
      LogObj.log("🔍 [DataCenter] 正在读取碰撞明细: $hash");
      // 使用你封装好的 QccHttp 调用 Java API
      final response = await QccHttp.get("${QccExplorerService.baseUrl}/v1/winhashtx/$hash");

      if (response.statusCode == 200) {
        final Map<String, dynamic> rootJson = jsonDecode(response.body);
        if (rootJson['ok'] == true && rootJson['data'] != null) {
          // 返回 Win 单列表
          LogObj.log("🔍 索引返回碰撞明细订单所有内容data:${rootJson["data"]}");
          return jsonDecode(rootJson['data']) as List<dynamic>;
        }
      }
    } catch (e) {
      LogObj.log("❌ [DataCenter] 读取碰撞明细异常: $e");
    }
    return [];
  }


  /// ✅ 核心逻辑：通过 Win 明细反演 Open 单的真实进度
  static Map<String, double> recalculateOrderState(Map<String, dynamic> order, List<dynamic> winList) {
    final String openAssetId = order['assetId'] ?? "";
    final double rate = (order['matchLogic']?['rate'] as num?)?.toDouble() ?? 0.0;

    // 1. 原始锁定量
    double originalHuman = QccAssetService().getHumanAmountNum(openAssetId, order['amount']);

    double spentHuman = 0.0;
    double obtainedHuman = 0.0;

    for (var win in winList) {
      String winAssetId = win['assetId'];
      double winAmt = QccAssetService().getHumanAmountNum(winAssetId, win['amount']);

      if (winAssetId.toUpperCase() == openAssetId.toUpperCase()) {
        // 卖出场景：消耗 QCC 得到 USD
        spentHuman += winAmt;
        obtainedHuman += (winAmt * rate);
      } else {
        // 买入场景：消耗 USD 得到 QCC
        obtainedHuman += winAmt;
        spentHuman += (rate > 0 ? winAmt / rate : 0);
      }
    }

    double remaining = originalHuman - spentHuman;
    if (remaining < 0.00000001) remaining = 0; // 防抖

    double progress = originalHuman > 0 ? (spentHuman / originalHuman) : 0;
    if (progress > 1.0) progress = 1.0; // 封顶 100%

    return {
      "spent": spentHuman,
      "obtained": obtainedHuman,
      "remaining": remaining,
      "progress": progress,
    };
  }


  static Future<Map<String, dynamic>?> syncOpenHashStatus(String address, String hash) async {
    try {
      final response = await QccHttp.get("${QccExplorerService.baseUrl}/v1/openhash/$hash");
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> resJson = jsonDecode(response.body);
      if (resJson['ok'] != true || resJson['data'] == null) return null;

      final stateData = jsonDecode(resJson['data']);
      List<Map<String, dynamic>> localOrders = await QccStorage.getDexOrders(address);
      int index = localOrders.indexWhere((e) => e['id'] == hash);
      if (index == -1) return null;

      var order = localOrders[index];

      // ✅ 统一使用锁定资产精度换算
      double originalRaw = (order['amount'] as num).toDouble();
      double originalHuman = QccAssetService().getHumanAmountNum(order['assetId'], originalRaw);

      double remainingRaw = (stateData['currentAmount'] as num).toDouble();
      double remainingHuman = QccAssetService().getHumanAmountNum(order['assetId'], remainingRaw);

      // ✅ 计算已成交的本位量
      double filledHuman = originalHuman - remainingHuman;
      if (filledHuman < 0) filledHuman = 0;

      // ✅ 计算进度
      int progress = originalHuman > 0 ? ((filledHuman / originalHuman) * 100).toInt() : 0;

      // 更新状态逻辑
      String remoteState = stateData['state'] ?? "ACTIVE";
      String finalStatus = "open";
      if (remainingRaw <= 0) {
        finalStatus = "filled";
      } else if (remoteState == "CANCELLED") finalStatus = "cancelled";

      // ✅ 写入更新后的 Map
      order['filledProgress'] = progress;
      order['filledAmount'] = filledHuman.toStringAsFixed(6); // 保留高精度字符串
      order['localStatus'] = finalStatus;
      order['remaining'] = remainingRaw;

      await QccStorage.saveAllDexOrders(address, localOrders);
      return order;
    } catch (e) {
      LogObj.log("同步错误: $e");
      return null;
    }
  }


  /// ✅ 获取单笔 Win 交易的原始详情
  static Future<Map<String, dynamic>?> getTransactionDetail(String txHash) async {
    try {
      // 调用查询单笔交易详情的接口
      final response = await QccHttp.get("${QccExplorerService.baseUrl}/v1/hash/$txHash");

      LogObj.log("获取win 交易单详情${response.body}");
      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        LogObj.log("获取win 交易单详情$resJson");
        if (resJson['ok'] == true) {
          return jsonDecode(resJson['data']); // 返回交易的 Payload
        }
      }
    } catch (e) {
      LogObj.log("查询交易详情失败: $e");
    }
    return null;
  }


  static List<QccTicker> getMarketTickers() {
    Map<String, QccTicker> tickers = {};

    // 遍历内存缓存中的所有有效挂单
    for (var tx in _orderCache.values) {
      try {
        Map<String, dynamic>? matchLogic = tx['matchLogic'];
        if (matchLogic == null || matchLogic['rule'] != "dex") continue;

        String lockedAsset = tx['assetId'] ?? "";
        String pairAsset = matchLogic['pairAssetId'] ?? "";
        double chainRate = (matchLogic['rate'] as num?)?.toDouble() ?? 0.0;
        double amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;

        if (chainRate <= 0 || lockedAsset.isEmpty || pairAsset.isEmpty) continue;

        // 识别买卖关系（锁定 USD 的是买单，锁定代币的是卖单）
        bool isBuy = lockedAsset.toUpperCase().contains("USDS");
        String tokenName = isBuy ? pairAsset : lockedAsset;
        String stableName = isBuy ? lockedAsset : pairAsset;

        // 初始化或获取交易对对象
        tickers.putIfAbsent(tokenName, () => QccTicker(assetId: tokenName, quoteAsset: stableName));
        var ticker = tickers[tokenName]!;

        // 计算市场单价 (1 Token = ? USD)
        // 买单：1 USD = N Token -> 价格 1/N
        // 卖单：1 Token = N USD -> 价格 N
        double marketPrice = isBuy ? (1.0 / chainRate) : chainRate;

        // 累加成交量（统一换算成 Token 数量）
        ticker.volume += isBuy ? (amount * chainRate) : amount;

        if (isBuy) {
          // 买单：更新该币种的“最高买价”
          if (marketPrice > ticker.bestBuy) ticker.bestBuy = marketPrice;
        } else {
          // 卖单：更新该币种的“最低卖价”
          if (ticker.bestSell == 0 || marketPrice < ticker.bestSell) ticker.bestSell = marketPrice;
        }
      } catch (e) {
        // 静默跳过格式错误的订单
      }
    }
    List<QccTicker> list = tickers.values.toList();

    // ✅ 核心改动：自定义排序逻辑
    list.sort((a, b) {
      // 1. QCC 永远排在第一位
      if (a.assetId.toUpperCase() == "QCC") return -1;
      if (b.assetId.toUpperCase() == "QCC") return 1;

      // 2. 其他代币按成交量降序排列
      return b.volume.compareTo(a.volume);
    });

    return list;
  }



}


// 在 QccOpenDataManager 类中增加以下代码

/// ✅ 市场行情模型
class QccTicker {
  final String assetId;      // 代币名称 (如 QCC)
  final String quoteAsset;   // 计价单位 (如 USD)
  double bestBuy = 0.0;      // 最高买入价 (买一)
  double bestSell = 0.0;     // 最低卖出价 (卖一)
  double volume = 0.0;       // 总挂单量

  QccTicker({required this.assetId, required this.quoteAsset});
}

// 扩展 QccOpenDataManager
extension QccMarketAggregator on QccOpenDataManager {

  /// ✅ 获取全市场报价列表 (聚合 Buy/Sell 价格)
  static List<QccTicker> getMarketTickers() {
    Map<String, QccTicker> tickers = {};

    QccOpenDataManager._orderCache.forEach((hash, tx) {
      try {
        String lockedAsset = tx['assetId'];
        String pairAsset = tx['matchLogic']?['pairAssetId'] ?? "";
        double chainRate = (tx['matchLogic']?['rate'] as num?)?.toDouble() ?? 0.0;
        double amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        amount=QccAssetService().getHumanAmountNum(lockedAsset, amount);
        if (chainRate <= 0) return;

        bool isBuy = lockedAsset.toUpperCase().contains("USDS");
        String tokenName = isBuy ? pairAsset : lockedAsset;
        String stableName = isBuy ? lockedAsset : pairAsset;

        if (tokenName.isEmpty || !stableName.toUpperCase().contains("USDS")) return;

        // 初始化 Ticker
        tickers.putIfAbsent(tokenName, () => QccTicker(assetId: tokenName, quoteAsset: stableName));
        var ticker = tickers[tokenName]!;

        // 计算市场单价 (1 Token = ? USD)
        double marketPrice = isBuy ? (1.0 / chainRate) : chainRate;
        ticker.volume += isBuy ? (amount * chainRate) : amount;

        if (isBuy) {
          // 买单：寻找最高买价 (Best Bid)
          if (ticker.bestBuy == 0 || marketPrice > ticker.bestBuy) {
            ticker.bestBuy = marketPrice;
          }
        } else {
          // 卖单：寻找最低卖价 (Best Ask)
          if (ticker.bestSell == 0 || marketPrice < ticker.bestSell) {
            ticker.bestSell = marketPrice;
          }
        }
      } catch (e) {
        // 容错处理
      }
    });

    return tickers.values.toList();
  }
}
