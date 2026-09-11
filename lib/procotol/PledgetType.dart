
class PledgetType {
  static const String authorizedPledge = "AuthorizedPledge";
  static const String superNode = "SuperNode";
  static const String pledgeReleaseScheduler = "PledgeReleaseScheduler";
  static const String stablecoinPledege = "StablecoinPledege";

  /// 普通质押（自我信托）：PledgeCommonTest.java 里 protocol 直接传空字符串，
  /// 不属于枚举里任何一个值，是独立于上面 4 个具名类型之外的第5种情况。
  static const String plain = "";

  /// 供 UI 展示用的中文名映射，未知值原样返回。
  static String label(String protocol) {
    switch (protocol) {
      case plain:
        return "普通质押（自我信托）";
      case authorizedPledge:
        return "授权质押";
      case superNode:
        return "超级节点质押";
      case pledgeReleaseScheduler:
        return "创世纪冻结质押";
      case stablecoinPledege:
        return "稳定币质押";
      default:
        return protocol;
    }
  }
}
