/// 对应 Java GasRecord 及接口返回的分页包装
/// 接口返回结构：
/// {
///   "address": "Q1DAw...",
///   "size": 50,
///   "count": 2,
///   "page": 0,
///   "records": [ { GasRecord }, ... ]
/// }

import 'dart:math';

// 【路径假设，跟之前 TransferSuccessPage.dart 用的是同一个 QccAssetService】
// 如果 GasRecord.dart 实际所在目录跟这个包路径对不上，麻烦帮我改一下。
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

class GasRecord {
  final String txType;       // "NORMAL" | "WIN" | "RULE_USER" | "RULE_ASSET" | "ENTITY_DATA"
  final String payer;        // 实际扣 gas 的地址
  final String to;           // 收款地址
  final String assetId;      // 资产 ID（如 "QCC"，也可能是其他精度不同的资产，如 USDS）
  final int amount;          // 转账金额（链上原始值/最小单位，单位精度取决于 assetId，不能固定按 1e9）
  final int totalGas;        // 总 gas（nano 单位，gas 永远是 QCC 原生币，固定按 1e9 显示）
  final int leaderUnits;     // leader 分成
  final int systemIncome;    // 系统收入
  final int devReward;       // 开发者奖励（无时为 0）
  final String? devAddress;  // 开发者地址（无时为 null）
  final String nodeId;       // 出块节点（leader）
  final String txId;         // 原始交易 hash
  final String containerHash;// 所属容器 tailHash
  final int timestamp;       // 容器时间戳（毫秒）

  const GasRecord({
    required this.txType,
    required this.payer,
    required this.to,
    required this.assetId,
    required this.amount,
    required this.totalGas,
    required this.leaderUnits,
    required this.systemIncome,
    required this.devReward,
    this.devAddress,
    required this.nodeId,
    required this.txId,
    required this.containerHash,
    required this.timestamp,
  });

  factory GasRecord.fromJson(Map<String, dynamic> json) {
    return GasRecord(
      txType:        json['txType']        ?? 'NORMAL',
      payer:         json['payer']         ?? '',
      to:            json['to']            ?? '',
      assetId:       json['assetId']       ?? 'QCC',
      amount:        (json['amount']       as num?)?.toInt() ?? 0,
      totalGas:      (json['totalGas']     as num?)?.toInt() ?? 0,
      leaderUnits:   (json['leaderUnits']  as num?)?.toInt() ?? 0,
      systemIncome:  (json['systemIncome'] as num?)?.toInt() ?? 0,
      devReward:     (json['devReward']    as num?)?.toInt() ?? 0,
      devAddress:    json['devAddress'],
      nodeId:        json['nodeId']        ?? '',
      txId:          json['txId']          ?? '',
      containerHash: json['containerHash'] ?? '',
      timestamp:     (json['timestamp']    as num?)?.toInt() ?? 0,
    );
  }

  /// 格式化时间
  String get timeStr {
    if (timestamp == 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// gas 费用——gas 永远是 QCC 原生币（不会是别的资产），固定按 QCC 的 9 位精度
  /// 换算是对的，这里不是bug，跟下面 amountFormatted 的情况不一样。
  String get gasFormatted => (totalGas / 1e9).toStringAsFixed(3);

  /// 转账金额——【本次修复】原来这里固定 `/1e9` + `toStringAsFixed(9)`，
  /// 相当于不管 assetId 是什么资产都当成 QCC(9精度) 处理。gas 那样写没问题是
  /// 因为 gas 永远是 QCC，但这里的 amount 单位是 assetId 对应的资产，比如
  /// USDS 是 2 位精度，硬编码 9 位精度会导致跟之前 TransferSuccessPage.dart
  /// 里那次一模一样的对标错误/显示错乱——现在改成按 assetId 去 QccAssetService
  /// 里查真实精度再换算，查不到时兜底按 9 位精度处理（跟 QccAssetService 内部
  /// 几个方法的兜底逻辑保持一致）。
  String get amountFormatted {
    final assetInstance = QccAssetService().followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      orElse: () => QccAsset(
        assetId: assetId,
        type: 'COIN',
        precision: 9,
        isFollowing: true,
        address: 'Q9999...',
      ),
    );
    final double divider = pow(10, assetInstance.precision).toDouble();
    String s = (amount / divider).toStringAsFixed(assetInstance.precision);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s.isEmpty ? '0' : s;
  }

  /// txType 的中文标签
  String get txTypeLabel {
    switch (txType) {
      case 'WIN':         return '出块奖励';
      case 'RULE_USER':   return '用户规则';
      case 'RULE_ASSET':  return '资产规则';
      case 'ENTITY_DATA': return '实体数据';
      case 'NORMAL':
      default:            return '普通交易';
    }
  }
}

/// 接口返回的分页包装
class GasRecordPage {
  final String address;
  final int size;    // 每页大小
  final int count;   // 本次返回条数
  final int page;    // 当前页码
  final List<GasRecord> records;

  const GasRecordPage({
    required this.address,
    required this.size,
    required this.count,
    required this.page,
    required this.records,
  });

  factory GasRecordPage.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    final List<GasRecord> records = (rawRecords is List)
        ? rawRecords.map((e) => GasRecord.fromJson(e as Map<String, dynamic>)).toList()
        : [];
    return GasRecordPage(
      address: json['address'] ?? '',
      size:    (json['size']  as num?)?.toInt() ?? 0,
      count:   (json['count'] as num?)?.toInt() ?? 0,
      page:    (json['page']  as num?)?.toInt() ?? 0,
      records: records,
    );
  }

  bool get isEmpty => records.isEmpty;
}