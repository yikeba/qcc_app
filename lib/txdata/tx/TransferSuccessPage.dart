import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../home/QccExplorerService.dart';
import '../../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';
import 'QccTransaction.dart';
import 'QccTxConfirmService.dart';

/// 交易结果页：按上链确认状态显示三种头部
/// - confirmed：已上链（高度、容器、确认时间）
/// - pending  ：已被节点接收、等待确认超时——不是失败，提供"刷新状态"
/// - failed   ：节点返回了明确失败状态
/// confirmState 为 null（旧入口 fromJson 构建的对象）时按 confirmed 展示，
/// 保持旧调用方行为不变。
class TransferSuccessPage extends StatefulWidget {
  final QccTransaction transaction;
  const TransferSuccessPage({super.key, required this.transaction});

  @override
  State<TransferSuccessPage> createState() => _TransferSuccessPageState();
}

class _TransferSuccessPageState extends State<TransferSuccessPage> {
  late QccTransaction _tx;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _tx = widget.transaction;
    LogObj.log("交易结果页: ${_tx.txHash} 状态=${_tx.confirmState} 金额=${_tx.amount} 高度=${_tx.height}");
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    final c = await QccTxConfirmService.waitForConfirmation(
      _tx.txHash,
      timeout: const Duration(seconds: 15),
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!c.isPending) _tx = _tx.withConfirmation(c);
    });
    if (c.isPending) Tools.showToast(context, "仍在等待上链，请稍后再试");
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tx.isPending;
    final failed = _tx.isFailed;

    final IconData icon = failed
        ? Icons.cancel_rounded
        : (pending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded);
    final Color iconColor =
    failed ? Colors.red : (pending ? Colors.orange : Colors.green);
    final String title =
    failed ? "交易失败" : (pending ? "已提交，等待上链确认" : "转账成功");

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
            // 1. 状态头
            const SizedBox(height: 20),
            Icon(icon, color: iconColor, size: 80),
            const SizedBox(height: 16),
            Trans(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (failed && (_tx.msg?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(_tx.msg!, style: TextStyle(fontSize: 13, color: Colors.red.shade400)),
            ],
            if (pending) ...[
              const SizedBox(height: 6),
              Trans("交易已进入节点缓存，通常数秒内上链；可稍后刷新状态",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("${_formatAmount(_tx.amount, _tx.assetId)} ",
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: failed ? Colors.grey : Colors.black)),
                Text(_tx.assetId,
                    style: const TextStyle(fontSize: 18, color: Colors.blueAccent)),
              ],
            ),
            const SizedBox(height: 40),

            // 2. 存证卡片
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  _buildDetailItem(context, "发送方", _shortAddr(_tx.from), _tx.from),
                  _buildDetailItem(context, "接收方", _shortAddr(_tx.to), _tx.to),
                  _buildDetailItem(context, "交易类型", _tx.type.toUpperCase(), ""),
                  _buildDetailItem(context, "哈希", _shortAddr(_tx.txHash), _tx.txHash, isHash: true),
                  if (_tx.height != null)
                    _buildDetailItem(context, "区块高度", "${_tx.height}", "${_tx.height}"),
                  if (_tx.containerId != null)
                    _buildDetailItem(context, "容器", _shortAddr(_tx.containerId!), _tx.containerId!),
                  if (_tx.confirmTimestamp != null)
                    _buildDetailItem(context, "确认时间", _fmtLocalTime(_tx.confirmTimestamp!),
                        _tx.confirmDateUTC ?? ""),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // 3. 动作按钮
            if (pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _recheck,
                    icon: _checking
                        ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: Trans(_checking ? "正在查询..." : "刷新上链状态"),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => _openExplorer(_tx.txHash),
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
                if (fullText.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }

  String _shortAddr(String addr) => addr.length > 16 ? "${addr.substring(0, 8)}...${addr.substring(addr.length - 8)}" : addr;

  /// 确认时间按手机本地时区显示；点击复制的是节点给的 UTC 字符串。
  String _fmtLocalTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return "${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}:${p(t.second)}";
  }

  /// 按资产自身精度格式化金额，去掉末尾多余的 0；查不到资产按 9 位兜底。
  String _formatAmount(dynamic amount, String assetId) {
    if (amount == null) return "0";

    double? val = amount is num ? amount.toDouble() : double.tryParse(amount.toString());
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
    Tools.openChrome("${QccExplorerService.baseUrl}/v1/hash/$hash");
  }
}