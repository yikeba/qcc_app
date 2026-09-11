class AssetDividendRule {
  final String assetId;         // 要分红的权益资产 (如：ITTC)
  final String dividendAssetId; // 发放的红利币种 (必须是稳定币，如：USD)
  final double amount;          // 总分红金额
  final String memo;            // 公告/备注

  AssetDividendRule({
    required this.assetId,
    required this.dividendAssetId,
    required this.amount,
    this.memo = "",
  });

  Map<String, dynamic> toJson() => {
    "assetId": assetId,
    "dividendAssetId": dividendAssetId,
    "amount": amount,
    "memo": memo,
  };
}