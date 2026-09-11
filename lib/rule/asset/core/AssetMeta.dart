/// 严格对应 Java qcc.rule.assetRule.AssetMeta（发行资产的核心容器）。
///
/// 【修复，重要】按你的要求"Java 为标准"补齐字段——原来这个 Dart 版本缺了
/// burnable / isWhitelist / whitelistAddresses 三个字段。这几个开关都是
/// 发行时一次性声明、之后无法追溯补授权的：AssetMeta.java 里 burnable 的
/// 原话注释是"协议上线前已发行的存量资产反序列化后本字段默认为 false，
/// 不会被追溯授予销毁能力，需重新发行资产才能启用"——所以发行表单必须能
/// 设置 burnable，不能等到做销毁功能时才想起来加。
///
/// isWhitelist / whitelistAddresses 这一阶段（发行+增发）先只做到字段对齐、
/// 默认 false + 空列表，暂不在发行表单里开放对应的 UI——白名单地址的增删
/// 是一块独立的管理功能，留到后面冻结/销毁管理阶段再做专门页面。
///
/// 顺带把原来的本地枚举名 AssetCoinType 改成 AssetMetaType，和 Java 端
/// qcc.rule.assetRule.AssetMetaType 保持同名（这个枚举目前在
/// Single/MultiSigTokenIssueWidget 里都没被直接引用，两边都是写
/// meta.type="COIN" 字符串字面量，改名不影响任何现有调用）。
///
/// 另外去掉了原来的 dataContentHash / storageLink 两个字段——Java 的
/// AssetMeta.java 里根本没有这两个字段，序列化过去 Java 端反序列化时会被
/// 直接忽略，是没有意义的冗余字段，两个现有 Widget 里也从未对它们赋值过。
enum AssetMetaType{
  COIN,
  Stablecoin
}


class AssetMeta {
  String? assetId;          // 资产代码 (如: QCC_USDT)
  String type = AssetMetaType.COIN.name;     // 资产类型
  String? owner;            // 资产发行人地址
  int precision = 9;        // 精度
  int initialSupply = 0;    // 对应 Java long (64位)
  bool mintable = true;
  bool freezable = true;

  /// 是否开启"销毁"能力（AssetBurnRule 的前置开关）。发行时一次性声明，
  /// 默认 false，和 mintable/freezable 同一模式但默认值不同——对齐 Java
  /// `public boolean burnable;`（Java boolean 字段未显式赋值默认为 false）。
  bool burnable = false;

  /// 是否开启白名单转账限制。默认 false（不限制）。见上方类注释：这一阶段
  /// 先不提供 UI 入口，字段对齐 Java 但老实传默认值。
  bool isWhitelist = false;
  List<String> whitelistAddresses = [];

  String? credentialHash = "";

  AssetMeta(this.assetId, this.owner);

  // 1:1 适配 Java 序列化结果
  Map<String, dynamic> toJson() => {
    "assetId": assetId,
    "type": type,
    "owner": owner,
    "precision": precision,
    "initialSupply": initialSupply,
    "mintable": mintable,
    "freezable": freezable,
    "isWhitelist": isWhitelist,
    "burnable": burnable,
    "credentialHash": credentialHash,
    "whitelistAddresses": whitelistAddresses,
  };
}

enum AssetType{
  AssetMeta,   //发布资产
  AssetMintRule,   //资产更新，增发
  AssetFreezeRule,   //资产冻结
  AssetBurnRule,
}