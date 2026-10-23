import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccQueryService.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
import '../../../home/QccExplorerService.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/AddressTool.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/LogObj.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../UserRuleFileStorage.dart';
import 'QccUserRuleExtras.dart';
import 'TagQueryService.dart';
import 'TagTransferSuccessPage.dart';

/// 标签资产转让 (TagTransfer) —— 对齐 Java qcc.testNetwork.userrule.TxTagTransferTest。
/// push 式转移：只认签名者 from == 当前 tag owner，newOwner 不需要签名。
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

  // 持有账户可选（原来固定 QccObj.activeWallet，和 TagRuleWidget 不一致）
  Map<String, String> _walletNames = {};
  List<String> _localAddrs = [];
  String nowaddress = "";

  _OwnershipCheck _ownership = _OwnershipCheck.idle;
  String? _queryErrorMessage;
  bool _isSubmitting = false;

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

  String _shortAddr(String addr) =>
      addr.length > 16 ? "${addr.substring(0, 8)}...${addr.substring(addr.length - 6)}" : addr;

  @override
  void dispose() {
    _tagController.dispose();
    _newOwnerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text("本机未导入任何钱包，无法转让标签。",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
      );
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

            _buildLabel("当前持有账户 (From)"),
            _buildAddressPicker(),
            const SizedBox(height: 12),
            _buildAccountInfoCard(nowaddress),
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
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                if (val.trim() == nowaddress) {
                  return Tools.getTra("不能转让给自己");
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildWarningNote(),
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
        Trans("标签资产转让 (TagTransfer)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "将您名下已注册的标签名称资产整体转让给另一个地址。转让为单向操作，"
              "受让方不需要签名确认——上链后，标签的全部归属权益立即转移，"
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
              if (val != null) {
                setState(() {
                  nowaddress = val;
                  // 换了持有账户，之前的归属验证结果不再有效
                  _ownership = _OwnershipCheck.idle;
                  _queryErrorMessage = null;
                });
              }
            },
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
            child: const Icon(Icons.swap_horiz_rounded, color: Colors.purple, size: 20),
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

  Widget _buildOwnershipHint() {
    if (_ownership == _OwnershipCheck.verified) {
      return _hintCard(Icons.check_circle, Colors.green, "已确认您是该标签的当前持有者，可以发起转让");
    }
    if (_ownership == _OwnershipCheck.notOwner) {
      return _hintCard(Icons.error_outline, Colors.redAccent, "当前账户不是该标签的持有者，提交转让必定被拒");
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
                  ? "转让手续费 ${_fmtQcc(_ruleGasQcc!)} QCC，由当前持有账户扣除"
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

  Future<TagInfo?> _checkOwnership() async {
    final String tagName = _tagController.text.trim();
    if (tagName.isEmpty) return null;
    setState(() => _ownership = _OwnershipCheck.checking);
    final info = await TagQueryService.query(tagName);
    if (!mounted) return info;
    setState(() {
      if (!info.ok) {
        _ownership = _OwnershipCheck.error;
        _queryErrorMessage = info.error;
      } else if (!info.found) {
        _ownership = _OwnershipCheck.notFound;
      } else {
        // 原来比对的是 QccObj.activeWallet，现在比对选中的持有账户
        _ownership = info.owner == nowaddress ? _OwnershipCheck.verified : _OwnershipCheck.notOwner;
      }
    });
    return info;
  }

  Future<void> _handleTransfer() async {
    if (!_formKey.currentState!.validate()) return;
    if (nowaddress.isEmpty) {
      Tools.showToast(context, "请选择持有账户");
      return;
    }
    final String from = nowaddress;
    final String tagName = _tagController.text.trim();
    final String newOwner = _newOwnerController.text.trim();

    // 提交前强制验证归属：查无此标签 / 不是持有者 → 必定被拒，不签名不扣费。
    // 查询失败不拦截，交给公链裁定。
    final pre = await _checkOwnership();
    if (!mounted) return;
    if (pre != null && pre.ok) {
      if (!pre.found) {
        Tools.showToast(context, "查无此标签，无法转让");
        return;
      }
      if (pre.owner != from) {
        Tools.showToast(context, "当前账户不是该标签的持有者");
        return;
      }
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    setState(() => _isSubmitting = true);
    try {
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, from, password);
      if (wallet == null || wallet.address != from || wallet.privateKey == null) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 对齐 Java buildTagTransferData()：transferJson {tagName, newOwner}
      statusNotifier.value = TxStep.building;
      final tagTransfer = QccTagTransfer(tagName: tagName, newOwner: newOwner);

      final ruleData = RuleData();
      ruleData.assetId = "QCCRule"; // Java 显式设置，原 Flutter 没设；须在 finalizeId() 前
      ruleData.from = from;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "TagTransfer";
      ruleData.ruleJson = jsonEncode(tagTransfer.toJson());
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: from,
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

      closeLoading();
      LogObj.log("标签转让返回参数${response.body}");
      if (response.statusCode != 200) throw "网络通讯失败: ${response.statusCode}";

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "转让被拒绝（请确认您仍是该标签的当前持有者）";
      }

      resData['ruleName'] = "TagTransfer";
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
          confirmedTitle: "标签转让已上链",
          details: [
            Text("标签：$tagName", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("转出：${_walletNames[from] ?? ''} ${_shortAddr(from)}", style: const TextStyle(fontSize: 12)),
            Text("受让：${_walletNames[newOwner] ?? ''} ${_shortAddr(newOwner)}", style: const TextStyle(fontSize: 12)),
            if (_ruleGasQcc != null) Text("手续费：${_fmtQcc(_ruleGasQcc!)} QCC"),
          ],
          footer: "上链后将在详情页按标签复核新的链上归属。",
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
            builder: (context) => TagTransferSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "标签转让上链失败：${st!.message ?? '未知原因'}", isError: true);
      } else {
        Tools.showToast(context, "转让已受理，尚未确认上链，请稍后在规则状态中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("标签转让异常: $e");
      if (mounted) Tools.showToast(context, "转让失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
