import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/QccTransactionData.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'package:http/http.dart' as http;

/// 继承中心（明细中心）—— 对应你要求的"继承的明细中心"。风格、结构直接照抄
/// LoanStatusWidget.dart（按本机地址/按 pid 两种查询方式 + 列表 + 详情弹窗里
/// 做操作），因为继承和借贷底层都是同一套 MatchProcess 机制
/// （TxMatchInheritTest.java 自己说"MatchProcessFactory 对 inherit 注册了
/// usesTo=true，把 tx.to 路由进基类的 borrower 字段"——inherit 和 loan 复用
/// 的是同一个基类结构：owner/borrower/state/currentAmount）。
///
/// ⚠️⚠️⚠️ 本文件风险最高的一点：查询接口地址是【纯猜的】，跟 Loan 那边不一样——
/// TxLoanTest.java 好歹自己写了 queryLoanByHash()/queryLoanByAddress() 两个
/// 方法给我核对；但 TxMatchInheritTest.java 里【完全没有任何查询接口调用】，
/// 全程只靠"查余额变化"来断言结果，没有一行 HTTP GET 代码可以参考。
/// 下面这个 "/v1/inherit/?address=" / "/v1/inherit/?hash=" 完全是按
/// "/v1/loan/" 的命名习惯（模块名对应域名）推的，有相当大概率是错的——
/// 也有可能借贷/继承/分红/空投这些 MatchType 压根不是分开查，而是共用同一个
/// 通用查询接口（比如 /v1/match/?type=inherit&address=xxx 这种形式），
/// 你那边如果知道真实接口，麻烦告诉我改一下，这个查询功能在那之前基本等于
/// 占位符，查不出东西是预期的，不代表创建/领取/撤销这几个提交操作有问题。
///
/// 【返回字段同样是猜的】沿用 loan 查询响应的字段名假设：pid/owner(委托人)/
/// borrower(继承人)/state/currentAmount(本金，继承没有部分领取，猜整笔都在
/// currentAmount 里)。maturityTime 会尝试从响应里读，读不到就显示"-"，
/// 到期判断退化成"允许你手动点击领取/撤销，具体会不会被链上拒绝以实际结果为准"。
class InheritStatusWidget extends StatefulWidget {
  const InheritStatusWidget({super.key});

  @override
  State<InheritStatusWidget> createState() => _InheritStatusWidgetState();
}

class _InheritStatusWidgetState extends State<InheritStatusWidget> {
  static final String _base = QccExplorerService.baseUrl;

  final _hashController = TextEditingController();
  List<String> _localAddrs = [];
  Map<String, String> _walletNames = {};
  String _queryAddress = "";

  bool _byHash = false;
  bool _isLoading = false;
  String? _errorMsg;
  List<Map<String, dynamic>> _trusts = [];

  @override
  void initState() {
    super.initState();
    _initialLoad();
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
        _queryAddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
    if (_queryAddress.isNotEmpty) _runQuery();
  }

  Future<void> _runQuery() async {
    final String param = _byHash ? _hashController.text.trim() : _queryAddress;
    if (param.isEmpty) {
      Tools.showToast(context, Tools.getTra(_byHash ? "请输入 pid" : "请选择本机地址"));
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _trusts = [];
    });
    try {
      // ⚠️ 见文件头注释：这个路径是猜的，没有 Java 参考代码可以核对。
      final String url = _byHash ? "$_base/v1/inherit/?hash=$param" : "$_base/v1/inherit/?address=$param";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        setState(() => _errorMsg = "网络通讯异常: ${response.statusCode}（也可能是接口路径猜错了，见本文件头部注释）");
        return;
      }
      final Map<String, dynamic> result = jsonDecode(response.body);
      if (result['ok'] != true) {
        setState(() => _errorMsg = "查询失败（也可能是接口路径/参数不对，见本文件头部注释）");
        return;
      }
      final String? dataStr = result['data']?.toString();
      if (dataStr == null || dataStr.isEmpty) {
        setState(() => _trusts = []);
        return;
      }
      final String trimmed = dataStr.trim();
      final List<Map<String, dynamic>> parsed = [];
      if (trimmed.startsWith('[')) {
        final List<dynamic> arr = jsonDecode(dataStr);
        for (final item in arr) {
          parsed.add(Map<String, dynamic>.from(item as Map));
        }
      } else {
        parsed.add(Map<String, dynamic>.from(jsonDecode(dataStr) as Map));
      }
      if (!mounted) return;
      setState(() => _trusts = parsed);
    } catch (e) {
      LogObj.log("继承状态查询出错: $e");
      setState(() => _errorMsg = "查询出错: $e（也可能是接口路径猜错了/返回格式跟猜测的不一样，见本文件头部注释）");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int? _maturityOf(Map<String, dynamic> trust) {
    final v = trust['maturityTime'];
    if (v == null) return null;
    return v is int ? v : int.tryParse(v.toString());
  }

  String _formatAmount(dynamic raw) {
    if (raw == null) return '-';
    final n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null) return raw.toString();
    String s = (n / 1000000000).toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s.isEmpty ? '0' : s;
  }

  String _formatDateTime(int? millis) {
    if (millis == null) return '-（查询接口没返回，或字段名猜错了）';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }

  Future<void> _handleClaim(Map<String, dynamic> trust) async {
    final String pid = (trust['pid'] ?? '').toString();
    final String heir = (trust['borrower'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("领取信托"),
        content: Text("到期前领取会被拒绝，受理成功也不代表一定执行成功，请提交后回来重新查询确认。\npid: $pid"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("确认领取")),
        ],
      ),
    );
    if (ok != true) return;

    final result = await QccTxFlow.run(
      context: context,
      address: heir,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = "QCC";
        tx.chain = "6666"; // 照 LoanIssueWidget/QccTransferPage.dart 硬编码
        tx.from = wallet.address;
        // 【按 TxMatchInheritTest.java 的实际代码，不是它的注释】doClaim()
        // 注释写"to 留空"，但代码实际设的是字面量 "pool address"——两者矛盾，
        // 好在 to 不参与 win 的业务判断(靠 matcHash)，具体填什么字符串大概率
        // 不影响结果，这里索性按注释描述的原意填空字符串，比照抄一个看起来
        // 像占位符的字面量更干净。
        tx.to = "";
        tx.amount = 0; // 全额一次性交割，金额由服务端按剩余本金结算
        tx.txType = "win";
        tx.matcHash = pid;
        tx.memo = "继承领取";
        tx.finalizeId();
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    if (result.cancelled) return;
    if (result.success) {
      Tools.showToast(context, "✅ 领取已提交（受理≠执行成功，稍后重新查询确认余额变化）");
      Navigator.of(context).pop();
      _runQuery();
    } else {
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  Future<void> _handleCancel(Map<String, dynamic> trust) async {
    final String pid = (trust['pid'] ?? '').toString();
    final String owner = (trust['owner'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("撤销信托"),
        content: Text("仅到期前有效，本金全额退回委托人。到期后撤销会被拒绝（信托不可逆）。\npid: $pid"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("确认撤销")),
        ],
      ),
    );
    if (ok != true) return;

    final result = await QccTxFlow.run(
      context: context,
      address: owner,
      buildPayload: (wallet) async {
        final tx = QccTransactionData();
        tx.assetId = "QCC";
        tx.chain = "6666";
        tx.from = wallet.address;
        // 同上：Java 注释说"to 留空"，代码实际写的是字面量 "pool-address"，
        // 按注释原意填空字符串。
        tx.to = "";
        tx.amount = 0;
        tx.txType = "cancel";
        tx.matcHash = pid;
        tx.memo = "继承撤销";
        tx.finalizeId();
        return QccSignPayload(toSign: tx.toSign(), payloadJson: jsonEncode(tx.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/txm",
    );

    if (!mounted) return;
    if (result.cancelled) return;
    if (result.success) {
      Tools.showToast(context, "✅ 撤销已提交");
      Navigator.of(context).pop();
      _runQuery();
    } else {
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  void _showDetail(Map<String, dynamic> trust) {
    final String pid = (trust['pid'] ?? '').toString();
    final String owner = (trust['owner'] ?? '').toString();
    final String heir = (trust['borrower'] ?? '').toString();
    final String state = (trust['state'] ?? '').toString();
    final int? maturity = _maturityOf(trust);
    final bool iAmOwner = _localAddrs.contains(owner);
    final bool iAmHeir = _localAddrs.contains(heir);
    final bool matured = maturity != null && DateTime.now().millisecondsSinceEpoch >= maturity;
    final bool active = state.toUpperCase() == 'ACTIVE' || state.isEmpty;
    // maturity 未知时不强行拦掉操作按钮（查询字段本来就是猜的），只是弹窗里
    // 会提示"到期时间未知，是否可操作以链上实际结果为准"。
    final bool canCancel = iAmOwner && active && (maturity == null || !matured);
    final bool canClaim = iAmHeir && active && (maturity == null || matured);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Trans("信托明细"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row("pid", pid, mono: true),
                _row("状态", state.isEmpty ? '-' : state),
                _row("委托人(owner)", _nameFor(owner)),
                _row("继承人(borrower)", _nameFor(heir)),
                _row("本金 currentAmount", _formatAmount(trust['currentAmount'])),
                _row("到期时间", _formatDateTime(maturity)),
                if (maturity == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "查询接口没返回到期时间字段（或字段名猜错了），下面按钮不代表链上一定会接受，以实际提交结果为准。",
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (canCancel)
              TextButton(
                onPressed: () => _handleCancel(trust),
                child: const Text("撤销信托", style: TextStyle(color: Colors.red)),
              ),
            if (canClaim)
              TextButton(
                onPressed: () => _handleClaim(trust),
                child: const Text("领取信托", style: TextStyle(color: Colors.green)),
              ),
            TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text("关闭")),
          ],
        );
      },
    );
  }

  String _nameFor(String addr) {
    final nick = _walletNames[addr];
    return nick != null ? "$nick ($addr)" : addr;
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: Colors.black87, fontFamily: mono ? 'monospace' : null),
          children: [
            TextSpan(text: "$label：", style: const TextStyle(color: Colors.black54, fontFamily: null)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "查询接口路径是猜的（没有 Java 参考代码），查不到数据不代表信托没创建成功，具体以链上结果为准，详见文件头注释。",
                        style: TextStyle(fontSize: 11, color: Colors.deepOrange),
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Trans("按本机地址"), icon: const Icon(Icons.account_balance_wallet_outlined, size: 16)),
                  ButtonSegment<bool>(value: true, label: Trans("按 pid"), icon: const Icon(Icons.tag, size: 16)),
                ],
                selected: <bool>{_byHash},
                onSelectionChanged: (s) => setState(() => _byHash = s.first),
                style: SegmentedButton.styleFrom(selectedBackgroundColor: const Color(0xFFB08900), selectedForegroundColor: Colors.white, side: BorderSide.none),
              ),
              const SizedBox(height: 12),
              if (_byHash)
                TextField(
                  controller: _hashController,
                  decoration: InputDecoration(
                    labelText: Tools.getTra("信托 pid"),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _runQuery),
                  ),
                  onSubmitted: (_) => _runQuery(),
                )
              else if (_localAddrs.isEmpty)
                Text("本机未导入任何钱包。", style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              else
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _queryAddress.isEmpty ? null : _queryAddress,
                        isExpanded: true,
                        items: _localAddrs
                            .map((a) => DropdownMenuItem(value: a, child: Text(_nameFor(a), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _queryAddress = val);
                            _runQuery();
                          }
                        },
                        decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _runQuery),
                  ],
                ),
            ],
          ),
        ),
        if (_errorMsg != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_trusts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text("当前没有查到信托记录（也可能是查询接口路径猜错了，见上方提示）。", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _trusts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildTrustTile(_trusts[i]),
    );
  }

  Widget _buildTrustTile(Map<String, dynamic> trust) {
    final String pid = (trust['pid'] ?? '').toString();
    final String owner = (trust['owner'] ?? '').toString();
    final String heir = (trust['borrower'] ?? '').toString();
    final String state = (trust['state'] ?? '').toString();
    final int? maturity = _maturityOf(trust);
    final bool iAmOwner = _localAddrs.contains(owner);
    final bool iAmHeir = _localAddrs.contains(heir);

    return InkWell(
      onTap: () => _showDetail(trust),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statePill(state),
                const SizedBox(width: 8),
                if (iAmOwner) _rolePill("我是委托人", Colors.blue),
                if (iAmHeir) _rolePill("我是继承人", const Color(0xFFB08900)),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Text("本金: ${_formatAmount(trust['currentAmount'])}  ·  到期: ${_formatDateTime(maturity)}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 6),
            Text("继承人: ${_nameFor(heir)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text("委托人: ${_nameFor(owner)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text("pid: $pid", style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _statePill(String state) {
    final bool active = state.isEmpty || state.toUpperCase() == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: (active ? Colors.green : Colors.grey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(state.isEmpty ? "-" : state, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.green.shade700 : Colors.grey.shade700)),
    );
  }

  Widget _rolePill(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}
