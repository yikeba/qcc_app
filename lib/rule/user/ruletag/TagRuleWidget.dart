import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccQueryService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
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
import 'QccUserRuleExtras.dart';
import 'TagQueryService.dart';
import 'TagRuleSuccessPage.dart';

/// 标签资产注册 (TagRule) —— 对齐 Java qcc.testNetwork.userrule.TxTagRuleTest。
/// 一次性写入、全网唯一的"这个 tag 归谁"登记，可作为去中心化应用的鉴权
/// 凭证 / 命名空间 / 域名解析；注册后可通过「标签转让」转给他人。
enum _TagAvailability { idle, checking, available, taken, error }

class TagRuleWidget extends StatefulWidget {
  const TagRuleWidget({super.key});

  @override
  State<TagRuleWidget> createState() => _TagRuleWidgetState();
}

class _TagRuleWidgetState extends State<TagRuleWidget> {
  final _formKey = GlobalKey<FormState>();
  final _tagController = TextEditingController();

  Map<String, String> _walletNames = {};
  List<String> _localAddrs = [];
  String nowaddress = "";

  _TagAvailability _availability = _TagAvailability.idle;
  String? _takenByAddress;
  int? _takenRegTime;
  String? _queryErrorMessage;
  bool _isSubmitting = false;

  /// 规则交易手续费（gas.quote 顶层 ruleGasQcc）
  double? _ruleGasQcc;
  bool _isLoadingGas = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _loadRuleGas();
  }

  Future<void> _initialLoad() async {
    final names = await QccStorage.getAllWalletNames();
    final addrs = QccObj.readWallets().map((e) => e.address).toSet().toList();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localAddrs = addrs;
      if (addrs.isNotEmpty) {
        final active = QccObj.activeWallet?.address;
        nowaddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
  }

  Future<void> _loadRuleGas() async {
    setState(() => _isLoadingGas = true);
    try {
      final q = await QccQueryService.gasQuoteOverview();
      if (mounted) setState(() => _ruleGasQcc = q.ruleGasQcc);
    } catch (_) {
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
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState(Icons.account_balance_wallet_outlined, "本机未导入任何钱包，无法注册标签。");
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            _buildLabel("注册账户 (Owner)"),
            _buildAddressPicker(),
            const SizedBox(height: 12),
            _buildAccountInfoCard(nowaddress),
            const SizedBox(height: 24),

            _buildLabel("标签名称 (Tag Name)"),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tagController,
                    onChanged: (_) {
                      if (_availability != _TagAvailability.idle) {
                        setState(() {
                          _availability = _TagAvailability.idle;
                          _takenByAddress = null;
                          _takenRegTime = null;
                          _queryErrorMessage = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "例如 qccname",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return Tools.getTra("请输入标签名称");
                      if (!RegExp(r'^[a-zA-Z0-9_\-]{2,32}$').hasMatch(val.trim())) {
                        return Tools.getTra("仅支持字母/数字/下划线/中划线，2-32位");
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _availability == _TagAvailability.checking ? null : _checkAvailability,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _availability == _TagAvailability.checking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Trans("查询"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildAvailabilityHint(),

            const SizedBox(height: 24),
            _buildInfoNote(),
            const SizedBox(height: 16),
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
        Trans("标签资产注册 (TagRule)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "标签是 QCC 公链上全网唯一、去中心化确权的命名资产，可用作去中心化"
              "应用的鉴权凭证、命名空间划分或去中心化域名解析。注册成功后此标签"
              "将永久归属于您的地址（除非您主动发起「标签转让」）。",
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

  Widget _buildAddressPicker() {
    return DropdownButtonFormField<String>(
      value: nowaddress.isEmpty ? null : nowaddress,
      isExpanded: true,
      items: _localAddrs
          .map((a) => DropdownMenuItem(
                value: a,
                child: Text(
                  _walletNames[a] != null ? "${_walletNames[a]} ($a)" : a,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: _isSubmitting
          ? null
          : (val) {
              if (val != null) setState(() => nowaddress = val);
            },
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAccountInfoCard(String address) {
    final String? nick = _walletNames[address];
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
            child: const Icon(Icons.sell_outlined, color: Colors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nick != null && nick.isNotEmpty)
                  Text(nick,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                Text(address,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: nick != null && nick.isNotEmpty ? FontWeight.normal : FontWeight.bold,
                        color: nick != null && nick.isNotEmpty ? Colors.grey[600] : Colors.black),
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

  Widget _buildAvailabilityHint() {
    if (_availability == _TagAvailability.available) {
      return _hintCard(Icons.check_circle, Colors.green, "该标签尚未被注册，可以放心提交");
    }
    if (_availability == _TagAvailability.taken) {
      final String ownerPart = _takenByAddress != null ? "，归属地址：${_shortAddr(_takenByAddress!)}" : "";
      final String timePart = _takenRegTime != null ? "，注册于 ${TagQueryService.formatTime(_takenRegTime!)}" : "";
      return _hintCard(Icons.error_outline, Colors.redAccent, "该标签已被注册$ownerPart$timePart");
    }
    if (_availability == _TagAvailability.error) {
      final String reason =
          (_queryErrorMessage != null && _queryErrorMessage!.isNotEmpty) ? "：$_queryErrorMessage" : "";
      return _hintCard(Icons.help_outline, Colors.grey, "查询失败$reason，仍可直接提交由公链最终裁定");
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

  String _shortAddr(String addr) =>
      addr.length > 16 ? "${addr.substring(0, 8)}...${addr.substring(addr.length - 6)}" : addr;

  Widget _buildInfoNote() {
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
          const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Trans(
              "标签资产可以通过「标签转让」交易整体转让给其他地址，转让后原地址将"
                  "失去该标签的全部权益。",
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  /// 本次规则交易手续费 —— gas.quote 的 ruleGasQcc
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
                  ? "注册手续费 ${_fmtQcc(_ruleGasQcc!)} QCC，由注册账户扣除"
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

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("签署并注册标签"),
      ),
    );
  }

  /// 手动查询可用性，返回查询结果供提交前复用。
  Future<TagInfo?> _checkAvailability() async {
    final String tagName = _tagController.text.trim();
    if (tagName.isEmpty) return null;
    setState(() => _availability = _TagAvailability.checking);
    final info = await TagQueryService.query(tagName);
    if (!mounted) return info;
    setState(() {
      if (!info.ok) {
        _availability = _TagAvailability.error;
        _queryErrorMessage = info.error;
      } else if (info.found) {
        _availability = _TagAvailability.taken;
        _takenByAddress = info.owner;
        _takenRegTime = info.regTime;
      } else {
        _availability = _TagAvailability.available;
      }
    });
    return info;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (nowaddress.isEmpty) {
      Tools.showToast(context, "请选择注册账户");
      return;
    }
    final String from = nowaddress; // 提交过程中锁定，避免中途切换
    final String tagName = _tagController.text.trim();

    // 提交前强制查一次：已被注册就不签名、不扣费。
    // 查询失败（ok:false/网络异常）不拦截，交给公链裁定。
    final pre = await _checkAvailability();
    if (!mounted) return;
    if (pre != null && pre.ok && pre.found) {
      Tools.showToast(context, pre.owner == from ? "该标签已归属当前账户，无需重复注册" : "该标签已被他人注册");
      return;
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 原写法成功路径先 pop loading，之后 throw 时 catch 再 pop 一次，弹掉的是当前页面
    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    setState(() => _isSubmitting = true);
    try {
      // 1. 还原私钥
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, from, password);
      if (wallet == null || wallet.address != from || wallet.privateKey == null) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 2. 标签注册对象 —— 对齐 Java tagJson {tagName, owner}；owner 仅声明，服务端以 from 为准
      statusNotifier.value = TxStep.building;
      final tagRule = QccTagRule(tagName: tagName, owner: from);

      // 3. 规则容器 —— 对齐 Java buildTagRuleData()
      final ruleData = RuleData();
      // Java 显式设置 assetId = "QCCRule"，原 Flutter 没设；参与 id/签名，须在 finalizeId() 前
      ruleData.assetId = "QCCRule";
      ruleData.from = from;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "TagRule";
      ruleData.ruleJson = jsonEncode(tagRule.toJson());
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();

      // 4. 签名（对应 Java WalletSigner.sign(ruleData.toSign()) 覆盖 packet.signature）
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: from,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 提交 —— 统一 baseUrl（原写死 tx.qccio.com）
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      closeLoading();
      LogObj.log("标签注册返回参数${response.body}");
      if (response.statusCode != 200) throw "网络通讯失败: ${response.statusCode}";

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      // 返回 {"status":"accepted","code":"ACCEPTED","txHash":..}；原判断 status=='ACCEPTED' 永不成立
      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "标签注册被拒绝（可能已被占用）";
      }

      resData['ruleName'] = "TagRule";
      resData['id'] = txHash;
      resData['from'] = from;
      resData['ruleJson'] = ruleData.ruleJson;
      resData['chainStatus'] = 'pending';
      if (_ruleGasQcc != null) resData['gas'] = _ruleGasQcc;

      await UserRuleFileStorage.saveRuleTask(resData);
      if (!mounted) return;

      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: "标签注册已上链",
          details: [
            Text("标签：$tagName", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("归属：${_walletNames[from] ?? ''} ${_shortAddr(from)}", style: const TextStyle(fontSize: 12)),
            if (_ruleGasQcc != null) Text("手续费：${_fmtQcc(_ruleGasQcc!)} QCC"),
          ],
          footer: "上链后将在详情页按标签复核链上归属。",
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
            builder: (context) => TagRuleSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "标签注册上链失败：${st!.message ?? '未知原因'}", isError: true);
      } else {
        Tools.showToast(context, "注册已受理，尚未确认上链，请稍后在规则状态中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("标签注册异常: $e");
      if (mounted) Tools.showToast(context, "注册失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
