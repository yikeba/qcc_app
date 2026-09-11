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
import '../UserRuleFileStorage.dart';
import '../ruletag/QccUserRuleExtras.dart';
import 'AddressEndSuccessPage.dart';

/// 【新增，高危】地址生命周期结束 (AddressEnd) —— 对齐 Java 端
/// qcc.client.userrule.TxAddressEndTest：地址持有者单签声明彻底结束自己的
/// 生命周期，此后即便拥有正确私钥也无法再签发任何交易，全网判定为"死亡
/// 地址"。这是三个新规则里唯一不可逆、后果最严重的一种，UI 交互力度必须
/// 远高于 TagRule/TagTransfer/Developer/Merchant/PayCall 这几种"随手一点
/// 就发"的规则交易：
///   1. 顶部醒目红色警示条 + 后果清单
///   2. 必须勾选"我已知晓"复选框
///   3. 必须手动输入确认短语才能解锁提交按钮
///   4. 点击提交后还有一道原生弹窗二次确认
/// 四道关卡全部通过才会真正进入密码校验 -> 签名 -> 广播流程。
class AddressEndWidget extends StatefulWidget {
  const AddressEndWidget({super.key});

  @override
  State<AddressEndWidget> createState() => _AddressEndWidgetState();
}

class _AddressEndWidgetState extends State<AddressEndWidget> {
  static const String _confirmPhrase = "确认结束";
  final _confirmController = TextEditingController();
  bool _ackRisk = false;
  bool _isSubmitting = false;

  bool get _canSubmit =>
      _ackRisk && _confirmController.text.trim() == _confirmPhrase && !_isSubmitting;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentAddress = QccObj.activeWallet?.address ?? Tools.getTra("未选择钱包");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDangerBanner(),
          const SizedBox(height: 20),
          _buildHeader(),
          const SizedBox(height: 24),

          _buildLabel("即将终止的地址 (From)"),
          _buildAccountInfoCard(currentAddress),
          const SizedBox(height: 24),

          _buildConsequenceList(),
          const SizedBox(height: 24),

          _buildAckCheckbox(),
          const SizedBox(height: 16),
          _buildConfirmInput(),
          const SizedBox(height: 32),

          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDangerBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Trans("高危操作：地址生命周期终止",
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Trans(
                  "一旦发起此交易，此地址将在全 QCC 公链范围内被判定为「死亡地址」，"
                      "公链将永久拒绝此地址发起的任何私钥交易。此操作不可逆、无法撤销、"
                      "任何人都无法帮您恢复，请务必确认您完全理解后果后再继续。",
                  style: const TextStyle(color: Colors.red, fontSize: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("地址死亡结束规则 (AddressEnd)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "这是 QCC 协议里的\"发布者退场\"机制：地址持有者可以单签声明彻底"
              "结束自己的生命周期，之后即使拥有正确私钥也无法再签发任何交易——"
              "常用于协议发布者主动交出权限，让已发布的协议内容变得永不可篡改。",
          style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
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
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.dangerous_rounded, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Trans("当前余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.red),
                  ],
                ),
                const SizedBox(height: 4),
                Trans("如有余额，建议先转出，否则可能被永久锁死在此地址中",
                    style: const TextStyle(fontSize: 10.5, color: Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsequenceList() {
    final List<String> items = [
      "该地址此后无法再发起转账、规则交易或任何私钥签名操作",
      "该地址持有的全部资产将无法被转出，实际等同于永久冻结",
      "该地址此前已发布的规则/协议内容将无法再被本地址修改或撤销",
      "此操作一旦公链确认，任何人（包括开发者/客服）都无法帮您恢复",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Trans("发起后将发生什么", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          ...items.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 5, color: Colors.redAccent),
                ),
                const SizedBox(width: 8),
                Expanded(child: Trans(t, style: const TextStyle(fontSize: 12.5, height: 1.4))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildAckCheckbox() {
    return InkWell(
      onTap: () => setState(() => _ackRisk = !_ackRisk),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _ackRisk ? Colors.red.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _ackRisk ? Colors.red.withValues(alpha: 0.4) : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _ackRisk,
              activeColor: Colors.red,
              onChanged: (v) => setState(() => _ackRisk = v ?? false),
            ),
            Expanded(
              child: Trans("我已完整阅读并理解上述后果，自愿、不可撤销地终止此地址的生命周期",
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("请输入「$_confirmPhrase」以解锁提交按钮", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _confirmController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _confirmPhrase,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.red.withValues(alpha: 0.02),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _canSubmit ? _handleConfirmAndSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认发起地址死亡交易", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// 提交前再来一道原生弹窗二次确认——防止手滑，通过之后才会真正进入
  /// 密码校验 -> 签名 -> 广播流程。
  Future<void> _handleConfirmAndSubmit() async {
    final bool? finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.dangerous_rounded, color: Colors.red),
            SizedBox(width: 8),
            Trans("最后确认"),
          ],
        ),
        content: const Trans(
          "此操作不可撤销。提交后此地址将永久无法再签发任何交易。\n\n真的要继续吗？",
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Trans("取消")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Trans("确认终止", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (finalConfirm != true) return;
    await _handleSubmit();
  }

  Future<void> _handleSubmit() async {
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
      QccWallet? wallet = await QccStorage.restoreWallet(context, QccObj.activeWallet!.address, password);
      if (wallet == null || wallet.address != QccObj.activeWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      if (wallet.privateKey == null) throw "支付密码错误";

      // 2. 构建地址结束对象——address 仅声明用途，服务端应以签名地址(from)为准
      statusNotifier.value = TxStep.building;
      final endRule = QccAddressEnd(address: QccObj.activeWallet!.address);

      // 3. 构建公链规则容器——RuleData() 构造函数已自动填好 timestamp/chain。
      final ruleData = RuleData();
      ruleData.from = QccObj.activeWallet!.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "AddressEnd";
      ruleData.ruleJson = jsonEncode(endRule.toJson());
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

      // 5. 广播
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("地址死亡结束交易返回参数${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          if (resData['data'] != null) {
            try {
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName'] ?? "AddressEnd";
            } catch (e) {
              LogObj.log("解析地址结束详情失败: $e");
              resData['ruleName'] = "AddressEnd";
            }
          } else {
            resData['ruleName'] = "AddressEnd";
          }
          // 【新增】标记该地址已成功提交过交易——虽然这个地址接下来就死亡了，
          // 不会再有下一笔交易需要"跳过公钥"，但这里仍保留调用以保持所有
          // 规则交易统一走同一套收尾流程，不额外特判。
          await SignUtil.instance.markSubmitted(wallet.address);
          await UserRuleFileStorage.saveRuleTask(resData);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AddressEndSuccessPage(ruleData: resData)),
            );
          }
        } else {
          throw resData['msg'] ?? "交易被拒绝";
        }
      } else {
        throw "网络通讯失败: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("地址死亡结束异常: $e");
      Tools.showToast(context, "提交失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}