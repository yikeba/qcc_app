/// 所有 QccBaseData 子类共用的二进制读写工具，对应 Java QccBaseData 的
/// writeString/readString/writeHash/readHash/writeBaseBytes/readBaseBytes
/// + ByteBuffer 基础读写。EntityData / RuleData / MultiTransactionData 都用这份。
///
/// 注：transaction_data.dart 里已经有一份几乎一样的私有实现（当时先交付，
/// 没有抽公共文件）。这份是给新增的三个类型用的，逻辑完全一致，
/// 后续你可以把 transaction_data.dart 也切换成 import 这份、删掉它自己的私有版本，
/// 我没有主动去改那个文件，怕引入不必要的回归风险，先并存。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/digests/sha3.dart';

class ByteWriter {
  final BytesBuilder _b = BytesBuilder();

  void putByte(int v) => _b.addByte(v & 0xFF);

  void putInt32(int v) {
    final bd = ByteData(4)..setInt32(0, v, Endian.big);
    _b.add(bd.buffer.asUint8List());
  }

  void putInt64(int v) {
    final bd = ByteData(8)..setInt64(0, v, Endian.big);
    _b.add(bd.buffer.asUint8List());
  }

  void putDouble(double v) {
    final bd = ByteData(8)..setFloat64(0, v, Endian.big);
    _b.add(bd.buffer.asUint8List());
  }

  void putBytes(List<int> bytes) => _b.add(bytes);

  Uint8List toBytes() => _b.toBytes();
}

class ByteReader {
  final ByteData _data;
  final Uint8List _raw;
  int _pos = 0;

  ByteReader(Uint8List bytes)
      : _raw = bytes,
        _data = ByteData.sublistView(bytes);

  int get remaining => _raw.length - _pos;

  int getByte() {
    final v = _data.getUint8(_pos);
    _pos += 1;
    return v;
  }

  int getInt32() {
    final v = _data.getInt32(_pos, Endian.big);
    _pos += 4;
    return v;
  }

  int getInt64() {
    final v = _data.getInt64(_pos, Endian.big);
    _pos += 8;
    return v;
  }

  double getDouble() {
    final v = _data.getFloat64(_pos, Endian.big);
    _pos += 8;
    return v;
  }

  Uint8List getBytes(int len) {
    final v = Uint8List.sublistView(_raw, _pos, _pos + len);
    _pos += len;
    return v;
  }
}

Uint8List hexToBytes(String hexStr) {
  final out = Uint8List(hexStr.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(Uint8List bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

String sha3256HexOfString(String payload) => sha3256HexOfBytes(Uint8List.fromList(utf8.encode(payload)));

String sha3256HexOfBytes(Uint8List input) {
  final digest = SHA3Digest(256);
  final output = digest.process(input);
  return bytesToHex(output);
}

// 对应 QccBaseData.writeString / readString
void writeString(ByteWriter w, String? str) {
  if (str == null) {
    w.putInt32(0);
  } else {
    final bytes = utf8.encode(str);
    w.putInt32(bytes.length);
    w.putBytes(bytes);
  }
}

String readString(ByteReader r) {
  final len = r.getInt32();
  if (len <= 0) return '';
  final bytes = r.getBytes(len);
  return utf8.decode(bytes);
}

// 对应 QccBaseData.writeHash / readHash（64位hex <-> 32字节）
void writeHash(ByteWriter w, String? hex) {
  if (hex == null || hex.length < 64) {
    w.putBytes(Uint8List(32));
  } else {
    w.putBytes(hexToBytes(hex.substring(0, 64)));
  }
}

String readHash(ByteReader r) {
  final bytes = r.getBytes(32);
  return bytesToHex(bytes);
}

/// 对应 QccBaseData 的公共字段集合，供各子类复用。
class QccBaseFields {
  String chain = '';
  String type = '';
  String id = '';
  String? assetId;
  String? from;
  int timestamp = 0;
  String? signatureHash;
}

/// 对应 QccBaseData.writeBaseBytes
void writeBaseBytes(ByteWriter w, int typeCode, QccBaseFields base) {
  w.putByte(typeCode);
  writeString(w, base.chain);
  writeHash(w, base.id);
  writeString(w, base.assetId);
  writeString(w, base.from);
  w.putInt64(base.timestamp);
  writeString(w, base.signatureHash);
}

/// 对应 QccBaseData.readBaseBytes（typeCode 由外部先读/跳过，这里内部处理一致）
QccBaseFields readBaseBytes(ByteReader r) {
  r.getByte(); // 跳过 typeCode
  final b = QccBaseFields();
  b.chain = readString(r);
  b.id = readHash(r);
  b.assetId = readString(r);
  b.from = readString(r);
  b.timestamp = r.getInt64();
  b.signatureHash = readString(r);
  return b;
}