import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../../QccRuleBaseObj.dart';
import '../UserRuleFileStorage.dart';
import 'PayCallRuleSuccessPage.dart';

// 内部组件与模型


class PayCallRuleWidget extends StatefulWidget {
  const PayCallRuleWidget({super.key});

  @override
  State<PayCallRuleWidget> createState() => _PayCallRuleWidgetState();
}

class _PayCallRuleWidgetState extends State<PayCallRuleWidget> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController(text: "https://api.merchant.com/v1/callback");
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    String currentAddress = QccObj.activeWallet?.address ?? Tools.getTra("未选择钱包");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildLabel("发起规则账户 (From)"),
            _buildAccountInfoCard(currentAddress),
            const SizedBox(height: 24),
            _buildLabel("配置回调地址"),
            TextFormField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: Tools.getTra("回调接口地址 (Callback URL)"),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                prefixIcon: const Icon(Icons.link, color: Colors.blue),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (value) => (value == null || value.isEmpty) ? Tools.getTra("请输入 URL") : null,
            ),
            const SizedBox(height: 40),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Trans("支付回调规则配置", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      Trans("配置后，公链在确认涉及您地址的收款交易时，将自动推送通知。", style: const TextStyle(color: Colors.grey, fontSize: 13)),
    ],
  );

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Trans(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
  );

  Widget _buildAccountInfoCard(String address) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
    child: Row(
      children: [
        const Icon(Icons.wallet, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              // 调用你项目中定义的余额组件
              QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.green),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildSubmitButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: _isSubmitting ? null : _handlePublish,
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : Trans("签名并发布规则交易"),
    ),
  );

  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate() || QccObj.activeWallet == null) return;
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      setState(() => _isSubmitting = true);

      // 1. 还原私钥 - 使用你提供的 getRawData
      statusNotifier.value = TxStep.restoring;
      /*  String? encryptedData = await QccStorage.getRawData(QccObj.activeWallet!.address);
      if (encryptedData == null) throw "找不到该账户的本地私钥数据";
      final wallet = await compute(QccStorage.restoreWalletTask, {'rawData': encryptedData, 'password': password});
      if (wallet == null || wallet.privateKey == null) throw "支付密码错误";
*/

      QccWallet? wallet=await QccStorage.restoreWallet(context,QccObj.activeWallet!.address,password);
      if (wallet == null || wallet.address != QccObj.activeWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      statusNotifier.value = TxStep.building;
      // 2. 构建子规则
      final payCallObj = QccPayCallRule(
        address: QccObj.activeWallet!.address,
        callUrl: _urlController.text.trim(),
        credentialHash: "",
      );

      // 3. 构建规则交易容器——RuleData() 构造函数已自动填好 timestamp/chain。
      final ruleData = RuleData();
      ruleData.from = QccObj.activeWallet!.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "PayCallRule";
      ruleData.ruleJson = jsonEncode(payCallObj.toJson());
      ruleData.ruleAppendJson = "";

      // 4. 计算哈希 (SHA3-256)
      ruleData.finalizeId();

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: QccObj.activeWallet!.address,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("QCC DEBUG_:支付回调返回 ${response.body}");

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);

        // --- 核心优化：按照你的建议解析 ruleName 并持久化 ---
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {

          // 深度解析 data 字段以提取业务标识 ruleName
          if (resData['data'] != null) {
            try {
              // 注意：data 在返回中可能是 String，需要二次解析
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName']; // 注入名称作为标识
            } catch (e) {
              LogObj.log("解析返回 Data 详情失败: $e");
              // 容错：如果解析失败，使用构建时的名称
              resData['ruleName'] = "PayCallRule";
            }
          } else {
            resData['ruleName'] = "PayCallRule";
          }
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          // 1. 保存到本地规则状态中心 (内部会调用 saveRawData)
          await UserRuleFileStorage.saveRuleTask(resData);

          Tools.showToast(context, "✅ 支付回调规则已成功广播");

          // 2. 成功后直接打开对应的详情页
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PayCallRuleSuccessPage(ruleData: resData),
              ),
            );
          }
        } else {
          throw resData['msg'] ?? "公链拒绝了该规则请求";
        }
      } else {
        throw "网络连接失败: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("规则发布异常: $e");
      Tools.showToast(context, "操作失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}