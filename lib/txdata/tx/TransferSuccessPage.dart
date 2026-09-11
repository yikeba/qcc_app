import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../home/QccExplorerService.dart';
import '../../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';
import 'QccTransaction.dart';

class TransferSuccessPage extends StatelessWidget {
  final QccTransaction transaction; // 使用解析后的对象
  const TransferSuccessPage({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    // 加一下运行时类型日志：如果修复后个别金额还是不对，把这行 log 的输出
    // 发我一下，能确认 transaction.amount 实际是 String 还是 double/int。
    LogObj.log("转账金额数据:${transaction.amount} (运行时类型: ${transaction.amount.runtimeType})");
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: CloseButton(color: Colors.black, onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            // 1. 成功状态头
            const SizedBox(height: 20),
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Trans("转账成功", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("${_formatAmount(transaction.amount, transaction.assetId)} ",
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                Text(transaction.assetId, // 如果有类型转换逻辑
                    style: const TextStyle(fontSize: 18, color: Colors.blueAccent)),
              ],
            ),
            const SizedBox(height: 40),

            // 2. 存证卡片 (电子收据风格)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  _buildDetailItem(context, "发送方", _shortAddr(transaction.from), transaction.from),
                  _buildDetailItem(context, "接收方", _shortAddr(transaction.to), transaction.to),
                  _buildDetailItem(context, "交易类型", transaction.type.toUpperCase(), ""),
                  _buildDetailItem(context, "哈希", _shortAddr(transaction.txHash), transaction.txHash, isHash: true),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // 3. 动作按钮
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => _openExplorer(transaction.txHash),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1C1E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Trans("在 QCC 浏览器中查看", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Trans("返回钱包", style: const TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, String label, String value, String fullText, {bool isHash = false}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          GestureDetector(
            onTap: () {
              if (fullText.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: fullText));
                Tools.showToast(context, "已复制到剪切板");
              }
            },
            child: Row(
              children: [
                Text(value,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isHash ? Colors.blue : Colors.black87
                    )),
                const SizedBox(width: 4),
                const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _shortAddr(String addr) => addr.length > 16 ? "${addr.substring(0, 8)}...${addr.substring(addr.length - 8)}" : addr;

  /// 【本次修正，对应你指出的"这会适配其他资产转账，其他资产未必9位"】
  /// 上一版直接硬编码按 9 位小数格式化——9 位是 QCC 自己的精度，但这个
  /// 成功页是通用的转账结果页，其他资产(比如 USDS 是 2 位)未必是 9 位，
  /// 硬编码 9 位有两个问题：1. 如果上游浮点换算本身带有超出该资产实际
  /// 精度的噪声(比如 2 位精度的资产算出 0.05000000037)，去掉末尾 0 之后
  /// 这段噪声会被当成"有效小数"露出来，显示成不属于该资产的假精度；
  /// 2. 语义上也不对——每个资产的最小单位是由它自己的 precision 决定的，
  /// 不该所有资产共用一个显示位数。
  ///
  /// 改成和 QccActiveWallet.dart 里同一套查资产精度的写法：
  ///   QccAssetService().followAsset.firstWhere(
  ///     (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
  ///     orElse: () => QccAsset(assetId: assetId, type: "COIN", precision: 9, address: 'Q...'),
  ///   )
  /// 查不到该资产时才兜底按 9 位（这个兜底值和 QccActiveWallet.dart 里的
  /// 默认值保持一致，不是我随便定的）。查到之后就按这个资产"自己的"
  /// precision 做 toStringAsFixed + 去掉末尾多余 0，这样：
  /// - USDS(2位)：0.01 正常显示"0.01"，不会因为格式化位数不对而消失或跑出多余小数；
  /// - QCC(9位)：0.000000001 这种到第9位的极小额度也能正常显示；
  /// - 任何资产都不会显示超出自己精度之外的"假小数"。
  String _formatAmount(dynamic amount, String assetId) {
    if (amount == null) return "0";

    double? val = amount is num ? amount.toDouble() : double.tryParse(amount.toString());

    // 解析失败就原样兜底显示，好歹不让页面崩溃或者显示 null
    if (val == null) return amount.toString();

    final assetInstance = QccAssetService().followAsset.firstWhere(
          (a) => a.assetId.toUpperCase() == assetId.toUpperCase(),
      orElse: () => QccAsset(assetId: assetId, type: "COIN", precision: 9, address: 'Q...'),
    );

    String s = val.toStringAsFixed(assetInstance.precision);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s.isEmpty ? "0" : s;
  }

  void _openExplorer(String hash) {
    // 以后接入你的开源浏览器地址
    // print("Opening Explorer: https://test.qccio.com/tx/$hash");
    Tools.openChrome("${QccExplorerService.baseUrl}/v1/hash/$hash");
  }
}