import 'dart:developer' as LogObj;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/rule/asset/core/AssetMeta.dart';
import '../views/myasset/QccAsset.dart';
import '../views/myasset/QccAssetService.dart';
import '../views/setting/AppTranslator.dart';
import 'QccApiService.dart';

// ✅ 余额回调的数据模型
class QccBalanceResult {
  final String assetId;
  final double amount;
  final String formatted;

  QccBalanceResult({
    required this.assetId,
    required this.amount,
    required this.formatted,
  });
}

typedef AssetFilter = bool Function(QccAsset asset);

class QccActiveWallet extends StatefulWidget {
  final String address;
  final String initialAssetId;
  final double fontSize;
  final Color fontColor;
  final ValueChanged<String>? onAssetChanged;
  final AssetFilter? assetFilter;
  final ValueChanged<QccBalanceResult>? onBalanceLoaded;

  const QccActiveWallet(
      this.address,
      this.initialAssetId, {
        super.key,
        this.fontSize = 22.0,
        this.fontColor = Colors.white,
        this.onAssetChanged,
        this.assetFilter,
        this.onBalanceLoaded,
      });

  static Widget onlyCoins(
      String address,
      String initialAssetId, {
        ValueChanged<String>? onAssetChanged,
        ValueChanged<QccBalanceResult>? onBalanceLoaded,
        Color color = Colors.white,
        double fontSize = 20,
      }) {
    return QccActiveWallet(
      address,
      initialAssetId,
      fontColor: color,
      fontSize: fontSize,
      onAssetChanged: onAssetChanged,
      onBalanceLoaded: onBalanceLoaded,
      assetFilter: (asset) => asset.type == AssetMetaType.COIN.name,
    );
  }

  static Widget onlyStables(
      String address,
      String initialAssetId, {
        ValueChanged<String>? onAssetChanged,
        ValueChanged<QccBalanceResult>? onBalanceLoaded,
        Color color = Colors.teal,
      }) {
    return QccActiveWallet(
      address,
      initialAssetId,
      fontColor: color,
      onAssetChanged: onAssetChanged,
      onBalanceLoaded: onBalanceLoaded,
      assetFilter: (asset) => asset.type == AssetMetaType.Stablecoin.name,
    );
  }

  @override
  State<QccActiveWallet> createState() => _QccActiveWalletState();
}

class _QccActiveWalletState extends State<QccActiveWallet> {
  late String _currentAssetId;
  // 核心优化：将 Future 持久化，防止 build 重新触发
  Future<String>? _balanceFuture;

  @override
  void initState() {
    super.initState();
    _currentAssetId = widget.initialAssetId;
    _refreshBalance(); // 初始化加载
  }

  @override
  void didUpdateWidget(covariant QccActiveWallet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果地址变了，需要重新加载
    if (oldWidget.address != widget.address) {
      _refreshBalance();
    }
  }

  /// 刷新余额的方法：手动控制 Future 的生命周期
  void _refreshBalance() {
    setState(() {
      _balanceFuture = _getFormattedBalance();
    });
  }

  Future<String> _getFormattedBalance() async {
    try {
      final assetInstance = QccAssetService().followAsset.firstWhere(
            (a) => a.assetId.toUpperCase() == _currentAssetId.toUpperCase(),
        orElse: () => QccAsset(assetId: _currentAssetId, type: "COIN", precision: 9, address: 'Q...'),
      );

      QccBalance balanceTool = QccBalance(widget.address, _currentAssetId);
      balanceTool.precision = assetInstance.precision;
      balanceTool.unit = BigInt.from(pow(10, assetInstance.precision));

      final String formattedStr = await balanceTool.getFormattedBalance(decimalPlaces: assetInstance.precision);
      final double realAmount = double.tryParse(formattedStr.replaceAll(',', '')) ?? 0.0;

      String uiFormatted = realAmount.toStringAsFixed(2);
      if (assetInstance.precision >= 4) {
        uiFormatted = realAmount.toStringAsFixed(4);
      }

      // 触发回调
      if (widget.onBalanceLoaded != null) {
        final result = QccBalanceResult(
          assetId: _currentAssetId,
          amount: realAmount,
          formatted: formattedStr,
        );
        Future.microtask(() {
          if (mounted) widget.onBalanceLoaded!(result);
        });
      }

      return uiFormatted;
    } catch (e) {
      LogObj.log("错误读取余额: $e");
      if (widget.onBalanceLoaded != null) {
        Future.microtask(() {
          if (mounted) {
            widget.onBalanceLoaded!(QccBalanceResult(assetId: _currentAssetId, amount: 0.0, formatted: "0"));
          }
        });
      }
      return "0.00";
    }
  }

  @override
  Widget build(BuildContext context) {
    // 软键盘弹出导致的 build 不会再触发 _getFormattedBalance()，因为 _balanceFuture 引用没变
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FutureBuilder<String>(
          future: _balanceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 24,
                width: 40,
                child: Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  ),
                ),
              );
            }
            return Text(
              snapshot.data ?? "0.00",
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w900,
                color: widget.fontColor,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        _buildAssetChip(),
      ],
    );
  }

  Widget _buildAssetChip() {
    return GestureDetector(
      onTap: _showAssetPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentAssetId,
              style: TextStyle(
                  color: widget.fontColor,
                  fontSize: widget.fontSize - 4,
                  fontWeight: FontWeight.bold
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: widget.fontColor),
          ],
        ),
      ),
    );
  }

  void _showAssetPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final List<QccAsset> allAssets = QccAssetService().followAsset;
        final List<QccAsset> displayAssets = widget.assetFilter != null
            ? allAssets.where((asset) => widget.assetFilter!(asset)).toList()
            : allAssets;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Trans(
                widget.assetFilter == null ? "选择资产" : "选择对价资产",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              if (displayAssets.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Text("暂无资产", style: TextStyle(color: Colors.grey)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: displayAssets.length,
                    itemBuilder: (context, index) {
                      final asset = displayAssets[index];
                      return ListTile(
                        leading: Icon(
                          asset.type == "Stablecoin" ? Icons.monetization_on : Icons.token_outlined,
                          color: asset.type == "Stablecoin" ? Colors.teal : Colors.blueAccent,
                        ),
                        title: Text(asset.assetId, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: asset.assetId == _currentAssetId ? const Icon(Icons.check, color: Colors.blue) : null,
                        onTap: () {
                          if (_currentAssetId != asset.assetId) {
                            setState(() {
                              _currentAssetId = asset.assetId;
                            });
                            _refreshBalance(); // 只有资产切换时才重新生成 Future
                            widget.onAssetChanged?.call(asset.assetId);
                          }
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}