import 'dart:convert';
import 'dart:math' as math;
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
import '../../../views/myasset/QccAssetService.dart';
import '../UserRuleFileStorage.dart';
import '../ruletag/QccUserRuleExtras.dart';
import 'AddressEndSuccessPage.dart';

/// 地址生命周期终止 (AddressEnd) —— 对齐 Java qcc.testNetwork.userrule.TxAddressEndTest。
/// 地址持有者单签终止自己，此后全公链拒绝该地址的任何私钥交易，
/// 地址上的全部资产等同于被自己永久、不可逆地冻结。
///
/// 关卡（全部通过才进入密码 → 签名 → 广播）：
///   1. 显式选择要终止的地址（不再隐式使用全局激活钱包）
///   2. 资产冻结检查：手续费之外的 QCC 余额、其他任何资产余额，逐项列出
///   3. 勾选"我已知晓"
///   4. 手动输入该地址末 6 位（防止终止错地址）
///   5. 最终确认弹窗再次列出将被冻结的资产
///   6. 提交前复查该地址是否已被终止
class AddressEndWidget extends StatefulWidget {
  const AddressEndWidget({super.key});

  @override
  State<AddressEndWidget> createState() => _AddressEndWidgetState();
}

/// 地址上持有的一项资产（原始最小单位）。显示统一走 QccAssetService.getHumanAmount，
/// 与资产管理页、质押页同一套精度换算。
class _HeldAsset {
  final String assetId;
  final int raw;
  const _HeldAsset(this.assetId, this.raw);

  String get display => QccAssetService().getHumanAmount(assetId, raw.toString());
}

class _AddressEndWidgetState extends State<AddressEndWidget> {
  /// 单笔 AddressEnd 默认手续费；链上 gas.quote 取到 ruleGasQcc 时以链上为准
  static const double _defaultFeeQcc = 100.0;
  static const int _qccPrecision = 9; // 1 QCC = 10^9

  final _confirmController = TextEditingController();
  bool _ackRisk = false;
  bool _isSubmitting = false;

  Map<String, String> _walletNames = {};
  List<String> _localAddrs = [];
  String nowaddress = "";

  double? _ruleGasQcc;

  // ---- 资产冻结检查 ----
  bool _scanning = false;
  int? _qccRaw; // null = 查询失败
  List<_HeldAsset> _otherHeld = [];
  int _scanFailed = 0; // 查询失败的资产数
  int _followedCount = 0; // 本次检查的关注资产数（不含 QCC）
  int _scanSeq = 0;

  double get _feeQcc => _ruleGasQcc ?? _defaultFeeQcc;
  int get _feeRaw => (_feeQcc * math.pow(10, _qccPrecision)).round();

  /// 必须输入要终止地址的末 6 位 —— 比固定短语更能防止"终止错地址"
  String get _confirmPhrase =>
      nowaddress.length >= 6 ? nowaddress.substring(nowaddress.length - 6) : nowaddress;

  bool get _qccInsufficient => _qccRaw != null && _qccRaw! < _feeRaw;
  int get _qccLeftRaw => _qccRaw == null ? 0 : math.max(0, _qccRaw! - _feeRaw);
  bool get _scanIncomplete => _qccRaw == null || _scanFailed > 0;
  bool get _hasExposure => _qccLeftRaw > 0 || _otherHeld.isNotEmpty;

  bool get _canSubmit =>
      nowaddress.isNotEmpty &&
          _ackRisk &&
          _confirmController.text.trim() == _confirmPhrase &&
          !_isSubmitting &&
          !_scanning &&
          !_qccInsufficient;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _loadRuleGas();
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
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
    if (nowaddress.isNotEmpty) _scanExposure();
  }

  Future<void> _loadRuleGas() async {
    try {
      final q = await QccQueryService.gasQuoteOverview();
      if (mounted) setState(() => _ruleGasQcc = q.ruleGasQcc);
    } catch (_) {
      // 取不到就用默认 100 QCC
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

  String _fmtQccRaw(int raw) => QccAssetService().getHumanAmount("QCC", raw.toString());

  // ---------------- 资产冻结检查 ----------------

  /// GET /v1/balance/{address}?asset=X（BalanceContext）
  /// 返回最小单位整数；null = 查询失败。
  ///
  /// 【假设，需要你确认】BalanceContext 的 data 是执行层原样字符串，格式我没见到。
  /// 这里按"最小单位整数"解析（纯数字串 / 数字 / {balance|amount|available} 对象）。
  /// 如果实际返回的是带小数的 QCC 金额，下面的手续费比较会差 10^9 倍，
  /// 请把 QccActiveWallet 的解析代码发我对齐。
  Future<int?> _queryBalanceRaw(String address, String assetId) async {
    try {
      final resp = await http
          .get(Uri.parse("${QccExplorerService.baseUrl}/v1/balance/$address?asset=${Uri.encodeComponent(assetId)}"))
          .timeout(const Duration(seconds: 10));
      final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map && body['ok'] == false) return null;
      return _parseBalance(body is Map ? body['data'] : body);
    } catch (e) {
      LogObj.log("余额查询失败 $assetId: $e");
      return null;
    }
  }

  static int? _parseBalance(dynamic d) {
    if (d is num) return d.toInt();
    if (d is String) {
      final t = d.trim();
      if (t.isEmpty || t == 'error') return null; // BalanceContext 失败时返回 "error"
      final n = int.tryParse(t);
      if (n != null) return n;
      try {
        d = jsonDecode(t);
      } catch (_) {
        return null;
      }
    }
    if (d is Map) {
      for (final k in const ['balance', 'amount', 'available', 'value']) {
        final v = d[k];
        if (v is num) return v.toInt();
        if (v is String) {
          final p = int.tryParse(v);
          if (p != null) return p;
        }
      }
    }
    return null;
  }

  /// 检查范围：QCC（必查）+ 用户在「资产管理」里关注的资产。
  /// 不扫全网资产列表：BalanceContext 一次只能查一种资产，全网资产多了会
  /// 打出大量请求；而用户真正持有、会在意的资产，就是他关注的那些。
  /// 未关注的资产不在检查范围内，界面上会明确说明这一点。
  Future<void> _scanExposure() async {
    final String addr = nowaddress;
    if (addr.isEmpty) return;
    final int seq = ++_scanSeq;
    setState(() {
      _scanning = true;
      _qccRaw = null;
      _otherHeld = [];
      _scanFailed = 0;
      _followedCount = 0;
    });

    final int? qcc = await _queryBalanceRaw(addr, "QCC");

    final List<_HeldAsset> held = [];
    int failed = 0;
    List<String> followed = [];
    try {
      final all = await QccAssetService().fetchAllAssets();
      followed = all
          .where((a) => a.isFollowing && a.assetId.toUpperCase() != "QCC")
          .map((a) => a.assetId)
          .toSet()
          .toList();

      // 每批 5 个并发
      for (int i = 0; i < followed.length; i += 5) {
        if (seq != _scanSeq || !mounted) return; // 地址已切换，放弃本轮
        final batch = followed.sublist(i, math.min(i + 5, followed.length));
        final results = await Future.wait(batch.map((id) => _queryBalanceRaw(addr, id)));
        for (int j = 0; j < batch.length; j++) {
          final raw = results[j];
          if (raw == null) {
            failed++;
          } else if (raw > 0) {
            held.add(_HeldAsset(batch[j], raw));
          }
        }
      }
    } catch (e) {
      LogObj.log("关注资产获取失败: $e");
      failed++;
    }

    if (seq != _scanSeq || !mounted) return;
    setState(() {
      _qccRaw = qcc;
      _otherHeld = held;
      _scanFailed = failed;
      _followedCount = followed.length;
      _scanning = false;
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text("本机未导入任何钱包。", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
      );
    }

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
          _buildAddressPicker(),
          const SizedBox(height: 12),
          _buildAccountInfoCard(nowaddress),
          const SizedBox(height: 16),

          _buildExposureCard(),
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
                  "一旦上链，此地址将在全 QCC 公链范围内被判定为「死亡地址」，公链将永久"
                      "拒绝此地址的任何交易。地址上的全部资产等同于被您自己永久、不可逆地冻结，"
                      "任何人都无法帮您恢复。",
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
        if (val == null || val == nowaddress) return;
        setState(() {
          nowaddress = val;
          // 换了地址，之前的确认全部作废
          _ackRisk = false;
          _confirmController.clear();
        });
        _scanExposure();
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.red.withValues(alpha: 0.03),
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
                if (nick != null && nick.isNotEmpty)
                  Text(nick,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                Text(address,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Trans("QCC 余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 资产冻结检查卡片：手续费、剩余 QCC、其他资产，逐项列出。
  Widget _buildExposureCard() {
    final List<Widget> rows = [];

    rows.add(_kv("本次手续费", "${_fmtQcc(_feeQcc)} QCC${_ruleGasQcc == null ? '（默认值）' : ''}"));

    if (_scanning) {
      rows.add(const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text("正在检查该地址的全部资产…", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ));
    } else {
      if (_qccRaw == null) {
        rows.add(_line(Icons.help_outline, Colors.grey, "QCC 余额查询失败，无法确认是否足够支付手续费"));
      } else if (_qccInsufficient) {
        rows.add(_line(Icons.block, Colors.red,
            "QCC 余额 ${_fmtQccRaw(_qccRaw!)}，不足支付手续费，交易必定失败"));
      } else if (_qccLeftRaw > 0) {
        rows.add(_line(Icons.lock, Colors.red,
            "扣除手续费后剩余 ${_fmtQccRaw(_qccLeftRaw)} QCC 将被永久冻结"));
      } else {
        rows.add(_line(Icons.check_circle, Colors.green, "QCC 余额恰好支付手续费，无剩余"));
      }

      for (final a in _otherHeld) {
        rows.add(_line(Icons.lock, Colors.red, "${a.assetId}：${a.display} 将被永久冻结"));
      }

      if (_scanFailed > 0) {
        rows.add(_line(Icons.help_outline, Colors.orange, "有 $_scanFailed 项资产余额查询失败，请刷新或自行确认"));
      } else if (_otherHeld.isEmpty && _qccRaw != null && _followedCount > 0) {
        rows.add(_line(Icons.check_circle, Colors.green, "已关注的 $_followedCount 种资产均无余额"));
      }
      rows.add(_line(Icons.info_outline, Colors.blueGrey,
          _followedCount == 0
              ? "仅检查了 QCC。其他资产只检查您在「资产管理」中关注的资产，当前未关注任何资产。"
              : "已检查 QCC 和您关注的 $_followedCount 种资产；未关注的资产不在检查范围内。"));
    }

    final Color border = (_hasExposure || _qccInsufficient) ? Colors.red : Colors.grey.shade300;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (_hasExposure || _qccInsufficient) ? Colors.red.withValues(alpha: 0.04) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("资产冻结检查", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.refresh, color: Colors.blueGrey),
                onPressed: _scanning || _isSubmitting ? null : _scanExposure,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...rows,
          if (_hasExposure) ...[
            const SizedBox(height: 8),
            const Text("建议先将上述资产转出到其他地址，再执行终止。",
                style: TextStyle(fontSize: 11.5, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text("$k：", style: const TextStyle(fontSize: 12, color: Colors.black54)),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
    ]),
  );

  Widget _line(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, height: 1.35))),
      ],
    ),
  );

  Widget _buildConsequenceList() {
    final List<String> items = [
      "该地址此后无法再发起转账、规则交易或任何私钥签名操作",
      "该地址持有的全部资产将无法被转出，等同于被自己永久冻结",
      "如该地址名下有标签、开发者或商户规则，将无法再转让或修改",
      "如该地址是多签账户的签名成员，其签名权将随之失效",
      "此后他人仍向此地址转入的资产，同样可能被永久锁定",
      "此操作一旦公链确认，任何人（包括开发者/客服）都无法帮您恢复",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
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
        Text("请输入要终止地址的最后 6 位「$_confirmPhrase」以解锁提交按钮",
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _confirmController,
          onChanged: (_) => setState(() {}),
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: "地址末 6 位",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.red.withValues(alpha: 0.02),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    String label = "确认发起地址死亡交易";
    if (_scanning) label = "正在检查资产…";
    if (_qccInsufficient) label = "QCC 不足以支付手续费";
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
            : Trans(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// 最终确认：再次列出将被冻结的资产，要求用户在知情的前提下决定是否继续。
  Future<void> _handleConfirmAndSubmit() async {
    final String addr = nowaddress;

    // 复查：该地址是否已被终止（避免对死地址重复付 100 QCC）
    final bool? ended = await AddressEndQuery.isEnded(addr);
    if (!mounted) return;
    if (ended == true) {
      Tools.showToast(context, "该地址已处于终止状态，无需重复操作");
      return;
    }

    final List<String> frozen = [
      if (_qccLeftRaw > 0) "${_fmtQccRaw(_qccLeftRaw)} QCC",
      ..._otherHeld.map((a) => "${a.display} ${a.assetId}"),
    ];

    final bool? finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dangerous_rounded, color: Colors.red),
            SizedBox(width: 8),
            Trans("最后确认"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${_walletNames[addr] ?? ''}\n$addr",
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text("手续费：${_fmtQcc(_feeQcc)} QCC", style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              if (frozen.isNotEmpty) ...[
                const Text("以下资产将被永久冻结，无法取回：",
                    style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...frozen.map((f) => Text("• $f", style: const TextStyle(fontSize: 13, color: Colors.red))),
                const SizedBox(height: 10),
              ],
              Text(
                  _followedCount == 0
                      ? "仅检查了 QCC 余额，未关注的资产不在检查范围内。"
                      : "已检查 QCC 和您关注的 $_followedCount 种资产，未关注的资产不在检查范围内。",
                  style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              const SizedBox(height: 10),
              if (_scanIncomplete)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text("部分资产余额查询失败，可能还有其他资产会被冻结。",
                      style: TextStyle(fontSize: 12.5, color: Colors.orange)),
                ),
              const Text("此操作不可撤销。上链后此地址将永久无法再签发任何交易。\n\n真的要继续吗？",
                  style: TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Trans("取消")),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(frozen.isNotEmpty ? "仍然终止" : "确认终止",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (finalConfirm != true || !mounted) return;
    await _handleSubmit(addr);
  }

  Future<void> _handleSubmit(String from) async {
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
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, from, password);
      if (wallet == null || wallet.address != from || wallet.privateKey == null) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 对齐 Java doAddressEnd()：endJson {address}，服务端以 from 为准
      statusNotifier.value = TxStep.building;
      final endRule = QccAddressEnd(address: from);

      final ruleData = RuleData();
      ruleData.assetId = "QCCRule"; // Java 显式设置，原 Flutter 没设；须在 finalizeId() 前
      ruleData.from = from;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "AddressEnd";
      ruleData.ruleJson = jsonEncode(endRule.toJson());
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
      LogObj.log("地址死亡结束交易返回参数${response.body}");
      if (response.statusCode != 200) throw "网络通讯失败: ${response.statusCode}";

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      // 返回 {"status":"accepted","code":"ACCEPTED","txHash":..}；原判断 status=='ACCEPTED' 永不成立
      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "交易被拒绝";
      }

      resData['ruleName'] = "AddressEnd";
      resData['id'] = txHash;
      resData['from'] = from;
      resData['ruleJson'] = ruleData.ruleJson;
      resData['chainStatus'] = 'pending';
      resData['gas'] = _feeQcc;

      await UserRuleFileStorage.saveRuleTask(resData);
      // 不调用 markSubmitted：该地址上链后不会再有下一笔交易，"跳过公钥"无意义
      if (!mounted) return;

      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: "地址终止已上链",
          details: [
            Text("终止地址：${_walletNames[from] ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(from, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            Text("手续费：${_fmtQcc(_feeQcc)} QCC"),
          ],
          footer: "上链后此地址将被全网永久终止，详情页会复核终止状态。",
          onFinal: (s) async {
            await UserRuleFileStorage.saveRuleTask({
              ...resData,
              'chainStatus': s.state.name,
              if (s.blockHeight != null) 'blockHeight': s.blockHeight,
              if (s.message != null) 'chainMsg': s.message,
            });
          },
        ),
      );

      if (!mounted) return;
      if (st?.state == TxChainState.confirmed) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AddressEndSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "终止交易上链失败：${st!.message ?? '未知原因'}，地址未被终止", isError: true);
      } else {
        Tools.showToast(context, "终止交易已受理，尚未确认上链，请稍后在规则状态中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("地址死亡结束异常: $e");
      if (mounted) Tools.showToast(context, "提交失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}