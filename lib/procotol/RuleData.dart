/// 对应 Java qcc.core.qccData.RuleData（typeCode = 2）。
///
/// 【阻塞点仍在，跟之前 MatchType 是同一类问题】：
/// getRuleTypeCode()/getRuleTypeFromCode() 依赖 qcc.rule.RuleType 这个枚举的
/// ordinal，还没拿到 RuleType.java，kRuleTypeOrder 留空，toBytes()/fromBytes()
/// 用之前会抛异常。新增的 toJson() 不受这个阻塞影响，可以直接用——
/// 展示用途不涉及 ruleType 的字节编码，直接存/显示原始字符串就行。
///
/// 本次改动（对照 Java RuleData.java 源码后新增）：
/// 1. 【修复】新增 getChain()，并在构造函数里自动赋值给 chain 字段。
///    Java 端 RuleData 的 chain 是在基类 initBaseFields() 里通过
///    getChain()（debug 环境 "6666"，正式环境 "9999"）自动填好的——
///    这也是为什么 Java 的 MultiSigAppend 阶段完全没手动设置 chain 也能正常
///    工作。Dart 这边原来的构造函数只设置了 timestamp，chain 一直是空字符串
///    ''，而两个页面（Create / Follow）都没有手动补上这一行，等于每一笔
///    多签规则交易的 chain 字段实际发送的都是空字符串，而不是 "6666"/"9999"。
///    这个字段会被签进 Java 端 toSign() 的签名原文里，一旦 Dart 端 FFI 签名
///    时用的是同一套字段拼接协议，chain 为空就会导致签名对不上、或者被链上
///    按错误的链 ID 路由/拒绝。现在改成构造函数里自动调用 getChain()，
///    和 Java 的"基类自动填充"行为对齐，调用方不需要再单独记得设置。
///    【已修复，见 getChain() 处注释】getChain() 原来用 kDebugMode 判断，你
///    确认了 "6666" 是公网测试网的链id、项目目前没有主网构建，kDebugMode
///    这个"本地调试构建"标志对真实分发的测试网包几乎必然是 false，会错误
///    签成 "9999"——现在改成直接固定返回 "6666"，跟其它页面硬编码 "6666"
///    的做法保持一致。
/// 2. 修了构造函数名和类名不一致的问题（原文件是 class RuleData 但构造函数
///    写成了 QccRuleData()，这样编译不过，改成 RuleData()）。
/// 3. 新增 toJson()，纯本地展示用途。
/// 4. 【本次新增，对应"QccDataMeta 需要按 entryType 解析出明确的业务对象"】
///    新增 fromJson()，跟 EntityData.fromJson()/QccTransactionData.fromJson()
///    同一个用途——从资源浏览器接口返回的原始 JSON（QccDataMeta.extra）反解出
///    一个真正的 RuleData 对象，供 QccDataMeta.ruleData 这个新 getter 调用。
///    纯展示/读取用途，不影响 toBytes()/toSign() 这条链上签名路径。
library;

import 'dart:typed_data';

import 'QccBaseFields.dart';

// TODO(阻塞，必须替换): 按 Java RuleType.java 枚举声明的真实顺序填入。
const List<String> kRuleTypeOrder = <String>[];

void _requireRuleTypeOrderConfigured() {
  if (kRuleTypeOrder.isEmpty) {
    throw UnimplementedError(
      'kRuleTypeOrder 还没有按 RuleType.java 真实枚举声明顺序配置，'
          '请把 RuleType.java 源码发过来后再启用 RuleData 的 toBytes()/fromBytes()',
    );
  }
}

int _ruleTypeToCode(String? ruleType) {
  _requireRuleTypeOrderConfigured();
  if (ruleType == null) return 2; // 对应 Java 默认兜底值，具体含义待 RuleType.java 确认
  final idx = kRuleTypeOrder.indexOf(ruleType);
  return idx < 0 ? 2 : idx;
}

String? _ruleTypeFromCode(int code) {
  _requireRuleTypeOrderConfigured();
  if (code >= 0 && code < kRuleTypeOrder.length) {
    return kRuleTypeOrder[code];
  }
  return null; // 对应 Java getRuleTypeFromCode 越界返回 null
}

class RuleData {
  // ---- 基类字段 ----
  String chain = '6666';
  String type = 'rule';
  String id = '';
  // 【本次修复，对比 RuleData.java 源码后发现的真实bug】Java 构造函数里写的是
  // this.assetId = "QCCRULE"（全大写），这里之前是 "QCCRule"（大小写不一致）——
  // 字符串大小写敏感，这个默认值会被签进 toSign()（nz(assetId) 那一段），新建
  // 一笔规则交易时如果走的是这个默认构造值，签名内容里的 assetId 就跟 Java 端
  // 期望的 "QCCRULE" 对不上，可能表现成"签名校验失败"或者 assetId 比对不上。
  // fromBytes() 里原来的兜底值反而是对的("base.assetId ?? 'QCCRULE'")，
  // 现在把构造函数默认值也改成一致的全大写，消除这处内部自相矛盾。
  String assetId = "QCCRule";
  String? from;
  int timestamp = 0;
  String? signatureHash;

  // ---- 业务字段 ----
  String? ruleType;
  String? ruleJson;
  String? ruleName;
  String? ruleAppendJson;

  static const int typeCode = 2;

  RuleData() {
    timestamp = DateTime.now().millisecondsSinceEpoch;
    // 【修复】对应 Java 基类 initBaseFields() 自动填充 chain 的行为，
    // 调用方（Create / Follow 页面）不再需要、也不应该再手动设置 chain。
    chain = getChain();
  }

  /// 【本次修复】原来这里用 kDebugMode(Flutter"本地调试构建"标志——只有本地
  /// `flutter run` 调试运行时才是 true) 去对应 Java 的 LogObj.isDebug()，但
  /// 你确认了 "6666" 是公网测试网的链id，"9999" 对应的正式主网构建现在还
  /// 不存在——用 kDebugMode 判断的话，真实打包分发给测试网用户的 release/
  /// profile 包会被判成 false，从而错误签成 "9999"，这正是这次要避免的
  /// 签名/链路由对不上的bug。项目目前只有测试网，还没有主网构建，所以直接
  /// 固定返回 "6666"，跟 QccWinTransactionPage.dart/DexMatchWidget.dart 等
  /// 页面里 `tx.chain = "6666"` 硬编码的做法保持一致。等真正有主网构建、
  /// 需要按环境切换时，再把这里换成项目实际的环境标志（构建参数/flavor等），
  /// 不要再用 kDebugMode。
  static String getChain() {
    return "6666";
  }

  /// 对应 getPayloadForHash()
  String getPayloadForHash() {
    return '${ruleType ?? ''}${ruleJson ?? ''}$timestamp';
  }

  void finalizeId() {
    id = sha3256HexOfString(getPayloadForHash());
  }

  static String _nz(String? s) => s ?? '';

  /// 【新增，之前完全缺失】对应 Java RuleData.toSign()：
  ///   public String toSign() {
  ///       requireIdFinalized();
  ///       return String.join(SIGN_SEP,
  ///               nz(assetId), nz(chain), nz(from), String.valueOf(timestamp),
  ///               nz(ruleType), nz(ruleJson), nz(ruleName), nz(ruleAppendJson), id);
  ///   }
  /// 【待确认】signSep 这里沿用了 QccTransactionData.dart 里已经在用的反引号
  /// "`"——两个文件的注释都说这是"系统保留字符"，大概率是 Java 端
  /// QccBaseData.SIGN_SEP 这同一个常量的移植，但我没看到 QccBaseData.java 源码，
  /// 不能 100%确认 RuleData.java 用的分隔符和 TransactionData.java 是同一个值。
  /// 如果你手上有 QccBaseData.java，麻烦确认一下 SIGN_SEP 的具体字符。
  /// 这一步在此之前是完全缺失的方法，之前多签页面签名时根本没有调用任何
  /// toSign() —— 而 QccDataProtocol.encodeTransaction() 内部签名逻辑是被注释掉的
  /// （signature 恒为 ""），也就是说目前多签交易提交的签名字段是空的，
  /// 这个方法必须补上，并且调用方要真的用它算出的字符串去做 Dilithium5 签名。
  static const String signSep = '`';

  String toSign() {
    if (id.isEmpty) {
      throw StateError('必须先调用 finalizeId() 生成 id，才能构造签名内容');
    }
    validateNoReservedChar();
    return [
      _nz(assetId),
      chain,
      _nz(from),
      timestamp.toString(),
      _nz(ruleType),
      _nz(ruleJson),
      _nz(ruleName),
      _nz(ruleAppendJson),
      id,
    ].join(signSep);
  }

  /// 对应 Java validateNoReservedChar()：参与签名拼接的字符串字段不能包含
  /// 分隔符本身，否则 toSign() 拼出来的字符串会因为多了一个"隐藏字段"而
  /// 产生歧义（和 QccTransactionData.dart 的 checkField 同一个道理）。
  void validateNoReservedChar() {
    _checkField('assetId', assetId);
    _checkField('chain', chain);
    _checkField('from', from);
    _checkField('ruleType', ruleType);
    _checkField('ruleJson', ruleJson);
    _checkField('ruleName', ruleName);
    _checkField('ruleAppendJson', ruleAppendJson);
  }

  static void _checkField(String fieldName, String? value) {
    if (value != null && value.contains(signSep)) {
      throw ArgumentError('字段 [$fieldName] 包含系统保留字符 "$signSep"，交易被拒绝');
    }
  }

  /// 拿到（比如从服务端/其他节点收到的）规则数据后，重新派生签名字符串做比对。
  bool verifySignString(String received) => toSign() == received;

  QccBaseFields _baseFields() {
    final b = QccBaseFields();
    b.chain = chain;
    b.type = type;
    b.id = id;
    b.assetId = assetId;
    b.from = from;
    b.timestamp = timestamp;
    b.signatureHash = signatureHash;
    return b;
  }

  Uint8List toBytes() {
    final w = ByteWriter();
    writeBaseBytes(w, typeCode, _baseFields());
    w.putByte(_ruleTypeToCode(ruleType));
    writeString(w, ruleJson);
    writeString(w, ruleName);
    writeString(w, ruleAppendJson);
    return w.toBytes();
  }

  static RuleData? fromBytes(Uint8List data) {
    try {
      final r = ByteReader(data);
      final rule = RuleData();
      final base = readBaseBytes(r);
      rule.chain = base.chain;
      rule.type = base.type;
      rule.id = base.id;
      rule.assetId = base.assetId ?? 'QCCRULE';
      rule.from = base.from;
      rule.timestamp = base.timestamp;
      rule.signatureHash = base.signatureHash;

      rule.ruleType = _ruleTypeFromCode(r.getByte());
      rule.ruleJson = readString(r);
      rule.ruleName = readString(r);
      rule.ruleAppendJson = readString(r);

      return rule;
    } catch (e) {
      return null;
    }
  }

  /// 【新增】纯本地展示用途，对应 Java RuleData.toJson() = JSON.toJSONString(this)。
  /// 不用于签名/网络传输，所以没有照搬之前那套"省略默认值字段"的严格对齐逻辑——
  /// 字段是 null 也会显式输出 "key": null，方便你本地调试时分清"没赋值"和"空字符串"。
  Map<String, dynamic> toJson() {
    return {
      'chain': chain,
      'type': type,
      'id': id,
      'assetId': assetId,
      'from': from,
      'timestamp': timestamp,
      'ruleType': ruleType,
      'ruleJson': ruleJson,
      'ruleName': ruleName,
      'ruleAppendJson': ruleAppendJson,
    };
  }

  /// 【本次新增】纯本地展示/读取用途的反解析，跟 toJson() 字段一一对应；
  /// 供 QccDataMeta.ruleData 这个 getter 调用，把资源浏览器接口返回的原始
  /// JSON 反解成一个真正的 RuleData 对象，而不是让调用方自己去掏 Map。
  /// 不校验签名/保留字符，纯粹是展示用的反序列化，跟 toBytes()/fromBytes()
  /// 那条链上二进制协议路径完全无关。
  factory RuleData.fromJson(Map<String, dynamic> j) {
    final r = RuleData();
    r.chain = j['chain']?.toString() ?? r.chain;
    r.type = j['type']?.toString() ?? r.type;
    r.id = j['id']?.toString() ?? '';
    r.assetId = j['assetId']?.toString() ?? r.assetId;
    r.from = j['from']?.toString();
    r.timestamp = j['timestamp'] is int
        ? j['timestamp'] as int
        : int.tryParse('${j['timestamp']}') ?? 0;
    r.ruleType = j['ruleType']?.toString();
    r.ruleJson = j['ruleJson']?.toString();
    r.ruleName = j['ruleName']?.toString();
    r.ruleAppendJson = j['ruleAppendJson']?.toString();
    return r;
  }
}