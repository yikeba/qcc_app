import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/procotol/QccTxFlow.dart';
import 'package:qcc_flutter/procotol/RuleData.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
// 这一个仍是同目录裸文件名相对引用——只要 WhitelistUpdateRule.dart 和本
// 文件放在同一个目录下，这一行永远正确，不受上面绝对路径推算影响。
import 'WhitelistUpdateRule.dart';

/// 资产白名单维护管理——单签版。
///
/// 【为什么白名单要单独立一个大类目录，不挂在"多签冻结/多签销毁"那几个
/// 二级菜单底下】按你的说明：白名单是 QCC 公链底层协议区别于其它公链的
/// 重要功能，目前支持 5000-10000 级白名单配置，未来要支持到亿级——量级和
/// 战略重要性都和"冻结单个地址""销毁一笔资产"这种一次性操作不是一个数量级，
/// 所以放在资产发行/资产管理的一堆二级菜单里容易被埋没，需要在
/// QccFinanceRuleListPage 顶层单独给一个"白名单管理"入口（对应新增的
/// WhitelistHubPage.dart）。
///
/// 【本页职责，对应你要求的"单签实现一个白名单维护管理"】
/// - 先取本机全部单签钱包地址 -> 只显示"这些地址自己发行过的资产"（不是
///   全网资产列表）-> 选择 ADD（加白）/ REMOVE（减白）-> 批量粘贴/输入
///   地址（多行文本框，每行一个地址，也支持逗号/空格分隔，自动去重）->
///   operator 固定为该资产的发行地址本身 -> 直接提交单签规则（POST
///   /v1/rule，不经过多签流程）。
/// - 依据 TxWhitelistFullSuiteTest.java 顶部注释核实：WhitelistUpdateRule
///   是纯单签模型，operator 和签名者一致即可立即生效，没有时间锁、没有
///   二次确认，Java 注释里明确提到"op 字段写错也会正常执行成功，协议层面
///   不会告诉你语义错了"——所以下面 ADD/REMOVE 的分段按钮做得很显眼，
///   而且提交前有一个二次确认弹窗，把"资产/操作类型/地址数量"完整复述
///   一遍，尽量补上协议本身没有的这层保护。
///
/// 【本轮修复，回应你的反馈】"MultiSigWhitelistProposalWidget 不能读取所有
/// 资产啊，qcc 未来可能数万个资产，你只能读取本地钱包地址涉及的资产，
/// 单签本地是否有单签地址资产发布信息"——原来这里是 fetchAllAssets() 拿到
/// 什么就全部扔进下拉框，现在改成：先读本机钱包地址集合，没有钱包直接不
/// 查资产；有钱包的话查回来立刻按"资产发行地址 ∈ 本机地址集合"过滤，只
/// 展示和本机相关的资产。具体见 _initialLoad() 里的详细说明。
///
/// 【依赖与假设，仍需要你核实】
/// a. 目前还没有按"该资产是否已开启白名单(isWhitelist)"过滤——因为我没有
///    拿到 QccAsset.dart 的真实字段定义，不确定这个模型上有没有
///    isWhitelist 这个布尔字段。如果有，在 _initialLoad() 过滤那一步加一个
///    a.isWhitelist==true 的条件即可。
/// b. "该地址当前是否已经在白名单内"目前无法查询展示——没有找到类似
///    /v1/assetFrozen 这种查询接口的 Java 源码（AssetFrozenContext.java
///    当时是你专门发我核实的）。如果链上有对应的白名单查询接口，请把它的
///    Context/Controller 源码发我，我可以照 QccFreezePage.dart 的
///    _checkFrozenStatus 套路加一个"批量地址逐一查询是否已在白名单"的功能。
/// c. 提交单签规则走的是 POST /v1/rule（和 TxWhitelistFullSuiteTest.java
///    里 RULE_URL 完全一致），不是 /v1/mtxrule——单签不需要多签流程。
/// d.【最重要，需要你确认】目前"只展示相关资产"仍然是靠一次全量
///    fetchAllAssets() 拉回来之后本地过滤实现的，没有找到"按发行地址查询
///    资产"的专属接口/方法。这解决了"页面上显示不相关资产"的正确性问题，
///    但没有解决"资产到数万级时，这一次全量请求本身"的规模问题。如果
///    QccAssetService.dart 已经有类似 fetchAssetsByOwner(address) 的方法，
///    或者后端有 /v1/asset?owner=xxx 这样的查询接口，请告诉我，我把这里
///    换成真正的按地址查询。
class QccWhitelistManagePage extends StatefulWidget {
  const QccWhitelistManagePage({super.key});

  @override
  State<QccWhitelistManagePage> createState() => _QccWhitelistManagePageState();
}

class _QccWhitelistManagePageState extends State<QccWhitelistManagePage> {
  // 【本轮重做，回应你的反馈】"MultiSigWhitelistProposalWidget 不能读取所有
  // 资产啊，qcc 未来可能数万个资产，你只能读取本地钱包地址涉及的资产"——
  // 单签这边同理：不应该把 fetchAllAssets() 拿到的全量资产列表直接扔进
  // 下拉框，只应该显示"本机已导入的单签钱包地址自己发行过的资产"。
  //
  // 做法：先拿本机全部单签钱包地址（QccObj.readWallets()），只有这个地址
  // 集合非空才去查资产；查回来之后立刻按 a.address ∈ 本机地址集合 过滤，
  // 不相关的资产根本不进 _assets、不出现在下拉框里。
  //
  // 【仍需你确认的问题，没有回避】目前没有找到"按 owner 地址查询资产"的
  // 专属接口/方法（QccAssetService.dart 源码我没有），所以这里事实上还是
  // 调了一次 fetchAllAssets() 全量拉取，只是拉回来之后立刻在本地过滤、
  // 只展示与本机地址相关的——这解决了"页面上不该显示的资产"这个正确性
  // 问题，但没有解决"未来数万级资产时，这一次全量请求本身流量/耗时"的
  // 问题。要彻底解决后者，需要后端提供一个"按地址查资产"的接口（类似
  // /v1/asset?owner=xxx 或 /v1/myAsset/{address}），麻烦告诉我是否已经有
  // 这样的接口，或者把对应的 Java Context 源码发我，我把这次的全量拉取
  // 换成真正的按地址查询。
  List<QccAsset> _assets = [];
  QccAsset? _selectedAsset;
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<String> _localWalletAddrs = [];
  bool _noLocalWallet = false;

  final _addressesController = TextEditingController();
  List<String> _parsedAddresses = [];

  String _op = WhitelistOp.add;

  Map<String, String> _walletNames = {};
  String nowaddress = "";

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      final names = await QccStorage.getAllWalletNames();
      final localAddrs = QccObj.readWallets().map((e) => e.address).toSet().toList();

      if (!mounted) return;

      if (localAddrs.isEmpty) {
        // 本机没有任何单签钱包，压根不用发起资产查询——省一次没有意义的
        // 全量网络请求。
        setState(() {
          _walletNames = names;
          _localWalletAddrs = [];
          _noLocalWallet = true;
          _isLoading = false;
        });
        return;
      }

      final localAddrSet = localAddrs.toSet();
      // 【见文件头部大段说明】仍是一次 fetchAllAssets()，但拿回来立刻按
      // 本机地址过滤——只展示"本机某个钱包地址自己发行"的资产。
      List<QccAsset> allAssets = await QccAssetService().fetchAllAssets();
      List<QccAsset> myAssets = allAssets.where((a) => localAddrSet.contains(a.address)).toList();

      if (!mounted) return;
      setState(() {
        _walletNames = names;
        _localWalletAddrs = localAddrs;
        _assets = myAssets;
        _isLoading = false;
        if (_assets.isNotEmpty) {
          _selectedAsset = _assets.first;
          // operator 就是该资产的发行地址本身（本机地址），不再像之前那样
          // 允许随便挑一个不相关的本机钱包当 operator。
          nowaddress = _selectedAsset!.address;
        }
      });
    } catch (e) {
      LogObj.log("加载白名单维护页失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 解析多行/逗号/空格混合分隔的地址批量输入，自动去重、去空白。
  void _parseAddresses(String raw) {
    final parts = raw
        .split(RegExp(r'[\s,，;；\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet() // 去重
        .toList();
    setState(() => _parsedAddresses = parts);
  }

  Future<bool> _confirmDialog() async {
    final actionText = _op == WhitelistOp.add ? "加入白名单" : "移出白名单";
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: _op == WhitelistOp.add ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Trans("二次确认"),
        ]),
        content: Text(
          "资产: ${_selectedAsset?.assetId}\n"
              "操作: $actionText\n"
              "地址数量: ${_parsedAddresses.length}\n\n"
              "该操作单签直接生效，没有时间锁、没有多签复核，请确认无误后再提交。",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("确认提交")),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _handleSubmit() async {
    if (_selectedAsset == null) return;
    if (_parsedAddresses.isEmpty) {
      Tools.showToast(context, Tools.getTra("请至少输入一个地址"));
      return;
    }
    if (nowaddress.isEmpty) {
      Tools.showToast(context, Tools.getTra("请选择签署地址"));
      return;
    }

    final confirmed = await _confirmDialog();
    if (!confirmed) return;

    setState(() => _isSubmitting = true);

    final result = await QccTxFlow.run(
      context: context,
      address: nowaddress,
      buildPayload: (wallet) async {
        WhitelistUpdateRule whitelistRule = WhitelistUpdateRule(
          assetId: _selectedAsset!.assetId,
          operator: wallet.address,
          op: _op,
          addresses: _parsedAddresses,
        );

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule";
        rule.ruleName = kWhitelistUpdateRuleName;
        rule.ruleJson = jsonEncode(whitelistRule.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();

        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      // 单签直接提交 /v1/rule，和 TxWhitelistFullSuiteTest.java 的
      // RULE_URL 一致，不走 /v1/mtxrule 多签流程。
      submitUrl: "https://tx.qccio.com/v1/rule",
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.cancelled) return;

    if (result.success) {
      Tools.showToast(context, "✅ 白名单${_op == WhitelistOp.add ? "加白" : "减白"}已提交");
      setState(() {
        _addressesController.clear();
        _parsedAddresses = [];
      });
    } else {
      LogObj.log("白名单维护提交异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: Trans("白名单维护管理(单签)"), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _noLocalWallet
          ? _buildEmptyState(Icons.account_balance_wallet_outlined, "本机未导入任何钱包，无法进行白名单维护。")
          : _assets.isEmpty
          ? _buildEmptyState(Icons.token_outlined, "本机导入的地址暂未发行任何资产。\n只有资产的发行地址（owner）才能维护它的白名单。")
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSectionCard("1. 选择资产 (仅本机地址发行的资产)", Icons.token_outlined, _buildAssetDropdown()),
            const SizedBox(height: 16),
            _buildSectionCard("2. 操作类型", Icons.rule_folder_outlined, _buildOpSelector()),
            const SizedBox(height: 16),
            _buildSectionCard("3. 批量地址 (每行一个，或用逗号/空格分隔)", Icons.list_alt_outlined, _buildAddressInput()),
            const SizedBox(height: 16),
            _buildOperatorInfo(),
            const SizedBox(height: 40),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Trans(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]),
          const Divider(height: 24, thickness: 0.5),
          child,
        ],
      ),
    );
  }

  Widget _buildAssetDropdown() {
    return DropdownButtonFormField<QccAsset>(
      value: _selectedAsset,
      isExpanded: true,
      items: _assets.map((a) => DropdownMenuItem(value: a, child: Text("${a.assetId} (Precision: ${a.precision})"))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() {
            _selectedAsset = val;
            // operator 固定就是这个资产的发行地址（保证在本机钱包里，
            // 因为 _assets 本来就是按本机地址过滤出来的）。
            nowaddress = val.address;
          });
        }
      },
      decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    );
  }

  Widget _buildOpSelector() {
    return SegmentedButton<String>(
      segments: <ButtonSegment<String>>[
        ButtonSegment<String>(value: WhitelistOp.add, label: Trans("加入白名单"), icon: const Icon(Icons.person_add_alt_1_outlined, size: 18)),
        ButtonSegment<String>(value: WhitelistOp.remove, label: Trans("移出白名单"), icon: const Icon(Icons.person_remove_outlined, size: 18)),
      ],
      selected: <String>{_op},
      onSelectionChanged: (s) => setState(() => _op = s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: _op == WhitelistOp.add ? Colors.green : Colors.redAccent,
        selectedForegroundColor: Colors.white,
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildAddressInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _addressesController,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: "Q1...\nQ2...\n(每行一个地址，也可以逗号/空格分隔粘贴)",
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste, size: 18),
              onPressed: () async {
                var data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  _addressesController.text = data!.text!;
                  _parseAddresses(data.text!);
                }
              },
            ),
          ),
          onChanged: _parseAddresses,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.tag, size: 14, color: Colors.blueGrey.shade400),
            const SizedBox(width: 4),
            Text(
              "已解析地址: ${_parsedAddresses.length} 个",
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            // 【提醒，见文件头部第5点】目前批量提交是一次性整段 JSON，未来
            // 亿级白名单大概率需要分片/分页接口，这里先标个提示，避免用户
            // 真的一次粘贴几十万个地址导致请求体过大失败。
            if (_parsedAddresses.length > 2000)
              Text("数量较大，如提交失败请分批操作", style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
          ],
        ),
      ],
    );
  }

  /// 【简化，见 _initialLoad 说明】operator 不再允许随便挑一个不相关的
  /// 本机钱包——它就是当前选中资产的发行地址本身，所以这里不再是可点击
  /// 切换的选择器，只是一张只读信息卡。
  Widget _buildOperatorInfo() {
    String? nick = _walletNames[nowaddress];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin, size: 16, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: "${Tools.getTra("签署地址(该资产发行地址)")}: ",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    children: [
                      TextSpan(
                        text: nowaddress.isEmpty ? Tools.getTra("未选择") : nowaddress,
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (nick != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24),
              child: Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
            ),
          if (nowaddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 24),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 4),
                  Text("QCC 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  QccActiveWallet(nowaddress, "QCC", fontSize: 12, fontColor: Colors.black87),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    bool active = !_isSubmitting && nowaddress.isNotEmpty && _selectedAsset != null && _parsedAddresses.isNotEmpty;
    Color themeColor = _op == WhitelistOp.add ? Colors.green : Colors.redAccent;
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: active ? LinearGradient(colors: [themeColor, themeColor.withOpacity(0.8)]) : null,
        color: active ? null : Colors.grey.shade300,
      ),
      child: ElevatedButton(
        onPressed: active ? _handleSubmit : null,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans(_op == WhitelistOp.add ? "确认提交加白" : "确认提交减白", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}