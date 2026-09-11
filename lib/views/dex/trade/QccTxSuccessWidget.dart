import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import '../../../home/QccExplorerService.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';

class QccTxSuccessWidget extends StatelessWidget {
  final Map<String, dynamic> response;

  const QccTxSuccessWidget({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    // 解析嵌套数据
    final innerData = jsonDecode(response['data']);
    final logic = innerData['matchLogic'] ?? {};
    final String rule = logic['rule'] ?? "unknown";
    final String txHash = response['txHash'];
    String assetId = innerData['assetId'];
    double amount = QccAssetService().getHumanAmountNum(assetId, innerData['amount']);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 成功动画图标
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 70),
          const SizedBox(height: 16),
          const Trans("交易已进入内存池", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Trans("正在等待节点打包确认...", style: TextStyle(color: Colors.grey, fontSize: 13)),

          const Divider(height: 40),

          // 2. 根据类型展示核心详情
          _buildDetailRow("交易类型", rule == "dex" || rule == "exchange" ? "去中心化交易 (DEX)" : "普通撮合"),
          _buildDetailRow("出售资产", "$amount   $assetId"),

          // ✅ 如果是 DEX 类型，展示对价信息
          if (rule == "dex" || rule == "exchange") ...[
            _buildDetailRow("对价资产", logic['pairAssetId'] ?? "--"),
            _buildDetailRow("设定汇率", "1 : ${logic['rate']}", valueColor: Colors.orange[800]),
          ],

          const SizedBox(height: 24),

          // 3. ✅ 优化后的哈希值展示区 (超大点击热区 + 水波纹反馈)
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Material(
              color: Colors.transparent, // 必须透明才能透出 Container 的背景色
              child: InkWell(
                borderRadius: BorderRadius.circular(12), // 保持与外框一致的圆角水波纹
                onTap: () => Tools.copytext(context, txHash),
                child: Padding(
                  // 加大内边距，整个框都是点击区
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Trans("交易哈希 (TxHash)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              txHash,
                              // 字体适当放大，颜色加深更清晰
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 图标加上一个浅蓝色背景圈，视觉上更像一个“按钮”
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.copy_rounded, size: 16, color: Colors.blue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 4. 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: const BorderSide(color: Colors.blue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Trans("返回列表", style: TextStyle(color: Colors.blue)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openExplorer(innerData["id"]),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.blue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Trans("区块详情", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _openExplorer(String hash) {
    // 以后接入你的开源浏览器地址
    // print("Opening Explorer: https://test.qccio.com/tx/$hash");
    Tools.openChrome("${QccExplorerService.baseUrl}/v1/hash/$hash");
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }
}