/// 对应 Java qcc.rule.PledgeRule.PledgeRules —— 质押规则统一载荷。
/// 字段逐一按你这次上传的 PledgeRules.java 源码核实（toJson()/toBytes()
/// 两套序列化方式并存，客户端提交走 toJson() 这一套，和其它 RuleData
/// 家族规则一致）：
///   address / assetId / amount(long) / actionType("lock"|"unlock") /
///   credentialHash / protocol / pledgeJson
///
/// 【字段含义，综合本次6个 Java 测试文件核实】
/// - address：质押发起地址（同时也是普通质押/超级节点质押的受益地址）。
/// - actionType：只有 "lock"（发起/建立）和 "unlock"（解押/吊销）两个值，
///   在全部6个测试文件里没有例外。
/// - protocol：区分质押子类型，对应 PledgetType 枚举的 4 个具名值，
///   PledgeCommonTest.java 的"普通质押（自我信托）"是唯一例外——直接用
///   空字符串 ""，不属于枚举里任何一个值，说明"最基础的自我质押"根本
///   不需要 protocol 分类。
/// - credentialHash：【仅用于 protocol=""（普通）和 protocol=SuperNode 这类
///   "简单质押"的 unlock】——必须填原 lock 交易的 txHash，服务端凭这个
///   hash 找到原始质押记录才能退款（PledgeCommonTest.java 顶部注释原文：
///   "unlock：必须带上原lock交易的txHash（作为credentialHash）才能查到
///   记录退款"）。
/// - pledgeJson：【仅 protocol=AuthorizedPledge 使用】装的是
///   AuthorizedPledge.toJson()——这种情况下 revoke（解押/吊销）用的是
///   AuthorizedPledge.revokeHash 这个嵌套字段，不是本类顶层的
///   credentialHash（PledgeUnlockTest.java 的 doRevoke() 只设置了
///   revoke.revokeHash，从没设置过 pledge.credentialHash，两条 unlock 路径
///   字段位置不一样，这里刻意保留这个区别，不做"统一简化"）。
///
/// 提交方式（综合6个测试文件核实）：
/// - 单签（普通质押 / 超级节点质押 / 授权质押）：包进
///   RuleData{ruleType="PledgeRule", ruleName="PledgeRule", assetId="QCCRule",
///   ruleJson=pledge.toJson()}，POST /v1/rule。
/// - 多签质押提案（目前只有 StablecoinPledege 这一种类型有测试证据）：
///   同样 ruleType="PledgeRule"、ruleName="PledgeRule"，POST /v1/mtxrule。
/// - 多签追随签署：【重要协议细节，和其它所有资产类追随签署页都不一样】
///   ruleType 变成 "UserRule"（不是 "PledgeRule"），ruleName 仍是
///   "PledgeRule"，ruleJson 换成上一步提案的 txHash——这是
///   PledgeFollowTest.java 里直接写明的，不是我的推测，照抄不做"统一化"。
class PledgeRules {
  String address;
  String assetId;
  int amount;
  String actionType; // "lock" | "unlock"
  String? credentialHash;
  String protocol; // 见 PledgetType.dart；普通质押固定传 ""
  String? pledgeJson;

  PledgeRules({
    required this.address,
    required this.assetId,
    required this.amount,
    required this.actionType,
    this.credentialHash,
    this.protocol = "",
    this.pledgeJson,
  });

  Map<String, dynamic> toJson() => {
        'address': address,
        'assetId': assetId,
        'amount': amount,
        'actionType': actionType,
        'credentialHash': credentialHash,
        'protocol': protocol,
        'pledgeJson': pledgeJson,
      };

  factory PledgeRules.fromJson(Map<String, dynamic> j) {
    return PledgeRules(
      address: j['address']?.toString() ?? '',
      assetId: j['assetId']?.toString() ?? '',
      amount: j['amount'] is int ? j['amount'] : int.tryParse(j['amount']?.toString() ?? '') ?? 0,
      actionType: j['actionType']?.toString() ?? PledgeActionType.lock,
      credentialHash: j['credentialHash']?.toString(),
      protocol: j['protocol']?.toString() ?? '',
      pledgeJson: j['pledgeJson']?.toString(),
    );
  }
}

/// actionType 字面量——见 PledgeCommonTest.java / PledgeNodeTest.java 等，
/// 全部6个测试文件里只出现过这两个值。
class PledgeActionType {
  static const String lock = "lock";
  static const String unlock = "unlock";
}
