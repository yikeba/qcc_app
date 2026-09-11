import 'dart:convert';

class MultiSignature {
  String multiaddress = "";
  List<String> owners;
  int threshold;
  int nonce;

  MultiSignature({
    required this.owners,
    required this.threshold,
  }) : nonce = DateTime.now().microsecondsSinceEpoch;


  String toJson() => jsonEncode({
    'multiaddress': multiaddress,
    'owners': owners,
    'threshold': threshold,
    'nonce': nonce,
  });
}