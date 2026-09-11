import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../home/QccExplorerService.dart';
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
import 'MerchantRuleSuccessPage.dart';

class MerchantRuleWidget extends StatefulWidget {
  const MerchantRuleWidget({super.key});

  @override
  State<MerchantRuleWidget> createState() => _MerchantRuleWidgetState();
}

class _MerchantRuleWidgetState extends State<MerchantRuleWidget> {
  final _formKey = GlobalKey<FormState>();

  // 核心配置
  bool _isGasDelegationEnabled = true;
  final _assetIdController = TextEditingController(text: "QCC"); // 预留 AssetId 配置

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

            // 1. 发起账户卡片
            _buildLabel("发起商户账户 (Merchant From)"),
            _buildAccountInfoCard(currentAddress),
            const SizedBox(height: 24),

            // 2. 到付开关
            _buildLabel("到付功能状态"),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Trans("开启 Gas 到付声明", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Trans("开启后，指定资产转入本地址时，Gas 由本地址承担", style: const TextStyle(fontSize: 12)),
                value: _isGasDelegationEnabled,
                activeColor: Colors.orange,
                onChanged: (bool value) => setState(() => _isGasDelegationEnabled = value),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.local_gas_station, color: Colors.orange, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. AssetId 配置 (前瞻性增加)
            _buildLabel("限定资产容器 (Asset ID)"),
            TextFormField(
              controller: _assetIdController,
              decoration: InputDecoration(
                hintText: "请输入限定的 AssetId (如 QCC 或 容器Hash)",
                helperText: Tools.getTra("仅针对此资产触发到付，不填则默认为所有资产"),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.token_outlined, size: 18),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 16),

            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("商户到付规则设置", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans("这是 QCC 原生商户协议，允许您声明特定的“资产接收”模式，优化您的用户交易体验。",
            style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Trans(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildAccountInfoCard(String address) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.store, color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Trans("当前余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handlePublish,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("发布商户规则交易", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- 核心逻辑：封装 MerchantRule 并广播 ---
  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate()) return;
    if (QccObj.activeWallet == null) {
      Tools.showToast(context, "未发现激活钱包");
      return;
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      setState(() => _isSubmitting = true);

      // 1. 还原私钥
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet=await QccStorage.restoreWallet(context,QccObj.activeWallet!.address,password);
      if (wallet == null || wallet.address != QccObj.activeWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      /* String? encryptedData = await QccStorage.getRawData(QccObj.activeWallet!.address);
      if (encryptedData == null) throw "找不到该账户的本地私钥数据";

      final wallet = await compute(QccStorage.restoreWalletTask, {
        'rawData': encryptedData,
        'password': password,
      });

      if (wallet == null || wallet.privateKey == null) throw "密码校验失败";*/

      // 2. 构建 MerchantRule (增加 assetId 扩展)
      statusNotifier.value = TxStep.building;
      final merchantRule = QccMerchantRule(
        address: QccObj.activeWallet!.address,
        credentialHash: "",
        gasDelegation: _isGasDelegationEnabled,
      );

      // 在 ruleJson 中临时手动插入 assetId 字段，以适配下一步公链升级
      Map<String, dynamic> ruleMap = merchantRule.toJson();
      ruleMap['assetId'] = _assetIdController.text.trim();

      // 3. 构建公链规则交易容器——RuleData() 构造函数已自动填好 timestamp/chain。
      final ruleData = RuleData();
      ruleData.from = QccObj.activeWallet!.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "MerchantRule";
      ruleData.ruleJson = jsonEncode(ruleMap);
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();
      // 4. 执行签名——统一走 SignUtil.signAndEncode()
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: QccObj.activeWallet!.address,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 发送至 /v1/rule 接口
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("商户规则返回参数${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          // --- 核心逻辑：解析 ruleName 并注入，用于本地存储识别和页面分流 ---
          if (resData['data'] != null) {
            try {
              // data 字段是字符串，需要二次解析
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName'] ?? "MerchantRule";
            } catch (e) {
              LogObj.log("解析 Merchant Data 详情失败: $e");
              resData['ruleName'] = "MerchantRule";
            }
          } else {
            resData['ruleName'] = "MerchantRule";
          }

          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);

          // 1. 保存到本地规则状态中心 (供 UserRuleStatusWidget 读取)
          await UserRuleFileStorage.saveRuleTask(resData);

          Tools.showToast(context, "✅ 商户规则已成功申请并广播");

          // 2. 跳转到商户规则专属成功页面
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MerchantRuleSuccessPage(ruleData: resData),
              ),
            );
          }

        } else {
          throw resData['msg'] ?? "规则发布被拒绝";
        }
      } else {
        throw "网络通讯异常: ${response.statusCode}";
      }

    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("商户规则配置异常: $e");
      Tools.showToast(context, "设置失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}