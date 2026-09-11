import 'dart:async';
import 'dart:convert';
import 'dart:developer' as LogObj;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../procotol/QccDataProtocol.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/QccTransactionData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../home/QccExplorerService.dart';
import '../../myasset/QccAssetService.dart';
import '../../setting/AppTranslator.dart';
import '../../setting/QccPassDialog.dart';
import '../../toolviews/QccLoading.dart';
import 'QccClaimSuccessPage.dart';

class QccClaimDividendPage extends StatefulWidget {
  const QccClaimDividendPage({super.key});

  @override
  State<QccClaimDividendPage> createState() => _QccClaimDividendPageState();
}

class _QccClaimDividendPageState extends State<QccClaimDividendPage> {
  final TextEditingController _hashController = TextEditingController();
  String _fromAddress = "";

  // 核心数据
  Map<String, dynamic>? _stateData;
  String _baseAssetId = "";
  String _quoteAssetId = "";
  double _dividendRate = 0.0;

  double _myHolding = 0.0;
  bool _isLoading = false;
  String _currentHash = "";

  @override
  void initState() {
    super.initState();
    _initAddress();
  }

  void _initAddress() {
    final wallets = QccObj.readWallets();
    if (wallets.isNotEmpty) {
      _fromAddress = QccObj.activeWallet?.address ?? wallets[0].address;
    }
  }

  Future<void> _fetchDividendInfo(String hash) async {
    if (hash.trim().isEmpty) {
      Tools.showToast(context, "请输入分红凭证 Hash");
      return;
    }

    setState(() {
      _isLoading = true;
      _stateData = null;
    });

    try {
      final res = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/hash/${hash.trim()}")).timeout(const Duration(seconds: 5));
      final root = jsonDecode(res.body);
      if (root['ok'] != true || root['data'] == null) throw "无效的 Hash 凭证";

      Map<String, dynamic> dataMap = root['data'] is String ? jsonDecode(root['data']) : root['data'];
      Map<String, dynamic> tx = dataMap['tx'] is String ? jsonDecode(dataMap['tx']) : dataMap['tx'];
      Map<String, dynamic> matchLogic = tx['matchLogic'] is String ? jsonDecode(tx['matchLogic']) : tx['matchLogic'];

      final stateRes = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/openhash/${hash.trim()}")).timeout(const Duration(seconds: 5));
      final stateRoot = jsonDecode(stateRes.body);
      if (stateRoot['ok'] != true || stateRoot['data'] == null) throw "该分红不在活跃状态";

      Map<String, dynamic> decodedStateData = stateRoot['data'] is String ? jsonDecode(stateRoot['data']) : stateRoot['data'];

      setState(() {
        _baseAssetId = matchLogic['pairAssetId'] ?? "TOKEN";
        _quoteAssetId = tx['assetId'] ?? "USDS";
        _dividendRate = (matchLogic['rate'] as num?)?.toDouble() ?? 0.0;
        _stateData = decodedStateData;
        _currentHash = hash.trim();
        _isLoading = false;
      });
    } catch (e) {
      Tools.showToast(context, "查询失败: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(title: const Trans("认领资产分红"), centerTitle: true, elevation: 0),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            _buildHashInputArea(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _stateData == null ? _buildGuideState() : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHashInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          _buildAddressSelector(),
          const SizedBox(height: 12),
          TextField(
            controller: _hashController,
            decoration: InputDecoration(
              hintText: "请粘贴分红凭证 Hash...",
              prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.blue),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.blue),
                onPressed: () => _fetchDividendInfo(_hashController.text),
              ),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onSubmitted: _fetchDividendInfo,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildPoolInfoCard(),
          const SizedBox(height: 12),
          _buildEligibilityPanel(),
          const SizedBox(height: 12),

          // ✅ 新增：资产冻结特别说明
          _buildFreezeNotice(),

          const SizedBox(height: 24),
          _buildClaimButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ✅ 核心：资产冻结期说明组件
  Widget _buildFreezeNotice() {
    final String unlockTime = DateFormat('yyyy-MM-dd HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(_stateData!['endTime'])
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_clock_rounded, size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Trans("资产冻结与解冻说明",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "认领分红后，您的 $_baseAssetId 持仓将被立即冻结，直至认领截止期（$unlockTime）结束后自动解冻。在此期间，该部分资产将无法进行转账、交易或质押操作。",
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF388E3C)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Trans("红利池剩余可领总额", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            "${QccAssetService().getHumanAmountNum(_quoteAssetId, _stateData!['currentAmount'].toString())} $_quoteAssetId",
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          _row("权益资产 (Base)", _baseAssetId),
          _row("派息比例 (Rate)", "1 : $_dividendRate $_quoteAssetId"),
          _row("认领截止 (解冻期)", DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_stateData!['endTime']))),
        ],
      ),
    );
  }

  Widget _buildEligibilityPanel() {
    double estimatedPayout = _myHolding * _dividendRate;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Trans("认领资格与收益预估:", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_baseAssetId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              QccActiveWallet.onlyCoins(
                _fromAddress,
                _baseAssetId,
                color: Colors.blue,
                onBalanceLoaded: (value) => setState(() => _myHolding = value.amount),
                onAssetChanged: (v) => setState(() => _baseAssetId = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.1))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Trans("预计可领红利:", style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
                Text("+ ${estimatedPayout.toStringAsFixed(2)} $_quoteAssetId", style: const TextStyle(color: Colors.blue, fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildHoldingStatus(),
        ],
      ),
    );
  }

  Widget _buildClaimButton() {
    bool isExpired = _stateData!['isExpired'] == true;
    bool canClaim = _myHolding > 0 && !isExpired;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: canClaim ? const Color(0xFF1E293B) : Colors.grey.shade400,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: canClaim ? _handleWinClaim : null,
        child: const Trans("立即认领红利", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _handleWinClaim() async {

    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, _fromAddress, password);
      statusNotifier.value = TxStep.building;
      final winTx = QccTransactionData();
      winTx.assetId=_quoteAssetId;
      winTx.from=_fromAddress;
      winTx.to = "win address";
      winTx.txType = "win";
      winTx.matcHash = _currentHash;
      winTx.amount = 0;
      winTx.finalizeId();

      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await compute(_signTransactionTask, {
        'payloadJson': jsonEncode(winTx.toJson()),
        'privHex': wallet!.privateKey!,
        'pubHex': wallet.pubkey!
      });

      statusNotifier.value = TxStep.submitting;
      final response = await http.post(Uri.parse("https://tx.qccio.com/v1/txm"), body: jsonEncode(packet.toJson()));
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (response.statusCode == 200) {
        // ✅ 提示语中增加冻结期提醒
        //Tools.showToast(context, "认领成功！$_baseAssetId 已锁定至认领期结束。");
        LogObj.log("领取分红成功返回${response.body}");
        // 构造展示用的 Map
        final res = jsonDecode(response.body);
        if (res['status'] == 'ACCEPTED') {
          final successData = {
            'txHash': res['txHash'],
            'assetId': _quoteAssetId,
            'baseAssetId': _baseAssetId,
            'estimatedAmount': (_myHolding * _dividendRate).toStringAsFixed(2),
            'unlockTime': DateFormat('yyyy-MM-dd HH:mm').format(
                DateTime.fromMillisecondsSinceEpoch(_stateData!['endTime'])
            ),
          };

          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) =>
                  QccClaimSuccessPage(result: successData))
          );
        }
        //Navigator.pop(context);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      Tools.showToast(context, "认领失败: $e");
    }
  }

  // --- 支撑 UI ---
  Widget _buildGuideState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_edu_rounded, size: 80, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 16), const Trans("请输入资产方发布的分红凭证 Hash", style: TextStyle(color: Colors.grey))]));

  Widget _buildHoldingStatus() {
    bool hasRight = _myHolding > 0;
    return Row(children: [Icon(hasRight ? Icons.check_circle_rounded : Icons.info_outline, color: hasRight ? Colors.blue : Colors.red, size: 14), const SizedBox(width: 6), Expanded(child: Text(hasRight ? "持仓核对通过" : "不符合条件: 账户未持有该权益资产", style: TextStyle(fontSize: 11, color: hasRight ? Colors.blue : Colors.red)))]);
  }

  Widget _buildAddressSelector() {
    return InkWell(
      onTap: _showAddressPicker,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)), child: Row(children: [const Icon(Icons.wallet, size: 16, color: Colors.blueGrey), const SizedBox(width: 10), Expanded(child: Text(_fromAddress, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))), const Icon(Icons.unfold_more, size: 16)])),
    );
  }

  void _showAddressPicker() {
    final wallets = QccObj.readWallets();
    showModalBottomSheet(context: context, builder: (context) => ListView(shrinkWrap: true, children: wallets.map((w) => ListTile(title: Text(w.address, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')), onTap: () { setState(() => _fromAddress = w.address); Navigator.pop(context); if(_currentHash.isNotEmpty) _fetchDividendInfo(_currentHash); })).toList()));
  }

  Widget _row(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Trans(label, style: const TextStyle(color: Colors.white70, fontSize: 11)), Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]));

  static Future<QccPacket> _signTransactionTask(Map<String, String> data) => QccDataProtocol.encodeTransaction(payloadJson: data['payloadJson']!, privateKeyHex: data['privHex']!, publicKeyHex: data['pubHex']!);
}