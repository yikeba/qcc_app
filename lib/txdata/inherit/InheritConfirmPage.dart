import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

/// 创建信托后的交易确认页 —— 按你的要求"继承交易需要返回一个交易确认页面"，
/// 单独做成一个页面（不是弹窗），风格对齐 TagRuleSuccessPage.dart：一张信息卡
/// + 可复制的关键字段 + 底部 hash 区块。
///
/// pid 就是这笔信托的"进程 pid"，之后领取(win)/撤销(cancel)/明细中心查询都要用它，
/// 这个页面把它放在最显眼的位置并可以直接复制。
class InheritConfirmPage extends StatefulWidget {
  final String pid;
  final String testator;
  final String heir;
  final String assetId;
  final int amountRaw;
  final int maturityTimeMs;

  const InheritConfirmPage({
    super.key,
    required this.pid,
    required this.testator,
    required this.heir,
    required this.assetId,
    required this.amountRaw,
    required this.maturityTimeMs,
  });

  @override
  State<InheritConfirmPage> createState() => _InheritConfirmPageState();
}

class _InheritConfirmPageState extends State<InheritConfirmPage> {
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  // 假设 precision=9，跟本会话里所有其它交易(质押/借贷)统一的换算规则一致。
  String _formatAmount(int raw) {
    String s = (raw / 1000000000).toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  String _formatDateTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }

  String _nameFor(String addr) {
    final nick = _walletNames[addr];
    return nick != null ? "$nick ($addr)" : addr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans("信托创建详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.family_restroom_outlined, color: Color(0xFFB08900), size: 70),
            const SizedBox(height: 16),
            Trans("信托已提交", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              "提交被受理不等于一定生效，到期前可撤销，到期后由继承人领取——详细状态请去「继承中心」查这个 pid。",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF8ED),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0E4C0)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "本金", "${_formatAmount(widget.amountRaw)} ${widget.assetId}"),
                  const Divider(height: 32),
                  _infoRow(context, "委托人(from)", _nameFor(widget.testator), isAddr: true, canCopy: true),
                  const Divider(height: 32),
                  _infoRow(context, "继承人(to)", _nameFor(widget.heir), isAddr: true, canCopy: true),
                  const Divider(height: 32),
                  _infoRow(context, "到期时间", _formatDateTime(widget.maturityTimeMs)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildHashSection(context, widget.pid),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Trans("返回创建页"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {bool isAddr = false, bool canCopy = false}) {
    String displayValue = value;
    if (isAddr && value.length > 30) {
      displayValue = "${value.substring(0, 16)}...${value.substring(value.length - 10)}";
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy
                ? () {
                    Clipboard.setData(ClipboardData(text: value));
                    Tools.showToast(context, "已复制到剪贴板");
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: isAddr ? 'monospace' : null,
                      color: canCopy ? Colors.blueAccent : Colors.black87,
                    ),
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHashSection(BuildContext context, String pid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("信托凭证 pid（领取/撤销/查询都要用它）", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: pid));
            Tools.showToast(context, "pid 已复制");
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(child: Text(pid, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
