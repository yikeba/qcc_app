import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/JsonUtil.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'dart:convert';

// 【本次修正，对应你的要求"也需要更换签名方式"】原来的手写
// compute(_signRuleTask,...) -> QccDataProtocol.encodeTransaction() 和
// MultiSigStableCoinIssueWidget.dart 修之前是同一个问题：encodeTransaction()
// 内部真正的签名调用整段被注释掉了，固定 return signature:""，之前这个
// 页面提交的跟签请求签名字段自始至终是空字符串。现在改用 QccTxFlow.run()，
// 内部走 SignUtil.instance.signAndEncode()，和 MultiSigPledgeFollowSignWidget.dart
// 等已验证过的跟签页面用同一套。
import '../../../procotol/QccTxFlow.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../../user/multiple/QccMultiSig.dart';
import '../core/AssetMeta.dart';
import 'QccStableCoinSignSuccessWidget.dart';

class MultiSigStableCoinFollowSignWidget extends StatefulWidget {
  const MultiSigStableCoinFollowSignWidget({super.key});

  @override
  State<MultiSigStableCoinFollowSignWidget> createState() => _MultiSigStableCoinFollowSignWidget();
}

class _MultiSigStableCoinFollowSignWidget extends State<MultiSigStableCoinFollowSignWidget> {
  final TextEditingController _hashController = TextEditingController();

  // 1. 本地多签账户数据
  List<MultiSigAccount> _accounts = [];
  MultiSigAccount? _selectedAccount;
  Map<String, String> _walletNames = {};

  // 2. 业务状态
  bool _isQuerying = false;
  Map<String, dynamic>? _proposalData;

  // 【本次新增，对应你的要求"签名选择"】原来 _currentSignerAddress 只是把
  // initState() 里当前活跃钱包地址(还是强制解包 QccObj.activeWallet!)原样
  // 显示出来，既没有校验这个地址是不是多签账户成员，也不能切换——照抄
  // MultiSigPledgeFollowSignWidget.dart 的套路，改成查询到提案详情之后，
  // 用 owners ∩ 本机钱包 ∩ 尚未签署，算出真正"有资格签这一笔"的候选地址，
  // 供选择/切换。
  String nowaddress = "";
  List<String> _eligibleSigners = [];
  bool _noLocalMember = false;
  bool _hasSignedByLocalWallet = false;

  // 【本次新增，对照 MuRuleUSDSAsset.java 逐字段核对后发现的真实问题】
  // Java 里跟签用的 apphash 是查询/发起时就固定下来的局部变量(appendRule.ruleJson
  // = apphash;)，之后不会再变。这边原来 _followstable() 却是在提交时重新去读
  // `_hashController.text`(而且没有 trim())——如果用户查询完之后又手滑改了
  // 输入框内容(或者输入框里本来就带了首尾空格)，实际签名/提交的 ruleJson 就会
  // 和查询、预览时用的哈希不一致，等于签了一个跟界面上显示的提案对不上的东西。
  // 照 MultiSigPledgeFollowSignWidget.dart 的 ruleHash 做法，查询成功那一刻就把
  // 哈希冻结在这个状态变量里，_followstable() 只认这个，不再重新读输入框。
  String _queriedHash = "";

  @override
  void initState() {
    super.initState();
    _loadMultiSigAccounts(); // 初始化时启动异步读取
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  /// ✅ 新增方法：从本地存储读取多签账户
  Future<void> _loadMultiSigAccounts() async {
    try {
      final list = await MultiSigAddressStorage.getAllAccounts();
      LogObj.log("追随页面读取到本地多签地址: ${list.length} 个");
      if (!mounted) return;
      setState(() {
        _accounts = list;
        if (_accounts.isNotEmpty) {
          _selectedAccount = _accounts.first;
        }
      });
    } catch (e) {
      LogObj.log("加载多签账户失败: $e");
    }
  }

  /// ✅ 修正后的查询方法：多签地址 + Hash 复合查询
  Future<void> _fetchProposalDetails() async {
    String hash = _hashController.text.trim();

    if (_selectedAccount == null) {
      Tools.showToast(context, "请先选择目标多签地址");
      return;
    }
    if (hash.length < 64) {
      Tools.showToast(context, "请输入完整的 64位 TxHash");
      return;
    }

    setState(() {
      _isQuerying = true;
      nowaddress = "";
      _eligibleSigners = [];
      _noLocalMember = false;
      _hasSignedByLocalWallet = false;
    });

    try {
      // 严格按照 MtxQueryServlet.java 逻辑构造 Query String
      final String address = _selectedAccount!.multiAddress;
      final queryUrl = "https://tx.qccio.com/v1/mtxquery?txHash=$hash&address=$address";

      LogObj.log("发起多签提案查询: $queryUrl");
      final response = await http.get(Uri.parse(queryUrl));

      if (response.statusCode == 200) {
        // 在 setState 内处理
        Map res=JsonUtil.strtoMap(response.body);
        LogObj.log("发起多签提案返回数据: $res");
        if (res['status'] == 'success') {
          var data = res['data'];
          // 1. 提取多签进度
          int current = data['currentCount'] ?? 0;
          int total = data['threshold'] ?? 0;

          // 2. 提取业务规则 (注意：日志里 ruleData.ruleJson 是 String，需要二次解析)
          Map<String, dynamic> ruleContent = {};
          if (data['ruleData'] != null && data['ruleData']['ruleJson'] != null) {
            ruleContent = jsonDecode(data['ruleData']['ruleJson']);
          }

          // 【本次新增，对应你的要求"签名选择"】照
          // MultiSigPledgeFollowSignWidget.dart 的套路：owners ∩ 本机钱包地址
          // ∩ 尚未签署，算出真正有资格对这一笔跟签的候选地址；本机没有任何
          // 成员地址、或成员地址已经全部签过了，都给出明确提示而不是硬塞一个
          // 不能签的地址。
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

          setState(() {
            nowaddress = selected;
            _eligibleSigners = eligible;
            _noLocalMember = memberLocalAddrs.isEmpty;
            _hasSignedByLocalWallet = memberLocalAddrs.isNotEmpty && eligible.isEmpty;
            // 查询成功这一刻把哈希冻结下来，跟 Java 的 apphash 局部变量一个道理——
            // 见上面 _queriedHash 声明处的说明。
            _queriedHash = hash;
            _proposalData = {
              'current': current,
              'total': total,
              'amount': ruleContent['amount'] ?? 0,
              'asset': ruleContent['assetId'] ?? "QCC",
              'target': ruleContent['address'] ?? "未知",
              // 【本次顺手修复】这里原来的兜底默认值写的是 "PledgeRule"——
              // 明显是从质押页面抄过来时忘了改，稳定币发行提案真正的 ruleName
              // 是 AssetType.AssetMeta.name("AssetMeta")，见
              // MultiSigStableCoinIssueWidget.dart 里 `rule.ruleName =
              // AssetType.AssetMeta.name`。只改了兜底默认值，不影响服务端
              // 真实返回值优先展示的逻辑。
              'ruleName': data['ruleData']['ruleName'] ?? AssetType.AssetMeta.name,
            };
          });
        }
      } else {
        Tools.showToast(context, "网络错误: ${response.statusCode}");
      }
    } catch (e) {
      LogObj.log("查询异常: $e");
      Tools.showToast(context, "查询服务异常");
    } finally {
      setState(() => _isQuerying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: Trans("多签稳定发行/增发"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 选择多签账户
            _buildSectionTitle("1. 选择目标多签地址"),
            _buildMultiSigSelector(),
            _buildMultiSigBalanceBar(),
            const SizedBox(height: 20),

            // 2. 输入提案 Hash
            _buildSectionTitle("2. 粘贴提案 TxHash"),
            _buildHashInput(),
            const SizedBox(height: 24),

            // 3. 内容预览
            _buildSectionTitle("3. 提案内容预览"),
            _buildProposalPreview(),
            const SizedBox(height: 24),

            // 4. 当前签署人信息
            _buildSectionTitle("4. 签署身份 (当前单签)"),
            _buildSignerSelector(),

            const SizedBox(height: 40),

            // 5. 提交按钮
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Trans(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildMultiSigSelector() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<MultiSigAccount>(
            value: _selectedAccount,
            isExpanded: true,
            hint: Trans("请选择多签账户"),
            items: _accounts.map((acc) => DropdownMenuItem(
              value: acc,
              child: Text(acc.multiAddress, style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (val) => setState(() {
              _selectedAccount = val;
              _proposalData = null; // 切换地址后清空旧查询
              // 切换多签账户后，上一次查询到的签署候选人、冻结的哈希都一并失效。
              nowaddress = "";
              _eligibleSigners = [];
              _noLocalMember = false;
              _hasSignedByLocalWallet = false;
              _queriedHash = "";
            }),
          ),
        ),
      ),
    );
  }

  /// 【本次新增，对应你的要求"余额显示"】多签托管账户本身的 QCC 余额——
  /// 和 MultiSigStableCoinIssueWidget.dart 的 _buildMultiSigBalanceBar() 同款。
  Widget _buildMultiSigBalanceBar() {
    if (_selectedAccount == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 4),
          Text("多签账户余额: ", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          QccActiveWallet(_selectedAccount!.multiAddress, "QCC", fontSize: 12, fontColor: Colors.black54),
        ],
      ),
    );
  }

  Widget _buildHashInput() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        title: TextField(
          controller: _hashController,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: "输入 64位 Hash",
            border: InputBorder.none,
          ),
        ),
        trailing: IconButton(
          icon: _isQuerying
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search, color: Colors.blue),
          onPressed: _fetchProposalDetails,
        ),
      ),
    );
  }

  Widget _buildProposalPreview() {
    if (_proposalData == null) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
        child: Trans("等待查询提案详情...", style: const TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    // 计算进度比例
    double progress = _proposalData!['current'] / _proposalData!['total'];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.purple, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 第一行：业务标题与金额
            /*Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Trans("稳定币资产发行j", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                Text(
                  "${(_proposalData!['amount'] / 1000000000).toStringAsFixed(2)} ${_proposalData!['asset']}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
            const Divider(height: 24),*/

            // 第二行：签署进度提示
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Trans("稳定币资产发行签署进度", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                Text(
                  "${_proposalData!['current']} / ${_proposalData!['total']}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 进度条可视化
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.purple.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
              ),
            ),

            const SizedBox(height: 16),

            // 补充信息：质押目标地址
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "稳定币assetId: ${_proposalData!['asset']}",
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }





  /// 【本次重写，对应你的要求"签名选择"+"余额显示"】原来的 _buildSignerCard()
  /// 只是把 initState() 里强制解包出来的当前活跃钱包地址原样显示，既不校验
  /// 这个地址是不是多签成员，也不能切换、不显示余额。照
  /// MultiSigPledgeFollowSignWidget.dart 的 _buildSignerSelector() 套路重写：
  /// 未查询到提案详情前不显示；本机没有成员地址/成员地址已全部签过时给出
  /// 明确提示；否则显示当前选中的签署地址(备注名+余额)，候选超过1个时可
  /// 点击切换。
  Widget _buildSignerSelector() {
    if (_proposalData == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(child: Text("请先查询提案详情，才能确定可用的签署地址。", style: TextStyle(fontSize: 12, color: Colors.grey))),
          ],
        ),
      );
    }
    if (_noLocalMember) {
      return _buildStatusBanner(icon: Icons.gpp_bad, color: Colors.red, text: "本机没有属于该多签账户成员的地址，无法签署此提案。");
    }
    if (_hasSignedByLocalWallet) {
      return _buildStatusBanner(icon: Icons.verified, color: Colors.green, text: "本机地址已完成签署，无需重复操作。");
    }

    final String? nick = _walletNames[nowaddress];
    final bool canSwitch = _eligibleSigners.length > 1;
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
                const Icon(Icons.security, size: 16, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(child: Trans("签署地址", style: const TextStyle(fontSize: 11, color: Colors.grey))),
                if (canSwitch) const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 4),
            if (nick != null) Text(nick, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
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

  /// 发起人有多个候选时，弹出底部选择列表——同 MultiSigPledgeFollowSignWidget.dart。
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
              Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Trans("选择签署地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
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
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.green : Colors.grey),
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

  bool _isSubmitting=false;

  /// 【本次重写，对应你的要求"更换签名方式"+"签名选择"】
  /// 1. 签名方式：原来手写 compute(_signRuleTask,...) ->
  ///    QccDataProtocol.encodeTransaction()——后者内部真正的签名调用整段被
  ///    注释掉，固定 signature:""，之前这个页面提交的跟签请求签名字段
  ///    自始至终是空字符串。现在改用 QccTxFlow.run()，内部走
  ///    SignUtil.instance.signAndEncode()。
  /// 2. 签名选择：原来固定用 QccObj.activeWallet!.address(强制解包，也没有
  ///    校验这个地址到底是不是多签成员/是否已签过)，现在改用查询阶段算出的
  ///    nowaddress(_computeEligibleProposers 同款逻辑，见 _fetchProposalDetails)。
  /// 密码框/loading 显示顺序、try/catch 兜底、失败提示都交给 QccTxFlow.run()
  /// 统一处理，不用在这个函数里再手写一遍。
  Future<void> _followstable() async {
    if (_selectedAccount == null) {
      Tools.showToast(context, "请选择多签账户");
      return;
    }
    if (nowaddress.isEmpty) {
      Tools.showToast(context, "请先选择签署地址");
      return;
    }
    if (_queriedHash.isEmpty) {
      Tools.showToast(context, "请先查询提案详情");
      return;
    }

    setState(() => _isSubmitting = true);
    LogObj.log("发起多签稳定币跟签 hash:$_queriedHash");
    LogObj.log("目标多签地址: ${_selectedAccount!.multiAddress}");
    LogObj.log("当前签署人: $nowaddress");

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        // 构建 RuleData 容器——跟签阶段沿用原文件既有的 ruleType/ruleName
        // 约定(与发行阶段一致，"AsseIdRule"/AssetMeta.name)，本次只换签名
        // 方式，不改动这两个字段的取值。
        // 【本次修正，对照 MuRuleUSDSAsset.java 发现的问题，见 _queriedHash
        // 声明处】ruleJson 改用查询成功时冻结下来的 _queriedHash，不再重新读
        // _hashController.text——避免提交时输入框内容和查询/预览时不一致。
        RuleData rule = RuleData();
        rule.assetId = "QCCRule";
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule";
        rule.ruleName = AssetType.AssetMeta.name;
        rule.ruleJson = _queriedHash;
        rule.ruleAppendJson = "";
        rule.finalizeId();
        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/mtxrule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      LogObj.log("✅ 多签稳定币跟签广播成功: ${resData['txHash'] ?? ''}");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => QccStableCoinSignSuccessWidget(responseData: resData)),
      );
    } else {
      LogObj.log("多签稳定币跟签异常: ${result.error}");
      Tools.showToast(context, "异常: ${result.error}");
    }
  }

  Widget _buildSubmitButton() {
    // 【本次新增】_proposalData 有值但本机没有可签署地址(_eligibleSigners
    // 为空——本机没有成员地址，或成员地址已全部签过)时，按钮也应保持禁用，
    // 避免点击后被 _followstable() 里的二次校验挡下、体验上却显示按钮可点。
    final bool canSubmit = _proposalData != null && _eligibleSigners.isNotEmpty && !_isSubmitting;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: canSubmit ? _followstable : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("确认并签署提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}