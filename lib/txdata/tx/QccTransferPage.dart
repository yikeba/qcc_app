
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
import '../../qccwallet/QccApiService.dart';
import '../../views/myasset/QccAssetService.dart' as server;
import '../../views/setting/AppTranslator.dart';
import '../../views/setting/QccPassDialog.dart';
import '../../views/toolviews/QccLoading.dart';
import 'TransferSuccessPage.dart';
import 'package:qcc_flutter/txdata/tx/QccTransaction.dart' as tx;

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
                          // 2. 增加输入限制，防止用户输入多个小数点或非数字字符
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
    // 1. 调起扫码页面
    String? scanResult = await QccScanner.scan(context);
    if (scanResult != null && scanResult.isNotEmpty) {
      // 2. 简单的地址格式初步校验 (根据 QCC 地址特征，例如以 'QCC' 开头或长度判断)
      // 如果你之前的备份二维码也是扫这个，这里需要区分是“备份数据”还是“普通地址”
      if (scanResult.startsWith("QCC_SECURE_V2:")) {
        Tools.showToast(context, "这是备份数据，请在地址管理中使用扫码恢复");
        return;
      }
      // 3. 将扫描到的地址填入输入框
      setState(() {
        _toController.text = scanResult;
      });
      // 4. 反馈
      HapticFeedback.lightImpact(); // 震动反馈
     // Tools.showToast(context, "地址已填入");
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


    // --- 关键优化：在所有耗时操作开始前，立即弹出唯一一次 Loading ---
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    _showDynamicLoading(context, statusNotifier);

    try {
      // ---- A. 还原钱包 (子线程计算) ----
      // 逻辑：先切状态，再跑耗时任务
      statusNotifier.value = TxStep.restoring;
      final sw = Stopwatch()..start();

      QccWallet? wallet=await QccStorage.restoreWallet(context,_currentWallet!.address,password);

      if (wallet == null || wallet.address != _currentWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      LogObj.log("钱包信息还原成功: ${wallet.address},耗时${sw.elapsedMilliseconds}ms");

      // ---- B. 构建交易 (网络请求) ----
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

      // ---- C. 执行抗量子签名 (子线程高能计算) ----
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask,{
        'tx': tran,
        'privHex': wallet.privateKey!,
        'pubHex': wallet.pubkey!
      });

      // ---- D. 提交交易 (网络请求) ----
      statusNotifier.value = TxStep.submitting;
      String url = "${QccExplorerService.baseUrl}/v1/txm";
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      // --- 任务完成：关闭 Loading ---
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("普通转账返回参数${response.body}");
      if (response.statusCode == 200) {
        final qccData = tx.QccTransaction.fromJson(response.body);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TransferSuccessPage(transaction: qccData),
          ),
        );
      } else {
        Tools.showToast(context, "网络异常: ${response.statusCode}");
      }

    } catch (e) {
      // --- 异常处理：确保出错时关闭 Loading 并提示用户 ---
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("交易执行出错: $e");
      Tools.showToast(context, "操作失败: ${e.toString()}");
    }
  }


// ------------------ 静态子线程任务 ------------------

  static Future<QccPacket> _signTransactionTask(Map<String,dynamic> data) async {
    // 在子线程中调用 C FFI 进行 Dilithium5 签名
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
    LogObj.log("🛡️ 签名原始字节长度: ${signatureBytes.length}"); // 理论上应为 4595
    LogObj.log("🛡️ 签名 Hex 字符串长度: ${signature.length}"); // 理论上应为 9190
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
                    // 使用你定义的 _stepMsgs
                    Text(
                      _stepMsgs[step] ?? "请稍候...",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const SizedBox(height: 15),
                    Trans(
                      "安全提示：抗量子签名需要约 1分钟，请不要关闭或切换到后台。\n正在进行极度复杂的格数学计算以保护资产，请勿离开或关闭屏幕。",
                      //textAlign: TextAlign.center,
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

// 严格对齐你代码中的 Map 变量名
final Map<TxStep, String> _stepMsgs = {
  TxStep.building: "正在构建交易数据...",
  TxStep.restoring: "🔐 正在从安全加固区还原钱包...",
  TxStep.signing: "✍️ 正在进行抗量子签名 (格数学计算)...",
  TxStep.submitting: "🚀 签名成功！正在同步至量子链节点...",
};