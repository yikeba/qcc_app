import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/views/myasset/QccAsset.dart';
import 'package:qcc_flutter/views/myasset/QccAssetService.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
// 【修复，重要】原来这里直接调 QccDataProtocol.encodeTransaction（内部签名
// 逻辑被注释掉，signature 恒为 ""），这正是你看到的
// {"status":"rejected","msg":"Invalid Signature"} 的原因，和其它资产
// 发行/增发 Widget 是同一个坑。改成统一走 SignUtil。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/Tools.dart';
import '../../../utile/QccObj.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../core/AssetBurnRule.dart';
import '../core/AssetMeta.dart';
import 'AssetBurnSuccessPage.dart';

class QccBurnPage extends StatefulWidget {
  const QccBurnPage({super.key});

  @override
  State<QccBurnPage> createState() => _QccBurnPageState();
}

class _QccBurnPageState extends State<QccBurnPage> {
  late QccWallet? _currentWallet;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _targetAddressController = TextEditingController();
  final TextEditingController _legalBasisController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();

  String _selectedAsset = ""; // 当前选中的资产ID
  List<QccAsset> _burnableAssets = []; // 过滤后的可销毁资产列表
  bool _isLoadingAssets = true;
  bool _isSubmitting = false;

  // 【新增】销毁类型：true=自烧（销毁发行方自己余额），false=销毁第三方
  // （已冻结满12个月的）地址余额，用于合规经营场景。
  bool _burnSelf = true;

  @override
  void initState() {
    super.initState();
    _currentWallet = QccObj.activeWallet;
    _loadAndFilterAssets();
  }

  // 1. 启动加载并过滤资产
  Future<void> _loadAndFilterAssets() async {
    try {
      List<QccAsset> allAssets = await QccAssetService().fetchAllAssets();
      setState(() {
        // 过滤规则：1. 不是 QCC 主币；2. 当前钱包地址是该资产的发行者 (creator/issuer)
        _burnableAssets = allAssets.where((asset) {
          bool isNotQcc = asset.assetId.toUpperCase() != "QCC";
          // 匹配资产的发行人地址与当前钱包地址
          bool isIssuer = asset.address == _currentWallet?.address;
          return isNotQcc && isIssuer;
        }).toList();

        if (_burnableAssets.isNotEmpty) {
          _selectedAsset = _burnableAssets.first.assetId;
        }
        _isLoadingAssets = false;
      });
    } catch (e) {
      LogObj.log("加载资产失败: $e");
      setState(() => _isLoadingAssets = false);
    }
  }

  /// 当前操作实际生效的目标地址：自烧=发行方自己；第三方=手动输入的地址。
  String get _effectiveTargetAddress =>
      _burnSelf ? (_currentWallet?.address ?? "") : _targetAddressController.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Trans("单签资产销毁", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoadingAssets
          ? const Center(child: CircularProgressIndicator())
          : _burnableAssets.isEmpty
          ? _buildEmptyState()
          : _buildMainBody(),
    );
  }

  // 当没有可销毁资产（非发行人）时的界面
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_person_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Trans("暂无可销毁资产", style: TextStyle(color: Colors.grey.shade600)),
          Trans("仅资产发行人可执行此操作", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMainBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Trans("资产发行人（当前钱包）", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          _buildSourceCard(_currentWallet),

          const SizedBox(height: 25),
          // 【新增】销毁类型切换
          Trans("销毁类型", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          _buildBurnTypeSelector(),

          const SizedBox(height: 25),
          if (_burnSelf) ...[
            Trans("销毁目标地址（发行方自己）", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            _buildTargetAddressReadonly(_currentWallet?.address ?? ""),
            const SizedBox(height: 20),
            _buildMemoInput(),
          ] else ...[
            Trans("销毁目标地址（第三方，需已连续冻结满12个月）", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            _buildTargetAddressInput(),
            const SizedBox(height: 20),
            _buildLegalBasisInput(),
          ],

          const SizedBox(height: 25),
          // 2. 资产下拉选择
          Trans("选择要销毁的资产", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedAsset,
                isExpanded: true,
                items: _burnableAssets.map((asset) {
                  return DropdownMenuItem(
                    value: asset.assetId,
                    child: Text(asset.assetId, style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedAsset = val!),
              ),
            ),
          ),

          const SizedBox(height: 25),
          // 3. 销毁金额输入
          Trans("销毁金额", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "0.00",
                    border: InputBorder.none,
                    suffixText: _selectedAsset,
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Trans(_burnSelf ? "可用余额:" : "目标地址余额:", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    _effectiveTargetAddress.isEmpty
                        ? const Text("--", style: TextStyle(fontSize: 12, color: Colors.grey))
                        : QccActiveWallet(_effectiveTargetAddress, _selectedAsset, fontSize: 12, fontColor: Colors.black54),
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 50),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _performBurn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 3,
              ),
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Trans("确认销毁资产", style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// 【新增】自烧 / 第三方地址销毁 切换器
  Widget _buildBurnTypeSelector() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: _buildBurnTypeOption(
              label: "自烧（销毁自己余额）",
              selected: _burnSelf,
              onTap: () => setState(() => _burnSelf = true),
            ),
          ),
          Expanded(
            child: _buildBurnTypeOption(
              label: "销毁第三方地址（合规）",
              selected: !_burnSelf,
              onTap: () => setState(() => _burnSelf = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBurnTypeOption({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade900 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetAddressReadonly(String addr) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(child: Text(addr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  /// 【新增】第三方目标地址输入框
  Widget _buildTargetAddressInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: _targetAddressController,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        decoration: const InputDecoration(
          hintText: "请输入已冻结满12个月的第三方地址",
          hintStyle: TextStyle(fontSize: 12),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: Icon(Icons.ac_unit, size: 18, color: Colors.blueAccent),
        ),
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  /// 【新增】合规依据输入框——对应 Java AssetBurnRule.legalBasis，销毁
  /// 第三方地址时必填。
  Widget _buildLegalBasisInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: _legalBasisController,
        maxLines: 3,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: Tools.getTra("合规依据 (必填)"),
          hintText: "例如：依据XX监管要求/司法文书对已冻结地址执行强制销毁",
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
          counterStyle: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  /// 【新增】自烧场景的可选备注——对应 Java AssetBurnRule.memo。
  Widget _buildMemoInput() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: _memoController,
        maxLines: 2,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: Tools.getTra("备注 (可选)"),
          hintText: "例如：季度存量回购销毁",
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
          counterStyle: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  // 构建钱包卡片
  Widget _buildSourceCard(wallet) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.grey.shade900, Colors.grey.shade700]),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: Colors.white24, child: Icon(Icons.account_balance_wallet, color: Colors.white)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wallet?.address ?? "",
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Trans("身份验证：资产发行人", style: const TextStyle(color: Colors.greenAccent, fontSize: 10)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _performBurn() async {
    String amountStr = _amountController.text.trim();
    if (amountStr.isEmpty || double.tryParse(amountStr) == 0) {
      Tools.showToast(context, "请输入有效的销毁金额");
      return;
    }

    String targetAddr = _effectiveTargetAddress;
    if (targetAddr.isEmpty) {
      Tools.showToast(context, _burnSelf ? "未找到当前钱包地址" : "请输入要销毁的第三方目标地址");
      return;
    }
    if (!_burnSelf && _legalBasisController.text.trim().isEmpty) {
      Tools.showToast(context, "销毁第三方地址资产必须填写合规依据说明");
      return;
    }

    // 再次确认弹窗
    bool confirm = await _showConfirmDialog(targetAddr);
    if (!confirm) return;

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    setState(() => _isSubmitting = true);
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      // 1. 还原
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, _currentWallet!.address, password);
      if (wallet == null || wallet.address != _currentWallet!.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // 2. 构建 AssetBurnRule（对标 Java AssetBurnRule）
      statusNotifier.value = TxStep.building;
      int amountInt = QccAssetService().getAmountRaw(_selectedAsset, amountStr);

      final burnRule = AssetBurnRule(
        assetId: _selectedAsset,
        targetAddress: targetAddr,
        amount: amountInt,
        legalBasis: _burnSelf ? null : _legalBasisController.text.trim(),
        memo: _burnSelf
            ? (_memoController.text.trim().isEmpty ? null : _memoController.text.trim())
            : null,
      );

      // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain/assetId。
      RuleData rule = RuleData();
      rule.from = wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      rule.ruleName = AssetType.AssetBurnRule.name; // "AssetBurnRule"，对齐 Java 字面量
      rule.ruleJson = jsonEncode(burnRule.toJson());
      // 对应 Java：ruleAppendJson = ""，必须显式写入——toSign() 的签名原文
      // 也包含这个字段。
      rule.ruleAppendJson = "";
      rule.finalizeId();

      // 4. 签名——统一走 SignUtil.signAndEncode()，不再是空签名。
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rule.toSign(),
        payloadJson: jsonEncode(rule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 提交到规则接口 /v1/rule（不再是 /v1/txm 转账接口）
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("销毁资产返回: ${response.body}");

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          resData['ruleName'] = AssetType.AssetBurnRule.name;
          // 标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          Tools.showToast(context, "✅ 销毁规则已广播成功");
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(
              builder: (context) => AssetBurnSuccessPage(ruleData: resData),
            ));
          }
        } else {
          // 【重要】第三方地址未满12个月冻结、或该资产 burnable=false 等业务
          // 拒绝场景，都会落到这里——把公链返回的原始 msg 原样展示，不做
          // 二次加工，方便定位具体是哪条协议规则没满足。
          LogObj.log("销毁资产错误非200: ${response.body}");
          throw resData['msg'] ?? "公链拒绝了该销毁请求";
        }
      } else {
        LogObj.log("销毁资产错误非200: ${response.body}");
        Tools.showToast(context, "网络异常: ${response.statusCode}");
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("销毁资产错误: $e");
      Tools.showToast(context, "销毁失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _showConfirmDialog(String targetAddr) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("极高风险操作"),
        content: Text(_burnSelf
            ? "您确定要永久销毁自己账户内的这些资产吗？此操作不可撤销，资产将从链上总量中扣除。"
            : "您确定要对第三方地址 $targetAddr 执行合规销毁吗？此操作要求该地址已连续冻结满12个月，否则会被公链拒绝；操作不可撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Trans("取消")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Trans("确定销毁", style: const TextStyle(color: Colors.red))
          ),
        ],
      ),
    ) ?? false;
  }
}