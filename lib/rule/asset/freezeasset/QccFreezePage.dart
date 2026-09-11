import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../home/QccExplorerService.dart';
import '../../../procotol/QccTxFlow.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/Tools.dart';
import '../../../utile/LogObj.dart';
import '../../../views/myasset/QccAsset.dart';
import '../../../views/myasset/QccAssetService.dart';
import '../../../views/setting/AppTranslator.dart';
import 'AssetFreezeRule.dart'; // 引用你定义的冻结规则模型

class QccFreezePage extends StatefulWidget {
  const QccFreezePage({super.key});

  @override
  State<QccFreezePage> createState() => _QccAssetFreezePageState();
}

enum FreezeAction { freeze, unfreeze }

/// 单签资产冻结/解冻。
///
/// 本轮按你的要求优化：
/// 1. 资产信息展示——选中资产后显示资产名称、发行地址、是否支持冻结
///    (freezable)。freezable 是发行时一次性声明的开关，QccAsset 本地模型
///    是否带这个字段不确定，所以额外查了一次 /v1/asset 拿权威数据（和
///    MultiSigAssetMintWidget.dart 里处理 mintable 同一个思路）。如果某个
///    资产 freezable=false，直接在这里提示并禁用提交——不可能冻结/解冻，
///    交给公链拒绝还不如提前说明白。
/// 2. 目标地址冻结状态查询——输入目标地址后自动查一次该地址在当前选中
///    资产下是不是已经处于冻结状态，供"要不要解冻"做参考。
///
/// 【/v1/assetFrozen 接口，已按你贴的 AssetFrozenContext.java 源码核实】
/// 请求是 GET /v1/assetFrozen?address={address}&asset={assetId}——注意
/// 资产参数名是 asset，不是 assetId。返回结构是
/// {ok:true/false, kind:"AssetFrozenStatus", data:{address, assetId,
/// status:"FROZEN"|"NORMAL"}}（失败时是 {ok:false, error:"..."}），和这个
/// 项目里其它接口常见的 {status:"success", data:...} 信封不是一回事，
/// _checkFrozenStatus() 已经按这个真实结构改过来了。
///
/// 【顺带修复】原来的签名提交走 compute + QccDataProtocol.encodeTransaction
/// （signature 恒为空，本 session 里其它页面都踩过的同一个坑），现在统一
/// 改走 QccTxFlow.run()。
class _QccAssetFreezePageState extends State<QccFreezePage> {
  final _formKey = GlobalKey<FormState>();
  final _targetAddressController = TextEditingController();

  List<QccAsset> _myIssuedAssets = [];
  QccAsset? _selectedAsset;
  // 【新增】assetId(大写) -> freezable，来自 /v1/asset 详情。
  Map<String, bool> _freezableByAssetId = {};

  bool _isLoading = true;
  FreezeAction _currentAction = FreezeAction.freeze;

  // 【新增】目标地址在当前选中资产下的冻结状态：null=未知/未查询，
  // true=已冻结，false=未冻结。
  bool? _targetFrozen;
  bool _isCheckingFrozen = false;

  @override
  void initState() {
    super.initState();
    _loadMyAssets();
  }

  // 1. 加载当前钱包发行的资产 + 每个资产的 freezable 开关
  Future<void> _loadMyAssets() async {
    try {
      String myAddr = QccObj.activeWallet!.address;
      List<QccAsset> all = await QccAssetService().fetchAllAssets();

      // 过滤：必须是当前单签钱包(Q开头)发行的资产
      List<QccAsset> filtered = all.where((a) =>
      a.address== myAddr && a.assetId.toUpperCase() != "QCC"
      ).toList();

      // 【新增】批量查一次 /v1/asset，拿到每个资产权威的 freezable 状态，
      // 不依赖 QccAssetService 本地模型是否带这个字段。
      Map<String, bool> freezableMap = {};
      try {
        final resp = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
        if (resp.statusCode == 200) {
          final res = jsonDecode(resp.body);
          List raw = jsonDecode(res['data']);
          for (final item in raw) {
            final aid = item['assetId']?.toString();
            if (aid != null) {
              freezableMap[aid.toUpperCase()] = item['freezable'] == true;
            }
          }
        }
      } catch (e) {
        LogObj.log("查询资产 freezable 状态失败: $e");
      }

      if (!mounted) return;
      setState(() {
        _myIssuedAssets = filtered;
        _freezableByAssetId = freezableMap;
        if (_myIssuedAssets.isNotEmpty) {
          _selectedAsset = _myIssuedAssets.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      LogObj.log("加载资产失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 【新增】查询目标地址在当前选中资产下是否已处于冻结状态。
  Future<void> _checkFrozenStatus(String address) async {
    if (address.isEmpty || _selectedAsset == null) {
      if (mounted) setState(() => _targetFrozen = null);
      return;
    }
    setState(() {
      _isCheckingFrozen = true;
      _targetFrozen = null;
    });
    try {
      final assetId = _selectedAsset!.assetId;
      // 【已按 AssetFrozenContext.java 源码核实】参数名是 asset，不是
      // assetId；返回信封是 {ok, kind, data:{...,status:"FROZEN"|"NORMAL"}}，
      // 不是这个项目里常见的 {status:"success", data}。
      final resp = await http.get(Uri.parse(
          "${QccExplorerService.baseUrl}/v1/assetFrozen?address=$address&asset=$assetId"));
      if (resp.statusCode == 200) {
        final res = jsonDecode(resp.body);
        if (res['ok'] == true) {
          final data = res['data'];
          final String? status = data is Map ? data['status']?.toString() : null;
          if (mounted) setState(() => _targetFrozen = status == 'FROZEN');
        } else {
          LogObj.log("查询地址冻结状态失败: ${res['error']}");
          if (mounted) setState(() => _targetFrozen = null);
        }
      }
    } catch (e) {
      LogObj.log("查询地址冻结状态失败: $e");
      if (mounted) setState(() => _targetFrozen = null);
    } finally {
      if (mounted) setState(() => _isCheckingFrozen = false);
    }
  }

  bool get _selectedFreezable {
    if (_selectedAsset == null) return false;
    return _freezableByAssetId[_selectedAsset!.assetId.toUpperCase()] ?? true;
    // 查不到时默认 true（不阻塞），毕竟这是本地补充查询，查询失败不该
    // 反过来锁死原本能用的功能——只有明确查到 false 才提示/禁用。
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = _currentAction == FreezeAction.freeze ? Colors.blueGrey.shade800 : Colors.green.shade700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("单签资产冻结"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myIssuedAssets.isEmpty
          ? _buildEmptyUI()
          : _buildMainForm(themeColor),
    );
  }

  Widget _buildEmptyUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_person_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Trans("未找到您发行的资产", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Trans("只有发行人才能冻结/解冻资产", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMainForm(Color themeColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 操作切换：冻结/解冻
            _buildActionToggle(),
            const SizedBox(height: 25),

            // 资产选择
            Trans("选择控制资产", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),
            _buildAssetPicker(),

            // 【新增】资产信息卡：名称/发行地址/是否支持冻结
            _buildAssetInfoCard(),

            const SizedBox(height: 25),

            // 目标地址
            Trans("目标地址 (Target)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),
            _buildTargetInput(),
            // 【新增】目标地址冻结状态查询结果
            _buildFrozenStatusRow(),
            // 【新增】按你的要求，输入目标地址后同时显示该地址持有的
            // 当前资产余额——冻结前先看一眼影响多大，解冻前也能确认
            // 地址上确实还有这个资产。
            _buildTargetBalanceRow(),
            // 【新增】解冻时如果查到"当前未冻结"，给一个提示（不阻断提交）
            _buildUnfreezeAdvisory(),

            const SizedBox(height: 15),
            _buildWarningBox(),

            const SizedBox(height: 50),

            // 提交按钮
            _buildSubmitButton(themeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildActionToggle() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: SegmentedButton<FreezeAction>(
        segments: [
          ButtonSegment(value: FreezeAction.freeze, label: Trans("执行冻结"), icon: const Icon(Icons.ac_unit)),
          ButtonSegment(value: FreezeAction.unfreeze, label: Trans("执行解冻"), icon: const Icon(Icons.wb_sunny_outlined)),
        ],
        selected: {_currentAction},
        onSelectionChanged: (set) => setState(() => _currentAction = set.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: _currentAction == FreezeAction.freeze ? Colors.blueGrey.shade800 : Colors.green,
          selectedForegroundColor: Colors.white,
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildAssetPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<QccAsset>(
          value: _selectedAsset,
          isExpanded: true,
          items: _myIssuedAssets.map((a) => DropdownMenuItem(value: a, child: Text(a.assetId, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() => _selectedAsset = val);
            // 换资产后，之前查到的目标地址冻结状态是针对旧资产的，需要
            // 重新查一次。
            _checkFrozenStatus(_targetAddressController.text.trim());
          },
        ),
      ),
    );
  }

  /// 【新增】资产信息卡：资产名称 / 发行地址 / 是否支持冻结。
  Widget _buildAssetInfoCard() {
    if (_selectedAsset == null) return const SizedBox.shrink();
    bool? freezable = _freezableByAssetId[_selectedAsset!.assetId.toUpperCase()];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow("资产名称", _selectedAsset!.assetId),
          const SizedBox(height: 6),
          _infoRow("发行地址", _selectedAsset!.address, isAddr: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Trans("是否支持冻结: ", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              Icon(
                freezable == true ? Icons.check_circle : Icons.cancel,
                size: 14,
                color: freezable == true ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                freezable == null ? "未知(查询失败)" : (freezable ? "支持" : "不支持"),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: freezable == true ? Colors.green : Colors.red),
              ),
            ],
          ),
          if (freezable == false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "该资产发行时 freezable=false，无法冻结/解冻（此开关只能在发行时一次性声明，不能事后补授权）",
                style: TextStyle(fontSize: 11, color: Colors.red.shade300),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isAddr = false}) {
    String display = value;
    if (isAddr && value.length > 20) {
      display = "${value.substring(0, 10)}...${value.substring(value.length - 8)}";
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
        Text(display, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildTargetInput() {
    return TextFormField(
      controller: _targetAddressController,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      decoration: InputDecoration(
        hintText: "请输入对方 Q 地址",
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.person_pin_rounded),
        suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () async {
          // 这里可以调用你的 QccScanner
        }),
      ),
      // 【新增】地址变动时自动查一次冻结状态。
      onChanged: (v) => _checkFrozenStatus(v.trim()),
      validator: (v) => (v == null || v.isEmpty) ? "地址不能为空" : null,
    );
  }

  /// 【新增】目标地址冻结状态查询结果展示。
  Widget _buildFrozenStatusRow() {
    if (_targetAddressController.text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (_isCheckingFrozen)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(
              _targetFrozen == null ? Icons.help_outline : (_targetFrozen! ? Icons.ac_unit : Icons.wb_sunny_outlined),
              size: 14,
              color: _targetFrozen == null ? Colors.grey : (_targetFrozen! ? Colors.blueGrey : Colors.green),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _isCheckingFrozen
                  ? "正在查询该地址冻结状态..."
                  : (_targetFrozen == null
                  ? "该地址当前冻结状态未知（查询失败或接口无返回）"
                  : (_targetFrozen! ? "该地址在此资产下当前已处于冻结状态" : "该地址在此资产下当前未被冻结")),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  /// 【新增】目标地址当前持有的选中资产余额——复用 QccActiveWallet 组件，
  /// 冻结前先看一眼影响多大，解冻前也能确认地址上确实还有这个资产。
  Widget _buildTargetBalanceRow() {
    final target = _targetAddressController.text.trim();
    if (target.isEmpty || _selectedAsset == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 12, color: Colors.blueGrey),
          const SizedBox(width: 4),
          Text("该地址 ${_selectedAsset!.assetId} 余额: ", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          QccActiveWallet(target, _selectedAsset!.assetId, fontSize: 12, fontColor: Colors.black87),
        ],
      ),
    );
  }

  /// 【新增】解冻场景下，如果查到目标地址当前其实并未被冻结，给一个
  /// 提示——不阻断提交，因为查询接口的真实返回结构我还没法百分百确认。
  Widget _buildUnfreezeAdvisory() {
    if (_currentAction != FreezeAction.unfreeze) return const SizedBox.shrink();
    if (_targetFrozen != false) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "查询结果显示该地址当前未处于冻结状态，解冻可能没有意义，请确认后再提交",
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Trans("注意：单签规则交易一旦广播成功将立即生效。", style: const TextStyle(fontSize: 11, color: Colors.orange))),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(Color themeColor) {
    bool active = _selectedFreezable;
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: active ? _executeFreezeRule : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: themeColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        child: Trans("确认并进行量子签名", style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // 执行单签冻结逻辑——统一走 QccTxFlow.run()，不再手抄
  // "密码->loading->还原钱包->签名->提交"，签名也不再走已确认损坏的
  // compute + QccDataProtocol.encodeTransaction（signature 恒为空）。
  Future<void> _executeFreezeRule() async {
    if (!_formKey.currentState!.validate() || _selectedAsset == null) return;
    if (!_selectedFreezable) {
      Tools.showToast(context, "该资产 freezable=false，无法冻结/解冻");
      return;
    }

    String target = _targetAddressController.text.trim();
    String myAddress = QccObj.activeWallet!.address;

    final result = await QccTxFlow.run(
      context: context,
      address: myAddress,
      buildPayload: (wallet) async {
        AssetFreezeRule freezeRule = AssetFreezeRule(
          assetId: _selectedAsset!.assetId,
          targetAddress: target,
          freeze: _currentAction == FreezeAction.freeze,
          expiry: 0, // 永久
        );
        LogObj.log("发起冻结的规则参数:${freezeRule.toJson()}");

        RuleData rule = RuleData();
        rule.from = wallet.address;
        rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
        rule.ruleName = "AssetFreezeRule"; // 必须这个规则名，调用 java class name
        rule.ruleJson = jsonEncode(freezeRule.toJson());
        rule.ruleAppendJson = "";
        rule.finalizeId();

        return QccSignPayload(toSign: rule.toSign(), payloadJson: jsonEncode(rule.toJson()));
      },
      submitUrl: "https://tx.qccio.com/v1/rule",
    );

    if (!mounted) return;

    if (result.cancelled) return;

    if (result.success) {
      final resData = result.data!;
      String finalHash = resData['txHash']?.toString() ?? resData['id']?.toString() ?? "";
      await AssetFreezeStorage.saveRecord(FreezeRecord(
        assetId: _selectedAsset!.assetId,
        targetAddress: target,
        isFrozen: _currentAction == FreezeAction.freeze,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        txHash: finalHash,
      ));
      Tools.showToast(context, "✅ 操作成功生效");
      if (mounted) Navigator.pop(context); // 回到资产页
    } else {
      LogObj.log("单签冻结异常: ${result.error}");
      Tools.showToast(context, "错误: ${result.error}");
    }
  }
}