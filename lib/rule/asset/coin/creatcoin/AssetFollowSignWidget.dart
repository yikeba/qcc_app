import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../../procotol/QccTxFlow.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../utile/QccObj.dart';

import '../../../../qccwallet/QccActiveWallet.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../AssetFileStorage.dart';
import '../../core/AssetMeta.dart';
import '../../AssetMultiSigProposalPage.dart';

/// 【重构说明，对应你这次提的3点】
/// 1. 签署地址可选：原来只会死板匹配"当前活跃钱包"，不是活跃钱包就直接
///    在提交那一刻才告诉你"不匹配"。现在改成查询到提案后立刻算出本机
///    所有"属于这个多签成员、且还没签过"的地址，做成可选择的列表，并显示
///    每个地址的本地昵称 + 实时 QCC 余额（复用 QccActiveWallet）。
/// 2. 读取 Hash 后验证签署钱包是否正确：原来的成员校验发生在点击"确认
///    签署"之后，且依赖本机 MultiSigAddressStorage 里是否registered过这个
///    多签地址（可能过期/没同步）。现在改成直接用查询接口返回的 owners /
///    signedOwners（链上权威数据）在查询完成的那一刻就算出本机能不能签、
///    该用哪个地址签，不需要等提交才知道结果。
/// 3. 签名方式改成统一的 QccTxFlow（本次会话新引入的统一提交流程类），
///    不再手抄"密码->loading->还原钱包->签名->提交"。
class AssetFollowSignWidget extends StatefulWidget {
  const AssetFollowSignWidget({super.key});

  @override
  State<AssetFollowSignWidget> createState() => _AssetFollowSignWidgetState();
}

class _AssetFollowSignWidgetState extends State<AssetFollowSignWidget> {
  final TextEditingController _hashController = TextEditingController();

  bool _isFetching = false;   // 正在查询详情
  bool _isProcessing = false; // 正在签署提交
  String nowaddress = "";     // 当前选中的签署地址
  Map<String, dynamic>? _proposalSummary; // 存储查询到的提案摘要
  String ruleHash = "";

  // 【新增】地址 -> 本地钱包昵称映射
  Map<String, String> _walletNames = {};
  // 【新增】本机可为这个提案签署的地址（是多签成员 & 尚未签署）
  List<String> _eligibleSigners = [];
  // 【新增】本机没有任何地址是这个多签的成员
  bool _noLocalMember = false;
  // 【新增】本机地址是成员，但已经全部签过了
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
        final ruleJson = jsonDecode(ruleData['ruleJson'] ?? "{}");
        final String multiSigAddr = (ruleJson['owner'] ?? "").toString();
        final List<dynamic> signedOwnersRaw = data['signedOwners'] ?? [];
        final List<dynamic> ownersRaw = data['owners'] ?? [];
        final List<String> signedOwners = signedOwnersRaw.map((e) => e.toString()).toList();
        final List<String> owners = ownersRaw.map((e) => e.toString()).toList();

        // 【核心新增，对应你的第2点】用查询接口返回的权威 owners/signedOwners
        // 现场算出：本机哪些地址是这个多签的成员、其中哪些还没签过。
        final List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
        final List<String> memberLocalAddrs = localAddrs.where((a) => owners.contains(a)).toList();
        final List<String> eligible = memberLocalAddrs.where((a) => !signedOwners.contains(a)).toList();

        String selected = "";
        if (eligible.isNotEmpty) {
          final active = QccObj.activeWallet?.address;
          selected = (active != null && eligible.contains(active)) ? active : eligible.first;
        }

        if (mounted) {
          setState(() {
            nowaddress = selected;
            _eligibleSigners = eligible;
            _noLocalMember = memberLocalAddrs.isEmpty;
            _hasSignedByLocalWallet = memberLocalAddrs.isNotEmpty && eligible.isEmpty;
            _proposalSummary = {
              "assetId": ruleJson['assetId'] ?? "Unknown",
              "precision": ruleJson['precision'] ?? 0,
              "initialSupply": ruleJson['initialSupply'],
              "threshold": data['threshold'],
              "currentCount": data['currentCount'],
              "owners": owners,
              "signedOwners": signedOwners,
              "originalRule": ruleData,
              "multiSigAddr": multiSigAddr,
            };
          });
        }
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

  // 修改摘要卡片，增加签署状态展示
  Widget _buildSummaryCard() {
    final s = _proposalSummary!;
    LogObj.log("解析签署内容$s");
    int p = s['precision'];
    num raw = s['initialSupply'] is String ? num.parse(s['initialSupply']) : s['initialSupply'];
    double displayAmount = raw / pow(10, p);
    bool hasSigned = _hasSignedByCurrent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // 如果已签，背景变灰
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
          _summaryRow("发行多签主体", s['multiSigAddr'], isAddr: true),
          const SizedBox(height: 10),
          _summaryRow("拟发行总量", "${_formatValue(displayAmount, p)} ${s['assetId']}"),
          const SizedBox(height: 10),
          _summaryRow("当前状态", hasSigned ? "该地址已完成签署" : "等待您的签署"),
          const SizedBox(height: 10),
          _summaryRow("签署进度", "已集齐 ${s['currentCount']} / 需满足 ${s['threshold']}"),
        ],
      ),
    );
  }

  // 辅助方法：增加地址缩略显示和已签状态颜色
  Widget _summaryRow(String label, String value, {bool isAddr = false}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 8)}...${value.substring(value.length - 8)}";
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
        Text(displayValue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace')),
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

  /// 【新增，对应你的第1+2点】签署地址选择卡：
  /// - 本机没有任何成员地址 -> 红色提示，不给选。
  /// - 本机成员地址都已签过 -> 绿色提示"已完成签署"。
  /// - 否则展示当前选中地址的昵称 + QCC 余额，多于1个可选地址时可点击切换。
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

  /// 【新增】签署地址选择弹层——只有本机匹配的成员地址不止一个时才需要弹。
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

  // 【重构】原来这里手抄了一遍"密码->loading->还原钱包->构建RuleData->
  // 签名->提交->解析返回"全流程，且 loading 弹出的时机在密码框"之前"
  // （取消密码框会导致卡死），成员校验也发生在提交这一刻才做。现在改成：
  // 成员校验已经在查询完成时做好（见 _queryProposal），这里只需要确认
  // 选中了签署地址，然后统一走 QccTxFlow.run()。
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
        // 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
        rule.ruleName = AssetType.AssetMeta.name;
        rule.ruleJson = ruleHash;
        // 对应 Java：ruleAppendJson = ""，必须显式写入——toSign() 的签名
        // 原文也包含这个字段。
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
      final resData = result.data!;
      LogObj.log("追随资产发行成功,返回$resData");
      resData['ruleName'] = AssetType.AssetMeta.name;
      await AssetFileStorage.saveAsset(resData);
      Tools.showToast(context, "✅ 资产发行规则已广播成功");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AssetMultiSigProposalPage(txHash: ruleHash)),
        );
      }
    } else {
      LogObj.log("多签追随签署资产发行异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Trans("追随资产签署")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.security_update_good, size: 60, color: Colors.purple),
            const SizedBox(height: 16),
            const Trans("输入提案 Hash 获取发行摘要", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            // Hash 输入
            TextField(
              controller: _hashController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: "在此粘贴 TxHash...",
                border: OutlineInputBorder(),
                fillColor: Colors.white,
                filled: true,
              ),
              onChanged: (_) => setState(() => _proposalSummary = null), // Hash 变动清空摘要
            ),
            const SizedBox(height: 16),

            // 查询按钮
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

            // ✅ 关键：显示发行规则摘要卡片
            if (_proposalSummary != null) _buildSummaryCard(),

            if (_proposalSummary != null) ...[
              const SizedBox(height: 16),
              // 【新增】签署地址选择/校验卡
              _buildSignerSelector(),
            ],

            const SizedBox(height: 32),

            // 签署提交按钮
            if (_proposalSummary != null)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_isProcessing || _eligibleSigners.isEmpty) ? null : _handleFollow,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: _isProcessing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Trans("确认签署此发行规则", style: TextStyle(color: Colors.white)),
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