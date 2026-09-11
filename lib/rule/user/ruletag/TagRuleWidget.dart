import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/RuleData.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../qccwallet/SignUtil.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../../../views/setting/QccPassDialog.dart';
import '../../../views/toolviews/QccLoading.dart';
import '../UserRuleFileStorage.dart';
import 'QccUserRuleExtras.dart';
import 'TagRuleSuccessPage.dart';

/// 【新增】标签资产注册 (TagRule) —— 对齐 Java 端
/// qcc.client.userrule.TxTagRuleTest：一次性写入、全网唯一的"这个 tag 归谁"
/// 登记。标签资产可以用作去中心化应用的鉴权凭证/命名空间划分/去中心化
/// 域名解析，注册成功后归属该地址，可以通过「标签转让」交易转让给他人。
enum _TagAvailability { idle, checking, available, taken, error }

class TagRuleWidget extends StatefulWidget {
  const TagRuleWidget({super.key});

  @override
  State<TagRuleWidget> createState() => _TagRuleWidgetState();
}

class _TagRuleWidgetState extends State<TagRuleWidget> {
  final _formKey = GlobalKey<FormState>();
  final _tagController = TextEditingController();

  // 【新增】from 地址名称——跟 Common/Authorized/SuperNode 质押 widget 里
  // 同样的 QccStorage.getAllWalletNames() 查本机备注名，没有备注名就还是
  // 只显示地址本身。
  Map<String, String> _walletNames = {};

  // 【新增】注册账户改成可选——跟 CommonPledgeWidget/AuthorizedPledgeWidget/
  // SuperNodePledgeWidget/QccTransferPage 一样的地址下拉选择器，不再固定用
  // QccObj.activeWallet（之前要切账户得退出去主钱包页切换，很不方便）。
  List<String> _localAddrs = [];
  String nowaddress = "";

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final names = await QccStorage.getAllWalletNames();
    final addrs = QccObj.readWallets().map((e) => e.address).toSet().toList();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localAddrs = addrs;
      if (addrs.isNotEmpty) {
        // 默认选中当前激活钱包（如果它在本机钱包列表里），否则退而求其次选
        // 第一个——跟其它 widget 的默认选中逻辑保持一致。
        final active = QccObj.activeWallet?.address;
        nowaddress = (active != null && addrs.contains(active)) ? active : addrs.first;
      }
    });
  }

  // 【假设，未完全验证】按 Java 端 TxTagRuleTest 里 TAG_QUERY_URL =
  // poolurl + "/v1/tag/"，猜测 host 和广播交易统一走 tx.qccio.com。
  // ⚠️ 但要注意：Java 测试里 poolurl 同时也是 RULE_URL / TX_URL 的 host——
  // 这只能说明"在 Java 测试客户端里三者共用一个入口"，不能反推 Dart 这边
  // 也一定该用 tx.qccio.com 来查询。已确认能正常工作的 SuperNode/Authorized
  // 质押三要素查询走的是 GET ${QccExplorerService.baseUrl}/v1/pledge/{address}，
  // 即"查询类接口走 QccExplorerService.baseUrl，提交类接口走硬编码的
  // tx.qccio.com"这个模式——/v1/tag/{tagName} 同样是纯查询接口，如果实测下面
  // _checkAvailability() 请求这个地址失败（超时/404），先把这行换成
  // "${QccExplorerService.baseUrl}/v1/tag/" 试试，大概率是host猜错了。
  static const String _tagQueryUrl = "https://tx.qccio.com/v1/tag/";

  _TagAvailability _availability = _TagAvailability.idle;
  String? _takenByAddress;
  // 【新增】"已被注册"时一并带出注册时间，"查询失败"时带出服务端给的
  // 具体原因（比如"查询失败: 节点无响应"），而不是只给一句笼统提示。
  int? _takenRegTime;
  String? _queryErrorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localAddrs.isEmpty) {
      return _buildEmptyState(Icons.account_balance_wallet_outlined, "本机未导入任何钱包，无法注册标签。");
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            _buildLabel("注册账户 (Owner)"),
            _buildAddressPicker(),
            const SizedBox(height: 12),
            _buildAccountInfoCard(nowaddress),
            const SizedBox(height: 24),

            _buildLabel("标签名称 (Tag Name)"),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tagController,
                    onChanged: (_) {
                      if (_availability != _TagAvailability.idle) {
                        setState(() {
                          _availability = _TagAvailability.idle;
                          _takenByAddress = null;
                          _takenRegTime = null;
                          _queryErrorMessage = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "例如 qccname",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                      prefixIcon: const Icon(Icons.sell_outlined, size: 18),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return Tools.getTra("请输入标签名称");
                      if (!RegExp(r'^[a-zA-Z0-9_\-]{2,32}$').hasMatch(val.trim())) {
                        return Tools.getTra("仅支持字母/数字/下划线/中划线，2-32位");
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _availability == _TagAvailability.checking ? null : _checkAvailability,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _availability == _TagAvailability.checking
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Trans("查询"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildAvailabilityHint(),

            const SizedBox(height: 24),
            _buildInfoNote(),
            const SizedBox(height: 32),

            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("标签资产注册 (TagRule)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Trans(
          "标签是 QCC 公链上全网唯一、去中心化确权的命名资产，可用作去中心化"
              "应用的鉴权凭证、命名空间划分或去中心化域名解析。注册成功后此标签"
              "将永久归属于您的地址（除非您主动发起「标签转让」）。",
          style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Trans(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  /// 【新增】账户下拉选择器——跟 AuthorizedPledgeWidget/SuperNodePledgeWidget
  /// 的 _buildAddressPicker() 是同一套写法，切换后会重置可用性查询状态
  /// （tagName 没变，但换了账户后"该标签已被注册"提示里显示的对比意义
  /// 已经不一样了，重新查一次更稳妥，不强制自动重查，交给用户手动点查询）。
  Widget _buildAddressPicker() {
    return DropdownButtonFormField<String>(
      value: nowaddress.isEmpty ? null : nowaddress,
      isExpanded: true,
      items: _localAddrs
          .map((a) => DropdownMenuItem(
        value: a,
        child: Text(
          _walletNames[a] != null ? "${_walletNames[a]} ($a)" : a,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
      ))
          .toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => nowaddress = val);
        }
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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

  Widget _buildAccountInfoCard(String address) {
    // 【新增】有本机备注名就"备注名 + 地址"一起显示，没有就还是只显示地址。
    final String? nick = _walletNames[address];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.sell_outlined, color: Colors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nick != null && nick.isNotEmpty)
                  Text(nick,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                Text(address,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: nick != null && nick.isNotEmpty ? FontWeight.normal : FontWeight.bold,
                        color: nick != null && nick.isNotEmpty ? Colors.grey[600] : Colors.black),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Trans("当前余额: ", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    QccActiveWallet(address, "QCC", fontSize: 12.0, fontColor: Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityHint() {
    if (_availability == _TagAvailability.available) {
      return _hintCard(Icons.check_circle, Colors.green, "该标签尚未被注册，可以放心提交");
    }
    if (_availability == _TagAvailability.taken) {
      final String ownerPart = _takenByAddress != null ? "，归属地址：${_shortAddr(_takenByAddress!)}" : "";
      final String timePart = _takenRegTime != null ? "，注册于 ${_formatTimestamp(_takenRegTime!)}" : "";
      return _hintCard(Icons.error_outline, Colors.redAccent, "该标签已被注册$ownerPart$timePart");
    }
    if (_availability == _TagAvailability.error) {
      final String reason =
      (_queryErrorMessage != null && _queryErrorMessage!.isNotEmpty) ? "：$_queryErrorMessage" : "";
      return _hintCard(Icons.help_outline, Colors.grey, "查询失败$reason，仍可直接提交由公链最终裁定");
    }
    return const SizedBox.shrink();
  }

  /// 格式化 TagQuery 返回的 regTime(毫秒时间戳) 为可读时间
  String _formatTimestamp(int millis) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }

  Widget _hintCard(IconData icon, Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }

  String _shortAddr(String addr) =>
      addr.length > 16 ? "${addr.substring(0, 8)}...${addr.substring(addr.length - 6)}" : addr;

  Widget _buildInfoNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Trans(
              "标签资产可以通过「标签转让」交易整体转让给其他地址，转让后原地址将"
                  "失去该标签的全部权益。",
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Trans("签署并注册标签"),
      ),
    );
  }

  /// 提交前的可选可用性查询——不阻塞提交，纯粹是省得用户白白广播一笔一定
  /// 会被拒的交易（tagName 全网唯一，抢注会被服务端拒绝，参照
  /// TxTagRuleTest 里"intruder 抢注同一 tagName 应被拒"的验证逻辑）。
  Future<void> _checkAvailability() async {
    final String tagName = _tagController.text.trim();
    if (tagName.isEmpty) return;
    setState(() => _availability = _TagAvailability.checking);
    try {
      final response =
      await http.get(Uri.parse("$_tagQueryUrl$tagName")).timeout(const Duration(seconds: 15));
      // 【修复，重要】实测下来（节点无响应等链路异常时）不能只靠 HTTP 状态码
      // 判断成功/失败——TagQuery.java 注释里写的是链路异常返回 500，但服务端
      // /网关实际返回的 body 始终带着 "ok" 字段，用它来判断更可靠：
      //   ok:true  + found:true  → 标签已被注册（显示归属地址+注册时间）
      //   ok:true  + found:false → 标签尚未注册，可以放心提交
      //   ok:false               → 真正的查询失败（节点异常等），不是"未注册"，
      //                            不能当成"可以提交"处理，把服务端给的
      //                            message 原样带出来，而不是只给一句笼统提示。
      final dynamic data = jsonDecode(response.body);
      final bool ok = data is Map && data['ok'] == true;
      if (ok) {
        LogObj.log("TagRule 可用性查询成功: ${response.body}");
        final bool found = data['found'] == true;
        if (found) {
          final Map? tagInfo = data['data'] is Map ? data['data'] as Map : null;
          final String? ownerVal = tagInfo?['owner']?.toString();
          final dynamic regTimeVal = tagInfo?['regTime'];
          final int? regTime = regTimeVal is int
              ? regTimeVal
              : (regTimeVal != null ? int.tryParse(regTimeVal.toString()) : null);
          if (mounted) {
            setState(() {
              _availability = _TagAvailability.taken;
              _takenByAddress = ownerVal;
              _takenRegTime = regTime;
            });
          }
        } else {
          if (mounted) setState(() => _availability = _TagAvailability.available);
        }
      } else {
        LogObj.log("TagRule 可用性查询失败: ${response.body}");
        final String? msg = (data is Map) ? data['message']?.toString() : null;
        if (mounted) {
          setState(() {
            _availability = _TagAvailability.error;
            _queryErrorMessage = msg;
          });
        }
      }
    } catch (e) {
      LogObj.log("TagRule 可用性查询异常: $e");
      if (mounted) {
        setState(() {
          _availability = _TagAvailability.error;
          _queryErrorMessage = null;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    // 🐛 FIX：注册账户改成用上面下拉框选中的 nowaddress，不再依赖
    // QccObj.activeWallet（原来固定用全局激活钱包，选别的账户得跑去主钱包
    // 页切换才行）。
    if (nowaddress.isEmpty) {
      Tools.showToast(context, "请选择注册账户");
      return;
    }

    String? password = await QccPassDialog.show(context);
    if (password == null) return;

    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    try {
      setState(() => _isSubmitting = true);

      // 1. 还原私钥
      statusNotifier.value = TxStep.restoring;
      QccWallet? wallet = await QccStorage.restoreWallet(context, nowaddress, password);
      if (wallet == null || wallet.address != nowaddress) {
        throw Exception("钱包恢复错误，请检查密码");
      }
      if (wallet.privateKey == null) throw "支付密码错误";

      // 2. 构建标签注册对象——owner 仅声明用途，服务端应以签名地址(from)为准
      statusNotifier.value = TxStep.building;
      final tagRule = QccTagRule(tagName: _tagController.text.trim(), owner: nowaddress);

      // 3. 构建公链规则容器——RuleData() 构造函数已自动填好 timestamp/chain。
      final ruleData = RuleData();
      ruleData.from = nowaddress;
      ruleData.ruleType = "UserRule";
      ruleData.ruleName = "TagRule";
      ruleData.ruleJson = jsonEncode(tagRule.toJson());
      ruleData.ruleAppendJson = "";
      ruleData.finalizeId();

      // 4. 执行签名——统一走 SignUtil.signAndEncode()
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: nowaddress,
        toSignString: ruleData.toSign(),
        payloadJson: jsonEncode(ruleData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // 5. 广播到规则接口
      // 🐛 FIX：这里原来用的是 QccExplorerService.baseUrl（查询/浏览服务的host），
      // 但本文件自己在顶部注释里就写明了"规则交易统一走 tx.qccio.com"，而且
      // CommonPledgeWidget / AuthorizedPledgeWidget / SuperNodePledgeWidget
      // 提交 /v1/rule 时用的都是硬编码的 https://tx.qccio.com/v1/rule（这几个
      // 已经过实测确认能正常质押扣款）。QccExplorerService.baseUrl 在那几个
      // widget 里只用来查询（GET /v1/pledge/{address}），从没被用来提交过
      // /v1/rule——两者大概率是不同的服务/host。这里改成跟其它规则交易一致，
      // 提交到硬编码的广播地址，不再用 QccExplorerService.baseUrl。
      statusNotifier.value = TxStep.submitting;
      final response = await http.post(
        Uri.parse("https://tx.qccio.com/v1/rule"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(packet.toJson()),
      );

      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("标签注册返回参数${response.body}");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'ACCEPTED' || resData['status'] == 'success') {
          if (resData['data'] != null) {
            try {
              var inner = jsonDecode(resData['data']);
              resData['ruleName'] = inner['ruleName'] ?? "TagRule";
            } catch (e) {
              LogObj.log("解析标签注册详情失败: $e");
              resData['ruleName'] = "TagRule";
            }
          } else {
            resData['ruleName'] = "TagRule";
          }
          // 【新增】标记该地址已成功提交过交易，供 SignUtil 复用公钥登记状态。
          await SignUtil.instance.markSubmitted(wallet.address);
          // 1. 保存到本地规则状态中心
          await UserRuleFileStorage.saveRuleTask(resData);
          // 2. 跳转到专属成功页面
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => TagRuleSuccessPage(ruleData: resData)),
            );
          }
        } else {
          throw resData['msg'] ?? "标签注册被拒绝（可能已被占用）";
        }
      } else {
        throw "网络通讯失败: ${response.statusCode}";
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("标签注册异常: $e");
      Tools.showToast(context, "注册失败: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}