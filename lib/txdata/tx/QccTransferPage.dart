import 'dart:convert';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/qccwallet/AddressTool.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import '../../../home/QccScanner.dart';
import '../../../procotol/QccDataProtocol.dart';
import '../../../procotol/QccPacket.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccLibOqsSigner.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../utile/Tools.dart';
import '../../../home/QccExplorerService.dart';
import '../../../utile/QccObj.dart';
import '../../views/myasset/QccAssetService.dart' as server;
import '../../views/setting/AppTranslator.dart';
import '../../views/setting/QccPassDialog.dart';
import '../../views/toolviews/QccLoading.dart';
import 'TransferSuccessPage.dart';
import 'package:qcc_flutter/txdata/tx/QccTransaction.dart' as tx;
import 'package:qcc_flutter/txdata/tx/QccTxConfirmService.dart';

// 修改后的 QccTransferPage 构造函数
class QccTransferPage extends StatefulWidget {
  final QccWallet? initialWallet; // 接收可选的初始钱包
  final String assetId;
  const QccTransferPage({super.key, this.initialWallet,required this.assetId});

  @override
  State<QccTransferPage> createState() => _QccTransferPageState();
}

class _QccTransferPageState extends State<QccTransferPage> {
  late QccWallet? _currentWallet; // 内部管理的付款钱包
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  String _selectedAsset = "QCC";

  @override
  void initState() {
    super.initState();
    // 如果传了初始钱包就用初始的，否则用全局激活的
    _currentWallet = widget.initialWallet ?? QccObj.activeWallet;
    _selectedAsset=widget.assetId;
  }


  @override
  Widget build(BuildContext context) {
    final activeWallet = QccObj.activeWallet;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Trans("发起转账", style: const TextStyle(color: Colors.black, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 付款来源展示
            Trans("付款账户", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            _buildSourceCard(activeWallet),

            const SizedBox(height: 30),

            // 2. 收款地址输入
            Trans("收款人地址", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _toController,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: Tools.getTra("请输入或粘贴 QCC Chain 地址"),
                fillColor: Colors.white,
                filled: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.document_scanner_outlined, color: Colors.blue),
                  onPressed: _onAddressScan, // 触发扫码方法
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 30),

            // 3. 转账金额输入
            Trans("转账金额", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(hintText: "0.00", border: InputBorder.none),
                        ),
                      ),
                      Text(_selectedAsset, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Trans("可用余额:", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      QccActiveWallet(activeWallet?.address ?? "", _selectedAsset, fontSize: 12, fontColor: Colors.black54),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 50),

            // 4. 下一步按钮 (触发本地签名逻辑)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _performTransfer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                ),
                child: Trans("确认转账", style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddressScan() async {
    String? scanResult = await QccScanner.scan(context);
    if (scanResult != null && scanResult.isNotEmpty) {
      if (scanResult.startsWith("QCC_SECURE_V2:")) {
        Tools.showToast(context, "这是备份数据，请在地址管理中使用扫码恢复");
        return;
      }
      setState(() {
        _toController.text = scanResult;
      });
      HapticFeedback.lightImpact(); // 震动反馈
    }
  }

  // 构建缩略版付款卡片
  Widget _buildSourceCard(activeWallet) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade700]),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.white24, child: const Icon(Icons.wallet, color: Colors.white)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activeWallet?.address ?? "",
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Trans("安全保护中", style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          )
        ],
      ),
    );
  }


  Future<void> _performTransfer() async {
    // 1. 基础校验
    String toAddress = _toController.text.trim();
    String amountStr = _amountController.text.trim();
    if (toAddress.isEmpty || amountStr.isEmpty) {
      Tools.showToast(context, "请完善接收地址和金额");
      return;
    }
    if(!AddressTool.isValidTransferAddress(toAddress)){
      Tools.showToast(context, "转账地方地址格式不正确");
      return;
    }

    // 2. 获取密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    _showDynamicLoading(context, statusNotifier);

    try {
      // ---- A. 还原钱包 ----
      statusNotifier.value = TxStep.restoring;
      final sw = Stopwatch()..start();

      QccWallet? wallet=await QccStorage.restoreWallet(context,_currentWallet!.address,password);

      if (wallet == null || wallet.address != _currentWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      LogObj.log("钱包信息还原成功: ${wallet.address},耗时${sw.elapsedMilliseconds}ms");

      // ---- B. 构建交易 ----
      statusNotifier.value = TxStep.building;
      int amountInt =server.QccAssetService().getAmountRaw(_selectedAsset, amountStr);

      QccTransactionData tran= QccTransactionData();
      tran.assetId=_selectedAsset;
      tran.from=_currentWallet!.address;
      tran.to=toAddress;
      tran.amount=amountInt;
      tran.fromdev="";
      tran.txType = "pay";
      tran.chain = "6666";
      tran.memo = "";
      tran.finalizeId();

      // ---- C. 抗量子签名 ----
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask,{
        'tx': tran,
        'privHex': wallet.privateKey!,
        'pubHex': wallet.pubkey!
      });

      // ---- D. 提交交易：新机制下只返回"已接收"(进入节点缓存) ----
      statusNotifier.value = TxStep.submitting;
      final String submitBase = QccExplorerService.baseUrl;
      String url = "$submitBase/v1/txm";
      LogObj.log("当期交易提交访问节点：${url}");
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );
      LogObj.log("普通转账返回参数${response.body}");
      final String txHash = _extractAcceptedTxHash(response);

      // ---- E. 等待上链确认：任一最高高度节点 /v1/hash 返回 SUCCESS 即确认 ----
      statusNotifier.value = TxStep.building;
      final confirmation = await QccTxConfirmService.waitForConfirmation(
        txHash,
        extraBaseUrls: [submitBase],
      );

      // 链上返回了交易本体就用链上数据；超时(pending)则用本地交易兜底展示
      final qccData = tx.QccTransaction.fromConfirmation(
        confirmation,
        localTx: Map<String, dynamic>.from(tran.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransferSuccessPage(transaction: qccData),
        ),
      );
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("交易执行出错: $e");
      Tools.showToast(context, "操作失败: ${e.toString()}");
    }
  }

  /// 解析交易接口的"接收"响应，返回 txHash；未被接收则抛异常（带服务端 msg）。
  /// 接收响应示例：{"status":"accepted","code":"ACCEPTED","txHash":"...","msg":"..."}
  /// 假设：status 为 accepted/ok/success（或缺省）都算接收；其它（例如缓存满
  /// 返回的系统忙）按失败处理。
  String _extractAcceptedTxHash(http.Response resp) {
    Map<String, dynamic> body = {};
    try {
      final d = jsonDecode(resp.body);
      if (d is Map) body = Map<String, dynamic>.from(d);
    } catch (_) {}

    final status = (body['status'] as String?)?.toLowerCase();
    final txHash = body['txHash'];
    final accepted = status == null || const {'accepted', 'ok', 'success'}.contains(status);
    if (resp.statusCode == 200 && accepted && txHash is String && txHash.isNotEmpty) {
      return txHash;
    }
    final reason = body['msg'] ?? body['code'] ?? "HTTP ${resp.statusCode}";
    throw Exception("交易未被节点接收: $reason");
  }


// ------------------ 静态子线程任务 ------------------

  static Future<QccPacket> _signTransactionTask(Map<String,dynamic> data) async {
    QccTransactionData tx=data["tx"];
    String payloadJson= jsonEncode(tx.toJson());
    if (payloadJson.isEmpty) {
      throw Exception("交易构建失败：服务器返回为空");
    }
    LogObj.log("发起签名内容:${tx.toSign()}");
    Uint8List signatureBytes = QccLibOqsSigner.sign(
        data['privHex'],
        tx.toSign()
    );
    String signature = hex.encode(signatureBytes);
    LogObj.log("🛡️ 签名原始字节长度: ${signatureBytes.length}");
    LogObj.log("🛡️ 签名 Hex 字符串长度: ${signature.length}");
    QccPacket qp= await QccDataProtocol.encodeTransaction(
      payloadJson: payloadJson,
      privateKeyHex: data['privHex']!,
      publicKeyHex: data['pubHex']!,
    );
    qp.signature=signature;
    return qp;
  }


  void _showDynamicLoading(BuildContext context, ValueNotifier<TxStep> notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: ValueListenableBuilder<TxStep>(
            valueListenable: notifier,
            builder: (context, step, _) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                title: const Text("🛡️ 抗量子安全传输", style: TextStyle(fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 25),
                    Trans("请稍候...",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const SizedBox(height: 15),
                    Trans(
                      "安全提示：抗量子签名需要约 1分钟，请不要关闭或切换到后台。\n正在进行极度复杂的格数学计算以保护资产，请勿离开或关闭屏幕。",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

}
