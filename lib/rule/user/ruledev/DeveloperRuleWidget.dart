import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import 'DeveloperRuleSuccessPage.dart';


class DeveloperRuleWidget extends StatefulWidget {
  const DeveloperRuleWidget({super.key});

  @override
  State<DeveloperRuleWidget> createState() => _DeveloperRuleWidgetState();
}

class _DeveloperRuleWidgetState extends State<DeveloperRuleWidget> {
  final _formKey = GlobalKey<FormState>();

  // 【修复，重要】开发者奖励比例不是申请人自己能填的——是系统固定
  // 20%、由系统在结算时原子级完成的（"系统原子建立"），之前这里做成一个
  // 可编辑的百分比输入框、默认值还写成 0.3(30%)，会让人误以为这个比例是
  // 可以自己申请/协商的，和实际业务规则不符。改成一个不可编辑的固定常量，
  // 界面上也相应改成纯展示，不再提供输入框。
  static const double _fixedRewardRate = 0.2;

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

            // --- 发起账户与余额卡片 ---
            _buildLabel("申请账户 (From)"),
            _buildAccountInfoCard(currentAddress),
            const SizedBox(height: 24),

            // --- 奖励比例：系统固定值，纯展示，不可编辑 ---
            _buildLabel("奖励比例 (Reward Rate)"),
            _buildFixedRateCard(),
            const SizedBox(height: 24),

            // 【新增】开发者奖励池总奖金——实时显示 SystemPool.devReward
            // 这个系统保留地址的余额，复用 QccActiveWallet 组件（和上面
            // "当前余额"是同一套查询/精度处理逻辑，QCC 9 位精度）。
            _buildLabel("开发者奖励池总奖金"),
            _buildRewardPoolCard(),
            const SizedBox(height: 32),

            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("开发者奖励规则申请", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        // 【修复】原来写的是"返还 Gas 费用的 30%"——实际系统固定比例是
        // 20%，由系统原子级完成结算，不是申请人自己商定的。同时补充说明
        // 奖励只计入"资金交易"和"字节存证交易"这两类，规则交易本身
        // （比如这次申请开发者身份的这笔交易）不计算奖励，避免被误解为
        // "多提交几笔规则交易也能拿奖励"。
        Trans(
          "成功申请后，该地址发起的【资金交易】和【字节存证交易】将触发系统"
              "原子级 QCC 奖励，按 Gas 费用的 20% 自动返还到该地址（规则类交易"
              "本身不计入奖励范围）。",
          style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  /// 【新增】固定奖励比例展示卡——不再是可编辑输入框。
  Widget _buildFixedRateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Trans("系统固定比例，全网统一，不支持自定义",
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ),
          Text(
            "${(_fixedRewardRate * 100).toStringAsFixed(0)}%",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
        ],
      ),
    );
  }

  /// 【新增】开发者奖励池实时总余额——地址是协议保留地址
  /// SystemPool.devReward（对应 Java 端 qcc.rule.qccRule.SystemPool.DEV_REWARD，
  /// "Q2222222222222222222222222222222222"），不是任何用户的私钥地址。
  /// 直接复用 QccActiveWallet 查普通地址余额的同一套逻辑——这个系统池
  /// 地址查余额走的也是标准的 /v1/balance/{address} 接口，和查任何一个
  /// 普通地址没有区别，不需要单独写一份 HTTP 请求。
  Widget _buildRewardPoolCard() {
    return Container(
      width: double.infinity,
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
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.savings_rounded, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Trans("开发者奖励池 (${SystemPool.devReward.label})",
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                QccActiveWallet(
                  SystemPool.devReward.address,
                  "QCC",
                  fontSize: 16.0,
                  fontColor: Colors.green.shade700,
                ),
              ],
            ),
          ),
        ],
      ),
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
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.code, color: Colors.blue, size: 20),
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

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("立即签署并申请开发者身份"),
      ),
    );
  }

  // --- 逻辑：构造规则数据并发送 ---
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (QccObj.activeWallet == null) {
      Tools.showToast(context, "请先激活钱包");
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
      });*/

      if (wallet == null || wallet.privateKey == null) throw "支付密码错误";

      // 2. 构建开发者规则对象 (对应 Java DeveloperRule)
      statusNotifier.value = TxStep.building;
      final devRule = QccDeveloperRule(
        address: QccObj.activeWallet!.address,
        credentialHash: "",
        // 【修复】不再从已删除的 _rateController 读取——奖励比例是系统
        // 固定的 20%，这里直接传常量，客户端不能也不需要自己指定比例。
        rewardRate: _fixedRewardRate,
      );

      // 3. 构建公链规则容器——RuleData() 构造函数已自动填好 timestamp/chain，
      // 不需要再手动赋值。
      final ruleData = RuleData();
      ruleData.from = QccObj.activeWallet!.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "DeveloperRule";
      ruleData.ruleJson = jsonEncode(devRule.toJson());
      // 对应 Java：ruleAppendJson = ""，必须显式写入——toSign() 的签名原文
      // 也包含这个字段，和 QccCreateMultiSigPage.dart 已验证可行的写法保持一致。
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();
      // 4. 执行 Dilithium 签名——统一走 SignUtil.signAndEncode()，内部会用
      // ruleData.toSign() 单独签名后覆盖 packet.signature，不再是空签名。
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: QccObj.activeWallet!.address,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 广播到规则接口
      statusNotifier.value = TxStep.submitting;
      String url = "https://tx.qccio.com/v1/rule";
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("开发者规则返回参数${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          // 深度解析 data 字段以提取业务标识 ruleName
          double rewardRate = _fixedRewardRate; // 默认值：系统固定 20%
          if (resData['data'] != null) {
            try {
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName'] ?? "DeveloperRule";
              rewardRate = (inner['rewardRate'] ?? _fixedRewardRate).toDouble();
            } catch (e) {
              LogObj.log("解析详情失败: $e");
              resData['ruleName'] = "DeveloperRule";
            }
          }
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 的
          // "已提交过就不重复发公钥" 特性使用。
          await SignUtil.instance.markSubmitted(wallet.address);
          // 1. 保存到本地规则状态中心 (内部会调用 saveRawData)
          await UserRuleFileStorage.saveRuleTask(resData);
// 2. 跳转到专属的开发者成功页面
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DeveloperRuleSuccessPage(
                  ruleData: resData,
                ),
              ),
            );
          }
        } else {
          throw resData['msg'] ?? "规则校验未通过";
        }
      } else {
        throw "网络通讯失败: ${response.statusCode}";
      }

    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("开发者规则申请异常: $e");
      Tools.showToast(context, "申请失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}


/// 对齐服务端 qcc.rule.qccRule.SystemPool —— QCC 协议层保留的系统池地址。
/// 这几个不是任何用户的私钥地址，是链上约定好的固定地址，专门用来
/// 存放系统级别的资金池（比如开发者奖励池）。
enum SystemPool {
  system('Q9999999999999999999999999999999999', '系统池'),
  devReward('Q2222222222222222222222222222222222', '开发者奖励池'),
  interest('Q1111111111111111111111111111111111', '利息分配池'),
  // 【待确认】和 Java 端注释一致——这个池子地址目前也是"见下方待确认"
  // 的状态，服务端自己都还没最终敲定，这里先照抄同步过来。
  nodePledge('Q3333333333333333333333333333333333', '节点质押池');

  final String address;
  final String label;

  const SystemPool(this.address, this.label);
}