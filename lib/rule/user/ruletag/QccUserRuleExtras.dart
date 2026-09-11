/// 【新增】三种用户规则的业务数据模型：标签资产注册(TagRule)/标签资产
/// 转让(TagTransfer)/地址生命周期终止(AddressEnd)。
///
/// 字段名对齐 Java 端 qcc.client.userrule.TxTagRuleTest / TxTagTransferTest /
/// TxAddressEndTest 里手工拼的 JSONObject——服务端目前是直接从 ruleJson 里
/// 的这几个 key 读数据，所以这里保持字段名完全一致：
///   TagRule:      {tagName, owner}     —— owner 仅声明用途，服务端应以
///                                          签名地址(from)为准，不采信客户端传值
///   TagTransfer:  {tagName, newOwner}  —— 必须由当前 tag owner(签名者=from)
///                                          发起，newOwner 不需要自己签名（push式转移）
///   AddressEnd:   {address}            —— 同样仅声明用途，服务端应以
///                                          签名地址(from)为准
///
/// 项目里已有的 QccDeveloperRule / QccMerchantRule / QccPayCallRule 这几个
/// 模型类放在 QccRuleBaseObj.dart 里，但那个文件的具体内容我这边看不到，
/// 没法直接往里加而不冒着覆盖你其他改动的风险——这三个新类型先单独放在
/// 这个文件里，用法（构造函数 + toJson()）和已有的几个类完全一致。如果你
/// 想把它们合并进 QccRuleBaseObj.dart，直接剪切过去即可，不影响其他文件
/// 的 import。
library qcc_user_rule_extras;

class QccTagRule {
  final String tagName;
  final String owner;

  QccTagRule({required this.tagName, required this.owner});

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'owner': owner,
      };
}

class QccTagTransfer {
  final String tagName;
  final String newOwner;

  QccTagTransfer({required this.tagName, required this.newOwner});

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'newOwner': newOwner,
      };
}

class QccAddressEnd {
  final String address;

  QccAddressEnd({required this.address});

  Map<String, dynamic> toJson() => {
        'address': address,
      };
}
