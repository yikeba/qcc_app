import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';

import '../../home/QccExplorerService.dart';
import '../../procotol/MultiTransactionData.dart';
import '../../procotol/QccTxFlow.dart';
import '../../qccwallet/QccActiveWallet.dart';
import '../../rule/user/multiple/QccMultiSig.dart';
import '../../rule/user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../utile/QccObj.dart';
import '../../utile/QccStorage.dart';
import '../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';

/// 多签转账——追随签署页。
///
/// 本轮按你的要求优化第5点"多签追随的时候通过hash查询内存明细显示"，
/// 顺带把这个页面和 AssetFollowSignWidget.dart / AssetMintFollowSignWidget.dart
/// 同一类问题也修了（原代码这里从没做过，属于同一个坑）：
/// 1. 查询到明细后，原代码只从查询结果里取了 signedOwners，从来没取
///    owners，导致没法在查询这一刻就算出"本机到底能不能签、该用哪个地址
///    签"——原来的做法是签署那一刻直接假设 QccObj.activeWallet 就是要签的
///    地址，如果活跃钱包根本不是这个多签的成员，会一直等到提交失败才知道。
///    现在改成查询完成时就用 owners/signedOwners 算出本机可签地址列表，
///    可选择签署地址、展示昵称 + QCC 余额（做法对齐另外两个跟签页面）。
/// 2. 签名统一改走 QccTxFlow.run()，不再用 compute + QccDataProtocol.
///    encodeTransaction（本 session 里确认过这个方法签名恒为空）。
///
/// 【已核实，之前的假设是错的——按你贴的真实返回内容改】
/// 你贴的 mtxquery 真实返回里 `owners: []`（空数组）、`threshold: null`——
/// 说明"顶层带 owners 字段、和资产规则跟签同一套结构"这个假设不成立：
/// 多签*转账*的内存会话（MultiSingManager 的 pendingTXSessions 那一路）
/// 压根不知道这个多签地址完整的成员名单，只知道"谁已经签了"
/// (signedOwners)，不知道"一共应该有哪些人签" (owners/threshold)。
/// 这两个字段只有*资产规则*多签（走 pendingSessions，携带完整 RuleData）
/// 才有意义——之前的假设是把两条不同的流程混为一谈了。
///
/// 现在改成：从查询结果里拿到 fromMulti（多签地址，比如
/// "MbkpxmmAmdJC3ixidPfrdff6MU3HbWtXrt"），去本机 MultiSigAddressStorage
/// （创建/确认多签地址时就应该已经存过一份 MultiSigAccount：multiAddress+
/// owners+threshold）里按这个地址查一遍，找到了就用它的 owners/threshold
/// 作为权威名单，再用查询结果里真实的 signedOwners 算出"还差哪些地址没
/// 签"，本机钱包里能匹配上这些"还没签"地址的，才是真正可签的地址；本机
/// 完全没有这个多签地址记录时，只能照实告知"本地未找到该多签的成员名单"，
/// 不强行伪造一份owners出来。
///
/// 【需要你核实的一处假设，和 QccMultiSigTransferPage.dart 是同一处】
/// MultiTransactionData 我手上没有源码，这里假设它和 RuleData /
/// QccTransactionData 一样有单独的 toSign() 方法。如果实际没有或字段不同，
/// 把 MultiTransactionData.dart 发我核对即可。
class QccFollowTransactionPage extends StatefulWidget {
  const QccFollowTransactionPage({super.key});

  @override
  State<QccFollowTransactionPage> createState() => _QccFollowTransactionPageState();
}

class _QccFollowTransactionPageState extends State<QccFollowTransactionPage> {
  final TextEditingController _hashController = TextEditingController();
  Map<String, dynamic>? _txDetail; // 解析后的交易明细
  bool _searching = false;
  bool _isProcessing = false;
  String? _errorMsg;

  // 【新增】地址 -> 本地钱包昵称映射
  Map<String, String> _walletNames = {};
  // 【新增】本机可为这个提案签署的地址（是多签成员 & 尚未签署）
  List<String> _eligibleSigners = [];
  String nowaddress = "";
  // 【新增】本机没有任何地址是这个多签的成员
  bool _noLocalMember = false;
  // 【新增】本机地址是成员，但已经全部签过了
  bool _hasSignedByLocalWallet = false;

  // 【新增】按 fromMulti 匹配到的本地多签账户（MultiSigAddressStorage 里
  // 创建/确认多签地址时应该已经存过一份 multiAddress+owners+threshold）；
  // 查不到时为 null——mtxquery 对转账提案的查询结果本身不带完整成员名单，
  // 见文件头部说明，所以这个信息只能从本地反查。
  MultiSigAccount? _matchedAccount;
  // 【新增】全体成员地址（来自 _matchedAccount.addrs，去重后），签署进度
  // 卡片和"还需谁签署"列表都按这份名单展示。查不到本地账户时为空列表。
  List<String> _allOwners = [];
  // 【新增】本机完全没有这个多签地址的本地记录——和"是成员但已签完"要
  // 分开提示，不能一概说成"无法签署"。
  bool _accountNotFoundLocally = false;

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

  // 查询提案明细 + 算出本机可签地址
  void _fetchTxDetail(String hash) async {
    String cleanHash = hash.trim();
    if (cleanHash.length < 64) {
      setState(() {
        _txDetail = null;
        _errorMsg = null;
        _eligibleSigners = [];
        _noLocalMember = false;
        _hasSignedByLocalWallet = false;
        nowaddress = "";
      });
      return;
    }

    setState(() {
      _searching = true;
      _errorMsg = null;
      _eligibleSigners = [];
      _noLocalMember = false;
      _hasSignedByLocalWallet = false;
      _accountNotFoundLocally = false;
      _matchedAccount = null;
      _allOwners = [];
      nowaddress = "";
    });
    try {
      final response = await http.get(
        Uri.parse("${QccExplorerService.baseUrl}/v1/mtxquery?txHash=$cleanHash"),
      );
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['status'] == 'success' && res['data'] != null) {
          final rawData = res['data'];
          LogObj.log("追随签署资产返回$res");
          Map<String, dynamic> detailData = {};
          if (rawData['data'] is String) {
            detailData = jsonDecode(rawData['data']);
          } else {
            detailData = rawData['data'];
          }

          // 【修复，见文件头部说明】查询结果里的 signedOwners 才是真实、
          // 权威的"谁已经签了"；但 owners/threshold 这两个字段这条查询接口
          // 根本不返回（转账提案的内存会话不携带完整成员名单），下面改成
          // 按 fromMulti 去本地 MultiSigAddressStorage 里反查。
          final List<dynamic> signedOwnersRaw = rawData['signedOwners'] ?? [];
          final List<String> signedOwners = signedOwnersRaw.map((e) => e.toString()).toList();
          final String fromMulti = (detailData['fromMulti'] ?? '').toString();

          // 【新增】按多签地址反查本地保存的成员名单/门槛。
          final List<MultiSigAccount> localAccounts = await MultiSigAddressStorage.getAllAccounts();
          MultiSigAccount? matched;
          for (final acc in localAccounts) {
            if (acc.multiAddress == fromMulti) {
              matched = acc;
              break;
            }
          }

          final List<String> allOwners = matched != null ? matched.addrs : <String>[];
          // 还没签的地址 = 全体成员 - 已签署（本地找不到成员名单时，这个
          // 列表算不出来，保持为空，不强行伪造"还差谁"）。
          final List<String> remaining = allOwners.where((a) => !signedOwners.contains(a)).toList();

          final List<String> localAddrs = QccObj.readWallets().map((e) => e.address).toList();
          // 本机地址里，属于这个多签成员、且还没签过的——才是真正可签的。
          final List<String> memberLocalAddrs = localAddrs.where((a) => allOwners.contains(a)).toList();
          final List<String> eligible = localAddrs.where((a) => remaining.contains(a)).toList();

          String selected = "";
          if (eligible.isNotEmpty) {
            final active = QccObj.activeWallet?.address;
            selected = (active != null && eligible.contains(active)) ? active : eligible.first;
          }

          if (!mounted) return;
          setState(() {
            // 合并外层的 signedOwners 到明细中，方便 UI 和后续逻辑使用；
            // owners/threshold 改用本地反查到的结果（查不到就是空/0）。
            _txDetail = {
              ...detailData,
              'signedOwners': signedOwners,
              'owners': allOwners,
              'remaining': remaining,
              'currentCount': signedOwners.length,
              'threshold': matched?.threshold ?? 0,
              'expiry': rawData['expiry'],
            };
            _matchedAccount = matched;
            _allOwners = allOwners;
            _eligibleSigners = eligible;
            nowaddress = selected;
            // 本地完全没有这个多签地址的记录——和"是成员但已签完"要分开
            // 提示。
            _accountNotFoundLocally = matched == null;
            _noLocalMember = matched != null && memberLocalAddrs.isEmpty;
            _hasSignedByLocalWallet = matched != null && memberLocalAddrs.isNotEmpty && eligible.isEmpty;
            _searching = false;
          });
          LogObj.log("QCC DEBUG_: 格式化后的明细: ${_txDetail.toString()}");
        } else {
          setState(() { _errorMsg = "未找到该交易提案或已失效"; _searching = false; });
        }
      }
    } catch (e) {
      LogObj.log("查询异常: $e");
      setState(() { _errorMsg = "网络查询失败"; _searching = false; });
    }
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

  // 2. 核心：执行追加签署逻辑——统一走 QccTxFlow.run()。
  Future<void> _onSign() async {
    if (_txDetail == null || nowaddress.isEmpty) return;

    setState(() => _isProcessing = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        final mudata = MultiTransactionData();
        mudata.from = wallet.address;
        mudata.fromMulti = _txDetail!['fromMulti'];
        mudata.to = _txDetail!['to'];
        mudata.amount = _txDetail!['amount']; // 保持原始金额
        mudata.assetId = _txDetail!['assetId'] ?? "QCC";
        mudata.txType = "pay";
        mudata.finalizeId();
        mudata.mutxHash = _hashController.text.trim(); // 追随签署的关键链接

        // 【假设，见文件顶部说明】
        return QccSignPayload(toSign: mudata.toSign(), payloadJson: jsonEncode(mudata.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mutxbaseData",
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (result.cancelled) return;

    if (result.success) {
      Tools.showToast(context, "✅ 追加签署成功！");
      if (mounted) Navigator.pop(context);
    } else {
      LogObj.log("多签转账跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("追随签署资产"), centerTitle: true, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHashInput(),
          const SizedBox(height: 24),
          if (_searching) const Center(child: LinearProgressIndicator()),
          if (_errorMsg != null) Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
          if (_txDetail != null) _buildDetailCard(), // 资产转账明细卡片
          if (_txDetail != null) ...[
            const SizedBox(height: 16),
            // 【新增】签署地址选择/校验卡
            _buildSignerSelector(),
          ],
          const SizedBox(height: 40),
          _buildSignButton(),
        ],
      ),
    );
  }

  Widget _buildHashInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: _hashController,
        onChanged: _fetchTxDetail,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
          labelText: Tools.getTra("粘贴待签交易 Hash"),
          hintText: "0x...",
          prefixIcon: const Icon(Icons.link),
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
      ),
    );
  }

  Widget _buildDetailCard() {
    String assetId = _txDetail!["assetId"];
    String readableAmount = QccAssetService().getHumanAmount(assetId, _txDetail!['amount']);
    List<dynamic> signedOwners = _txDetail!['signedOwners'] ?? []; // 获取已签署列表
    // 【新增】门槛——本地能反查到多签账户时才有意义，查不到时为 0。
    final int threshold = _txDetail!['threshold'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.security, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Trans("待签资产明细", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
              // 【修改】本地反查到多签账户时显示 "已签署 N/threshold"，
              // 查不到时（threshold=0）退回只显示已签署人数，避免出现
              // 让人误解的 "N/0"。
              Text(
                threshold > 0 ? "已签署: ${signedOwners.length} / $threshold" : "已签署: ${signedOwners.length}",
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),
          const Divider(height: 24),
          _infoRow("付款多签", _txDetail!['fromMulti']),
          _infoRow("收款地址", _txDetail!['to']),

          const SizedBox(height: 16),
          Trans("已签署成员:", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (signedOwners.isEmpty)
            Text("暂无", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ...signedOwners.map((addr) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    addr.toString(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                  ),
                ),
              ],
            ),
          )),

          // 【新增，这就是你要的"剩余多签地址"】仅在本地能反查到多签账户
          // 完整成员名单时才显示——按 fromMulti 匹配 MultiSigAddressStorage
          // 得到全体成员，再减去已签署地址，剩下的就是"还需要签署"的地址。
          if (_matchedAccount != null) ...[
            const SizedBox(height: 16),
            Trans("待签署成员:", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if ((_txDetail!['remaining'] as List).isEmpty)
              Text("全部已签署", style: TextStyle(fontSize: 11, color: Colors.green.shade600))
            else
              ...(_txDetail!['remaining'] as List).map((addr) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        addr.toString(),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              )),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "本地未找到该多签地址的成员名单，无法显示还差谁签署",
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ],

          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("转账金额", style: const TextStyle(color: Colors.grey)),
              Text("$readableAmount $assetId", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value ?? "---", style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    ),
  );

  /// 【新增】签署地址选择卡——本机没有成员地址就红色提示；都签过了就绿色
  /// 提示；否则展示当前选中地址的昵称 + QCC 余额，多于1个可选地址时可
  /// 点击切换。做法对齐 AssetFollowSignWidget.dart / AssetMintFollowSignWidget.dart。
  Widget _buildSignerSelector() {
    // 【新增】本地压根没有这个多签地址的成员名单记录——区别于"是成员但
    // 签过了"/"确实不是成员"，这种情况下不能断言本机无法签署，只是暂时
    // 判断不出来（比如这台设备从没参与过创建/确认这个多签账户）。
    if (_accountNotFoundLocally) {
      return _buildStatusBanner(
        icon: Icons.help_outline,
        color: Colors.blueGrey,
        text: "本地未找到该多签地址 (${_txDetail!['fromMulti'] ?? '--'}) 的成员记录，暂时无法判断本机是否可以签署。",
      );
    }
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

  Widget _buildSignButton() {
    bool canSign = _txDetail != null && !_searching && !_isProcessing && _eligibleSigners.isNotEmpty;
    return ElevatedButton(
      onPressed: canSign ? _onSign : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isProcessing
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Trans("确认并追加签名", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}