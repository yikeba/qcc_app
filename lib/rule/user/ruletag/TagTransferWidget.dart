import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// 【修复，重要】按你刚上传的真实 TagRuleWidget.dart 自己的 import 深度反推：
// 它比 DeveloperRuleWidget.dart 所在的 rule/user/ 深一层，是放在 rule/user/
// 下一个独立的子文件夹里（这里先假设叫 ruletag/，和 QccUserRulePage.dart
// 那边的假设保持一致）。TagTransferWidget.dart 是标签功能的另一半，理应
// 和 TagRuleWidget.dart 放同一个子文件夹，所以这里的相对路径统一比之前
// （按扁平目录写的版本）多加一层 `../`。
import '../../../home/QccExplorerService.dart';
import '../../../procotol/QccPacket.dart';
// 【修复，重要】改用协议层真正实现了 toSign()/toBytes() 的 RuleData，不再
// 用 QccRuleBaseObj.dart 里的 QccRuleData——该类整体不再使用。
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/AddressTool.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
// 【修复，重要】原来直接调 QccDataProtocol.encodeTransaction，内部签名逻辑
// 被注释掉（signature 恒为 ""）——这正是"Invalid Signature"被拒的原因。
// 改成统一走 SignUtil（和多签两个页面昨天已经改过的方式一致）。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/LogObj.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../../QccRuleBaseObj.dart';
import '../UserRuleFileStorage.dart';
import 'QccUserRuleExtras.dart';
import 'TagTransferSuccessPage.dart';

/// 【新增】标签资产转让 (TagTransfer) —— 对齐 Java 端
/// qcc.client.userrule.TxTagTransferTest：把自己名下的标签名称资产整体
/// 转让给另一个地址（push式转移，受让人不需要自己签名）。服务端只认
/// rd.from(签名者) == 当前 tag owner，所以这里在提交前提供一个"验证归属"
/// 按钮，先确认发起地址确实是这个 tagName 的当前 owner，避免提交一笔
/// 必定被拒的交易。
class TagTransferWidget extends StatefulWidget {
  const TagTransferWidget({super.key});

  @override
  State<TagTransferWidget> createState() => _TagTransferWidgetState();
}

enum _OwnershipCheck { idle, checking, verified, notOwner, notFound, error }

class _TagTransferWidgetState extends State<TagTransferWidget> {
  final _formKey = GlobalKey<FormState>();
  final _tagController = TextEditingController();
  final _newOwnerController = TextEditingController();

  static const String _tagQueryUrl = "https://tx.qccio.com/v1/tag/";

  _OwnershipCheck _ownership = _OwnershipCheck.idle;
  // 【新增】"查询失败"时带出服务端给的具体原因（比如"查询失败: 节点无
  // 响应"），和 TagRuleWidget 里的同款修复保持一致。
  String? _queryErrorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _tagController.dispose();
    _newOwnerController.dispose();
    super.dispose();
  }

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

            _buildLabel("当前持有账户 (From)"),
            _buildAccountInfoCard(currentAddress),
            const SizedBox(height: 24),

            _buildLabel("待转让的标签名称 (Tag Name)"),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tagController,
                    onChanged: (_) {
                      if (_ownership != _OwnershipCheck.idle) {
                        setState(() {
                          _ownership = _OwnershipCheck.idle;
                          _queryErrorMessage = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "您已注册的标签名称",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                    ),
                    validator: (val) => (val == null || val.trim().isEmpty) ? Tools.getTra("请输入标签名称") : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _ownership == _OwnershipCheck.checking ? null : _checkOwnership,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _ownership == _OwnershipCheck.checking
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Trans("验证归属"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildOwnershipHint(),

            const SizedBox(height: 24),
            _buildLabel("受让地址 (New Owner)"),
            TextFormField(
              controller: _newOwnerController,
              decoration: InputDecoration(
                hintText: "对方的 QCC 单签(Q)或多签(M)地址",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return Tools.getTra("请输入受让地址");
                if (!AddressTool.isValidTransferAddressFormat(val.trim())) {
                  return Tools.getTra("地址格式不正确");
                }
                if (val.trim() == (QccObj.activeWallet?.address ?? "")) {
                  return Tools.getTra("不能转让给自己");
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildWarningNote(),
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
        Trans("标签资产转让 (TagTransfer)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "将您名下已注册的标签名称资产整体转让给另一个地址。转让为单向操作，"
              "受让方不需要签名确认——提交成功后，标签的全部归属权益立即转移，"
              "原地址将不再拥有该标签的任何权限。",
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
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.purple, size: 20),
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

  Widget _buildOwnershipHint() {
    if (_ownership == _OwnershipCheck.verified) {
      return _hintCard(Icons.check_circle, Colors.green, "已确认您是该标签的当前持有者，可以发起转让");
    }
    if (_ownership == _OwnershipCheck.notOwner) {
      return _hintCard(Icons.error_outline, Colors.redAccent, "当前钱包不是该标签的持有者，提交转让必定被拒");
    }
    if (_ownership == _OwnershipCheck.notFound) {
      return _hintCard(Icons.help_outline, Colors.redAccent, "查无此标签，请确认名称是否输入正确");
    }
    if (_ownership == _OwnershipCheck.error) {
      final String reason =
      (_queryErrorMessage != null && _queryErrorMessage!.isNotEmpty) ? "：$_queryErrorMessage" : "";
      return _hintCard(Icons.help_outline, Colors.grey, "查询失败$reason，建议先重试验证归属再提交");
    }
    return const SizedBox.shrink();
  }

  Widget _hintCard(IconData icon, Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }

  Widget _buildWarningNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Trans(
              "请仔细核对受让地址，转让一经公链确认不可撤销，转错地址将无法追回该标签。",
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
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
        onPressed: _isSubmitting ? null : _handleTransfer,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("签署并发起转让"),
      ),
    );
  }

  Future<void> _checkOwnership() async {
    final String tagName = _tagController.text.trim();
    if (tagName.isEmpty) return;
    setState(() => _ownership = _OwnershipCheck.checking);
    try {
      final response =
      await http.get(Uri.parse("$_tagQueryUrl$tagName")).timeout(const Duration(seconds: 15));
      // 【修复，重要】和 TagRuleWidget._checkAvailability() 同一个问题——
      // 不能只靠 HTTP 状态码判断成功/失败，实测下来节点异常时 body 里也会
      // 带 200 之外的状态但 JSON 结构完好，统一用 body 里的 "ok" 字段判断：
      //   ok:true  + found:true  → 查到归属，比对是否是当前钱包
      //   ok:true  + found:false → 查无此标签
      //   ok:false               → 真正的查询失败(节点异常等)，原样带出
      //                            服务端给的 message，不能当成"查无此标签"
      final dynamic data = jsonDecode(response.body);
      final bool ok = data is Map && data['ok'] == true;
      if (ok) {
        LogObj.log("TagTransfer 归属验证成功: ${response.body}");
        final bool found = data['found'] == true;
        if (!found) {
          if (mounted) setState(() => _ownership = _OwnershipCheck.notFound);
          return;
        }
        final Map? tagInfo = data['data'] is Map ? data['data'] as Map : null;
        final String? ownerVal = tagInfo?['owner']?.toString();
        final bool isOwner = ownerVal != null && ownerVal == QccObj.activeWallet?.address;
        if (mounted) {
          setState(() => _ownership = isOwner ? _OwnershipCheck.verified : _OwnershipCheck.notOwner);
        }
      } else {
        LogObj.log("TagTransfer 归属验证失败: ${response.body}");
        final String? msg = (data is Map) ? data['message']?.toString() : null;
        if (mounted) {
          setState(() {
            _ownership = _OwnershipCheck.error;
            _queryErrorMessage = msg;
          });
        }
      }
    } catch (e) {
      LogObj.log("TagTransfer 归属验证异常: $e");
      if (mounted) {
        setState(() {
          _ownership = _OwnershipCheck.error;
          _queryErrorMessage = null;
        });
      }
    }
  }

  Future<void> _handleTransfer() async {
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
      QccWallet? wallet = await QccStorage.restoreWallet(context, QccObj.activeWallet!.address, password);
      if (wallet == null || wallet.address != QccObj.activeWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      if (wallet.privateKey == null) throw "支付密码错误";

      // 2. 构建转让对象——服务端只认签名地址(from)==当前 owner，newOwner
      // 不需要自己签名（push式转移）
      statusNotifier.value = TxStep.building;
      final tagTransfer = QccTagTransfer(
        tagName: _tagController.text.trim(),
        newOwner: _newOwnerController.text.trim(),
      );

      // 3. 构建公链规则容器——RuleData() 构造函数已自动填好 timestamp/chain。
      final ruleData = RuleData();
      ruleData.from = QccObj.activeWallet!.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "TagTransfer";
      ruleData.ruleJson = jsonEncode(tagTransfer.toJson());
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
      LogObj.log("标签转让返回参数${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          if (resData['data'] != null) {
            try {
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName'] ?? "TagTransfer";
            } catch (e) {
              LogObj.log("解析标签转让详情失败: $e");
              resData['ruleName'] = "TagTransfer";
            }
          } else {
            resData['ruleName'] = "TagTransfer";
          }
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          await UserRuleFileStorage.saveRuleTask(resData);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => TagTransferSuccessPage(ruleData: resData)),
            );
          }
        } else {
          throw resData['msg'] ?? "转让被拒绝（请确认您仍是该标签的当前持有者）";
        }
      } else {
        throw "网络通讯失败: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("标签转让异常: $e");
      Tools.showToast(context, "转让失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}