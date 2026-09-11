/// 对应 Java qcc.rule.PledgeRule.Authorize.AuthorizedPledge。
/// 装在 PledgeRules.pledgeJson 里，仅当 protocol=PledgetType.authorizedPledge
/// 时使用（授权质押场景）。
///
/// 字段核实自 AuthorizedPledge.java 源码 + PledgeAuthorizedTest.java /
/// PledgeUnlockTest.java 两个测试的用法：
/// - to：被授权地址（可为空表示自我鉴权：授权给质押人自己）。
/// - tag：授权标签，如 "node" / "s3"，可逗号分隔多个标签。
/// - revokeHash：【吊销专用】要吊销的授权 hash（即建授权时那笔 lock 交易的
///   txHash）——lock（建立授权）时不填，unlock（吊销）时才指定。
///   PledgeUnlockTest.java 的 doRevoke() 只设置了这一个字段，从未设置过
///   PledgeRules 顶层的 credentialHash——这是授权质押和普通/超级节点质押在
///   解押字段位置上唯一不同的地方，实现时不要"统一简化"成都用顶层字段。
class AuthorizedPledge {
  String? to;
  String? tag;
  String? revokeHash;

  AuthorizedPledge({this.to, this.tag, this.revokeHash});

  Map<String, dynamic> toJson() => {
        'to': to,
        'tag': tag,
        'revokeHash': revokeHash,
      };

  factory AuthorizedPledge.fromJson(Map<String, dynamic> j) {
    return AuthorizedPledge(
      to: j['to']?.toString(),
      tag: j['tag']?.toString(),
      revokeHash: j['revokeHash']?.toString(),
    );
  }
}
