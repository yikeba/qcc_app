import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/rule/asset/stablecoin/QccStableCoinSignSuccessWidget.dart';
import 'package:qcc_flutter/utile/JsonUtil.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'dart:convert';

import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccWallet.dart';
// 【修复，重要】原来直接调 QccDataProtocol.encodeTransaction，内部签名逻辑
// 被注释掉（signature 恒为 ""）——这正是"Invalid Signature"被拒的原因，
// 和其它资产发行 Widget 是同一个坑。改成统一走 SignUtil。
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../user/multiple/QccMultiSig.dart';
import '../user/multiple/multicreat/MultiSigAddressStorage.dart';
import 'core/AssetMeta.dart';


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

  // 2. 业务状态
  bool _isQuerying = false;
  Map<String, dynamic>? _proposalData;
  String _currentSignerAddress = "";

  @override
  void initState() {
    super.initState();
    _currentSignerAddress = QccObj.activeWallet!.address;
    _loadMultiSigAccounts(); // 初始化时启动异步读取
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

    setState(() => _isQuerying = true);

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

          setState(() {
            _proposalData = {
              'current': current,
              'total': total,
              'amount': ruleContent['amount'] ?? 0,
              'asset': ruleContent['assetId'] ?? "QCC",
              'target': ruleContent['address'] ?? "未知",
              // 【修复，重要】这里原来硬编码 fallback 成 "PledgeRule"（明显是从
              // 别的质押追随页面复制过来的默认值，跟这个页面的稳定币场景不
              // 匹配）。这个字段必须是被追随提案自己真实的 ruleName——资产域
              // (AsseIdRule) 的追随规则是"提案和追随用同一个 ruleName"（参照
              // Java MuRuleUSDSAsset.java：appendRule.ruleName 和
              // createRule.ruleName 都是 "AssetMeta"），如果这里查到的其实是
              // 一笔增发(AssetMintRule)提案，追随时却把 ruleName 写成
              // "AssetMeta"，会导致追随交易和原提案的业务类型对不上。
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
            _buildSignerCard(),

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
            }),
          ),
        ),
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

  Widget _buildSignerCard() {
    return Card(
      color: Colors.purple.withValues(alpha: 0.05),
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.security, color: Colors.purple),
        title: Text(_currentSignerAddress, style: const TextStyle(fontSize: 11)),
        subtitle: Trans("此私钥将参与本次多签背书"),
      ),
    );
  }
  bool _isSubmitting=false;

  /// 发起追随签署逻辑
  Future<void> _followstable() async {
    setState(() => _isSubmitting = true);
    if (_selectedAccount == null) {
      Tools.showToast(context, "请选择多签账户");
      return;
    }
    String currentFromAddress=QccObj.activeWallet!.address;
    LogObj.log("发起多签稳定币逻辑触发 hash:${_hashController.text}");
    LogObj.log("目标多签地址: ${_selectedAccount!.multiAddress}");
    LogObj.log("当前发起人: $currentFromAddress");
    // 2. 验证支付密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    // 3. 启动状态通知 Loading (复用您的 TxStep 和 QccLoading)
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      // ---- A. 还原钱包 (在隔离的子线程中处理耗时的解密) ----
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet=await QccStorage.restoreWallet(context,currentFromAddress,password);
      if (wallet == null || wallet.address !=currentFromAddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      // ---- B. 构建多签交易数据 ----
      statusNotifier.value = TxStep.building;

      // 3. 构建 RuleData 容器——RuleData() 构造函数已自动填好 timestamp/chain。
      RuleData rule = RuleData();
      rule.from = wallet.address;
      rule.ruleType = "AsseIdRule"; // 资产类规则固定类型
      // 【修复，重要】原来这里不管三七二十一都写死
      // AssetType.AssetMeta.name——但这个页面既可能追随"发行"提案也可能
      // 追随"增发"提案，两者的 ruleName 不一样(AssetMeta / AssetMintRule)。
      // 改成用查询回来的、这笔提案自己真实的 ruleName，和 Java 端
      // "提案与追随 ruleName 必须一致"的约定保持一致。
      rule.ruleName = _proposalData?['ruleName'] ?? AssetType.AssetMeta.name;
      rule.ruleJson=_hashController.text;
      // 【修复，重要】对应 Java：ruleAppendJson = ""，必须显式写入——toSign()
      // 的签名原文也包含这个字段，原代码完全没有设置这一行。
      rule.ruleAppendJson = "";
      // 计算 TxHash (finalizeId)
      rule.finalizeId();
      // 3. 签名——统一走 SignUtil.signAndEncode()
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rule.toSign(),
        payloadJson: jsonEncode(rule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );
      // 4. POST 至多签提案池
      String url="https://tx.qccio.com/v1/mtxrule";
      // 5. HTTP 广播
      var response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );
      LogObj.log("多签资产稳定币追随签署返回:${response.body}");
      if (Navigator.canPop(context)) Navigator.pop(context);
      if (response.statusCode == 200) {
        Map<String,dynamic> resData=JsonUtil.strtoMap(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          // 1. 提取交易哈希 (这是其他成员追随签署的唯一凭证)
          String txHash = resData['txHash'] ?? "";
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => QccStableCoinSignSuccessWidget(responseData: resData),
            ),
          );
          if (!mounted) return;
          LogObj.log("✅ 多签稳定币提案跳转成功: $txHash");

        } else {
          throw resData['msg'] ?? "提案发布失败";
        }
      }
    } catch (e) {
      Tools.showToast(context, "异常: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_proposalData == null) ? null : () {
          _followstable();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Trans("确认并签署提案", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
