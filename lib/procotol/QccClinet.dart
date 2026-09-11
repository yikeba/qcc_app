import 'dart:convert';
import 'dart:developer' as LogObj;
import 'package:http/http.dart' as http;


// ══════════════════════════════════════════════════════════════════
//  统一响应对象
// ══════════════════════════════════════════════════════════════════
class TxResponse {
  final bool ok;
  final Map? data;
  final String? message;

  const TxResponse({required this.ok, this.data, this.message});

  factory TxResponse.fromJson(Map json) => TxResponse(
    ok: json['ok'] as bool,
    data: json['data'] ,
    message: json['message'] as String?,
  );

  /// 提取交易 id，追随交易时作为 hash 传入下一步
  String? get txId => data?['id'] as String?;

  @override
  String toString() => ok ? 'TxResponse(ok, txId=$txId)' : 'TxResponse(err=$message)';
}

// ══════════════════════════════════════════════════════════════════
//  统一 API 客户端 — 单一入口 submit()
// ══════════════════════════════════════════════════════════════════
class QccTxClient {
  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  QccTxClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 15),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// 统一提交入口 — 所有交易类型走这一个函数
  Future<TxResponse> submit(QccTxRequest request) async {
    final uri = Uri.parse(baseUrl);
    late http.Response response;
    LogObj.log("提交服务器构建交易对象:${request.toJson()}");
    try {
      response = await _http
          .post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(request.toJson()),
      ).timeout(timeout);
    } on Exception catch (e) {
      return TxResponse(ok: false, message: '网络请求失败: $e');
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 429:
        return const TxResponse(ok: false, message: '请求过于频繁，请稍后再试');
      case 413:
        return const TxResponse(ok: false, message: '请求体超过 10K 限制');
      default:
        return TxResponse(ok: false, message: 'HTTP ${response.statusCode}');
    }

    try {
      //PhoneUtil.applog("返回构建交易对象内容${response.body}");
      Map json = jsonDecode(response.body) as Map<String, dynamic>;

      final datamap=json["data"];
      LogObj.log("返回构建交易data type:${datamap.runtimeType}");
      LogObj.log("返回构建交易data value:$datamap");
      return TxResponse.fromJson(json);
    } on Exception catch (e) {
      return TxResponse(ok: false, message: '响应解析失败: $e');
    }
  }

  void dispose() => _http.close();
}

// ══════════════════════════════════════════════════════════════════
//  Action 枚举 — 完全对应 Java switch case
// ══════════════════════════════════════════════════════════════════
enum QccAction {
  issueAsset('ISSUE_ASSET'),        // 1. 单签发布资产
  entityData('ENTITY_DATA'),        // 2. 实体数据发布
  createMsign('CREATE_MSIGN'),      // 3. 创建多签账户规则
  buildMutx('BUILD_MUTX'),          // 4. 构建多签转账交易
  appendMsign('APPEND_MSIGN'),      // 5. 多签创建追随
  appendMutx('APPEND_MUTX'),        // 6. 多签交易追随
  issueAssetMu('ISSUE_ASSET_MU'),   // 7. 多签发布资产
  appendAssetMu('APPEND_ASSET_MU'), // 8. 多签资产追随
  openTx("TXOPEN"),
  winTx ("TXWIN"),  // open 交易（matchLogic，不传 action）
  simplePay("TransactionData");                  // default → 普通转账（不传 action）

  final String? value;
  const QccAction(this.value);
}

// ══════════════════════════════════════════════════════════════════
//  MatchType 枚举 — 对应 Java MatchType
// ══════════════════════════════════════════════════════════════════
enum MatchType {
  random,  // 随机分配
  fixed,   // 固定分配
  dex,     // 去中心化交换
}

// ══════════════════════════════════════════════════════════════════
//  MatchLogic — 对应 Java MatchLogic（字段顺序与 @JSONField ordinal 一致）
// ══════════════════════════════════════════════════════════════════
class MatchLogic {
  /// ordinal=1 对价资产ID，dex 模式时填写，其余可为 null
  final String? pairAssetId;

  /// ordinal=2 汇率
  final double rate;

  /// ordinal=3 总份数（红包个数）
  final int maxParticipants;

  /// ordinal=4 分配规则
  final MatchType rule;

  /// ordinal=5 剩余金额（服务端状态机维护，客户端发起时传 0）
  final int remainingAmount;

  const MatchLogic({
    this.pairAssetId,
    this.rate = 1.0,
    this.maxParticipants = 5,
    this.rule = MatchType.random,
    this.remainingAmount = 0,
  });

  Map<String, dynamic> toJson() => {
    if (pairAssetId != null) 'pairAssetId': pairAssetId,
    'rate': rate,
    'maxParticipants': maxParticipants,
    'rule': rule.name,           // "random" / "fixed" / "dex"
    'remainingAmount': remainingAmount,
  };

  factory MatchLogic.fromJson(Map<String, dynamic> json) => MatchLogic(
    pairAssetId: json['pairAssetId'] as String?,
    rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
    maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 5,
    rule: MatchType.values.firstWhere(
          (e) => e.name == json['rule'],
      orElse: () => MatchType.random,
    ),
    remainingAmount: (json['remainingAmount'] as num?)?.toInt() ?? 0,
  );
}

// ══════════════════════════════════════════════════════════════════
//  统一请求对象 — 所有字段超集，按 action 按需填写
// ══════════════════════════════════════════════════════════════════
class QccTxRequest {
  final QccAction action;

  // ── 通用 ────────────────────────────────────────────────────────
  final String? from;

  // ── ISSUE_ASSET ─────────────────────────────────────────────────
  final String? ruleName;
  final String? ruleJson;

  // ── ENTITY_DATA ─────────────────────────────────────────────────
  final String? content;

  // ── CREATE_MSIGN ────────────────────────────────────────────────
  final List<String>? owners;
  final int? threshold;

  // ── 转账通用（BUILD_MUTX / APPEND_MUTX / SIMPLE_PAY）──────────
  final String? to;
  final int? amount;
  final String? assetId;
  final String? fromMulti;

  // ── 追随引用（APPEND_MSIGN / APPEND_MUTX / APPEND_ASSET_MU）────
  final String? hash;

  // ── ISSUE_ASSET_MU 专属 ─────────────────────────────────────────
  final String? type;
  final int? precision;
  final bool? mintable;
  final bool? freezable;
  final int? initialSupply;

  // ── OPEN_TX 专属 ─────────────────────────────────────────────────
  final MatchLogic? matchLogic;

  const QccTxRequest({
    required this.action,
    this.from,
    this.ruleName,
    this.ruleJson,
    this.content,
    this.owners,
    this.threshold,
    this.to,
    this.amount,
    this.assetId,
    this.fromMulti,
    this.hash,
    this.type,
    this.precision,
    this.mintable,
    this.freezable,
    this.initialSupply,
    this.matchLogic,
  });

  // ── 核心：对应 Java switch(action) 路由 ────────────────────────
  Map<String, dynamic> toJson() {
    return switch (action) {
      QccAction.issueAsset    => _buildIssueAsset(),
      QccAction.entityData    => _buildEntityData(),
      QccAction.createMsign   => _buildMSignRule(),
      QccAction.buildMutx     => _buildMultiTx(),
      QccAction.appendMsign   => _buildAppendMSign(),
      QccAction.appendMutx    => _buildAppendMultiTx(),
      QccAction.issueAssetMu  => _buildMuAsset(),
      QccAction.appendAssetMu => _buildMuAssetAppend(),
      QccAction.openTx        => _buildOpenTx(),
      QccAction.winTx         => _buildWinTx(),
      QccAction.simplePay     => _buildSimplePay(),
    };
  }

  // ── 各 action 对应的 JSON 构造（方法名与 Java 一致）────────────

  /// 对应 buildIssueAsset()
  Map<String, dynamic> _buildIssueAsset() => {
    'action': action.value,
    'from': from,
    'ruleName': ruleName,
    'ruleJson': ruleJson,
  };

  /// 对应 buildEntityData()
  Map<String, dynamic> _buildEntityData() => {
    'action': action.value,
    'from': from,
    'content': content,
  };

  /// 对应 buildMSignRule()
  Map<String, dynamic> _buildMSignRule() => {
    'action': action.value,
    'from': from,
    'owners': owners,
    'threshold': threshold,
  };

  /// 对应 buildMultiTx()
  Map<String, dynamic> _buildMultiTx() => {
    'action': action.value,
    'from': from,
    'fromMulti': fromMulti,
    'to': to,
    'amount': amount,
    'assetId': assetId,
  };

  /// 对应 buildAppendMSign()
  Map<String, dynamic> _buildAppendMSign() => {
    'action': action.value,
    'from': from,
    'hash': hash,
  };

  /// 对应 buildAppendMultiTx()
  Map<String, dynamic> _buildAppendMultiTx() => {
    'action': action.value,
    'from': from,
    'fromMulti': fromMulti,
    'to': to,
    'amount': amount,
    'assetId': assetId,
    'hash': hash,
  };

  /// 对应 buildmuasset()
  Map<String, dynamic> _buildMuAsset() => {
    'action': action.value,
    'from': from,
    'fromMulti': fromMulti,
    'assetId': assetId,
    'type': type,
    'precision': precision,
    'mintable': mintable,
    'freezable': freezable,
    'initialSupply': initialSupply,
  };

  /// 对应 buildmuassetapend()
  Map<String, dynamic> _buildMuAssetAppend() => {
    'action': action.value,
    'from': from,
    'hash': hash,
  };

  /// 对应 sendOpenTransaction() — txType=open + matchLogic
  Map<String, dynamic> _buildOpenTx() => {
    'action': action.value,
    'from': from,
    'to': to,              // 通常传 "MATCH_RESERVED_ADDR_" + uuid
    'amount': amount,
    'assetId': assetId,
    'txType': 'open',
    'maxParticipants' :  matchLogic!.maxParticipants,
    'rule' : matchLogic!.rule.name,
    'rate' :  matchLogic!.rate,
    //'matchLogic': matchLogic?.toJson(),
  };

  Map<String, dynamic> _buildWinTx() => {
    'action': action.value,
    'from': from,
    'assetId': assetId,
    'txType': 'win',
    'hash' : hash
  };

  /// 对应 buildSimplePay()（default，不传 action）
  Map<String, dynamic> _buildSimplePay() => {
    'action': action.value,
    'from': from,
    'to': to,
    'amount': amount,
    'assetId': assetId,
  };
}



