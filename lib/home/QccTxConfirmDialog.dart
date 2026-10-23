import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/utile/Tools.dart';

/// 通用上链确认弹窗 —— 所有"/v1/xxx 返回 ACCEPTED → 轮询 /v1/hash/{txHash}"
/// 的交易共用（存证、商户规则、后续白名单等）。
///
/// 用法：final st = await showDialog<TxChainStatus?>(barrierDismissible: false,
///         builder: (_) => QccTxConfirmDialog(txHash: h, ...));
/// 关闭时返回最后一次状态：confirmed / failed / pending（超时或提前关闭），
/// 返回键关闭时为 null，调用方按 pending 处理。
class QccTxConfirmDialog extends StatefulWidget {
  final String txHash;

  /// 已上链时的标题，例如"存证已上链""商户规则已上链"。
  final String confirmedTitle;

  /// txHash 下方的业务信息（大小、规则内容等），由调用方决定。
  final List<Widget> details;

  /// 底部灰字说明，例如"该记录已保存到本机发布明细"。
  final String? footer;

  /// 拿到最终结果（confirmed/failed）时回调一次，用于写回本地记录。
  final Future<void> Function(TxChainStatus status)? onFinal;

  const QccTxConfirmDialog({
    super.key,
    required this.txHash,
    this.confirmedTitle = "交易已上链",
    this.details = const [],
    this.footer,
    this.onFinal,
  });

  @override
  State<QccTxConfirmDialog> createState() => _QccTxConfirmDialogState();
}

class _QccTxConfirmDialogState extends State<QccTxConfirmDialog> {
  StreamSubscription<TxChainStatus>? _sub;
  TxChainStatus? _st;
  int _tries = 0;
  bool _timedOut = false;
  bool _finalHandled = false;

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
      if (s.isFinal && !_finalHandled) {
        _finalHandled = true;
        widget.onFinal?.call(s);
      }
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
      titleText = widget.confirmedTitle;
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
      statusLine = "已查询 $_tries 次仍未上链。交易已被受理，可稍后再查询。";
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
            if (widget.details.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...widget.details,
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
            if (widget.footer != null) ...[
              const SizedBox(height: 4),
              Text(widget.footer!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
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
        if (_timedOut) TextButton(onPressed: _start, child: const Text("继续等待")),
        TextButton(onPressed: () => Navigator.of(context).pop(_st), child: const Text("关闭")),
      ],
    );
  }
}
