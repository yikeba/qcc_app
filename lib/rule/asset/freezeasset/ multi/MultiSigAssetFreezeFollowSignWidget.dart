import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';

import '../../../../home/QccExplorerService.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../procotol/QccTxFlow.dart';
import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../utile/QccObj.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../core/AssetMeta.dart';
import '../../AssetMultiSigProposalPage.dart';

/// 多签资产冻结/解冻——追随签署页。
///
/// 【为什么单独建这个页面，而不是复用 AssetFollowSignWidget.dart】
/// 和 AssetMintFollowSignWidget.dart 同一个理由：AssetFollowSignWidget.dart
/// 是专门给资产发行(AssetMeta)写的，硬套 owner/precision/initialSupply 这三
/// 个字段拼摘要卡片；冻结提案的 ruleJson 形如
/// `{"assetId":"OSNB","targetAddress":"Q...","freeze":true,"expiry":0}`，
/// 字段完全不同，套过去会崩溃或者显示错误信息。查hash→用owners/
/// signedOwners算本机可签地址→选地址→展示昵称+QCC余额→QccTxFlow提交
/// 这一整套主流程和 AssetMintFollowSignWidget.dart 完全一致，照搬过来，
/// 只换了摘要卡片的字段和提交时的 ruleName。
///
/// 【顺带做的事，对应你要的"查询地址是否已经被冻结"同一个能力】查询到
/// 提案摘要后，额外查一次目标地址当前的真实冻结状态（同一个
/// /v1/assetFrozen 接口），签署前能看到"这个操作到底有没有意义"——比如
/// 别人发起的是"解冻"提案，但查出来这个地址其实早就不是冻结状态了。
class MultiSigAssetFreezeFollowSignWidget extends StatefulWidget {
  const MultiSigAssetFreezeFollowSignWidget({super.key});

  @override
  State<MultiSigAssetFreezeFollowSignWidget> createState() => _MultiSigAssetFreezeFollowSignWidgetState();
}

class _MultiSigAssetFreezeFollowSignWidgetState extends State<MultiSigAssetFreezeFollowSignWidget> {
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

  // 【新增】目标地址当前真实冻结状态查询结果。
  bool? _targetFrozenNow;
  bool _isCheckingFrozen = false;

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

  /// 查询目标地址在这个资产下当前真实的冻结状态——和
  /// MultiSigAssetFreezeWidget.dart / QccFreezePage.dart 用的是同一个已经
  /// 按 AssetFrozenContext.java 源码核实过的接口。
  Future<void> _checkCurrentFrozenStatus(String assetId, String targetAddress) async {
    setState(() {
      _isCheckingFrozen = true;
      _targetFrozenNow = null;
    });
    try {
      final resp = await http.get(Uri.parse(
          "${QccExplorerService.baseUrl}/v1/assetFrozen?address=$targetAddress&asset=$assetId"));
      if (resp.statusCode == 200) {
        final res = jsonDecode(resp.body);
        if (res['ok'] == true) {
          final data = res['data'];
          final String? status = data is Map ? data['status']?.toString() : null;
          if (mounted) setState(() => _targetFrozenNow = status == 'FROZEN');
        } else {
          if (mounted) setState(() => _targetFrozenNow = null);
        }
      }
    } catch (e) {
      LogObj.log("查询地址冻结状态失败: $e");
      if (mounted) setState(() => _targetFrozenNow = null);
    } finally {
      if (mounted) setState(() => _isCheckingFrozen = false);
    }
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
        _targetFrozenNow = null;
      });
    }
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/mtxquery?txHash=$ruleHash"));
      final resData = jsonDecode(response.body);
      if (resData['status'] == 'success' && resData['data'] != null) {
        final data = resData['data'];
        final ruleData = data['ruleData'];
        final String ruleName = (ruleData['ruleName'] ?? '').toString();

        // 【防呆】哈希对应的不是冻结/解冻提案（比如粘错成发行/增发/销毁的
        // hash），直接提示，不要硬套字段崩溃或者签出一个语义不对的提案。
        if (ruleName != AssetType.AssetFreezeRule.name) {
          throw "该哈希对应的不是资产冻结/解冻提案(ruleName=$ruleName)，请确认哈希输入正确";
        }

        final freezeJson = jsonDecode(ruleData['ruleJson'] ?? "{}");
        final String assetId = (freezeJson['assetId'] ?? '').toString();
        final String targetAddress = (freezeJson['targetAddress'] ?? '').toString();
        final bool freeze = freezeJson['freeze'] == true;
        final int expiry = int.tryParse(freezeJson['expiry'].toString()) ?? 0;

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

        if (!mounted) return;
        setState(() {
          nowaddress = selected;
          _eligibleSigners = eligible;
          _noLocalMember = memberLocalAddrs.isEmpty;
          _hasSignedByLocalWallet = memberLocalAddrs.isNotEmpty && eligible.isEmpty;
          _proposalSummary = {
            "assetId": assetId,
            "targetAddress": targetAddress,
            "freeze": freeze,
            "expiry": expiry,
            "threshold": data['threshold'],
            "currentCount": data['currentCount'],
            "owners": owners,
            "signedOwners": signedOwners,
            "ruleName": ruleName,
          };
        });

        // 顺带查一次目标地址当前真实冻结状态，不阻塞摘要展示。
        _checkCurrentFrozenStatus(assetId, targetAddress);
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
    bool hasSigned = _hasSignedByCurrent;
    bool freeze = s['freeze'] == true;
    int expiry = s['expiry'] ?? 0;

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
              Row(
                children: [
                  Icon(freeze ? Icons.ac_unit : Icons.wb_sunny_outlined, size: 18, color: freeze ? Colors.blueGrey : Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    "${s['assetId'].toString().toUpperCase()} · ${freeze ? '冻结' : '解冻'}",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: hasSigned ? Colors.grey : (freeze ? Colors.blueGrey : Colors.green)),
                  ),
                ],
              ),
              _buildProgressBadge(s['currentCount'], s['threshold'], hasSigned),
            ],
          ),
          const Divider(height: 24),
          _summaryRow("目标地址", s['targetAddress'], isAddr: true),
          const SizedBox(height: 10),
          _summaryRow("拟执行操作", freeze ? "冻结该地址" : "解除冻结"),
          const SizedBox(height: 10),
          _summaryRow("有效期", expiry == 0 ? "永久（直至手动撤销）" : "$expiry"),
          const SizedBox(height: 10),
          _summaryRow("当前状态", hasSigned ? "该地址已完成签署" : "等待您的签署"),
          const SizedBox(height: 10),
          _summaryRow("签署进度", "已集齐 ${s['currentCount']} / 需满足 ${s['threshold']}"),
          const Divider(height: 24),
          _buildTargetNowFrozenRow(),
        ],
      ),
    );
  }

  /// 【新增，对应你要的"查询地址是否已经被冻结"】目标地址当前真实冻结
  /// 状态——和提案里"拟执行的操作"分开展示，方便判断这个提案现在签是否
  /// 还有意义（比如提案是解冻，但地址其实早被别的途径解开了）。
  Widget _buildTargetNowFrozenRow() {
    return Row(
      children: [
        if (_isCheckingFrozen)
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(
            _targetFrozenNow == null ? Icons.help_outline : (_targetFrozenNow! ? Icons.ac_unit : Icons.wb_sunny_outlined),
            size: 14,
            color: _targetFrozenNow == null ? Colors.grey : (_targetFrozenNow! ? Colors.blueGrey : Colors.green),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _isCheckingFrozen
                ? "正在查询目标地址当前冻结状态..."
                : (_targetFrozenNow == null
                    ? "目标地址当前冻结状态未知（查询失败）"
                    : "目标地址当前实际状态：${_targetFrozenNow! ? '已冻结' : '未冻结'}"),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      ],
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

  /// 签署地址选择卡——和 AssetMintFollowSignWidget.dart 完全一致。
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
  /// AssetFreezeRule 填，不是写死 AssetMeta——这样公链才知道这条签名是
  /// 要追加到"冻结/解冻"这条提案上。ruleJson 依然只填 ruleHash 本身
  /// （引用被签署的提案），和资产发行/增发跟签页面同一个约定。
  ///
  /// 【提交成功后的处理，需要你确认，同 AssetMintFollowSignWidget.dart】
  /// 这里没有更新 MultiSigFileStorage 里的本地记录状态（比如把 PENDING
  /// 改成 SUCCESS）——我没有 MultiSigFileStorage 除 saveTask 之外用于"追加
  /// 签署后更新已有记录"的确认约定，如果需要在追随签署成功后同步更新
  /// 本地"多签冻结状态中心"里对应那条记录的状态，请告诉我具体想要哪种
  /// 行为（比如调用 MultiSigFileStorage.updateStatus(txHash, 'SUCCESS')）。
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
        rule.ruleName = AssetType.AssetFreezeRule.name;
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
      Tools.showToast(context, "✅ 冻结/解冻跟签已广播成功");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: ruleHash)),
        );
      }
    } else {
      LogObj.log("多签冻结跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Trans("追随冻结签署")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.ac_unit, size: 60, color: Colors.blueGrey),
            const SizedBox(height: 16),
            const Trans("输入冻结/解冻提案 Hash 获取摘要", style: TextStyle(color: Colors.grey)),
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
                style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                  child: _isProcessing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Trans("确认签署此冻结/解冻规则", style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
