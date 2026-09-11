import 'dart:convert';
import 'dart:developer' as LogObj;

enum MultiSigStatus { pending, signing, completed, failed }

class QccMultiSig {
  final String createHash;     // 发起创建的哈希（凭据）
  final int threshold;         // 必须签名的权重总和（M）
  final List<String> signers;  // 参与者的公钥或地址（N）
  final Map<String, int> weights; // 每个参与者的权重
  final MultiSigStatus status;

  QccMultiSig({
    required this.createHash,
    required this.threshold,
    required this.signers,
    required this.weights,
    this.status = MultiSigStatus.pending,
  });

  // 从 Java 端的 RuleData 或 MultiSignature 转换而来
  factory QccMultiSig.fromHash(String hash, Map<String, dynamic> data) {
    return QccMultiSig(
      createHash: hash,
      threshold: data['threshold'] ?? 1,
      signers: List<String>.from(data['signers'] ?? []),
      weights: Map<String, int>.from(data['weights'] ?? {}),
    );
  }
}


// 建议的数据模型，兼容你提供的 Log 结构
class MultiSigResult {
  final String txHash;
  final List<String> owners;
  final int threshold;
  final String ruleName;

  MultiSigResult.fromLog(Map<String, dynamic> response) :
        txHash = response['txHash'] ?? '',
  // 解析嵌套的 data 字符串
        threshold = jsonDecode(response['data'])['threshold'] ?? 0,
        owners = List<String>.from(jsonDecode(jsonDecode(response['data'])['ruleJson'])['owners'] ?? []),
        ruleName = jsonDecode(response['data'])['ruleName'] ?? '';
}



class MultiSigAccount {
  final String multiAddress;
  final List<String> owners;
  final int threshold;
  final String? txHash;
  final int createTime; // 依然保留，但会自动生成

  MultiSigAccount({
    required this.multiAddress,
    required this.owners,
    required this.threshold,
    this.txHash,
    int? createTime, // 设为可选
  }) : createTime = createTime ?? DateTime.now().millisecondsSinceEpoch; // 自动赋能系统时间

  // 你的高级算法逻辑：实际签署人数
  /// 调整后的计算逻辑
  int get actualSignerCount {
    if (owners.isEmpty) return 0;
    // 使用 Set 对 owners 列表进行去重，得到的就是实际投过票的独立地址总数
    return owners.toSet().length;
  }

  int get maxCount {
    if (owners.isEmpty) return 0;
    // 使用 Set 对 owners 列表进行去重，得到的就是实际投过票的独立地址总数
    return owners.toSet().length;
  }

  List<String> get addrs{
    return owners.toSet().toList();
  }

  Map<String, dynamic> toMap() => {
    'multiAddress': multiAddress,
    'owners': owners,
    'threshold': threshold,
    'txHash': txHash,
    'createTime': createTime,
  };

  factory MultiSigAccount.fromMap(Map<String, dynamic> map) => MultiSigAccount(
    multiAddress: map['multiAddress'] ?? "",
    owners: List<String>.from(map['owners'] ?? []),
    threshold: map['threshold'] ?? 0,
    txHash: map['txHash'],
    createTime: map['createTime'], // 从存储读取时恢复时间
  );
}

class MultiSigParser {
  static MultiSigAccount? parse(Map<String, dynamic> item) {
    try {
      String? mAddress;
      List<String> owners = [];
      int threshold = 0;

      // 统一解析逻辑：逐层剥离 QCC 的嵌套 JSON
      Map<String, dynamic> bizData = {};

      if (item['data'] != null) {
        // 如果是 Service 返回的 Wrapper 数据
        bizData = item['data'];
      } else {
        bizData = item;
      }

      // 解析 ruleJson
      if (bizData['ruleJson'] != null) {
        final rule = bizData['ruleJson'] is String
            ? jsonDecode(bizData['ruleJson'])
            : bizData['ruleJson'];

        mAddress = rule['multiaddress'] ?? rule['multiAddress'];
        owners = List<String>.from(rule['owners'] ?? []);
        threshold = rule['threshold'] ?? 0;
      }

      // 判定：只有 M 地址存在且满足 QCC 算法逻辑才算有效资产
      if (mAddress != null && mAddress.startsWith('M')) {
        return MultiSigAccount(
          multiAddress: mAddress,
          owners: owners, // 【关键】不再去重，保留所有签署序列用于审计
          threshold: threshold,
          txHash: item['txHash'],
          createTime: DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      LogObj.log("Parser Error: $e");
    }
    return null;
  }
}