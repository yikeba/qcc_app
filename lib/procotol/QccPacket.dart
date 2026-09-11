import 'dart:convert';
import 'dart:typed_data';

class QccPacket {
  String publicKey;
  String signature;
  String payloadJson;
  int clientTime;
  int nonce;

  QccPacket({
    required this.publicKey,
    required this.signature,
    required this.payloadJson,
    required this.clientTime,
    required this.nonce,
  });

  Uint8List toBytes() {
    // 1. 预转换所有字节
    Uint8List pubBytes = Uint8List.fromList(utf8.encode(publicKey));
    Uint8List sigBytes = Uint8List.fromList(utf8.encode(signature));
    Uint8List payBytes = Uint8List.fromList(utf8.encode(payloadJson));

    // 打印调试：核对这里输出的 payBytes.length 是否是服务器报错的 344
    print("PayloadJson Length: ${payBytes.length}");
    print("PayloadJson Content: $payloadJson");

    // 2. 计算精确总长度
    int totalSize = 4 + pubBytes.length +
        4 + sigBytes.length +
        8 + 8 +
        4 + payBytes.length;

    ByteData bd = ByteData(totalSize);
    int pos = 0;
    // 写入 PublicKey (BigEndian)
    bd.setInt32(pos, pubBytes.length); pos += 4;
    bd.buffer.asUint8List().setRange(pos, pos + pubBytes.length, pubBytes);
    pos += pubBytes.length;

    // 写入 Signature
    bd.setInt32(pos, sigBytes.length); pos += 4;
    bd.buffer.asUint8List().setRange(pos, pos + sigBytes.length, sigBytes);
    pos += sigBytes.length;

    // 写入 clientTime & Nonce
    bd.setInt64(pos, clientTime); pos += 8;
    bd.setInt64(pos, nonce); pos += 8;

    // 写入 Payload
    bd.setInt32(pos, payBytes.length); pos += 4;
    bd.buffer.asUint8List().setRange(pos, pos + payBytes.length, payBytes);

    return bd.buffer.asUint8List();
  }

  // 保留 JSON 供其他地方使用
  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'signature': signature,
    'payloadJson': payloadJson,
    'clientTime': clientTime,
    'nonce': nonce,
  };
}