
import 'package:flutter/material.dart';
import 'package:qcc_flutter/txdata/tx/QccTransaction.dart';
import 'package:qcc_flutter/utile/JsonUtil.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../txdata/tx/TransferSuccessPage.dart';
import 'QccDataMeta.dart';
import 'QCCDataResolver.dart';
import 'QccDataWidget.dart';

class QccDetailPage extends StatefulWidget {
  final QccDataMeta meta;
  const QccDetailPage({super.key, required this.meta});

  @override
  State<QccDetailPage> createState() => _QccDetailPageState();
}

class _QccDetailPageState extends State<QccDetailPage> {
  QccResolveResult? _resolvedData;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    // ✅ 核心逻辑：如果是支付交易，直接重定向
    if (widget.meta.extra?['txType'] == 'pay') {
      _redirectToTransferSuccess();
    } else {
      _handleContent();
    }
  }

  /// 内部重定向方法
  void _redirectToTransferSuccess() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 封装符合 QccTransactionData.fromJson 的结构
     /* Map<String, dynamic> fullPackage = {
        "status": "success",
        "txHash": widget.meta.metaHash,
        "data": widget.meta.extra // extra 已经是 Map 了
      };*/
      String json=JsonUtil.maptostr(widget.meta.extra!);
      final transaction = QccTransaction.fromJson(json);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TransferSuccessPage(transaction: transaction),
        ),
      );
    });
  }

  void _handleContent() {
    // 只有当 entryType 为 data 且不是转账时进行二进制解析
    if (widget.meta.entryType == QccEntryType.data) {
      setState(() => _isResolving = true);
      try {
        final Map<String, dynamic> txDetail = widget.meta.extra!;
        if (txDetail.containsKey('payload')) {
          final List<int> payload = List<int>.from(txDetail['payload']);
          _resolvedData = QccDataResolver.resolve(payload);
        }
      } catch (e) {
        LogObj.log("解析存证数据失败: $e");
      } finally {
        setState(() => _isResolving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果是转账类型，显示加载中（等待路由跳转）
    if (widget.meta.extra?['txType'] == 'pay') {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.meta.entryType == QccEntryType.data ? "链上存证详情" : "交易明细"),
        elevation: 0,
      ),
      body: _isResolving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: QccDataWidget(
          meta: widget.meta,
          resolved: _resolvedData,
          txHash: widget.meta.metaHash,
          isFullPage: true,
        ),
      ),
    );
  }
}