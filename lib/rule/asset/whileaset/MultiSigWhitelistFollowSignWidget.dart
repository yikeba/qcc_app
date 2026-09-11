import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/procotol/RuleData.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
// 【这一行是本文件里唯一没有独立证据、纯猜测的绝对路径】其它规则的跟签
// 页（AssetMintFollowSignWidget.dart 等）都是用 '../AssetMultiSigProposalPage.dart'
// 这种相对路径引用它，我没有在任何"确认未被我改动过"的文件里见过它的
// package: 绝对路径，只能按 rule/asset/AssetMeta.dart（QccActiveWallet.dart
// 里确认过的绝对路径）同级推测它也直接放在 rule/asset/ 下。如果编译报错
// 找不到这个文件，请把真实路径告诉我，或者直接告诉我它的绝对 import 语句。
import 'package:qcc_flutter/rule/asset/AssetMultiSigProposalPage.dart';
import 'WhitelistUpdateRule.dart';

/// 白名单提案 —— 追随签署页。做法完全对齐 AssetMintFollowSignWidget.dart：
/// 查hash -> 校验 ruleName -> 用 owners/signedOwners 算本机可签地址 -> 选
/// 地址 -> 展示昵称+QCC余额 -> QccTxFlow 提交 -> 跳转 AssetMultiSigProposalPage。
///
/// 【和增发/冻结跟签页的一处关键区别，直接回应你提到的"未来亿级白名单"】
/// WhitelistUpdateRule 的 addresses 字段可能是几千甚至更多个地址，摘要卡片
/// 不能像其它规则那样把所有字段都直接摊平展示——这里只显示地址总数 +
/// 前5个预览，点"查看全部地址"才弹出一个用 ListView.builder 懒加载的
/// 底部弹层，避免地址数量一大就把整个摘要卡片撑爆或者卡顿。
class MultiSigWhitelistFollowSignWidget extends StatefulWidget {
  const MultiSigWhitelistFollowSignWidget({super.key});

  @override
  State<MultiSigWhitelistFollowSignWidget> createState() => _MultiSigWhitelistFollowSignWidgetState();
}

class _MultiSigWhitelistFollowSignWidgetState extends State<MultiSigWhitelistFollowSignWidget> {
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

        // 【防呆】哈希对应的不是白名单提案（比如粘错成增发/冻结/销毁的
        // hash），直接提示，不要硬套字段崩溃或者签出一个语义不对的提案。
        if (ruleName != kWhitelistUpdateRuleName) {
          throw "该哈希对应的不是白名单提案(ruleName=$ruleName)，请确认哈希输入正确";
        }

        final whitelistJson = jsonDecode(ruleData['ruleJson'] ?? "{}");
        final WhitelistUpdateRule rule = WhitelistUpdateRule.fromJson(whitelistJson);

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
            "assetId": rule.assetId,
            "operator": rule.operator,
            "op": rule.op,
            "addresses": rule.addresses,
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

  void _showAllAddressesSheet() {
    final List<String> addrs = List<String>.from(_proposalSummary!['addresses'] ?? []);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Trans("全部地址 (${addrs.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const Divider(height: 1),
                Expanded(
                  // 【回应"未来亿级白名单"】ListView.builder 懒加载，就算地址
                  // 数量到几千上万，也只渲染屏幕可见的那几十行，不会卡顿。
                  child: ListView.builder(
                    itemCount: addrs.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      leading: Text("${i + 1}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      title: Text(addrs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard() {
    final s = _proposalSummary!;
    bool hasSigned = _hasSignedByCurrent;
    final List<String> addrs = List<String>.from(s['addresses'] ?? []);
    final String op = s['op'];
    final preview = addrs.take(5).toList();

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
          _summaryRow("操作类型", op == WhitelistOp.add ? "加入白名单 (ADD)" : "移出白名单 (REMOVE)"),
          const SizedBox(height: 10),
          _summaryRow("发起人(operator)", s['operator'], isAddr: true),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("涉及地址", style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
              Text("共 ${addrs.length} 个", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          ...preview.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(a, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
              )),
          if (addrs.length > preview.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _showAllAddressesSheet,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                child: Text("查看全部 ${addrs.length} 个地址 >", style: const TextStyle(fontSize: 12)),
              ),
            ),
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

  /// 【提交成功后的处理，同样需要你确认】和 AssetMintFollowSignWidget.dart
  /// 一样，没有拿到 MultiSigFileStorage 之外还有没有专属"白名单本地缓存"
  /// 需要更新，这里先只做提示 + 跳转到 AssetMultiSigProposalPage(txHash)
  /// 展示签署进度。
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
        rule.ruleName = kWhitelistUpdateRuleName;
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
      Tools.showToast(context, "✅ 白名单跟签已广播成功");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: ruleHash)),
        );
      }
    } else {
      LogObj.log("白名单跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Trans("追随白名单签署")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.playlist_add_check_circle_outlined, size: 60, color: Colors.purple),
            const SizedBox(height: 16),
            const Trans("输入白名单提案 Hash 获取摘要", style: TextStyle(color: Colors.grey)),
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
                      : const Trans("确认签署此白名单规则", style: TextStyle(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
