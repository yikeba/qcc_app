import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccQueryService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
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
import '../../../home/QccTxConfirmDialog.dart';

class MerchantRuleWidget extends StatefulWidget {
  /// 可选：外部指定的商户钱包；不传则默认当前激活钱包。
  final QccWallet? initialWallet;
  const MerchantRuleWidget({super.key, this.initialWallet});

  @override
  State<MerchantRuleWidget> createState() => _MerchantRuleWidgetState();
}

class _MerchantRuleWidgetState extends State<MerchantRuleWidget> {
  final _formKey = GlobalKey<FormState>();

  // 核心配置
  bool _isGasDelegationEnabled = true;
  final _assetIdController = TextEditingController(text: "QCC");

  bool _isSubmitting = false;

  /// 规则交易手续费（gas.quote 顶层 ruleGasQcc），查不到时不显示。
  double? _ruleGasQcc;

  // ---- 商户地址选择（与存证发布页同一模式）----
  QccWallet? _currentWallet;
  List<QccWallet> _localWallets = [];
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    _currentWallet = widget.initialWallet;
    _loadLocalWallets();
    _loadRuleGas();
  }

  /// 加载本机全部钱包和昵称；未指定钱包时默认当前激活钱包，否则取第一个。
  Future<void> _loadLocalWallets() async {
    final names = await QccStorage.getAllWalletNames();
    final wallets = QccObj.readWallets();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localWallets = wallets;
      if (_currentWallet == null && wallets.isNotEmpty) {
        final active = QccObj.activeWallet;
        _currentWallet = (active != null && wallets.any((w) => w.address == active.address))
            ? active
            : wallets.first;
      }
    });
  }

  void _pickMerchantAddress() {
    if (_localWallets.length <= 1 || _isSubmitting) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Trans("选择商户地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _localWallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = _localWallets[i];
                    final bool isSelected = _currentWallet?.address == w.address;
                    final String? nick = _walletNames[w.address];
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: isSelected ? Colors.orange : Colors.grey),
                      title: Text(nick ?? Tools.getTra("未命名钱包"),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      trailing: QccActiveWallet(w.address, "QCC", fontSize: 12, fontColor: Colors.black87),
                      onTap: () {
                        setState(() => _currentWallet = w);
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _assetIdController.dispose();
    super.dispose();
  }

  Future<void> _loadRuleGas() async {
    try {
      final q = await QccQueryService.gasQuoteOverview();
      if (mounted) setState(() => _ruleGasQcc = q.ruleGasQcc);
    } catch (_) {
      // 查不到就不显示，不影响发布
    }
  }

  String _fmtQcc(double v) {
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            _buildLabel("发起商户账户 (Merchant From)"),
            _buildAccountInfoCard(),
            const SizedBox(height: 24),

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

            if (_ruleGasQcc != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  "本次规则交易手续费：${_fmtQcc(_ruleGasQcc!)} QCC",
                  style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                ),
              ),

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

  /// 商户账户卡片：显示昵称 + 地址 + 余额；本机有多个钱包时可点击切换。
  Widget _buildAccountInfoCard() {
    final String? address = _currentWallet?.address;
    final String? nick = address == null ? null : _walletNames[address];
    final bool canSwitch = _localWallets.length > 1 && !_isSubmitting;

    return InkWell(
      onTap: canSwitch ? _pickMerchantAddress : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
                  Text(
                    nick ?? Tools.getTra(address == null ? "未选择钱包" : "未命名钱包"),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address != null) ...[
                    const SizedBox(height: 2),
                    Text(address,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.blueGrey),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Trans("当前余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.green),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (canSwitch) ...[
              const SizedBox(width: 8),
              const Icon(Icons.swap_horiz, color: Colors.blueGrey),
            ],
          ],
        ),
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

  // --- 核心逻辑：封装 MerchantRule → 提交 → 受理 → 轮询上链 ---
  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate()) return;
    // 用页面上选中的商户地址，而不是全局激活钱包
    final active = _currentWallet;
    if (active == null) {
      Tools.showToast(context, "请先选择商户地址");
      return;
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 原来的写法：成功路径里先 pop 了 loading，随后如果 throw（被拒/非 200），
    // catch 里会再 pop 一次 —— 弹出的是当前页面本身。用标志位保证只关一次。
    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. 还原私钥
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, active.address, password);
      if (wallet == null || wallet.address != active.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 2. 构建 MerchantRule —— 字段对齐 Java MerchantRule：
      //    address / assetId / gasDelegation / credentialHash
      statusNotifier.value = TxStep.building;
      final String assetId = _assetIdController.text.trim();
      final merchantRule = QccMerchantRule(
        address: active.address,
        credentialHash: "",
        gasDelegation: _isGasDelegationEnabled,
      );
      // Java 端 MerchantRule 已经有正式的 assetId 字段，不再是"临时插入"。
      // 建议把 assetId 加进 QccMerchantRule 类本身，这里是过渡写法。
      final Map<String, dynamic> ruleMap = merchantRule.toJson();
      ruleMap['assetId'] = assetId;

      // 3. 规则交易容器 —— 对齐 Java TxUserRuleTest.sendRuleRequest()
      final ruleData = RuleData(); // 构造函数已填 timestamp/chain
      // Java 显式设置了 assetId = "QCCRule"，原 Flutter 代码没设。
      // 它参与 id 与签名计算，必须在 finalizeId() 之前赋值。
      ruleData.assetId = "QCCRule";
      ruleData.from = active.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "MerchantRule";
      ruleData.ruleJson = jsonEncode(ruleMap);
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();

      // 4. 签名
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: active.address,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 提交 /v1/rule
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      closeLoading();
      LogObj.log("商户规则返回参数${response.body}");
      if (response.statusCode != 200) {
        throw "网络通讯异常: ${response.statusCode}";
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      // 现在的返回：{"status":"accepted","code":"ACCEPTED","txHash":..,"msg":..}
      // 原来判断 status=='ACCEPTED'||'success'，对小写 accepted 永远不成立，
      // 会把"已受理"当成失败抛出，用户看到"设置失败"后重发，就会重复扣费。
      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "规则发布被拒绝";
      }

      // 新返回里没有 data 字段，ruleName 直接用本地值；id 兼容旧格式 data.id。
      resData['ruleName'] = "MerchantRule";
      resData['id'] = txHash;
      resData['from'] = active.address;
      resData['ruleJson'] = ruleData.ruleJson;
      resData['chainStatus'] = 'pending';

      // 6. 先落本地记录（受理 ≠ 上链）
      await UserRuleFileStorage.saveRuleTask(resData);

      if (!mounted) return;

      // 7. 轮询上链
      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: "商户规则已上链",
          details: [
            Text("规则：商户 Gas 到付 ${_isGasDelegationEnabled ? '开启' : '关闭'}"),
            Text("限定资产：${assetId.isEmpty ? '全部资产' : assetId}"),
          ],
          footer: "规则只有上链后才生效。",
          onFinal: (s) async {
            await UserRuleFileStorage.saveRuleTask({
              ...resData,
              'chainStatus': s.state.name, // confirmed / failed
              if (s.blockHeight != null) 'blockHeight': s.blockHeight,
              if (s.message != null) 'chainMsg': s.message,
            });
            // 公钥登记以"上链"为准：只受理未上链就标记，下一笔交易会省掉公钥，
            // 若这一笔最终失败，下一笔就会因链上查不到公钥而验签失败。
            if (s.state == TxChainState.confirmed) {
              await SignUtil.instance.markSubmitted(wallet.address);
            }
          },
        ),
      );

      if (!mounted) return;
      if (st?.state == TxChainState.confirmed) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MerchantRuleSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "规则上链失败：${st!.message ?? '未知原因'}", isError: true);
      } else {
        Tools.showToast(context, "规则交易已受理，尚未确认上链，请稍后在规则状态中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("商户规则配置异常: $e");
      if (mounted) Tools.showToast(context, "设置失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}