import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// 原来是 import 'dart:developer' as LogObj —— 名字一样，但日志进的是
// DevTools，不进工程自己的 LogObj，真机上看不到。换成工程的 LogObj。
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';
import 'package:qcc_flutter/home/QccTxConfirmDialog.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/rule/asset/AssetIssueSuccessPage.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../utile/QccObj.dart';
// 【修复，重要】原来这里直接调 QccDataProtocol.encodeTransaction，但那个
// 方法内部的签名逻辑是被注释掉的（signature 恒为 ""）——也就是说这个页面
// 之前提交上去的资产发行交易，签名字段实际上是空的，这正是"Invalid
// Signature"被拒的原因，和之前六个用户规则 Widget、多签创建/追加页面是
// 同一个坑。改成统一走 SignUtil，不再需要直接 import QccDataProtocol.dart。
import '../../../qccwallet/SignUtil.dart';
// 【新增】发行地址余额展示——直接复用项目里已经验证好的 QccActiveWallet，
// 和 DeveloperRuleWidget.dart 展示奖励池余额、MultiSigStableCoinIssueWidget.dart
// 展示多签账户余额是同一套组件，内部走标准 /v1/balance/{address} 接口。
import '../../../qccwallet/QccActiveWallet.dart';
// 【新增】资产 ID 查重——和 MultiSigStableCoinIssueWidget.dart 的
// _checkAssetId 是同一个查询接口（GET /v1/asset，本地按 assetId 过滤）。
import '../../../home/QccExplorerService.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../AssetFileStorage.dart';
import '../core/AssetMeta.dart';
import 'AssetIdSecurity.dart';
class SingleSigTokenIssueWidget extends StatefulWidget {
  const SingleSigTokenIssueWidget({super.key});

  @override
  State<SingleSigTokenIssueWidget> createState() => _SingleSigTokenIssueWidgetState();
}

class _SingleSigTokenIssueWidgetState extends State<SingleSigTokenIssueWidget> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _supplyController = TextEditingController();
  final _precisionController = TextEditingController(text: "9");

  bool _mintable = true;
  bool _freezable = true;
  // 【新增】对应 AssetMeta.java 的 burnable 字段——发行时一次性声明，默认
  // 不开启，事后无法追溯补授权，所以发行表单必须让用户在这里就做选择。
  bool _burnable = false;
  bool _isSubmitting = false;

  // 【新增】发行地址可选——不再写死当前活跃钱包，允许从本机已导入的
  // 钱包里挑一个作为发行源。
  List<QccWallet> _localWallets = [];
  String _selectedAddress = "";
  Map<String, String> _walletNames = {};
  bool _isLoadingWallets = true;

  // 【新增】资产 ID 查重状态——命名和判断逻辑对齐
  // MultiSigStableCoinIssueWidget.dart 的 _isAssetIdAvailable/_isCheckingAsset。
  bool _isAssetIdAvailable = true;
  bool _isCheckingAsset = false;

  // 查重防抖 + 序号：原来每敲一个字就拉一次 /v1/asset 全量列表，且响应
  // 乱序时，旧输入的结果可能覆盖新输入的结果（显示"可用"其实已被占用）。
  Timer? _checkDebounce;
  int _checkSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  @override
  void dispose() {
    _checkDebounce?.cancel();
    _idController.dispose();
    _supplyController.dispose();
    _precisionController.dispose();
    super.dispose();
  }

  void _onAssetIdChanged(String v) {
    _checkDebounce?.cancel();
    final id = v.trim();
    // 格式不合法就不去查重：查也没意义，链上反正会拒
    if (AssetIdSecurity.explain(id) != null) {
      _checkSeq++; // 作废在途的查重请求
      if (_isCheckingAsset || !_isAssetIdAvailable) {
        setState(() {
          _isCheckingAsset = false;
          _isAssetIdAvailable = true;
        });
      }
      return;
    }
    _checkDebounce = Timer(const Duration(milliseconds: 400), () => _checkAssetId(id));
  }

  Future<void> _loadWallets() async {
    final wallets = QccObj.readWallets();
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() {
      _localWallets = wallets;
      _walletNames = names;
      final active = QccObj.activeWallet?.address;
      if (active != null && wallets.any((w) => w.address == active)) {
        _selectedAddress = active;
      } else if (wallets.isNotEmpty) {
        _selectedAddress = wallets.first.address;
      }
      _isLoadingWallets = false;
    });
  }

  /// 资产 ID 查重：和多签稳定币发行走同一个 GET /v1/asset 接口，本地按
  /// assetId 大小写不敏感过滤已注册资产列表。
  /// 返回 true 表示可用。提交前也会再调一次，以提交瞬间的结果为准。
  Future<bool> _checkAssetId(String assetId) async {
    final int seq = ++_checkSeq;
    if (assetId.isEmpty) {
      if (mounted) setState(() => _isAssetIdAvailable = true);
      return true;
    }
    if (mounted) setState(() => _isCheckingAsset = true);
    try {
      final response = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/asset"));
      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        List assets = jsonDecode(res['data']);
        bool exists = assets.any((a) => a['assetId'].toString().toUpperCase() == assetId.toUpperCase());
        if (mounted && seq == _checkSeq) setState(() => _isAssetIdAvailable = !exists);
        return !exists;
      }
    } catch (e) {
      LogObj.log("资产查重失败: $e");
    } finally {
      if (mounted && seq == _checkSeq) setState(() => _isCheckingAsset = false);
    }
    return _isAssetIdAvailable; // 查询失败时沿用上次结果，由链上做最终判定
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Trans("单签代币发行")),
      body: _isLoadingWallets
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildAddressSelector(),
              const SizedBox(height: 20),

              _buildAssetIdInput(),

              Row(
                children: [
                  Expanded(child: _buildInput("精度 (2-9)", _precisionController, "最大9位", isNum: true)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildInput("发行总量 (Supply)", _supplyController, "输入整数", isNum: true)),
                ],
              ),

              const Divider(height: 32),
              _buildSwitch("允许后续增发 (Mintable)", _mintable, (v) => setState(() => _mintable = v)),
              _buildSwitch("允许冻结逻辑 (Freezable)", _freezable, (v) => setState(() => _freezable = v)),
              _buildSwitch("允许销毁逻辑 (Burnable)", _burnable, (v) => setState(() => _burnable = v)),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _handleSubmit(_selectedAddress),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Trans("确认并发布资产规则"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit(String addr) async {
    if (!_formKey.currentState!.validate()) return;

    if (addr.isEmpty) {
      Tools.showToast(context, "请先选择发行地址");
      return;
    }
    // 提交瞬间再查一次：防抖期间直接点提交，或输入后别人刚注册了同名资产
    _checkDebounce?.cancel();
    final bool available = await _checkAssetId(_idController.text.trim());
    if (!mounted) return;
    if (!available) {
      Tools.showToast(context, "该资产代码已被注册，请更换");
      return;
    }

    int p = int.tryParse(_precisionController.text) ?? 9;
    if (p > 9 || p < 0) {
      Tools.showToast(context, "精度必须在 0-9 之间");
      return;
    }

    try {
      // 1. 获取输入的整数总量
      BigInt baseSupply = BigInt.parse(_supplyController.text);
      // 2. 计算乘数 (10的p次方)
      BigInt multiplier = BigInt.from(10).pow(p);
      // 3. 计算最终要存入 Java long 的值
      BigInt totalInitialSupply = baseSupply * multiplier;
      // 4. 定义 Java long 的最大值限制
      BigInt maxJavaLong = BigInt.parse("9223372036854775807");
      if (totalInitialSupply > maxJavaLong) {
        Tools.showToast(context, "发行总量超过公链最大数值限制");
        return;
      }
      // 把已校验过的 BigInt 结果直接传下去，不再在 _processIssue 里用
      // pow() 重新算一遍（两处算法不同，迟早不一致）。
      _processIssue(p, addr, totalInitialSupply.toInt());
    } catch (e) {
      Tools.showToast(context, "发行总量格式错误");
    }
  }

  // 核心处理进程：参考 DeveloperRuleWidget 逻辑
  // 【修复】原来永远用 QccObj.activeWallet!.address 还原钱包，现在发行地址
  // 可选了，必须按用户实际选中的 issuerAddr 去还原对应的私钥，否则会出现
  // "选了地址A，签名却用了活跃钱包B的私钥"这种地址错配（同
  // QccCreateMultiSigPage.dart 已修过的同类问题）。
  Future<void> _processIssue(int precision, String issuerAddr, int initialSupplyRaw) async {
    setState(() => _isSubmitting = true);
    String? password = await QccPassDialog.show(context);
    if (password == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 原写法：成功路径先 pop 了 loading，之后被拒/非 200 时 throw，catch 里
    // 再 pop 一次，弹出的是当前页面。用标志位保证 loading 只关一次。
    bool loadingOpen = true;
    void closeLoading() {
      if (loadingOpen && mounted && Navigator.canPop(context)) Navigator.pop(context);
      loadingOpen = false;
    }

    try {
      // 1. 还原私钥
      LogObj.log("开始还原本地钱包$issuerAddr");
      statusNotifier.value = TxStep.restoring;
      LogObj.log("获取钱包助记词完成，通过支付密码构建钱包");
      QccWallet? wallet = await QccStorage.restoreWallet(context, issuerAddr, password);
      if (wallet == null || wallet.address != issuerAddr) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      // 1. 构建 AssetMeta (严格匹配 Java 类，无 Name 属性)
      AssetMeta meta = AssetMeta(_idController.text.trim(), wallet.address);
      meta.precision = precision;
      meta.mintable = _mintable;
      meta.freezable = _freezable;
      meta.burnable = _burnable;
      meta.type="COIN";
      // 2. 初始供应量换算 (int 对应 Java long)
      meta.initialSupply = initialSupplyRaw;
      LogObj.log("资产发行meta配置${meta.toJson()}");
      // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
      RuleData rule = RuleData();
      rule.from = wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      rule.ruleName = AssetType.AssetMeta.name;
      rule.ruleJson=jsonEncode(meta.toJson());
      // 【修复，重要】对应 Java：ruleAppendJson = ""，必须显式写入——toSign()
      // 的签名原文也包含这个字段，原代码完全没有设置这一行，和
      // QccCreateMultiSigPage.dart 已验证可行的写法保持一致。
      rule.ruleAppendJson = "";
      // 计算 TxHash (finalizeId)
      rule.finalizeId();
      LogObj.log("资产发行创建交易完毕${rule.toJson()}");
// 5. 广播到规则接口
      statusNotifier.value = TxStep.submitting;
      // 【修复，重要】统一走 SignUtil.signAndEncode()：单独对 rule.toSign()
      // 做 Dilithium5 签名后覆盖 packet.signature，不再是空签名。
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rule.toSign(),
        payloadJson: jsonEncode(rule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );
      // 原来写死 https://tx.qccio.com，和查重用的 baseUrl 不是同一个节点；
      // 切测试网/主网时发行会发错网。统一走 QccExplorerService.baseUrl。
      final response = await http.post(
        Uri.parse("${QccExplorerService.baseUrl}/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );
      closeLoading();
      LogObj.log("资产发行返回json ${response.body}");
      if (response.statusCode != 200) {
        throw "网络通讯异常: ${response.statusCode}";
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) throw "返回格式异常: ${response.body}";
      final Map<String, dynamic> resData = Map<String, dynamic>.from(decoded);

      // 返回：{"status":"accepted","code":"ACCEPTED","txHash":..,"msg":..}
      // 原来判断 status=='ACCEPTED'||'success'，对小写 accepted 永远不成立，
      // 已受理被当成失败，用户重发就会重复发行同一资产（第二笔会因重名失败，
      // 但手续费照扣）。以 code 为准。
      final String code = (resData['code'] ?? resData['status'] ?? '').toString().toUpperCase();
      final String txHash = (resData['txHash'] ?? '').toString();
      if (code != 'ACCEPTED' || txHash.isEmpty) {
        throw resData['msg'] ?? "公链拒绝了该资产发布";
      }

      resData['ruleName'] = AssetType.AssetMeta.name;
      resData['id'] = txHash; // 兼容旧格式 data.id
      resData['from'] = wallet.address;
      resData['assetId'] = _idController.text.trim();
      resData['ruleJson'] = rule.ruleJson;
      resData['chainStatus'] = 'pending';

      // 先落本地记录（受理 ≠ 上链）
      await AssetFileStorage.saveAsset(resData);

      if (!mounted) return;
      final TxChainStatus? st = await showDialog<TxChainStatus?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QccTxConfirmDialog(
          txHash: txHash,
          confirmedTitle: "资产发行已上链",
          details: [
            Text("资产代码：${_idController.text.trim()}"),
            Text("发行总量：${_supplyController.text}（精度 $precision）"),
            Text("增发 ${_mintable ? '允许' : '禁止'} · 冻结 ${_freezable ? '允许' : '禁止'} · 销毁 ${_burnable ? '允许' : '禁止'}",
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          footer: "资产上链前不可转账或增发。",
          onFinal: (s) async {
            await AssetFileStorage.saveAsset({
              ...resData,
              'chainStatus': s.state.name,
              if (s.blockHeight != null) 'blockHeight': s.blockHeight,
              if (s.message != null) 'chainMsg': s.message,
            });
            // 公钥登记以上链为准，理由同商户规则
            if (s.state == TxChainState.confirmed) {
              await SignUtil.instance.markSubmitted(wallet.address);
            }
          },
        ),
      );

      if (!mounted) return;
      if (st?.state == TxChainState.confirmed) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AssetIssueSuccessPage(ruleData: {
              ...resData,
              'chainStatus': 'confirmed',
              if (st!.blockHeight != null) 'blockHeight': st.blockHeight,
            }),
          ),
        );
      } else if (st?.state == TxChainState.failed) {
        Tools.showToast(context, "资产发行上链失败：${st!.message ?? '未知原因'}", isError: true);
      } else {
        Tools.showToast(context, "资产发行已受理，尚未确认上链，请稍后在资产记录中查看");
      }
    } catch (e) {
      closeLoading();
      LogObj.log("发布资产错误$e");
      if (mounted) Tools.showToast(context, "发布失败: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- UI 构建组件 ---

  /// 【新增】可选择的发行地址框：点击弹出本机钱包列表选择，选中后下方
  /// 直接展示该地址的 QCC 余额（QccActiveWallet 内部会随地址变化自动刷新）。
  Widget _buildAddressSelector() {
    String? nick = _walletNames[_selectedAddress];
    return InkWell(
      onTap: _pickWallet,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Trans("资产发行源 (From / Owner)", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const Icon(Icons.swap_horiz, size: 16, color: Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 5),
            if (nick != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(nick, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
              ),
            Text(
              _selectedAddress.isEmpty ? Tools.getTra("未选择钱包") : _selectedAddress,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Trans("QCC 余额: ", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                if (_selectedAddress.isNotEmpty)
                  QccActiveWallet(
                    _selectedAddress,
                    "QCC",
                    fontSize: 15,
                    fontColor: Colors.black87,
                  )
                else
                  const Text("--", style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 【新增】本机钱包选择弹层，样式对齐 QccCreateMultiSigPage.dart 里的
  /// _pickOwnerWallet()，但这里选中后直接切换 _selectedAddress，不经过
  /// TextEditingController。
  void _pickWallet() {
    if (_localWallets.isEmpty) {
      Tools.showToast(context, "未找到本地钱包地址");
      return;
    }
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
                child: Trans("选择发行地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _localWallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = _localWallets[i];
                    final bool isSelected = _selectedAddress == w.address;
                    final String? nick = _walletNames[w.address];
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      onTap: () {
                        setState(() => _selectedAddress = w.address);
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

  /// 【新增】资产代码输入框：onChanged 触发查重，suffixIcon 展示
  /// 查询中/可用/已占用三种状态，和 MultiSigStableCoinIssueWidget.dart
  /// 的 _buildAssetParams() 里的写法保持一致。
  Widget _buildAssetIdInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _idController,
        textCapitalization: TextCapitalization.characters,
        onChanged: _onAssetIdChanged,
        decoration: InputDecoration(
          labelText: Tools.getTra("资产代码 (assetId)"),
          hintText: "如: QCC_USDT",
          border: const OutlineInputBorder(),
          suffixIcon: _isCheckingAsset
              ? const UnconstrainedBox(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(_isAssetIdAvailable ? Icons.check_circle : Icons.error, color: _isAssetIdAvailable ? Colors.green : Colors.red),
        ),
        validator: (v) => v!.isEmpty ? Tools.getTra("不能为空") : (!_isAssetIdAvailable ? "资产代码已存在" : null),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, String hint, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: Tools.getTra(label),
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => v!.isEmpty ? Tools.getTra("不能为空") : null,
      ),
    );
  }

  Widget _buildSwitch(String title, bool val, Function(bool) onChanged) {
    return SwitchListTile(
      title: Trans(title, style: const TextStyle(fontSize: 14)),
      value: val,
      onChanged: onChanged,
    );
  }
}