/// 对应 Java qcc.core.qccData.MatchLogic + MatchType。
///
/// 【本次按你发的 MatchType.java 做的修正】
/// MatchType.java 顶部原文写着"⚠️⚠️ 枚举顺序是协议的一部分，永久冻结 ⚠️⚠️
/// ...新值只能追加在末尾，绝对不能在中间插入/删除/重排"，并给出了完整 10
/// 个值、真实声明顺序：
///   random(0), fixed(1), dex(2), dividend(3), cancel(4), loan(5), repay(6),
///   cancelloan(7), inherit(8), nodeweight(9)
/// 这份文件之前维护的 kMatchTypeOrder 只有前 8 个，inherit/nodeweight 是
/// 这次新确认补上的，位置就是 Java 源码里的真实声明顺序，不再是推测。
/// QccMatchType 这个 Dart 枚举也补齐成同样的 10 个值、同样的顺序（你上一版
/// 草稿已经在枚举声明里加上了，但配套的 label switch 还是只有前 5 个 case，
/// Dart 对枚举做 switch 要求穷尽所有分支，编译会报错——这次一并把 label
/// 补全了）。
///
/// 【仍然没有做，原因不变】没有实现 toBytes()/fromBytes()。见下面
/// QccMatchType 声明处的说明——inherit/nodeweight 的顺序现在已经确认了，
/// 不再是这个决定的理由；真正的理由还是 QccTransactionData.dart 自己写明
/// 的"前端不做 toBytes()/fromBytes()，只走 toJson()/fromJson()"这条既定
/// 架构，client 从没有需要在本地把 MatchLogic 序列化成二进制的场景。如果
/// 以后确实需要，kMatchTypeOrder 现在已经是可以直接拿去用的真实顺序表了。
library;

import 'QccTransactionData.dart';

/// 完整对应 Java MatchType.java 的 10 个值，顺序与 Java 源码逐一核对过，
/// 与下面 kMatchTypeOrder 保持一致（多出的 nodeweight 目前没有字符串表
/// 用途，只是让枚举本身完整，避免以后再有人拿这个枚举的 index 去做编码时
/// 踩坑——它的下标现在等于 Java 真实 ordinal，可以放心当真值参考，但仍然
/// 不建议直接拿 .index 做二进制编码，见下方 kMatchTypeOrder 说明的理由：
/// 编码逻辑本身该走字符串表 + indexOf，不要依赖枚举声明顺序不会被后人
/// 不小心调整）。
enum QccMatchType {
  random,      // 随机红包 / 随机空投
  fixed,       // 等额红包 / 等额空投
  dex,         // 现货挂单撮合
  dividend,    // 按持仓比例分红
  cancel,      // 取消 open 订单（退款式，通用）
  loan,        // 借贷
  repay,       // 还款
  cancelloan,  // 取消借贷状态（债务核销，仅适用于 loan，无资金转移）
  inherit,     // 继承
  nodeweight,  // 权重购买交易
}

extension QccMatchTypeExt on QccMatchType {
  String get label {
    switch (this) {
      case QccMatchType.random: return "随机 (红包/空投)";
      case QccMatchType.fixed:  return "固定 (等额/现货)";
      case QccMatchType.dex:    return "去中心交易 (DEX)";
      case QccMatchType.dividend: return "分红 (Dividend)";
      case QccMatchType.cancel: return "取消 (Cancel)";
      case QccMatchType.loan: return "借贷 (Loan)";
      case QccMatchType.repay: return "还款 (Repay)";
      case QccMatchType.cancelloan: return "借贷核销 (CancelLoan)";
      case QccMatchType.inherit: return "继承 (Inherit)";
      case QccMatchType.nodeweight: return "节点权重 (NodeWeight)";
    }
  }
}

/// 【已按 MatchType.java 源码确认，不再是推测】真实声明顺序(ordinal 0起)：
/// random, fixed, dex, dividend, cancel, loan, repay, cancelloan, inherit,
/// nodeweight——和上面 QccMatchType 枚举的声明顺序逐一对应。
/// 当前仍然没有任何代码路径调用 _ruleToCode/_ruleFromCode（因为 Dart 客户端
/// 不做 toBytes()，见文件头说明），这张表继续作为已核实的协议知识留存，
/// 以后如果真的需要在 Dart 端做二进制编码，可以直接放心使用。
const List<String> kMatchTypeOrder = <String>[
  'random',
  'fixed',
  'dex',
  'dividend',
  'cancel',
  'loan',
  'repay',
  'cancelloan',
  'inherit',
  'nodeweight',
];

/// 对应 MatchLogic.getRuleCode()——目前未被调用，见文件头说明。
// ignore: unused_element
int _ruleToCode(String? rule) {
  if (rule == null) return 0;
  final idx = kMatchTypeOrder.indexOf(rule);
  return idx < 0 ? 0 : idx + 1; // 对应 Java catch(IllegalArgumentException) return 0
}

/// 对应 MatchLogic.getRuleFromCode()——目前未被调用，见文件头说明。
// ignore: unused_element
String _ruleFromCode(int code) {
  final idx = code - 1;
  if (idx < 0 || idx >= kMatchTypeOrder.length) return 'unknown';
  return kMatchTypeOrder[idx];
}

class QccMatchLogic {
  String? pairAssetId;
  double rate;
  int maxParticipants;
  String? rule;
  int remainingAmount;

  /// 继承到期时间(Unix毫秒)，只有 rule=="inherit" 时有意义，其余类型恒为0。
  /// 对应 Java 的 `long maturityTime`——Java 那边排除它的 JSON 注解实际是
  /// 死代码，字段目前会正常参与 JSON 序列化，详见 toJson()/fromJson()。
  int maturityTime;

  /// 【本次修正，你指出的问题】Java 的 MatchLogic 根本没有自定义构造函数——
  /// 全是 `public` 字段，用的是隐式无参构造 `new MatchLogic()`，字段各自
  /// 保持 Java 基本类型默认值(double=0.0, int=0, long=0, String=null)，
  /// 调用方之后再按需逐个赋值。之前这里写成 `required` 是我加的、Java 里
  /// 并不存在的约束，会导致必须一次性把所有字段都传进构造函数，和 Java
  /// 那种"先 new 出来、再一个个字段赋值"的用法对不上——比如 LoanIssueWidget.dart
  /// 里 `final logic = QccMatchLogic(); logic.rule = "loan"; ...` 这种写法，
  /// 遇到 required 参数根本编译不过。现在全部改成可选、给 Java 同款默认值，
  /// `QccMatchLogic()` 空参构造完全合法，逐个赋值和一次性传参两种写法都能用。
  QccMatchLogic({
    this.pairAssetId,
    this.rate = 0.0,
    this.maxParticipants = 0,
    this.rule,
    this.remainingAmount = 0,
    this.maturityTime = 0,
  });

  /// 对应 Java hasExtendedFields()：判据是字面量比较 rule=="inherit"，
  /// 不依赖任何枚举 ordinal。
  bool get hasExtendedFields => rule == 'inherit';

  /// 解析服务端返回的 JSON。字段用 `?? 默认值` 兜底而不是强制类型转换失败
  /// 就抛异常——避免服务端某个基本类型字段因为等于默认值而被序列化成 null
  /// 或干脆缺省时，这里直接崩掉。
  factory QccMatchLogic.fromJson(Map<String, dynamic> json) => QccMatchLogic(
    pairAssetId: json['pairAssetId'] as String?,
    rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 0,
    rule: json['rule'] as String?,
    remainingAmount: (json['remainingAmount'] as num?)?.toInt() ?? 0,
    maturityTime: (json['maturityTime'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'pairAssetId': pairAssetId,
    'rate': rate,
    'maxParticipants': maxParticipants,
    'rule': rule,
    'remainingAmount': remainingAmount,
    'maturityTime': maturityTime,
  };

  /// 必须和 Java 端 toSignFragment() 逐字节一致。
  /// ⚠️ rate 是 double —— 这是整套 value-only 签名方案里唯一一个
  /// "无法保证跨语言格式天然一致"的字段，见 QccTransactionData.dart 底部说明。
  /// rule=="inherit" 时按 Java 的安全要求在末尾追加 maturityTime，其余类型
  /// (loan/repay/cancelloan 等)完全不受影响，字段数量、内容都不变。
  String toSignSegment() {
    final List<String> parts = [
      pairAssetId ?? '',
      QccTransactionData.formatDoubleForSign(rate),
      maxParticipants.toString(),
      rule ?? '',
      remainingAmount.toString(),
    ];
    if (hasExtendedFields) {
      parts.add(maturityTime.toString());
    }
    return parts.join(QccTransactionData.signSep);
  }

  /// 与 QccTransactionData.validateNoReservedChar() 对称：
  /// pairAssetId / rule 是自由字符串字段需要校验，数值字段天然不会含任意字符，不查。
  void validateNoReservedChar(String reservedChar) {
    if (pairAssetId != null && pairAssetId!.contains(reservedChar)) {
      throw ArgumentError('字段 [matchLogic.pairAssetId] 包含系统保留字符 "$reservedChar"，交易被拒绝');
    }
    if (rule != null && rule!.contains(reservedChar)) {
      throw ArgumentError('字段 [matchLogic.rule] 包含系统保留字符 "$reservedChar"，交易被拒绝');
    }
  }
}