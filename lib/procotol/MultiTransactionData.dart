/// 对应 Java qcc.core.qccData.MultiTransactionData（typeCode = 4，多签转账）。
///
/// 本次改动：对照你上传的 MultiTransactionData.java 源码，和你自己现在这份 Dart
/// 草稿逐行比对后修的。草稿本身字段名/字段类型都是对的，缺的都是"签名相关"的
/// 方法——也就是说，之前 QccMultiSigTransferPage.dart / QccFollowTransactionPage.dart
/// 里调用的 `mudata.toSign()` 在这份草稿里根本不存在，编译都过不了。逐条说明：
///
/// 1.【新增，之前完全缺失】toSign()。这是本次最关键的补丁：没有这个方法，
///    多签转账/追加签署时签的字符串就是 undefined，之前两个页面里 QccTxFlow.run()
///    的 buildPayload 回调调用 mudata.toSign() 会直接报"方法不存在"编译错误。
///    字段顺序、SIGN_SEP 拼接严格按 Java 源码搬：
///    assetId, chain, from, fromMulti, to, amount, timestamp, memo, txType,
///    matchLogicToSign(matchLogic), matcHash, mutxHash, mutxList, id
///    （matchLogic 为 null 时贡献 1 个空字符串字段，14 段；非 null 时展开为
///    5 个子字段，净增 4 段，共 18 段——和 Java parseSignFields() 的注释一致）。
///
/// 2.【新增】signSep 常量。沿用 RuleData.dart / QccTransactionData.dart 里已经在
///    用的反引号 "`"。同样的免责声明：我没看到 QccBaseData.java 源码，不能
///    100% 确认 MultiTransactionData.java 的 SIGN_SEP 和另外两个文件是同一个值，
///    只是三份 Java 类都继承同一个 QccBaseData 基类，大概率是同一个常量。
///    如果你手上有 QccBaseData.java，麻烦确认一下。
///
/// 3.【修复】getPayloadForHash() 的 null 处理。你的草稿里所有可空字段统一用了
///    `?? ''`，但 Java 源码里只有 memo 和 mutxHash 显式做了三元判断
///    （`memo != null ? memo : ""` / `mutxHash != null ? mutxHash : ""`），
///    chain/from/fromMulti/to/assetId 都是裸的 `+` 拼接——如果这些字段在 Java
///    端真的是 null，字符串拼接结果会是字面量 "null" 这四个字符，而不是空串。
///    这是"按 Java 原样保留歧义行为"的一贯做法（QccTransactionData.dart 头部
///    注释也提过同样的原则）：Dart 的字符串插值 `$field` 对 null 值同样会输出
///    "null" 四个字符，行为天然对齐，所以这几个字段直接用插值，不要加 `?? ''`。
///    这样才能保证 Dart 算出来的 id/toSign() 签名原文和 Java 端字节对齐；如果用
///    `?? ''`，一旦某个字段真的为 null，两端算出来的 hash/签名会对不上。
///
/// 4.【新增】validateNoReservedChar() + checkField()。防止字段里混入 signSep
///    本身导致 toSign() 拼出来的字符串产生"隐藏字段"歧义，和 RuleData.dart 里
///    的 _checkField 同一个道理。因为 Dart 这边没有真的继承 QccBaseData 基类，
///    基类校验的 assetId/chain/from 这几个字段也直接内联在这个方法里一起查。
///
/// 5.【新增】getTxHash() / verifySignString() / parseSignFields()，逐一对应
///    Java 同名方法。
///
/// 6.【移除】草稿里那个没人用的私有 _baseFields()（组装一个 QccBaseFields 对象），
///    这个类根本没有 toBytes()/fromBytes()，_baseFields() 纯属死代码。已按项目
///    既定约定（前端不做二进制序列化，只走 toJson()/toSign()）删掉。
///    同时删掉了草稿里未使用的 `dart:typed_data` import。
///
/// 7. toJson() / finalizeId() / 各字段声明保持你草稿里原样，这两处本来就和
///    Java 对得上，没有改动。
///
/// 8.【待你确认】matchLogic 字段：QccMatchLogic.dart 这个文件我手上没有源码
///    （草稿里只是 import 了它），_matchLogicToSign() 里直接按 Java 源码用到的
///    5 个字段名（pairAssetId / rate / maxParticipants / rule / remainingAmount）
///    访问，字段名应该没问题（这是从 Java 源码里直接抄的），但 rate /
///    remainingAmount 具体是 int 还是 double，我按 Java `String.valueOf(...)`
///    统一用 `.toString()` 处理，两边数值类型只要 toString() 结果一致（比如
///    Java long 和 Dart int 都是 "123" 这种不带小数点的形式）就没问题；如果
///    Java 里 rate/remainingAmount 其实是 double 而 Dart 那边存成了 int，
///    toString() 结果可能不一致（"1.0" vs "1"），麻烦把 QccMatchLogic.dart 发我核对。
library;

import 'QccBaseFields.dart';

class MultiTransactionData {
  // ---- 基类字段（对应 Java QccBaseData） ----
  String chain = '6666';
  String type = 'multitransaction';
  String id = '';
  String? assetId;
  String? from;
  int timestamp = 0;
  String? signatureHash;

  // ---- 业务字段（对应 Java MultiTransactionData） ----
  String? fromMulti; // 多签地址 (M开头)
  String? to; // 接收地址
  int amount = 0; // 金额
  String? memo; // 备注 (可选)
  String? txType; // 交易子类型 (pay, transfer, open, win)
  QccMatchLogic? matchLogic; // 撮合逻辑 (可选)
  String? matcHash; // 撮合关联Hash (可选)
  String? mutxHash; // 多签会话Hash：首笔交易的ID。为空表示创建，非空表示追加。
  String? mutxList; // 完成多签的其他交易单List 结构

  static const int typeCode = 4; // 多签交易固定 Code 4

  MultiTransactionData() {
    timestamp = DateTime.now().millisecondsSinceEpoch;
    chain = getChain();
  }

  /// 对应 Java MultiTransactionData.getChain()：
  /// return LogObj.isDebug() ? "6666" : "9999";
  /// 【待确认，同 RuleData.dart】这里暂用 Flutter 的 kDebugMode 判断调试环境，
  /// 如果 LogObj.dart 已经有专门对应 Java LogObj.isDebug() 的开关，应该改用那个。
  static String getChain() {
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    return isDebug ? "6666" : "9999";
  }

  /// 对应 getPayloadForHash()：
  ///   return chain + from + fromMulti + to + amount + timestamp +
  ///           (memo != null ? memo : "") + assetId +
  ///           (mutxHash != null ? mutxHash : "");
  /// 【重要，见文件顶部第 3 条】chain/from/fromMulti/to/assetId 故意不加 `?? ''`，
  /// 按 Java 原样用字符串插值直接拼接（null 时两端都会得到字面量 "null"）。
  String getPayloadForHash() {
    return '$chain$from$fromMulti$to$amount$timestamp'
        '${memo ?? ""}$assetId'
        '${mutxHash ?? ""}';
  }

  void finalizeId() {
    id = sha3256HexOfString(getPayloadForHash());
  }

  static String nz(String? s) => s ?? '';

  /// 沿用 RuleData.dart 已经在用的反引号，详见文件顶部第 2 条说明。
  static const String signSep = '`';

  /// 【新增，之前完全缺失】对应 Java toSign()：
  ///   public String toSign() {
  ///       requireIdFinalized();
  ///       return String.join(SIGN_SEP,
  ///               nz(assetId), nz(chain), nz(from), nz(fromMulti), nz(to),
  ///               String.valueOf(amount), String.valueOf(timestamp), nz(memo), nz(txType),
  ///               matchLogicToSign(matchLogic), nz(matcHash), nz(mutxHash), nz(mutxList), id);
  ///   }
  String toSign() {
    if (id.isEmpty) {
      throw StateError('必须先调用 finalizeId() 生成 id，才能构造签名内容');
    }
    validateNoReservedChar();
    return [
      nz(assetId),
      nz(chain),
      nz(from),
      nz(fromMulti),
      nz(to),
      amount.toString(),
      timestamp.toString(),
      nz(memo),
      nz(txType),
      _matchLogicToSign(matchLogic),
      nz(matcHash),
      nz(mutxHash),
      nz(mutxList),
      id,
    ].join(signSep);
  }

  /// 对应 Java 私有静态 matchLogicToSign(MatchLogic ml)：
  ///   if (ml == null) return "";
  ///   return String.join(SIGN_SEP, nz(ml.pairAssetId), String.valueOf(ml.rate),
  ///           String.valueOf(ml.maxParticipants), nz(ml.rule),
  ///           String.valueOf(ml.remainingAmount));
  /// 【待确认，见文件顶部第 8 条】字段名已按 Java 源码核对，数值字段的具体类型
  /// （int/double）需要你用 QccMatchLogic.dart 的真实定义核对一下。
  static String _matchLogicToSign(QccMatchLogic? ml) {
    if (ml == null) return '';
    return [
      nz(ml.pairAssetId),
      ml.rate.toString(),
      ml.maxParticipants.toString(),
      nz(ml.rule),
      ml.remainingAmount.toString(),
    ].join(signSep);
  }

  bool verifySignString(String received) => toSign() == received;

  /// 对应 Java parseSignFields()：
  ///   String[] parts = signStr.split(SIGN_SEP, -1);
  ///   if (parts.length != 14 && parts.length != 18) throw ...;
  /// Dart 的 String.split() 本身就不会像 Java 无 limit 参数的 split() 那样丢弃
  /// 末尾空字符串，行为已经和 Java 的 split(SIGN_SEP, -1) 对齐，不需要额外处理。
  static List<String> parseSignFields(String signStr) {
    final parts = signStr.split(signSep);
    if (parts.length != 14 && parts.length != 18) {
      throw ArgumentError('字段数量不符合协议，收到 ${parts.length} 个字段');
    }
    return parts;
  }

  /// 【新增】对应 Java validateNoReservedChar()。Dart 这边没有真的继承
  /// QccBaseData 基类，所以把基类本该校验的 assetId/chain/from 也内联进来，
  /// 和 RuleData.dart 的做法一致。
  void validateNoReservedChar() {
    _checkField('assetId', assetId);
    _checkField('chain', chain);
    _checkField('from', from);
    _checkField('fromMulti', fromMulti);
    _checkField('to', to);
    _checkField('memo', memo);
    _checkField('txType', txType);
    _checkField('matcHash', matcHash);
    _checkField('mutxHash', mutxHash);
    _checkField('mutxList', mutxList);
    if (matchLogic != null) {
      _checkField('matchLogic.pairAssetId', matchLogic!.pairAssetId);
      _checkField('matchLogic.rule', matchLogic!.rule);
    }
  }

  static void _checkField(String fieldName, String? value) {
    if (value != null && value.contains(signSep)) {
      throw ArgumentError('字段 [$fieldName] 包含系统保留字符 "$signSep"，交易被拒绝');
    }
  }

  /// 对应 Java getTxHash()：
  ///   if (this.id == null || this.id.isEmpty()) finalizeId();
  ///   return this.id;
  String getTxHash() {
    if (id.isEmpty) {
      finalizeId();
    }
    return id;
  }

  /// 纯本地展示用途，对应 Java toJson()（走 fastjson2 JSON.toJSONString）。
  /// 不用于签名/网络传输，字段为 null 也显式输出 "key": null。
  Map<String, dynamic> toJson() {
    return {
      'chain': chain,
      'type': type,
      'id': id,
      'assetId': assetId,
      'from': from,
      'timestamp': timestamp,
      'fromMulti': fromMulti,
      'to': to,
      'amount': amount,
      'memo': memo,
      'txType': txType,
      'matchLogic': matchLogic == null
          ? null
          : {
        'pairAssetId': matchLogic!.pairAssetId,
        'rate': matchLogic!.rate,
        'maxParticipants': matchLogic!.maxParticipants,
        'rule': matchLogic!.rule,
        'remainingAmount': matchLogic!.remainingAmount,
      },
      'matcHash': matcHash,
      'mutxHash': mutxHash,
      'mutxList': mutxList,
    };
  }
}

/// 【占位，待你确认】对应 Java qcc.core.qccData.MatchLogic。
/// 我手上没有 QccMatchLogic.dart 的真实源码，这里只按 MultiTransactionData.java
/// 里用到的 5 个字段名声明了一个最小版本，避免这个文件因为缺类定义而编译不过。
/// 如果你项目里已经有 QccMatchLogic.dart，请删掉下面这段，改成：
///   import 'QccMatchLogic.dart';
/// 并核对字段名/类型是否和这里一致。
class QccMatchLogic {
  String? pairAssetId;
  num rate = 0;
  int maxParticipants = 0;
  String? rule;
  num remainingAmount = 0;
}