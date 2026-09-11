import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/JsonUtil.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import '../../../../procotol/QccPacket.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../qccwallet/QccWallet.dart';
import '../../../../qccwallet/SignUtil.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../../../views/setting/QccPassDialog.dart';
import '../../../../views/toolviews/QccLoading.dart';
import '../MultiSigFileStorage.dart';
import '../QccMultiSig.dart';
import 'MultiSigAddressStorage.dart';
import 'MultiSigInitiatedPage.dart';
import 'MultiSigNode.dart';
import 'QccMultiSigService.dart';

class QccFollowMultiSigPage extends StatefulWidget {
  const QccFollowMultiSigPage({super.key});

  @override
  State<QccFollowMultiSigPage> createState() => _QccFollowMultiSigPageState();
}

class _QccFollowMultiSigPageState extends State<QccFollowMultiSigPage> {
  final TextEditingController _hashController = TextEditingController();
  bool _isProcessing = false;

  // 【新增】追随签署用哪个地址签，原来这里完全没有选择余地，直接读全局
  // QccObj.activeWallet——如果这个人本机有好几个地址，而多签规则里登记的
  // 是"另一个"地址，之前是没法在这个页面切换过去签的。参照
  // WalletInitPage.dart 里 _walletNames / _nameFor 的做法，加一个页面内的
  // 地址选择（不改全局 activeWallet，只影响这次签署用哪个地址）。
  QccWallet? _selectedWallet;
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    // 默认还是用全局当前活跃钱包，和原来行为保持一致，只是现在允许切换。
    _selectedWallet = QccObj.activeWallet;
    _loadWalletNames();
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  String _nameFor(String address) {
    return _walletNames[address] ?? QccStorage.shortAddress(address);
  }

  /// 弹出本机所有地址列表，供用户切换"这次用哪个地址签署"。
  void _pickSigningWallet() {
    final wallets = QccObj.readWallets();
    if (wallets.isEmpty) {
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Trans("选择签署地址", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: wallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final w = wallets[index];
                    final bool isSelected = _selectedWallet?.address == w.address;
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(_nameFor(w.address), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(
                        w.address,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        setState(() => _selectedWallet = w);
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSigningWalletCard() {
    final wallet = _selectedWallet;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle, color: Colors.orange, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Trans("签署地址", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  wallet == null ? "未选择地址" : _nameFor(wallet.address),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (wallet != null)
                  Text(
                    wallet.address,
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _pickSigningWallet,
            child: Trans("切换"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 原代码遗漏：TextEditingController 必须 dispose，否则内存泄漏
    _hashController.dispose();
    super.dispose();
  }

  // 执行多签追随 (完全对齐 Java 阶段 2 逻辑)
  Future<void> _handleFollow() async {
    final String ruleHash = _hashController.text.trim();
    if (ruleHash.isEmpty) {
      Tools.showToast(context, "请先输入或粘贴交易哈希");
      return;
    }

    // 2. 格式与长度校验 (正则判断：64位十六进制)
    final RegExp hashRegex = RegExp(r'^[a-fA-F0-9]{64}$');
    if (!hashRegex.hasMatch(ruleHash)) {
      Tools.showToast(context, "哈希格式不正确，请确保是64位十六进制字符串");
      return;
    }

    // 1. 获取本次用于签署的钱包（原来这里读的是全局 QccObj.activeWallet，
    // 现在改成读页面内可切换的 _selectedWallet）
    final signingWallet = _selectedWallet;
    if (signingWallet == null) {
      Tools.showToast(context, "请先选择签署地址");
      return;
    }

    // 2. 验证密码并解密
    LogObj.log("当前签署钱包地址:${signingWallet.address}");
    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    if (!mounted) return;

    // 防止重复点击 + 驱动按钮 loading 态（原代码声明了 _isProcessing 但从未赋值）
    setState(() => _isProcessing = true);

    // 3. 启动状态通知 Loading (TxStep 分为还原、构造、签名、广播)
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    bool loadingShown = false;
    QccLoading.show(context, statusNotifier);
    loadingShown = true;

    try {
      // ---- A. 还原钱包 (隔离子线程解密) ----
      statusNotifier.value = TxStep.restoring;

      QccWallet? wallet =
      await QccStorage.restoreWallet(context, signingWallet.address, password);
      if (!mounted) return;
      if (wallet == null || wallet.address != signingWallet.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // ---- B. 构造追随规则 (对应 Java: MultiSigAppend) ----
      statusNotifier.value = TxStep.building;

      final appendRule = RuleData();
      appendRule.timestamp = DateTime.now().millisecondsSinceEpoch;
      appendRule.assetId = "QCCRule";
      appendRule.from = wallet.address;
      appendRule.ruleType = "UserRule";
      appendRule.ruleName = "MultiSigAppend";
      // 关键点：ruleJson 填入的是第一步创建时产生的 Hash
      appendRule.ruleJson = ruleHash;
      // 【修复】Java 端 appendRule.ruleAppendJson="" 是显式设置的，
      // finalizeId() 会把该字段编入 Hash 计算；Dart 端原来遗漏了这一行，
      // 如果 RuleData() 默认值不是 ""（比如 null），会导致 toSign()/id 与
      // Java 端不一致，进而签名或哈希校验失败。
      appendRule.ruleAppendJson = "";
      // 生成规则唯一 ID (finalizeId 内部应包含计算 Hash 逻辑)
      appendRule.finalizeId();

      // ---- C. 抗量子签名 (在子线程执行 Dilithium5 签名任务) ----
      statusNotifier.value = TxStep.signing;
      LogObj.log("构建多签追随交易json ${appendRule.toJson()}");
      // 【修复】原来这里直接调 QccDataProtocol.encodeTransaction，但那个方法
      // 内部的签名逻辑是被注释掉的（signature 恒为 ""），也就是说提交上去的
      // 追随签署交易，签名字段实际上是空的。改成统一走 SignUtil，它会用
      // appendRule.toSign() 单独签名后再覆盖 packet.signature。
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: appendRule.toSign(),
        payloadJson: jsonEncode(appendRule.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // ---- D. 发送广播 ----
      statusNotifier.value = TxStep.submitting;
      // 【修改】按你的决定：多签创建/追加/查询统一固定打 MultiSigNode.baseUrl
      // 这一个节点，不再走 QccNodeManager 的动态选择——原因见
      // MultiSigNode.dart 顶部注释：追加签署必须和当初创建时落在同一个节点，
      // 否则服务端内存里的待签会话查不到，会直接 404。固定节点后，创建方和
      // 所有追随者天然都打同一个地方，不再需要"把节点信息编码进分享内容里
      // 再解析"这一层。
      final String baseUrl = MultiSigNode.baseUrl;
      final String url = "$baseUrl/v1/mtxrule";
      late final http.Response response;
      try {
        response = await http
            .post(
          Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(packet.toJson()),
        )
        // 原有修复保留：没有超时控制，服务端无响应时 Loading 会永久卡死。
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        // 固定节点这次请求失败（超时/网络层错误）：没有其他节点可以切换，
        // 直接交给外层 catch 统一处理 Loading 关闭/提示。
        rethrow;
      }

      if (!mounted) return;

      // 【修复】原代码完全没检查 HTTP 状态码
      if (response.statusCode != 200) {
        throw Exception("服务器返回异常状态码: ${response.statusCode}");
      }

      LogObj.log("追随多签发起后，返回:${response.body}");
      Map<String, dynamic> resData = JsonUtil.strtoMap(response.body);

      if (resData['status'] == "ACCEPTED") {
        // 【新增】标记该地址已成功提交过交易，供 SignUtil 的
        // "已提交过就不重复发公钥" 特性使用。
        await SignUtil.instance.markSubmitted(wallet.address);
        await MultiSigFileStorage.saveTask({'txHash': resData['txHash']});

        final rawData = resData['data'];
        Map<String, dynamic> innerData = {};
        try {
          if (rawData is String) {
            final decoded = jsonDecode(rawData);
            if (decoded is Map) innerData = Map<String, dynamic>.from(decoded);
          } else if (rawData is Map) {
            innerData = Map<String, dynamic>.from(rawData);
          }
        } catch (_) {
          // 解析失败不影响主流程——innerData 只用来猜 type，猜不出就按
          // 默认的 createRule 处理。
        }

        // 【修复，重要】上一版这里不管三七二十一，提交完一律再打一次
        // fetchTask() 网络查询才决定要不要跳转——结果你这次 2-of-2 的场景，
        // 响应体里其实已经带了完整的合并结果（multiaddress/owners/threshold
        // 都在），却还要多等 mtxquery（最多 15s）再等链上查询兜底
        // （再 15s）才跳转，Loading 转了老半天跟"没反应"没区别，你就没等到。
        //
        // 改成两条路：响应体里的 ruleJson 如果已经是一个"带 multiaddress
        // 的完整 Map"——这次追加凑巧（或者说必然，只要凑满门槛服务端就是
        // 这么返回的，不分是不是 2-of-2）就是最后一棒，直接用这份数据，
        // 不需要再多打一次网络请求，跟以前一样"提交完立刻跳转"；
        // 只有响应体给的是"纯 Hash 回执"（3 人以上组合、还没凑满门槛的
        // 那次追加，见下面 else 分支）——这种情况下响应体确实看不出
        // owners/threshold，才需要多查一次权威状态来确认"是不是已经在
        // 别的地方被查全、还是真的没完成"。
        dynamic ruleData = innerData['ruleJson'];
        Map<String, dynamic>? directRuleJson;
        if (ruleData is Map) {
          directRuleJson = Map<String, dynamic>.from(ruleData);
        } else if (ruleData is String) {
          final String ruleStr = ruleData.trim();
          if (ruleStr.startsWith('{')) {
            try {
              final decoded = jsonDecode(ruleStr);
              if (decoded is Map) directRuleJson = Map<String, dynamic>.from(decoded);
            } catch (_) {}
          }
        }

        final String? directMultiAddress =
        (directRuleJson?['multiaddress'] ?? directRuleJson?['multiAddress'])?.toString();

        MultiSigSummary summary;
        if (directRuleJson != null && directMultiAddress != null && directMultiAddress.isNotEmpty) {
          // 快路径：响应体本身就是合并完的完整规则，直接用，立刻跳转。
          final List<String> directOwners = List<String>.from(directRuleJson['owners'] ?? [])
              .map((e) => e.toString())
              .toSet()
              .toList();
          summary = MultiSigSummary(
            owners: directOwners,
            signedOwners: directOwners,
            threshold: directRuleJson['threshold'] ?? 0,
            multiAddress: directMultiAddress,
            isFinished: true,
          );
        } else {
          // 慢路径：响应体只是这次追加自己的确认回执（纯 Hash / 缺
          // owners、threshold），查一次权威状态（mtxquery 内存优先，查不到
          // 再退回链上查询——和 QccMultiSigCenterPage 列表页同一条路径）。
          // MultiAddressQueryContext（verifyMultiSigAddress）只在下面作为
          // "已生成"之后的二次确认，不参与这里"是否还要继续签"的判定。
          final MultiSigTaskWrapper? statusTask =
          await QccMultiSigService.fetchTask(resData['txHash']);
          summary = statusTask != null
              ? QccMultiSigService.summarize(statusTask)
              : const MultiSigSummary(
              owners: [], signedOwners: [], threshold: 0, multiAddress: null, isFinished: false);
        }

        final String? multiAddress = summary.multiAddress;
        final List<String> owners = summary.owners;
        final int threshold = summary.threshold;
        // 核心判定：是否已经达成完成条件——以查回来的权威状态为准。
        final bool isFinished =
            summary.isFinished && multiAddress != null && multiAddress.isNotEmpty;

        // 签署刚好凑满 threshold、生成出多签地址的这一刻，做几件事：
        // (a) 顺手用 MultiAddressQueryContext 二次校验这个地址确实已经在
        //     链上（规则登记服务）注册成功——仅作日志/辅助参考；
        // (b) 写进本地"多签中心"任务记录（MultiSigFileStorage），供列表页
        //     继续用同一套查询逻辑展示；
        // (c) 【新增】同时写进专门的"多签地址簿"(MultiSigAddressStorage)——
        //     之前只写了 (b)，多签地址栏目读的是 MultiSigAddressStorage，
        //     一直看不到这笔已完成的记录；
        // (d) 【新增】弹一个明确的"多签地址已生成"提示框，而不是让用户自己
        //     从下一页的 UI 细节里去发现"哦原来已经生成了"。
        if (isFinished && multiAddress != null && multiAddress.isNotEmpty) {
          final bool verified = await QccMultiSigService.verifyMultiSigAddress(multiAddress);
          LogObj.log(verified
              ? "QCC DEBUG_: 多签地址链上校验通过: $multiAddress"
              : "QCC DEBUG_: 多签地址链上校验未通过（可能是登记服务还没同步过来，不影响本地展示）: $multiAddress");

          await MultiSigFileStorage.saveConfirmedAccount({
            'multiaddress': multiAddress,
            'owners': owners,
            'threshold': threshold,
            'txHash': resData['txHash'],
          });

          await MultiSigAddressStorage.saveConfirmedAccount(MultiSigAccount(
            multiAddress: multiAddress,
            owners: owners,
            threshold: threshold,
            txHash: resData['txHash'],
            createTime: null,
          ));

          if (!mounted) return;
          await _showFinishedDialog(multiAddress);
        } else {
          // 【新增】3 人以上组合（或任何还没凑满门槛）的这次追加签署——
          // 明确提醒"已经提交成功，还差几个人才能完成"，而不是让用户提交完
          // 什么反馈都没看到，自己纳闷是不是失败了。
          if (!mounted) return;
          await _showStillPendingDialog(summary);
        }

        if (!mounted) return;

        // 跳转时，让目标页面知道"已经完成了"，并把已签署地址子集
        // (summary.signedOwners) 一并带过去，详情页可以逐个地址标出谁签了。
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MultiSigInitiatedPage(
              txHash: resData['txHash'],
              multiAddress: multiAddress,
              type: (innerData['kind'] == 'MULTI_TX' || innerData['type'] == 'transaction')
                  ? MultiSigPageType.transfer
                  : MultiSigPageType.createRule,
              owners: owners,
              signedOwners: summary.signedOwners,
              threshold: threshold,
              isFinish: isFinished,
            ),
          ),
        );
      } else {
        // 【修复】原代码对非 ACCEPTED 状态没有任何反馈，用户点了提交后
        // 界面看起来"什么都没发生"。这里把服务端返回的信息透出来。
        final String msg = (resData['message'] ?? resData['msg'] ?? resData['status'] ?? '未知错误')
            .toString();
        Tools.showToast(context, "签署提交失败: $msg");
      }
    } catch (e) {
      // 【修复】原代码整段核心逻辑的 try/catch 被注释掉了：
      // 钱包恢复失败、网络异常、JSON 解析异常都会直接抛出未捕获异常，
      // 轻则 Loading 弹窗永远关不掉，重则页面崩溃。
      LogObj.log("追随多签失败: $e");
      if (mounted) {
        Tools.showToast(context, "追随失败: $e");
      }
    } finally {
      if (loadingShown && mounted) {
        Navigator.pop(context); // 确保 Loading 弹窗一定会被关闭
      }
      statusNotifier.dispose();
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// 【新增】签署一旦真正凑满门槛、生成出多签地址，明确弹一个完成提示框，
  /// 而不是只靠下一页（MultiSigInitiatedPage）UI 细节里的图标/文案变化让
  /// 用户自己发现"已经完成了"。
  Future<void> _showFinishedDialog(String multiAddress) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.celebration_rounded, color: Colors.green),
            SizedBox(width: 8),
            Trans("多签地址已生成"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Trans("所有签署已完成，多签地址：", style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            SelectableText(
              multiAddress,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: multiAddress));
              Tools.showToast(dialogContext, "地址已复制");
            },
            child: const Trans("复制地址"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Trans("知道了"),
          ),
        ],
      ),
    );
  }

  /// 【新增】签署提交成功，但还没凑满门槛（3 人以上组合的常见情况）——
  /// 明确告诉用户"提交成功了，还差几个人"，而不是提交完什么反馈都没有，
  /// 让人怀疑是不是失败了。
  Future<void> _showStillPendingDialog(MultiSigSummary summary) {
    final int total = summary.threshold;
    final int signed = summary.signedOwners.length;
    final int remaining = total > 0 ? (total - signed).clamp(0, total) : 0;
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.hourglass_bottom_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Trans("签署已提交"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Trans("您的签名已成功提交。", style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            if (total > 0)
              Text(
                "当前进度：$signed / $total，还需要 $remaining 位伙伴签署才能生成多签地址。",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              )
            else
              const Trans("请继续邀请其他伙伴完成签署。", style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Trans("知道了"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Trans("追随多签签署")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.link_rounded, size: 60, color: Colors.orange),
            const SizedBox(height: 20),
            Trans("多签追加签署", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Trans("粘贴发起人提供的交易 Hash，确认后将提交您的签名。账户需有少量手续费。",
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            // 【新增】显示 + 切换"这次用哪个地址签署"，之前完全没有这个信息，
            // 用户不知道即将用哪个地址提交，也没法切换到多签规则里登记的那个地址。
            _buildSigningWalletCard(),
            const SizedBox(height: 20),
            TextField(
              controller: _hashController,
              maxLines: 3, // Hash 较长，多行显示更易检查
              decoration: const InputDecoration(
                hintText: "在此粘贴交易哈希 (Hash)",
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _handleFollow,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isProcessing
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
                    : const Trans("确认提交签署", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}