/// 对应 Java qcc.rule.assetRule.WhitelistUpdateRule —— 资产转账白名单
/// 增/删地址规则。字段逐一按你这次上传的三个 Java 源码核实：
///
/// 1.【字段来源：TxWhitelistFullSuiteTest.java 第121-141行】
///    ```java
///    WhitelistUpdateRule rule = new WhitelistUpdateRule();
///    rule.assetId = assetId;
///    rule.operator = wallet.address;
///    rule.op = "ADD";               // 或 "REMOVE"
///    rule.addresses = addresses;     // List<String>
///    rule.nonce = System.currentTimeMillis();
///    ```
/// 2.【ruleName 字面量来源：同文件 sendAssetRuleRequest(wallet, "WhitelistUpdateRule", rule)
///    调用点】——这是本次上传里唯一一处直接把 ruleName 当字符串字面量传参
///    的地方，比其它规则（靠 AssetType.xxx.name 枚举反推）更硬的证据，
///    所以这里 ruleName 直接写死 "WhitelistUpdateRule"，不经过枚举。
/// 3.【ruleType 来源：同文件 sendAssetRuleRequest 内部
///    ruleData.ruleType = RuleType.AsseIdRule.name()】—— 和 AssetFreezeRule/
///    AssetMintRule/AssetBurnRule 同一套规则模型，ruleType 固定 "AsseIdRule"，
///    RuleData.dart 里 assetId 默认值本来就是 "QCCRule"（和 Java
///    demoUtil.sendAssetRuleRequest 里 ruleData.assetId = "QCCRule" 一致），
///    不需要在这几个新页面里再手动赋值。
///
/// 4.【重要架构提醒，直接翻译自 TxWhitelistFullSuiteTest.java 顶部注释】
///    WhitelistUpdateRule 是纯单签模型——operator 和签名者一致即可立即生效，
///    没有时间锁、没有二次确认。Java 注释原文举了个真实案例：
///    "之前 removeRule.op 误写成 'ADD' 也能正常执行成功，就是'没有二次确认'
///    风险的真实案例——协议层面不会告诉你语义错了"。所以单签维护页面上
///    ADD/REMOVE 的选择必须做得非常显眼，多签场景下这个风险由多签门限本身
///    兜底（需要 threshold 个成员签署才生效）。
///
/// 5.【关于未来亿级白名单的扩展性提醒】目前 addresses 是一次性整段 List，
///    5000-10000 级地址一次性提交没问题；如果未来做到亿级，protocol 大概率
///    会改成分片/分页提交（不可能一个 JSON body 塞几亿个地址字符串），
///    到时候这个模型和三个页面的批量提交逻辑都需要跟着协议改动同步调整，
///    这里先按你现在给的 Java 源码实现"一次性整段提交"。
class WhitelistUpdateRule {
  String assetId;
  String operator;
  String op; // "ADD" or "REMOVE"
  List<String> addresses;
  int nonce;

  WhitelistUpdateRule({
    required this.assetId,
    required this.operator,
    required this.op,
    required this.addresses,
    int? nonce,
  }) : nonce = nonce ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'operator': operator,
        'op': op,
        'addresses': addresses,
        'nonce': nonce,
      };

  factory WhitelistUpdateRule.fromJson(Map<String, dynamic> j) {
    List<String> addrs = [];
    final raw = j['addresses'];
    if (raw is List) {
      addrs = raw.map((e) => e.toString()).toList();
    }
    int parsedNonce;
    final n = j['nonce'];
    if (n is int) {
      parsedNonce = n;
    } else {
      parsedNonce = int.tryParse(n?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch;
    }
    return WhitelistUpdateRule(
      assetId: j['assetId']?.toString() ?? '',
      operator: j['operator']?.toString() ?? '',
      op: j['op']?.toString() ?? WhitelistOp.add,
      addresses: addrs,
      nonce: parsedNonce,
    );
  }
}

/// ruleName 字面量——见文件头部第2点，直接来自 Java 调用点，不经枚举。
const String kWhitelistUpdateRuleName = "WhitelistUpdateRule";

/// op 字面量——见 Java addToWhitelist()/removeFromWhitelist()。
class WhitelistOp {
  static const String add = "ADD";
  static const String remove = "REMOVE";
}
