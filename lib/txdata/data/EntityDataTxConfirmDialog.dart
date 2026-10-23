import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/utile/Tools.dart';

/// 存证提交后的上链确认弹窗。
/// 流程：已受理 → 轮询 /v1/hash/{txHash} → 已上链（可打开链上查询）/ 失败 / 超时。
/// 关闭弹窗只会停止本次轮询，记录仍保持 pending，可以在"发布明细"里重新查询。
class EntityDataTxConfirmDialog extends StatefulWidget {
  final String txHash;
  final int size;
  final String serverMsg;

  /// 拿到最终结果（已上链/失败）时回调，用于写回本机记录。
  final Future<void> Function(TxChainStatus status) onFinal;

  const EntityDataTxConfirmDialog({
    super.key,
    required this.txHash,
    required this.size,
    required this.serverMsg,
    required this.onFinal,
  });

  @override
  State<EntityDataTxConfirmDialog> createState() => _EntityDataTxConfirmDialogState();
}

class _EntityDataTxConfirmDialogState extends State<EntityDataTxConfirmDialog> {
  StreamSubscription<TxChainStatus>? _sub;
  TxChainStatus? _st;
  int _tries = 0;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sub?.cancel();
    setState(() {
      _timedOut = false;
      _tries = 0;
    });
    _sub = QccTxStatusService.poll(widget.txHash).listen((s) {
      if (!mounted) return;
      setState(() {
        _st = s;
        _tries++;
      });
      if (s.isFinal) widget.onFinal(s);
    }, onDone: () {
      if (mounted && !(_st?.isFinal ?? false)) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _st?.state ?? TxChainState.pending;
    final bool confirmed = state == TxChainState.confirmed;
    final bool failed = state == TxChainState.failed;

    Widget titleIcon;
    String titleText;
    if (confirmed) {
      titleIcon = const Icon(Icons.verified, color: Colors.green);
      titleText = "存证已上链";
    } else if (failed) {
      titleIcon = const Icon(Icons.error, color: Colors.red);
      titleText = "上链失败";
    } else if (_timedOut) {
      titleIcon = const Icon(Icons.hourglass_bottom, color: Colors.orange);
      titleText = "仍在等待上链";
    } else {
      titleIcon = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      titleText = "已受理，等待上链…";
    }

    String statusLine;
    if (confirmed) {
      statusLine = _st!.blockHeight != null ? "已打包进区块 #${_st!.blockHeight}" : "链上已查到该交易";
    } else if (failed) {
      statusLine = "链上执行失败：${_st!.message ?? '未知原因'}";
    } else if (_timedOut) {
      statusLine = "已查询 $_tries 次仍未上链。交易已被受理，可稍后在「发布明细」中重新查询。";
    } else {
      statusLine = "第 $_tries 次查询${_st?.message != null ? '：${_st!.message}' : ''}";
    }

    return AlertDialog(
      title: Row(children: [titleIcon, const SizedBox(width: 8), Expanded(child: Text(titleText))]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("交易哈希 (txHash)：", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: SelectableText(widget.txHash, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
            const SizedBox(height: 12),
            Text("数据大小：${widget.size} bytes  (${(widget.size / 1024).toStringAsFixed(2)} KB)"),
            if (widget.serverMsg.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text("受理消息：${widget.serverMsg}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            const SizedBox(height: 10),
            Text(
              statusLine,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: confirmed ? Colors.green.shade700 : (failed ? Colors.red : Colors.orange.shade800),
              ),
            ),
            if (confirmed) ...[
              const SizedBox(height: 6),
              const Text("可通过链上查询链接独立核对这条存证。", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 4),
            const Text("该记录已保存到本机发布明细。", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.txHash));
            Tools.showToast(context, "已复制 txHash");
          },
          child: const Text("复制哈希"),
        ),
        if (confirmed)
          TextButton(
            onPressed: () => QccTxStatusService.openChainUrl(context, widget.txHash),
            child: const Text("链上查询"),
          ),
        if (_timedOut)
          TextButton(onPressed: _start, child: const Text("继续等待")),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("关闭")),
      ],
    );
  }
}
