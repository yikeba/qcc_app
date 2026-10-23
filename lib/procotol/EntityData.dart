/// 对应 Java qcc.core.qccData.EntityData（extends QccBaseData）—— 全量字节
/// 存证发布交易结构。字段/方法逐一按你这次上传的 EntityData.java 源码核实。
///
/// 【这是本轮排查"签名不一样"的关键结论，写在最前面】
/// Java 端 QccDataProtocol.encodeEntityData() 签的是 data.getPayloadForHash()
/// 这个"|"拼接的短字符串，不是 toBytes()、也不是 JSON、更不是像 RuleData
/// 那样单独一个 SIGN_SEP 拼接的 toSign()——EntityData 根本没有 toSign()
/// 这个方法，这一点和 RuleData/PledgeRules 不一样，不要套那边的模式。
/// 之前 QccDataBroadcastPage.dart 里手搭的 _signEntityTask 用
/// eData.getPayloadForHash() 当签名对象，这个选择本身是对的；真正的风险
/// 点在于：这个文件（EntityData.dart）在项目里此前并未提供给我核实，如果
/// 它现有实现里 getPayloadForHash() 拼接的字段、顺序、分隔符，或者
/// toBytes() 的二进制布局，和 Java 源码对不上——尤其是 fromdev 字段（本次
/// 核实到的、之前 Dart 页面完全没有设置过的新字段，同时参与 id 与签名）——
/// 服务端重放校验时用 fromBytes() 反序列化回来的 EntityData 重新算一遍
/// getPayloadForHash() 去验签，只要哪个字段没对齐，就会表现成"签名不一样/
/// 验签失败"，即使 Dilithium 签名算法本身完全没问题。这个文件就是照
/// EntityData.java 重新完整实现一遍，从根源上保证这个对齐。
///
/// 【逐项核实】
/// - fromdev：开发者推广地址，参与 getPayloadForHash()/id 计算。之前的
///   QccDataBroadcastPage.dart 从未设置过这个字段，需要你告诉我 App 里
///   这个值应该从哪来（详见我这次回复正文）。
/// - payload：核心载荷，上限 1MB（MAX_PAYLOAD_SIZE=1024*1024）——注意不是
///   你口头说的 256KB，这是 Java 源码注释"载荷上限调整为 1MB"里写明的，
///   已经在回复正文里跟你确认。
/// - getPayloadForHash()：assetId|from|fromdev|dataDigest|timestamp，
///   dataDigest = payload 非空时 SHA3-256(payload) 的 hex；payload 为空
///   (凭证包场景) 则用已有 dataHash，再没有就是字面量 "empty"。
/// - toBytes()：按 payload 是否为空自动二选一：
///     MODE_FULL(0x01)    = baseBytes + fromdev + 0x01 + 4B payloadLen + payload
///     MODE_RECEIPT(0x02) = baseBytes + fromdev + 0x02 + 4B payloadSize + 32B dataHash
///   "凭证包"(MODE_RECEIPT) 是 Java 注释里"影子账本两阶段提交"给余额状态机
///   用的，客户端(本 Dart 钱包 App)发起存证时 payload 必然非空，实际总是走
///   MODE_FULL 这条路径——toReceipt()/凭证包这条路径这里照样完整实现，
///   只是标注清楚客户端目前用不到，纯粹是为了 fromBytes() 能够对称解析、
///   以及未来万一需要复用。
/// - baseBytes / fromdev / mode-byte 这几段的读写完全复用
///   QccBaseFields.dart 里 writeBaseBytes/readBaseBytes/writeString/
///   readString/writeHash/readHash 这套已经给 RuleData.dart 用过的工具
///   （该文件头部注释本来就写明是"EntityData / RuleData / MultiTransactionData
///   都用这份"），字段顺序/长度前缀格式和 Java QccBaseData 对齐的假设也是
///   沿用 RuleData.dart 已经验证过的那一份，没有另起炉灶。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'QccBaseFields.dart';

class EntityData {
  // ---- 基类(QccBaseData)字段 ----
  String chain = '6666';
  String type = 'entity';
  String id = '';
  String? assetId;
  String? from;
  int timestamp = 0;
  String? signatureHash;

  // ---- 本类新增，上链字段 ----
  /// 开发者推广地址；参与 getPayloadForHash()，即参与 id 与签名。
  String? fromdev;

  /// 唯一核心载荷；为 null/空时 toBytes() 自动走"凭证包"路径。
  Uint8List? payload;

  // ---- 本地计算字段，不参与 JSON/不参与上链序列化的"业务字段"部分 ----
  // 【和 Java 一致】这两个字段本身确实会被 writeBaseBytes 之外的
  // mode-byte 分支写进二进制(凭证包路径里 payloadSize/dataHash 是主体)，
  // 但不参与 toJson()（Java 用 @JSONField(serialize=false) 标注）。
  int payloadSize = 0;
  String? dataHash;

  static const int typeCode = 3; // 对应 Java getTypeCode()
  static const int maxPayloadSize = 1024 * 1024; // 对应 MAX_PAYLOAD_SIZE，1MB，不是256KB

  static const int _modeFull = 0x01;
  static const int _modeReceipt = 0x02;

  /// 拼接签名字符串用的分隔符——注意这是 EntityData 自己在
  /// getPayloadForHash() 里直接用的业务分隔符"|"，和 RuleData.dart 那个
  /// 防重放校验用的保留字符 SIGN_SEP("`")是两回事，不要混用。
  static const String _fieldSep = '|';

  /// 【和 RuleData.dart 一致的保留字符】沿用 QccBaseData 基类的
  /// validateNoReservedChar() 防护——防的是这个反引号，不是上面那个竖线。
  /// Java 源码里 EntityData 自己 override 了 validateNoReservedChar()，
  /// 多加了一条 fromdev 的校验，这里原样照做。
  static const String _reservedChar = '`';

  EntityData() {
    timestamp = DateTime.now().millisecondsSinceEpoch;
    chain = getChain();
  }

  /// 对应 Java EntityData.getChain()：LogObj.isDebug() ? "6666" : "9999"。
  static String getChain() => kDebugMode ? "6666" : "9999";

  /// 对应 getTxHash()：id 为空则先 finalizeId()，再返回。
  String getTxHash() {
    if (id.isEmpty) finalizeId();
    return id;
  }

  /// 对应 getPayloadForHash()——这是真正被签名的字符串。
  String getPayloadForHash() {
    ensureLocalFields();
    final String dataDigest = (payload != null && payload!.isNotEmpty)
        ? sha3256HexOfBytes(payload!)
        : ((dataHash != null && dataHash!.isNotEmpty) ? dataHash! : "empty");
    return [
      assetId ?? '',
      from ?? '',
      fromdev ?? '',
      dataDigest,
      timestamp.toString(),
    ].join(_fieldSep);
  }

  /// 对应 EntityData 覆写的 validateNoReservedChar()：先调用基类校验
  /// (chain/from/assetId)，再补充校验 fromdev。
  void validateNoReservedChar() {
    _checkField('assetId', assetId);
    _checkField('chain', chain);
    _checkField('from', from);
    _checkField('fromdev', fromdev);
  }

  static void _checkField(String name, String? v) {
    if (v != null && v.contains(_reservedChar)) {
      throw ArgumentError('字段 [$name] 包含系统保留字符 "$_reservedChar"，交易被拒绝');
    }
  }

  /// 对应基类 finalizeId()：校验保留字符后，对 getPayloadForHash() 做
  /// SHA3-256 得到 id(=txHash)。
  void finalizeId() {
    validateNoReservedChar();
    id = sha3256HexOfString(getPayloadForHash());
  }

  /// 对应 ensureLocalFields()：懒计算 payloadSize/dataHash，只算一次。
  void ensureLocalFields() {
    if (payload != null && payload!.isNotEmpty) {
      payloadSize = payload!.length;
      if (dataHash == null || dataHash!.isEmpty) {
        dataHash = sha3256HexOfBytes(payload!);
      }
    } else {
      payloadSize = payloadSize > 0 ? payloadSize : 0;
      dataHash = (dataHash != null && dataHash!.isNotEmpty) ? dataHash : "empty";
    }
  }

  /// 对应 toReceipt()：生成剥离 payload 的"凭证对象"，供余额状态机场景
  /// 使用。【标注】客户端目前的存证发布场景不需要调用这个方法——发起
  /// 存证时 payload 必然非空，直接调 toBytes() 就会走完整包路径。
  EntityData toReceipt() {
    ensureLocalFields();
    final r = EntityData();
    r.chain = chain;
    r.type = type;
    r.id = id;
    r.assetId = assetId;
    r.from = from;
    r.fromdev = fromdev;
    r.timestamp = timestamp;
    r.signatureHash = signatureHash;
    r.payloadSize = payloadSize;
    r.dataHash = dataHash;
    r.payload = null;
    return r;
  }

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

  /// 对应 toBytes()：按 payload 是否非空自动二选一。
  Uint8List toBytes() {
    ensureLocalFields();
    if (payload != null && payload!.isNotEmpty) {
      return _toBytesAsFull();
    } else {
      return _toBytesAsReceipt();
    }
  }

  Uint8List _toBytesAsFull() {
    if (payload!.length > maxPayloadSize) {
      throw StateError('Entity payload exceeds $maxPayloadSize bytes (1MB) limit!');
    }
    final w = ByteWriter();
    writeBaseBytes(w, typeCode, _baseFields());
    writeString(w, fromdev);
    w.putByte(_modeFull);
    w.putInt32(payload!.length);
    w.putBytes(payload!);
    return w.toBytes();
  }

  Uint8List _toBytesAsReceipt() {
    final w = ByteWriter();
    writeBaseBytes(w, typeCode, _baseFields());
    writeString(w, fromdev);
    w.putByte(_modeReceipt);
    w.putInt32(payloadSize);
    writeHash(w, dataHash);
    return w.toBytes();
  }

  /// 对应 fromBytes()：按 1B 模式标识精确分流，和 Java 端保持完全对称。
  static EntityData? fromBytes(Uint8List data) {
    if (data.isEmpty) return null;
    try {
      final r = ByteReader(data);
      final entity = EntityData();
      final base = readBaseBytes(r);
      entity.chain = base.chain;
      entity.id = base.id;
      entity.assetId = base.assetId;
      entity.from = base.from;
      entity.timestamp = base.timestamp;
      entity.signatureHash = base.signatureHash;

      entity.fromdev = readString(r);

      if (r.remaining < 1) {
        // 老版本仅基础字段的包，保持原语义直接返回。
        return entity;
      }

      final int mode = r.getByte();
      if (mode == _modeFull) {
        if (r.remaining < 4) return null;
        final int payloadLen = r.getInt32();
        if (payloadLen <= 0 || payloadLen > maxPayloadSize || r.remaining < payloadLen) {
          return null;
        }
        entity.payload = r.getBytes(payloadLen);
        entity.payloadSize = payloadLen;
        entity.dataHash = sha3256HexOfBytes(entity.payload!);
      } else if (mode == _modeReceipt) {
        if (r.remaining < 4 + 32) return null;
        final int size = r.getInt32();
        if (size < 0 || size > maxPayloadSize) return null;
        entity.payloadSize = size;
        entity.dataHash = readHash(r);
        entity.payload = null;
      } else {
        return null;
      }
      return entity;
    } catch (e) {
      return null;
    }
  }

  /// 纯本地展示/调试用途，不用于签名/网络传输(那条路径走 toBytes())。
  Map<String, dynamic> toJson() {
    return {
      'chain': chain,
      'type': type,
      'id': id,
      'assetId': assetId,
      'from': from,
      'fromdev': fromdev,
      'timestamp': timestamp,
      'signatureHash': signatureHash,
      'payload': (payload == null) ? null : base64Encode(payload!),
    };
  }

  factory EntityData.fromJson(Map<String, dynamic> j) {
    final e = EntityData();
    e.chain = j['chain']?.toString() ?? e.chain;
    e.type = j['type']?.toString() ?? e.type;
    e.id = j['id']?.toString() ?? '';
    e.assetId = j['assetId']?.toString();
    e.from = j['from']?.toString();
    e.fromdev = j['fromdev']?.toString();
    e.timestamp = j['timestamp'] is int ? j['timestamp'] as int : int.tryParse('${j['timestamp']}') ?? 0;
    e.signatureHash = j['signatureHash']?.toString();
    final p = j['payload'];
    e.payload = (p is String && p.isNotEmpty) ? base64Decode(p) : null;
    return e;
  }
}