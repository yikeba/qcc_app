import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../../home/QccExplorerService.dart';
import '../../../../qccnodemap/QccNodeManager.dart';
import 'MultiSigNode.dart';


class QccMultiSigService {
  // 【修复，重要】原来这里写死 "https://tx.qccio.com/v1" 去查 mtxquery。
  // 对照 MultiSingManager.java：mtxquery 查的是"待签署会话"(pendingSessions /
  // pendingTXSessions / pendingUniversalSessions)，这几个都是纯内存的
  // ConcurrentHashMap，只存在于【当初收到那次创建/追加请求的那一台节点】的
  // JVM 里，节点间完全不同步。按你的决定：多签的创建/追加/查询现在统一固定
  // 打 MultiSigNode.baseUrl 这一个节点（而不是像其他普通交易那样用
  // QccNodeManager 动态挑选），所以这里直接引用同一个常量，不再自己维护一份
  // 写死地址——以后要换节点，改 MultiSigNode.dart 一处就行。
  static String chainUrl = "${QccExplorerService.baseUrl}/v1";

  static Future<MultiSigTaskWrapper?> fetchTask(String hash) async {
    // 1. 尝试查询内存池 (mtxquery)
    try {
      final mtxRes = await http
          .get(Uri.parse("${MultiSigNode.baseUrl}/v1/mtxquery?txHash=$hash"))
      // 【修复】原来没有超时控制，节点如果刚好不可达，这次查询会一直
      // 挂起，FutureBuilder 的 loading 态可能长时间卡住。
          .timeout(const Duration(seconds: 15));
      if (mtxRes.statusCode == 200) {
        final res = jsonDecode(mtxRes.body);
        if (res['status'] == 'success' && res['data'] != null && res['data'] is Map) {
          return _parsePending(res['data'], hash);
        }
      }
    } catch (e) {
      // 内存池可能因为数据已上链而报错（或者节点暂时不可达），
      // 静默处理进入下一步——走链上查询兜底。
    }

    // 2. 内存无结果，按照 QCC 标准查询上链 (v1/hash/)
    // 【说明】这一步查的是已经上链、全网同步过的数据，不属于"单节点内存
    // 会话"的范畴，所以不需要 nodeBaseUrl，继续用 QccExplorerService 的地址
    // 即可。
    try {
      final hashRes =
      await http.get(Uri.parse("$chainUrl/hash/$hash")).timeout(const Duration(seconds: 15));
      if (hashRes.statusCode == 200) {
        final res = jsonDecode(hashRes.body);
        if (res['ok'] == true && res['data'] != null) {
          // QCC 标准：第一层解 data 字符串
          Map<String, dynamic> dataMap = jsonDecode(res['data'].toString());
          // 第二层解 dataMap['tx'] 字符串
          if (dataMap.containsKey('tx')) {
            Map<String, dynamic> txDetail = jsonDecode(dataMap['tx'].toString());
            return _parseConfirmed(txDetail, hash);
          }
        }
      }
    } catch (e) {
      LogObj.log("QCC DEBUG_: 解析失败 $hash: $e");
    }
    return null;
  }

  /// 【新增】mtxquery（内存）和链上查询都失败时的兜底：如果本地之前已经
  /// 记录过这个 hash "签署完成、生成了多签地址"（MultiSigFileStorage.
  /// saveConfirmedAccount 写的 status=='SUCCESS' + multiAddress），不应该
  /// 因为这一次网络查询失败（节点暂时不可达、链上索引还没同步过来、
  /// IPv6 不通等等）就把整条记录显示成"加载失败/已失效"——本地这条记录
  /// 本来就是当初签署成功那一刻权威、及时写下来的，用它兜底即可。
  ///
  /// localRecord 是 QccMultiSigCenterPage 从 MultiSigFileStorage.getAllTasks()
  /// 读到的、和这个 hash 对应的那条原始记录（可能为 null）。这里顺手用
  /// MultiAddressQueryContext（verifyMultiSigAddress）再校验一次地址是否
  /// 确实注册成功，但只作为日志参考——校验失败（网络问题/还没同步）不影响
  /// 展示，展示与否只看本地记录本身。
  static Future<MultiSigTaskWrapper?> fetchTaskWithLocalFallback(
      String hash, Map<String, dynamic>? localRecord) async {
    final MultiSigTaskWrapper? live = await fetchTask(hash);
    if (live != null) return live;

    if (localRecord == null) return null;
    final String? storedAddress =
    (localRecord['multiAddress'] ?? localRecord['multiaddress'])?.toString();
    final bool storedFinished =
        localRecord['status'] == 'SUCCESS' && storedAddress != null && storedAddress.isNotEmpty;
    if (!storedFinished) return null;

    // 不 await，不阻塞展示——只是留个日志方便排查。
    verifyMultiSigAddress(storedAddress).then((verified) {
      LogObj.log(verified
          ? "QCC DEBUG_: 本地兜底记录二次校验通过: $storedAddress"
          : "QCC DEBUG_: 本地兜底记录二次校验未通过（可能是登记服务还没同步/网络问题，不影响展示）: $storedAddress");
    });

    final List<String> owners = List<String>.from(localRecord['owners'] ?? [])
        .map((e) => e.toString())
        .toSet()
        .toList();
    return MultiSigTaskWrapper(
      type: MultiSigTaskType.rule,
      txHash: hash,
      data: {
        'status': 'SUCCESS',
        'multiAddress': storedAddress,
        'owners': owners,
        'threshold': localRecord['threshold'] ?? 0,
        // 标记这条数据是"本地兜底"重建出来的，不是这次真查到的——目前
        // 页面逻辑用不到这个标记，留着方便以后排查/区分数据来源。
        'localFallback': true,
      },
      signedOwners: owners,
      isConfirmed: true,
    );
  }

  static MultiSigTaskWrapper _parsePending(Map<String, dynamic> data, String hash) {
    MultiSigTaskType type = _identifyType(data);
    return MultiSigTaskWrapper(
      type: type,
      txHash: hash,
      data: data,
      signedOwners: List<String>.from(data['signedOwners'] ?? []),
      isConfirmed: false,
    );
  }

  static MultiSigTaskWrapper _parseConfirmed(Map<String, dynamic> tx, String hash) {
    MultiSigTaskType type = _identifyType(tx);

    // 解析最内层的 ruleJson 字符串以获取阈值和地址
    Map<String, dynamic> rule = {};
    if (tx['ruleJson'] != null) {
      try { rule = jsonDecode(tx['ruleJson'].toString()); } catch (_) {}
    }

    return MultiSigTaskWrapper(
      type: type,
      txHash: hash,
      data: tx,
      signedOwners: List<String>.from(rule['owners'] ?? []),
      isConfirmed: true,
    );
  }

  static MultiSigTaskType _identifyType(Map<String, dynamic> data) {
    String kind = data['kind'] ?? "";
    if (kind == 'RULE_MULTI_SIG' || data.containsKey('ruleJson')) return MultiSigTaskType.rule;
    if (kind == 'MULTI_TX' || data.containsKey('multiTxData')) return MultiSigTaskType.transaction;
    return MultiSigTaskType.unknown;
  }

  /// 【新增】验证一个 M 开头的多签地址是否已经在链上（规则登记服务）注册成功。
  /// 对应后端优化后的 MultiAddressQueryContext：GET /v1/multiAddressQuery/{address}。
  ///
  /// 【重要，和 mtxquery 不一样】这个接口查的是 UserRuleManager 通过 Hub 上的
  /// 规则/余额服务拿到的注册记录——不是 MultiSingManager 那几个"只活在 leader
  /// 内存里"的 pendingSessions/pendingTXSessions/pendingUniversalSessions。
  /// 也就是说它不属于我们之前诊断的"必须打在 leader 上才查得到"那类接口，
  /// 正常走 QccNodeManager 挑一个当前活跃节点即可，不需要 MultiSigNode.baseUrl
  /// 那种"固定节点"的特殊处理。
  ///
  /// 返回 true 表示后端确认这个地址已注册；false 既可能是"确实没注册"，
  /// 也可能是网络失败/超时/登记服务还没来得及同步——调用方不应该把 false
  /// 当作"创建失败"的强判定，这里只是一次锦上添花的二次确认，本地是否
  /// 显示这笔多签，应该以创建/追加签署本身返回的 ACCEPTED + multiaddress
  /// 为准（更权威、更及时），这个校验结果只作为日志/辅助参考。
  /// 【新增】把 MultiSigTaskWrapper 归纳成"当前签了几个、门槛是多少、
  /// 多签地址有没有生成"这几个通用字段——不管调用方是刚提交完追加签署、
  /// 还是稍后重新打开列表查看，都走这一个方法，不要在每个页面里各自摸索
  /// task.data 的形状（待签内存形状 vs 已上链 RuleData 形状完全不同，
  /// 之前 QccMultiSigCenterPage 和 QccFollowMultiSigPage 里各写了一份、
  /// 还不完全一致，容易走偏）。
  static MultiSigSummary summarize(MultiSigTaskWrapper task) {
    if (task.isConfirmed) {
      // 已上链：ruleJson 是权威数据源
      Map<String, dynamic> rule = {};
      if (task.data['ruleJson'] != null) {
        try { rule = jsonDecode(task.data['ruleJson'].toString()); } catch (_) {}
      }
      List<String> owners = List<String>.from(rule['owners'] ?? [])
          .map((e) => e.toString())
          .toSet()
          .toList();
      return MultiSigSummary(
        owners: owners,
        // 已完成，视为 owners 里的都已经签过（后端目前不单独区分"候选人"
        // 和"实际签名人"两个字段）。
        signedOwners: owners,
        threshold: rule['threshold'] ?? 0,
        multiAddress: (rule['multiaddress'] ?? rule['multiAddress'])?.toString(),
        isFinished: true,
      );
    }
    // 还在 leader 内存里等待签署：顶层字段就是权威数据源，
    // 此时多签地址肯定还没生成，不强行伪造。
    List<String> owners = List<String>.from(task.data['owners'] ?? [])
        .map((e) => e.toString())
        .toSet()
        .toList();
    List<String> signedOwners = List<String>.from(task.data['signedOwners'] ?? [])
        .map((e) => e.toString())
        .toSet()
        .toList();
    return MultiSigSummary(
      owners: owners,
      signedOwners: signedOwners,
      threshold: task.data['threshold'] ?? 0,
      multiAddress: null,
      isFinished: false,
    );
  }

  static Future<bool> verifyMultiSigAddress(String multiAddress) async {
    try {
      await QccNodeManager.instance.init();
      final String baseUrl = QccNodeManager.instance.currentBaseUrl();
      final res = await http
          .get(Uri.parse("$baseUrl/v1/multiAddressQuery/$multiAddress"))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['ok'] == true && body['data'] is Map) {
          return body['data']['exists'] == true;
        }
      }
    } catch (e) {
      LogObj.log("QCC DEBUG_: 多签地址校验请求失败 $multiAddress: $e");
    }
    return false;
  }
}

enum MultiSigTaskType { rule, transaction, asset, unknown }

/// 【新增】summarize() 的归纳结果：owners 是全体参与地址，signedOwners 是
/// 其中已经签过的子集，multiAddress 只有在真正完成时才非空。
class MultiSigSummary {
  final List<String> owners;
  final List<String> signedOwners;
  final int threshold;
  final String? multiAddress;
  final bool isFinished;

  const MultiSigSummary({
    required this.owners,
    required this.signedOwners,
    required this.threshold,
    required this.multiAddress,
    required this.isFinished,
  });
}

class MultiSigTaskWrapper {
  final MultiSigTaskType type;
  final String txHash;
  final Map<String, dynamic> data;
  final List<String> signedOwners;
  final bool isConfirmed;

  MultiSigTaskWrapper({
    required this.type,
    required this.txHash,
    required this.data,
    required this.signedOwners,
    required this.isConfirmed,
  });
}