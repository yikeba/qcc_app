import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/rule/asset/core/AssetMeta.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../procotol/QccTxFlow.dart';
import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../utile/QccObj.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../AssetMultiSigProposalPage.dart';
import '../core/AssetBurnRule.dart';

/// 多签资产销毁——跟随签署页。
///
/// 【为什么单独建这个页面】和 AssetMintFollowSignWidget.dart /
/// MultiSigAssetFreezeFollowSignWidget.dart 同一个理由：销毁提案的
/// ruleJson 形如
/// `{"assetId":"OSNB","targetAddress":"Q...","amount":..., "legalBasis":..., "memo":...}`
/// （字段取自 AssetBurnRule.dart，已确认对应 Java
/// qcc.rule.assetRule.AssetBurnRule），和发行/增发/冻结的字段都不一样，
/// 不能硬套 AssetFollowSignWidget.dart。查hash→用owners/signedOwners算
/// 本机可签地址→选地址→展示昵称+QCC余额→QccTxFlow提交，主流程照搬。
///
/// 【依赖需要你核实，和其它几个新文件不一样的一点】我没有拿到
/// MultiSigAssetBurnWidget.dart（多签销毁提案发起页）的真实源码，只从
/// MultiSigAssetManageHubPage.dart 里的 import 知道它存在、以及
/// AssetBurnRule.dart 确认的字段结构——这个跟签页本身按 AssetBurnRule 的
/// 真实字段写的，应该没问题；但如果 MultiSigAssetBurnWidget.dart 发起
/// 提案时 ruleJson 的字段名或组织方式和 AssetBurnRule.toJson() 不一致
/// （比如它自己拼了另一套 Map 而不是用这个类），这个页面解析出来的摘要
/// 就会跟发起时的实际内容对不上。麻烦把 MultiSigAssetBurnWidget.dart 发我
/// 核对一下，和 MultiSigAssetFreezeWidget.dart 这次的优化一起补上。
class MultiSigAssetBurnFollowSignWidget extends StatefulWidget {
  const MultiSigAssetBurnFollowSignWidget({super.key});

  @override
  State<MultiSigAssetBurnFollowSignWidget> createState() => _MultiSigAssetBurnFollowSignWidgetState();
}

class _MultiSigAssetBurnFollowSignWidgetState extends State<MultiSigAssetBurnFollowSignWidget> {
  final TextEditingController _hashController = TextEditingController();

  bool _isFetching = false;
  bool _isProcessing = false;
  String nowaddress = "";
  Map<String, dynamic>? _proposalSummary;
  String ruleHash = "";

  Map<String, String> _walletNames = {};
  List<String> _eligibleSigners = [];
  bool _noLocalMember = false;
  bool _hasSignedByLocalWallet = false;

  @override
  void initState() {
    super.initState();
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  /// 销毁提案的 ruleJson（AssetBurnRule）不带精度，另查一次 /v1/asset——
  /// 和 AssetMintFollowSignWidget.dart 同一个思路/同一个接口。
  Future<int> _fetchPrecision(String assetId) async {
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        List assets = jsonDecode(res['data']);
        final match = assets.firstWhere(
          (a) => a['assetId'].toString().toUpperCase() == assetId.toUpperCase(),
          orElse: () => null,
        );
        if (match != null) {
          return int.tryParse(match['precision'].toString()) ?? 0;
        }
      }
    } catch (e) {
      LogObj.log("查询资产精度失败: $e");
    }
    return 0;
  }

  void _queryProposal() async {
    ruleHash = _hashController.text.trim();
    if (ruleHash.isEmpty) {
      Tools.showToast(context, "请输入交易哈希");
      return;
    }
    if (mounted) {
      setState(() {
        _isFetching = true;
        _proposalSummary = null;
        nowaddress = "";
        _eligibleSigners = [];
        _noLocalMember = false;
        _hasSignedByLocalWallet = false;
      });
    }
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/mtxquery?txHash=$ruleHash"));
      final resData = jsonDecode(response.body);
      if (resData['status'] == 'success' && resData['data'] != null) {
        final data = resData['data'];
        final ruleData = data['ruleData'];
        final String ruleName = (ruleData['ruleName'] ?? '').toString();

        // 【防呆】哈希对应的不是销毁提案，直接提示，不要硬套字段崩溃。
        if (ruleName != AssetType.AssetBurnRule.name) {
          throw "该哈希对应的不是资产销毁提案(ruleName=$ruleName)，请确认哈希输入正确";
        }

        final burnJson = jsonDecode(ruleData['ruleJson'] ?? "{}");
        final burnRule = AssetBurnRule.fromStructure(burnJson);

        final List<dynamic> signedOwnersRaw = data['signedOwners'] ?? [];
        final List<dynamic> ownersRaw = data['owners'] ?? [];
        final List<String> signedOwners = signedOwnersRaw.map((e) => e.toString()).toList();
        final List<String> owners = ownersRaw.map((e) => e.toString()).toList();

        final List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
        final List<String> memberLocalAddrs = localAddrs.where((a) => owners.contains(a)).toList();
        final List<String> eligible = memberLocalAddrs.where((a) => !signedOwners.contains(a)).toList();

        String selected = "";
        if (eligible.isNotEmpty) {
          final active = QccObj.activeWallet?.address;
          selected = (active != null && eligible.contains(active)) ? active : eligible.first;
        }

        final int precision = await _fetchPrecision(burnRule.assetId);
        if (!mounted) return;

        setState(() {
          nowaddress = selected;
          _eligibleSigners = eligible;
          _noLocalMember = memberLocalAddrs.isEmpty;
          _hasSignedByLocalWallet = memberLocalAddrs.isNotEmpty && eligible.isEmpty;
          _proposalSummary = {
            "assetId": burnRule.assetId,
            "targetAddress": burnRule.targetAddress,
            "amountRaw": burnRule.amount,
            "legalBasis": burnRule.legalBasis,
            "memo": burnRule.memo,
            "precision": precision,
            "threshold": data['threshold'],
            "currentCount": data['currentCount'],
            "owners": owners,
            "signedOwners": signedOwners,
            "ruleName": ruleName,
          };
        });
      } else {
        ruleHash = "";
        throw "提案查询失败或哈希无效";
      }
    } catch (e) {
      Tools.showToast(context, "查询异常: $e");
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  bool get _hasSignedByCurrent {
    if (nowaddress.isEmpty || _proposalSummary == null) return false;
    final signed = _proposalSummary!['signedOwners'] as List?;
    return signed?.contains(nowaddress) == true;
  }

  Widget _buildSummaryCard() {
    final s = _proposalSummary!;
    int precision = s['precision'];
    int amountRaw = s['amountRaw'];
    double displayAmount = amountRaw / pow(10, precision);
    bool hasSigned = _hasSignedByCurrent;
    String? legalBasis = s['legalBasis'];
    String? memo = s['memo'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hasSigned ? Colors.grey[100] : Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(s['assetId'].toString().toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: hasSigned ? Colors.grey : Colors.teal)),
              _buildProgressBadge(s['currentCount'], s['threshold'], hasSigned),
            ],
          ),
          const Divider(height: 24),
          _summaryRow("被销毁地址", s['targetAddress'], isAddr: true),
          const SizedBox(height: 10),
          _summaryRow("拟销毁数量", "${_formatValue(displayAmount, precision)} ${s['assetId']}"),
          if (legalBasis != null && legalBasis.isNotEmpty) ...[
            const SizedBox(height: 10),
            _summaryRow("合规依据", legalBasis),
          ],
          if (memo != null && memo.isNotEmpty) ...[
            const SizedBox(height: 10),
            _summaryRow("备注", memo),
          ],
          const SizedBox(height: 10),
          _summaryRow("当前状态", hasSigned ? "该地址已完成签署" : "等待您的签署"),
          const SizedBox(height: 10),
          _summaryRow("签署进度", "已集齐 ${s['currentCount']} / 需满足 ${s['threshold']}"),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isAddr = false}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 8)}...${value.substring(value.length - 8)}";
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
        Flexible(
          child: Text(displayValue,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _buildProgressBadge(int current, int threshold, bool hasSigned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: hasSigned ? Colors.grey : Colors.orange,
          borderRadius: BorderRadius.circular(6)
      ),
      child: Text("$current / $threshold",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildSignerSelector() {
    if (_noLocalMember) {
      return _buildStatusBanner(
        icon: Icons.gpp_bad,
        color: Colors.red,
        text: "本机没有属于这个多签账户成员的地址，无法签署此提案。",
      );
    }
    if (_hasSignedByLocalWallet) {
      return _buildStatusBanner(
        icon: Icons.verified,
        color: Colors.green,
        text: "本机地址已完成签署，无需重复操作。",
      );
    }

    String? nick = _walletNames[nowaddress];
    bool canSwitch = _eligibleSigners.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickSigner : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note, size: 16, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(child: Trans("签署地址", style: const TextStyle(fontSize: 11, color: Colors.grey))),
                if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 4),
            if (nick != null)
              Text(nick, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
            Text(nowaddress, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Text("QCC 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                QccActiveWallet(nowaddress, "QCC", fontSize: 12, fontColor: Colors.black87),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _pickSigner() {
    if (_eligibleSigners.length <= 1) return;
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
                child: Trans("选择签署地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _eligibleSigners.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final addr = _eligibleSigners[i];
                    final bool isSelected = nowaddress == addr;
                    final String? nick = _walletNames[addr];
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(addr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onTap: () {
                        setState(() => nowaddress = addr);
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

  Future<void> _handleFollow() async {
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请先选择签署地址"));
      return;
    }
    setState(() => _isProcessing = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule";
        rule.ruleName = AssetType.AssetBurnRule.name;
        rule.ruleJson = ruleHash;
        rule.ruleAppendJson = "";
        rule.finalizeId();
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.cancelled) return;

    if (result.success) {
      Tools.showToast(context, "✅ 销毁跟签已广播成功");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: ruleHash)),
        );
      }
    } else {
      LogObj.log("多签销毁跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Trans("追随销毁签署")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.delete_forever_outlined, size: 60, color: Colors.teal),
            const SizedBox(height: 16),
            const Trans("输入销毁提案 Hash 获取摘要", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            TextField(
              controller: _hashController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: "在此粘贴 TxHash...",
                border: OutlineInputBorder(),
                fillColor: Colors.white,
                filled: true,
              ),
              onChanged: (_) => setState(() => _proposalSummary = null),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isFetching ? null : _queryProposal,
                icon: _isFetching ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
                label: const Trans("查询提案详情"),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
              ),
            ),

            const SizedBox(height: 24),

            if (_proposalSummary != null) _buildSummaryCard(),

            if (_proposalSummary != null) ...[
              const SizedBox(height: 16),
              _buildSignerSelector(),
            ],

            const SizedBox(height: 32),

            if (_proposalSummary != null)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isProcessing || _eligibleSigners.isEmpty) ? null : _handleFollow,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: _isProcessing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Trans("确认签署此销毁规则", style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatValue(double val, int p) {
    String str = val.toStringAsFixed(p);
    if (!str.contains('.')) return str;
    return str.replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
  }
}
