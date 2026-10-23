import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccQueryService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
import '../../../../../home/QccExplorerService.dart';
import '../../../../../procotol/QccPacket.dart';
import '../../../../../procotol/RuleData.dart';
import '../../../../../qccwallet/QccActiveWallet.dart';
import '../../../../../qccwallet/QccWallet.dart';
import '../../../../../qccwallet/SignUtil.dart';
import '../../../../../utile/QccObj.dart';
import '../../../../../utile/QccStorage.dart';
import '../../../../../utile/Tools.dart';
import '../../../../../views/setting/AppTranslator.dart';
import '../../../../../views/setting/QccPassDialog.dart';
import '../../../../../views/toolviews/QccLoading.dart';
import '../../../qccsys/SystemPool.dart';
import '../../QccRuleBaseObj.dart';
import '../UserRuleFileStorage.dart';
import 'DeveloperRuleSuccessPage.dart';
import 'DeveloperRuleWidget.dart';


class DeveloperRuleWidget extends StatefulWidget {
  /// 可选：外部指定的申请钱包；不传则默认当前激活钱包。
  final QccWallet? initialWallet;
  const DeveloperRuleWidget({super.key, this.initialWallet});

  @override
  State<DeveloperRuleWidget> createState() => _DeveloperRuleWidgetState();
}

class _DeveloperRuleWidgetState extends State<DeveloperRuleWidget> {
  final _formKey = GlobalKey<FormState>();

  // 开发者奖励比例是系统固定 20%，由系统结算时原子完成，不可自定义。
  static const double _fixedRewardRate = 0.2;

  bool _isSubmitting = false;

  /// 规则交易手续费（gas.quote 顶层 ruleGasQcc），查不到时不显示。
  double? _ruleGasQcc;
  bool _isLoadingGas = false;

  // ---- 申请地址选择（与商户规则同一模式）----
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

  Future<void> _loadRuleGas() async {
    setState(() => _isLoadingGas = true);
    try {
      final q = await QccQueryService.gasQuoteOverview();
      if (mounted) setState(() => _ruleGasQcc = q.ruleGasQcc);
    } catch (_) {
      // 查不到就不显示，不影响申请
    } finally {
      if (mounted) setState(() => _isLoadingGas = false);
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
            const SizedBox(height: 20),

            _buildHowItWorks(),
            const SizedBox(height: 24),

            _buildLabel("开发者地址（注册后填入你应用的 fromdev）"),
            _buildAccountInfoCard(),
            const SizedBox(height: 10),
            _buildFromdevHint(),
            const SizedBox(height: 24),

            _buildLabel("奖励比例 (Reward Rate)"),
            _buildFixedRateCard(),
            const SizedBox(height: 24),

            _buildLabel("开发者奖励池总奖金"),
            _buildRewardPoolCard(),
            const SizedBox(height: 24),

            _buildGasCard(),
            const SizedBox(height: 16),

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
        Trans("注册 QCC 开发者", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "开发钱包、选举、民调或任何基于 QCC 的应用，都可以注册为开发者。"
              "此后任何人通过你的应用在 QCC 上交易，公链都会按该笔 Gas 的 20% "
              "把奖励直接结算给你。",
          style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  /// 开发者奖励的完整说明：怎么注册、怎么接入、奖励怎么来、哪些交易计奖。
  Widget _buildHowItWorks() {
    const TextStyle body = TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.5);
    const TextStyle note = TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.5);

    Widget step(int n, String title, String desc) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              child: Text("$n", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(desc, style: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("开发者奖励如何运作", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 12),
          step(1, "用你的地址注册（一次性）",
              "在任意钱包用你的地址发布本开发者规则交易，支付一次性注册手续费。上链后，该地址即成为链上登记的 QCC 开发者。"),
          step(2, "在你的应用里填写 fromdev",
              "你的应用构造交易时，把交易的 fromdev 字段设为这个开发者地址。fromdev 参与交易签名，用户和中间节点都无法篡改奖励归属。"),
          step(3, "用户交易，公链自动结算奖励",
              "任何人通过你的应用发起交易，公链在执行该笔交易时，原子级地把 Gas 的 20% 结算给 fromdev。无需你的服务器参与，也无需任何人工结算。"),
          const Divider(height: 20),
          const Text("计奖范围", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text("✓ 资金交易（转账等）\n✓ 字节存证交易\n✗ 规则类交易不计奖（包括本次注册交易）", style: body),
          const SizedBox(height: 8),
          const Text(
            "奖励比例为全网统一的 20%，由公链执行层固定计算，不可申请或自定义。"
                "奖励只在本规则上链之后产生，此前带该 fromdev 的交易不追溯计奖。",
            style: note,
          ),
        ],
      ),
    );
  }

  /// 把当前选中的地址作为 fromdev 示例展示，并可一键复制，方便开发者填进自己的应用。
  Widget _buildFromdevHint() {
    final String? addr = _currentWallet?.address;
    if (addr == null) return const SizedBox.shrink();
    final String code = 'tx.fromdev = "$addr";';
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: addr));
        Tools.showToast(context, "开发者地址已复制");
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("在你的应用中：", style: TextStyle(fontSize: 10.5, color: Colors.white54)),
                  const SizedBox(height: 4),
                  Text(code,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF7DD3FC))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.copy, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

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

  /// 开发者奖励池实时余额 —— 协议保留地址 SystemPool.devReward。
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

  /// 本次规则交易手续费，取自 gas.quote 的 ruleGasQcc（链上实时规则）。
  Widget _buildGasCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_gas_station_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _ruleGasQcc != null
                  ? "一次性注册手续费 ${_fmtQcc(_ruleGasQcc!)} QCC，由开发者地址扣除"
                  : (_isLoadingGas ? "正在查询链上手续费…" : "手续费查询失败，以链上实际扣除为准"),
              style: TextStyle(
                fontSize: 12,
                fontWeight: _ruleGasQcc != null ? FontWeight.bold : FontWeight.normal,
                color: _ruleGasQcc != null ? Colors.deepOrange : Colors.grey,
              ),
            ),
          ),
          if (_ruleGasQcc == null && !_isLoadingGas)
            IconButton(
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.refresh, color: Colors.deepOrange),
              onPressed: _loadRuleGas,
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

  /// 申请账户卡片：昵称 + 地址 + 余额；本机多个钱包时可点击切换。
  Widget _buildAccountInfoCard() {
    final String? address = _currentWallet?.address;
    final String? nick = address == null ? null : _walletNames[address];
    final bool canSwitch = _localWallets.length > 1 && !_isSubmitting;

    return InkWell(
      onTap: canSwitch ? _pickAddress : null,
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
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.code, color: Colors.blue, size: 20),
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

  void _pickAddress() {
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
                child: Trans("选择申请地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                          color: isSelected ? Colors.blueAccent : Colors.grey),
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

  // --- 构造规则 → 提交 → 受理 → 轮询上链 ---
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    final active = _currentWallet;
    if (active == null) {
      Tools.showToast(context, "请先选择申请地址");
      return;
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 原写法成功路径先 pop loading，之后 throw 时 catch 再 pop 一次，弹掉的是
    // 当前页面。用标志位保证只关一次。
    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. 还原私钥（按选中的地址）
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, active.address, password);
      if (wallet == null || wallet.address != active.address || wallet.privateKey == null) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 2. 开发者规则对象（对应 Java DeveloperRule）
      statusNotifier.value = TxStep.building;
      final devRule = QccDeveloperRule(
        address: active.address,
        credentialHash: "",
        rewardRate: _fixedRewardRate,
      );

      // 3. 规则容器 —— 对齐 Java TxUserRuleTest.sendRuleRequest()（四种用户规则共用）
      final ruleData = RuleData();
      // Java 显式设置 assetId = "QCCRule"，原 Flutter 代码没设；参与 id/签名，
      // 必须在 finalizeId() 之前。
      ruleData.assetId = "QCCRule";
      ruleData.from = active.address;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "DeveloperRule";
      ruleData.ruleJson = jsonEncode(devRule.toJson());
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

      // 5. 提交 —— 原来写死 https://tx.qccio.com，改为统一 baseUrl
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      closeLoading();
      LogObj.log("开发者规则返回参数${response.body}");
      if (response.statusCode != 200) {
        throw "网络通讯失败: ${response.statusCode}";
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      // 返回 {"status":"accepted","code":"ACCEPTED","txHash":..}；原来判断
      // status=='ACCEPTED' 对小写 accepted 永远不成立。以 code 为准。
      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "规则校验未通过";
      }

      resData['ruleName'] = "DeveloperRule";
      resData['id'] = txHash;
      resData['from'] = active.address;
      resData['ruleJson'] = ruleData.ruleJson;
      resData['chainStatus'] = 'pending';
      if (_ruleGasQcc != null) resData['gas'] = _ruleGasQcc;

      // 6. 先落本地记录（受理 ≠ 上链）
      await UserRuleFileStorage.saveRuleTask(resData);

      if (!mounted) return;

      // 7. 轮询上链
      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: "开发者身份已上链",
          details: [
            Text("申请地址：${_walletNames[active.address] ?? ''} ${active.address}",
                style: const TextStyle(fontSize: 12)),
            Text("奖励比例：${(_fixedRewardRate * 100).toStringAsFixed(0)}%（系统固定）"),
            if (_ruleGasQcc != null) Text("手续费：${_fmtQcc(_ruleGasQcc!)} QCC"),
          ],
          footer: "上链后，该地址的资金交易与存证交易才开始计算开发者奖励。",
          onFinal: (s) async {
            await UserRuleFileStorage.saveRuleTask({
              ...resData,
              'chainStatus': s.state.name,
              if (s.blockHeight != null) 'blockHeight': s.blockHeight,
              if (s.message != null) 'chainMsg': s.message,
            });
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
            builder: (context) => DeveloperRuleSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "开发者规则上链失败：${st!.message ?? '未知原因'}", isError: true);
      } else {
        Tools.showToast(context, "申请已受理，尚未确认上链，请稍后在规则状态中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("开发者规则申请异常: $e");
      if (mounted) Tools.showToast(context, "申请失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
