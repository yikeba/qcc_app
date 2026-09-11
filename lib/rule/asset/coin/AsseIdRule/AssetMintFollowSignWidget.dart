import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../../procotol/QccTxFlow.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../utile/QccObj.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../AssetMultiSigProposalPage.dart';
import '../../core/AssetMeta.dart';
/// 多签资产增发 —— 跟随签署页。
///
/// 【为什么单独建这个页面，而不是复用 AssetFollowSignWidget.dart】
/// AssetFollowSignWidget.dart 是专门给资产发行(AssetMeta)写的：查询到提案
/// 后直接假设 ruleJson 里有 owner/precision/initialSupply 这三个字段去拼
/// 摘要卡片，提交时也把 ruleName 写死成 AssetType.AssetMeta.name。
/// 但 AssetMintRule 的 ruleJson 形如
/// `{"assetId":"OSNB","amount":10000000,"receiver":"M...","proof":"..."}`——
/// 根本没有 owner/precision/initialSupply 字段（initialSupply 恒为 null），
/// 硬套过去摘要卡片那步就会崩溃，这正是你贴的查询结果里三个字段都不对的
/// 原因。所以这里单独复制一份跟签流程，只把"摘要卡片怎么显示"和"提交时
/// ruleName 填什么"换成 AssetMintRule 专属的——查hash→用owners/signedOwners
/// 算本机可签地址→选地址→展示昵称+QCC余额→QccTxFlow提交 这一整套主流程
/// 和 AssetFollowSignWidget.dart 完全一致，照搬过来。
class AssetMintFollowSignWidget extends StatefulWidget {
  const AssetMintFollowSignWidget({super.key});

  @override
  State<AssetMintFollowSignWidget> createState() => _AssetMintFollowSignWidgetState();
}

class _AssetMintFollowSignWidgetState extends State<AssetMintFollowSignWidget> {
  final TextEditingController _hashController = TextEditingController();

  bool _isFetching = false;   // 正在查询详情
  bool _isProcessing = false; // 正在签署提交
  String nowaddress = "";     // 当前选中的签署地址
  Map<String, dynamic>? _proposalSummary; // 存储查询到的提案摘要
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

  /// AssetMintRule 的 ruleJson 里不带 precision（这个字段只在 AssetMeta 里
  /// 有），增发数量要换算成好读的小数展示，得另查一次 /v1/asset 拿到该
  /// 资产当前登记的精度——和资产查重、MultiSigAssetMintWidget.dart 走的是
  /// 同一个接口。查不到就按 0 位精度展示原始整数，不阻塞主流程。
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

        // 【防呆】哈希对应的不是增发提案（比如粘错成发行/冻结/销毁的
        // hash），直接提示，不要硬套字段崩溃或者签出一个语义不对的提案。
        if (ruleName != AssetType.AssetMintRule.name) {
          throw "该哈希对应的不是资产增发提案(ruleName=$ruleName)，请确认哈希输入正确";
        }

        final mintJson = jsonDecode(ruleData['ruleJson'] ?? "{}");
        final String assetId = (mintJson['assetId'] ?? '').toString();
        final String receiver = (mintJson['receiver'] ?? '').toString();
        final int amountRaw = int.tryParse(mintJson['amount'].toString()) ?? 0;
        final String? proof = (mintJson['proof'] as String?)?.trim();

        final List<dynamic> signedOwnersRaw = data['signedOwners'] ?? [];
        final List<dynamic> ownersRaw = data['owners'] ?? [];
        final List<String> signedOwners = signedOwnersRaw.map((e) => e.toString()).toList();
        final List<String> owners = ownersRaw.map((e) => e.toString()).toList();

        // 用查询接口返回的权威 owners/signedOwners 现场算出：本机哪些地址
        // 是这个多签的成员、其中哪些还没签过——和 AssetFollowSignWidget.dart
        // 同一套做法。
        final List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
        final List<String> memberLocalAddrs = localAddrs.where((a) => owners.contains(a)).toList();
        final List<String> eligible = memberLocalAddrs.where((a) => !signedOwners.contains(a)).toList();

        String selected = "";
        if (eligible.isNotEmpty) {
          final active = QccObj.activeWallet?.address;
          selected = (active != null && eligible.contains(active)) ? active : eligible.first;
        }

        // 增发的 ruleJson 本身不带精度，另查一次。
        final int precision = await _fetchPrecision(assetId);
        if (!mounted) return;

        setState(() {
          nowaddress = selected;
          _eligibleSigners = eligible;
          _noLocalMember = memberLocalAddrs.isEmpty;
          _hasSignedByLocalWallet = memberLocalAddrs.isNotEmpty && eligible.isEmpty;
          _proposalSummary = {
            "assetId": assetId,
            "receiver": receiver,
            "amountRaw": amountRaw,
            "proof": proof,
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
    String? proof = s['proof'];

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
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: hasSigned ? Colors.grey : Colors.orange)),
              _buildProgressBadge(s['currentCount'], s['threshold'], hasSigned),
            ],
          ),
          const Divider(height: 24),
          _summaryRow("多签接收地址", s['receiver'], isAddr: true),
          const SizedBox(height: 10),
          _summaryRow("拟增发数量", "${_formatValue(displayAmount, precision)} ${s['assetId']}"),
          if (proof != null && proof.isNotEmpty) ...[
            const SizedBox(height: 10),
            _summaryRow("铸造来源", proof),
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

  /// 签署地址选择卡——和 AssetFollowSignWidget.dart 的 _buildSignerSelector
  /// 完全一致：本机没有成员地址就红色提示；都签过了就绿色提示；否则展示
  /// 当前选中地址的昵称 + QCC 余额，多于1个可选地址时可点击切换。
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

  /// 【关键区别，对应本页存在的意义】ruleName 从查询结果里读出来的
  /// AssetMintRule 填，不是 AssetFollowSignWidget.dart 那样写死 AssetMeta——
  /// 这样公链才知道这条签名是要追加到"增发"这条提案上，而不是发行提案。
  /// ruleJson 依然只填 ruleHash 本身（引用被签署的提案），和资产发行跟签
  /// 页面同一个约定。
  ///
  /// 【提交成功后的处理，需要你确认】这里没有调用 AssetFileStorage.saveAsset
  /// ——那个方法是给"新资产发行"落地用的，增发跟签不产生新资产。我没有
  /// MultiSigFileStorage/其它本地存储类的源码，不确定增发跟签成功后本机
  /// 是否需要更新某个本地缓存的"当前发行总量"之类的记录，所以这里先只做
  /// 提示 + 跳转到 AssetMultiSigProposalPage(txHash) 展示签署进度（和资产
  /// 发行跟签页复用同一个结果页，因为它本身就是"输入hash查进度"的通用页
  /// 面）。如果增发跟签成功后还需要写某个本地文件，请告诉我具体应该调
  /// 哪个方法。
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
        rule.ruleName = AssetType.AssetMintRule.name;
        rule.ruleJson = ruleHash;
        rule.ruleAppendJson = "";
        rule.finalizeId();
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "${QccExplorerService.baseUrl}/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.cancelled) return;

    if (result.success) {
      Tools.showToast(context, "✅ 增发跟签已广播成功");
      LogObj.log("多签增发成功，返回内容:$ruleHash");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: ruleHash)),
        );
      }
    } else {
      LogObj.log("多签增发跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Trans("追随增发签署")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.security_update_good, size: 60, color: Colors.purple),
            const SizedBox(height: 16),
            const Trans("输入增发提案 Hash 获取摘要", style: TextStyle(color: Colors.grey)),
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
                style: OutlinedButton.styleFrom(foregroundColor: Colors.purple),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: _isProcessing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Trans("确认签署此增发规则", style: TextStyle(color: Colors.white)),
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
