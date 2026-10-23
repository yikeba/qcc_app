/// 系统资金池地址 —— 对齐服务端 qcc.rule.qccRule.SystemPool（0x39 保留版本字节命名空间）。
///
/// 这四个地址不由任何密钥派生，永久无人可动用，只进不出，出账只能由协议层发起。
/// 地址长度恒为 34（与单签/多签一致）。
/// 声明顺序必须与 Java 一致：AddressIndex 按此顺序预注册为 id 1..4。
///
/// 原来定义在 DeveloperRuleWidget.dart 里，且四个地址都多写了一位（35 位）。
/// 抽成独立文件供全局复用（开发者规则页、系统资金池看板、转账页防误转提示等）。
enum SystemPool {
  system('Q999999999999999999999999999999999', '系统池', 'System Pool'),
  devReward('Q222222222222222222222222222222222', '开发者奖励池', 'Developer Reward Pool'),
  interest('Q111111111111111111111111111111111', '利息分配池', 'Interest Distribution Pool'),
  nodePledge('Q333333333333333333333333333333333', '节点质押池', 'Node Pledge Pool');

  final String address;
  final String label;
  final String labelEn;

  const SystemPool(this.address, this.label, this.labelEn);

  static const int addressLength = 34;

  /// Java isSystemPool()：闭集成员校验
  static bool isSystemPool(String? address) => of(address) != null;

  /// Java of()：非系统池地址返回 null
  static SystemPool? of(String? address) {
    if (address == null || address.length != addressLength) return null;
    for (final p in SystemPool.values) {
      if (p.address == address) return p;
    }
    return null;
  }
}
