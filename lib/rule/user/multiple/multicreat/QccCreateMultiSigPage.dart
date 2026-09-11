import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/qccwallet/SignUtil.dart';
import '../../../../procotol/QccPacket.dart';
import '../../../../procotol/RuleData.dart';
import '../../../../qccwallet/QccWallet.dart';
import '../../../../utile/QccObj.dart';
import '../../../../utile/QccStorage.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../../../../views/setting/QccPassDialog.dart';
import '../../../../views/toolviews/QccLoading.dart';
import '../MultiSigFileStorage.dart';
import '../MultiSignature.dart';
import 'MultiSigInitiatedPage.dart';
import 'MultiSigNode.dart';

class QccCreateMultiSigPage extends StatefulWidget {
  const QccCreateMultiSigPage({super.key});

  @override
  State<QccCreateMultiSigPage> createState() => _QccCreateMultiSigPageState();
}

class _QccCreateMultiSigPageState extends State<QccCreateMultiSigPage> {
  final List<TextEditingController> _ownerControllers = [];
  final String _storageKey = "cache_multisig_draft"; // 本地缓存Key

  // 【修复】原代码没有任何"处理中"状态：确认按钮在等待密码弹窗 / 网络请求
  // 期间可以被重复点击，存在重复发起创建多签交易的风险。
  bool _isProcessing = false;

  // 【新增】地址 -> 本地钱包昵称 映射（照搬 WalletInitPage.dart 里 _walletNames 的做法）。
  // 注意：这里只可能查到"本地自己保存过的钱包"的昵称。持有人列表里第 0 项默认就是
  // 当前活跃钱包自己的地址（见 _resetToDefault），所以通常只有它能查到昵称；
  // 后面手动追加的其他共同持有人地址，本机没有为他们存过昵称，_nameFor 会返回 null，
  // 这是预期行为，不是 bug——对方的昵称本来就不可能存在本机存储里。
  Map<String, String> _walletNames = {};

  @override
  void initState() {
    super.initState();
    // 使用调度回调，确保在组件完全挂载后执行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDraft();
    });
    _loadWalletNames();
  }

  // 【新增】加载本地地址昵称索引，用于持有人列表里显示"我的地址"的昵称
  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  // 【新增】统一的昵称查询入口：查不到（比如其他人地址、还没同步）时返回 null，
  // 由调用方决定是否显示，不强行兜底成缩写地址（这里地址本身已经在输入框里显示了）。
  String? _nameFor(String address) {
    if (address.isEmpty) return null;
    final name = _walletNames[address];
    if (name == null || name.trim().isEmpty) return null;
    return name;
  }

  // 1. 载入草稿逻辑
  Future<void> _loadDraft() async {
    // 【待确认】方法名 getRawkeyuData 和其他几处 QccStorage.getRawData /
    // saveRawData / removeData 的命名风格对不上，请确认这是不是笔误
    // （比如应该是某个统一的 getRawData/getRawKeyData），不然这里读草稿
    // 可能一直读的不是预期的 key。
    String? draft = await QccStorage.getRawkeyuData(_storageKey);
    // 检查组件是否还在渲染树中，防止异步返回时页面已销毁
    if (!mounted) return;
    if (draft != null) {
      try {
        LogObj.log("读取临时记录信息$draft");
        Map<String, dynamic> data = jsonDecode(draft);
        List<dynamic> owners = data['owners'] ?? [];
        if (owners.isNotEmpty) {
          setState(() {
            // 先清空当前的控制器，防止跟默认初始化的冲突
            for (var c in _ownerControllers) {
              c.dispose();
            }
            _ownerControllers.clear();
            for (var addr in owners) {
              _ownerControllers.add(TextEditingController(text: addr.toString()));
            }
            // 【修改】阈值不再是可配置项/不再从草稿里读取，见下方"联合签署"说明。
          });
          return;
        }
      } catch (e) {
        LogObj.log("草稿解析失败: $e");
      }
    } else {
      LogObj.log("没有读取到缓存数据");
    }

    // 如果无草稿，执行默认重置
    _resetToDefault();
  }

  // 2. 临时保存逻辑 (在页面销毁或添加地址时调用)
  Future<void> _saveDraft() async {
    List<String> owners = _ownerControllers.map((c) => c.text.trim()).toList();
    // 【修改】QCC 多签是"联合签署"：参与几人就必须几人签署（N-of-N），
    // 阈值不再是用户可选、可编辑的独立信息，本身就等于持有人数量，
    // 所以草稿里不再单独记录 threshold 字段，避免出现"草稿里存了一个
    // 旧的、和当前持有人数量对不上的阈值"这种脏数据。
    Map<String, dynamic> data = {
      'owners': owners,
    };
    LogObj.log("保存临时多签地址$data");
    await QccStorage.saveRawData(_storageKey, jsonEncode(data));
  }

  // 3. 重置功能
  void _resetToDefault() {
    setState(() {
      for (var c in _ownerControllers) {
        c.dispose();
      }
      _ownerControllers.clear();
      _ownerControllers.add(TextEditingController(text: QccObj.activeWallet?.address));
      _ownerControllers.add(TextEditingController());
    });
    QccStorage.removeData(_storageKey); // 清除缓存
  }

  // 增加持有人
  void _addOwner() {
    setState(() {
      _ownerControllers.add(TextEditingController());
    });
    _saveDraft();
  }

  // 删除持有人
  void _removeOwner(int index) {
    setState(() {
      // 【修复】原代码 removeAt 之前没有 dispose 被移除的 controller，
      // 每删一次都会泄漏一个 TextEditingController。
      final removed = _ownerControllers.removeAt(index);
      removed.dispose();
    });
    _saveDraft();
  }

  @override
  void dispose() {
    _saveDraft(); // 退出页面前保存
    for (var c in _ownerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Trans("生成多签规则交易"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _resetToDefault, // 重置按钮
            tooltip: "清空重置",
          )
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: Colors.grey[50]), // 浅灰色背景提升质感
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle("参与持有人 (Owners)", Icons.people_alt_rounded),
            const SizedBox(height: 10),
            ..._ownerControllers.asMap().entries.map((entry) => _buildOwnerField(entry.key, entry.value)),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addOwner,
              icon: const Icon(Icons.add),
              label: Trans("添加参与者"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),

            // 【修改】QCC 多签是"联合签署"：参与多少人就必须多少人签署（N-of-N），
            // 不存在"部分持有人签名即可生效"的场景，所以取消阈值可配置项，
            // 改成一行说明文字，让用户理解生效条件，而不是让他去选一个
            // 实际上永远等于持有人数量的数字。
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Trans(
                      "多签为联合签署：以上全部持有人都签名后才生效",
                      style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 50),
            // 现代化的大按钮
            Container(
              height: 55,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.indigo]),
              ),
              child: ElevatedButton(
                // 【修复】按钮加上 _isProcessing 防重复提交
                onPressed: _isProcessing ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text("确认发布到链上", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 抽离标题组件
  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
      ],
    );
  }

  // 抽离输入框组件
  Widget _buildOwnerField(int index, TextEditingController controller) {
    // 【新增】按当前输入框里的地址实时查一次本地昵称。
    final String? ownerName = _nameFor(controller.text.trim());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 【新增】查到昵称才显示这一行；index 0（本机自己的地址）通常能查到，
              // 后面追加的其他持有人地址本机没有昵称记录，这里就不会显示，符合预期。
              if (ownerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4, bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.badge_outlined, size: 13, color: Colors.blueGrey),
                      const SizedBox(width: 4),
                      Text(
                        index == 0 ? "$ownerName（我的地址）" : ownerName,
                        style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: controller,
                onChanged: (v) {
                  // 【修复】原代码 onChanged 只调用了 _saveDraft()，不触发 setState，
                  // 昵称这一行不会跟着输入实时刷新（比如粘贴地址后昵称行不会出现）。
                  setState(() {});
                  _saveDraft();
                },
                decoration: InputDecoration(
                  hintText: "粘贴或输入 QCC 地址",
                  hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.wallet, size: 20),
                  // 【修复】原来第 0 项（本机自己的地址）是 _resetToDefault() 里
                  // 写死的 QccObj.activeWallet?.address，整个输入框没有任何切换
                  // 入口；其他项也只能手动粘贴，没法直接从本机已导入的钱包里选。
                  // 这里给所有行都加一个"从本机钱包选择"的图标，index>0 时再叠加
                  // 原有的删除按钮（suffixIcon 只接受一个 widget，用 Row 包起来）。
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.blueGrey),
                        tooltip: "从本机钱包选择",
                        onPressed: () => _pickOwnerWallet(index, controller),
                      ),
                      if (index > 0)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                          onPressed: () => _removeOwner(index),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 【新增】弹出本机所有钱包地址，供某一个持有人输入框直接选择，而不是只能
  /// 手动粘贴。index==0（本机自己签署的那一项）选中后，_handleCreate 会按这里
  /// 选中的地址重新去本机钱包列表里匹配对应的 QccWallet 用于签名——不再像原来
  /// 那样始终固定使用全局 QccObj.activeWallet，避免"选了别的地址当持有人 0，
  /// 但实际签名用的私钥还是原来那个 activeWallet"这种地址错配。
  void _pickOwnerWallet(int index, TextEditingController controller) {
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Trans(
                  index == 0 ? "选择我的签署地址" : "选择持有人地址",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: wallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = wallets[i];
                    final bool isSelected = controller.text.trim() == w.address;
                    final String? nick = _nameFor(w.address);
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        nick ?? QccStorage.shortAddress(w.address),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        w.address,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        setState(() {
                          controller.text = w.address;
                        });
                        _saveDraft();
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

  // 核心发布逻辑：包含参数校验、钱包还原、抗量子签名与广播
  Future<void> _handleCreate() async {
    // 1. 基础合法性校验
    List<String> owners = _ownerControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (owners.length < 2) {
      Tools.showToast(context, "多签至少需要 2 个持有地址");
      return;
    }

    // 【修复，重要】原代码不管持有人列表第 0 项实际填的是什么地址，永远直接用
    // 全局 QccObj.activeWallet 去恢复钱包、签名——在第 0 项是写死地址时刚好凑巧
    // 一致，但现在第 0 项已经可以通过上面新增的钱包图标改选成本机任意一个地址，
    // 如果签名逻辑还是继续用 QccObj.activeWallet，就会出现"规则里登记的持有人
    // 0 是地址 A，但实际签名、rData.from 用的却是另一个地址 B"这种错配。这里
    // 改成按 owners[0] 直接去本机钱包列表里查一遍，找到真正持有对应私钥的
    // QccWallet，后面全部改用这个 wallet，不再依赖全局 activeWallet。
    final String selfAddress = owners[0];
    final List<QccWallet> localWallets = QccObj.readWallets();
    QccWallet? activeWallet;
    for (final w in localWallets) {
      if (w.address == selfAddress) {
        activeWallet = w;
        break;
      }
    }
    if (activeWallet == null) {
      Tools.showToast(context, "第一个持有人地址必须是本机已导入的钱包（用于签署），请点击右侧钱包图标选择");
      return;
    }

    // 【修复】原代码只校验了下限，没有上限。Java 侧 toBytes() 的注释明确写了
    // "确保 9-15 人多签不会溢出"，说明后端/协议对持有人数量是有上限约束的，
    // 这里补一个和后端一致的上限保护（如果实际上限不是 15，请按真实值调整）。
    const int kMaxOwners = 15;
    if (owners.length > kMaxOwners) {
      Tools.showToast(context, "多签持有地址最多支持 $kMaxOwners 个");
      return;
    }
    // 【修改】联合签署 (N-of-N)：阈值不再由用户输入，永远等于持有人数量。
    final int threshold = owners.length;

    // 2. 验证支付密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);

    // 3. 启动状态通知 Loading
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);
    bool loadingShown = true;

    try {
      // ---- A. 还原钱包 (在隔离的子线程中处理耗时的解密) ----
      statusNotifier.value = TxStep.restoring;

      QccWallet? wallet = await QccStorage.restoreWallet(context, activeWallet.address, password);
      if (!mounted) return;
      if (wallet == null || wallet.address != activeWallet.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // ---- B. 构建多签规则数据 (RuleData) ----
      statusNotifier.value = TxStep.building;
      final ms = MultiSignature(owners: owners, threshold: threshold);
      final rData = RuleData();
      rData.from = wallet.address;
      rData.ruleType = "UserRule";
      rData.ruleName = "MultiSignature";
      rData.ruleJson = ms.toJson();
      // 【修复】对应 Java：createRule.ruleAppendJson = "";
      // Java 端注释明确写了 toBytes() 里 "必须写入，否则上链数据不全"，
      // 且 toSign() 的签名原文也包含这个字段，原代码完全没有设置这一行。
      rData.ruleAppendJson = "";
      rData.finalizeId(); // 生成规则唯一 ID
      // chain 字段现在由 RuleData() 构造函数自动填充（对齐 Java 基类行为），
      // 这里不需要再手动设置。

      // ---- C. 抗量子签名 (在子线程执行 Dilithium5 签名任务) ----
      statusNotifier.value = TxStep.signing;
      // 【修复】原来这里直接调 QccDataProtocol.encodeTransaction，但那个方法
      // 内部的签名逻辑是被注释掉的（signature 恒为 ""），也就是说提交上去的
      // 创建多签交易，签名字段实际上是空的。改成统一走 SignUtil，它会用
      // rData.toSign() 单独签名后再覆盖 packet.signature。
      final QccPacket packet = await SignUtil.instance.signAndEncode(
        from: wallet.address,
        toSignString: rData.toSign(),
        payloadJson: jsonEncode(rData.toJson()),
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // ---- D. 广播至 QCC 网络 (API: /v1/mtxrule) ----
      statusNotifier.value = TxStep.submitting;
      // 【修改】之前这里改成过 QccNodeManager.instance.currentBaseUrl() 动态
      // 挑活跃节点，但按你的决定：多签的创建/追加/查询这几类请求现在统一固定
      // 打 MultiSigNode.baseUrl 这一个节点，不再参与 QccNodeManager 的动态
      // 选择/故障转移——原因见 MultiSigNode.dart 顶部注释：多签"待签会话"是
      // 单节点内存态，创建和追加签署如果落在不同节点会直接 404，签名永远凑
      // 不齐。固定节点后不再需要 reportSuccess/reportFailure 这类给
      // QccNodeManager 反馈健康度的调用（这里已经不参与它的节点挑选了）。
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
            // 原有修复保留：没有超时控制，服务器无响应时 Loading 会一直卡住。
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        // 固定节点这次请求失败（超时/网络层错误）：没有其他节点可以切换，
        // 直接交给外层 catch 统一处理 Loading 关闭/提示。
        rethrow;
      }

      if (!mounted) return;
      Navigator.pop(context); // 任务完成，关闭 Loading 弹窗
      loadingShown = false;

      if (response.statusCode == 200) {
        Map<String, dynamic> resData = jsonDecode(response.body);
        LogObj.log("创建多签返回的内容:$resData");

        // 【修复】原代码只处理了 statusCode==200，完全没检查业务层的
        // resData['status']（对照 Follow 页面用的是 status=="ACCEPTED"
        // 判定），200 但业务失败时用户拿到的是"什么都没发生"。
        if (resData['status'] != null && resData['status'] != 'ACCEPTED') {
          final String msg =
              (resData['message'] ?? resData['msg'] ?? resData['status']).toString();
          Tools.showToast(context, "创建失败: $msg");
          return;
        }

        // 【新增】标记该地址已成功提交过交易，供 SignUtil 的
        // "已提交过就不重复发公钥" 特性使用（该特性目前默认关闭，
        // 见 SignUtil.dart 里 enablePublicKeySkip 的说明）。
        await SignUtil.instance.markSubmitted(wallet.address);

        // 1. 先异步保存到本地文件
        // 【说明】不再需要记录 nodeBaseUrl 了——创建/追加/查询现在统一固定
        // 打 MultiSigNode.baseUrl，不存在"这次提交到了哪个节点"这个变量了。
        await MultiSigFileStorage.saveTask({
          'txHash': resData['txHash'],
          'type': 'rule',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        // 2. 解析出 UI 需要显示的参数 (从嵌套的 data 字符串中提取)
        final Map<String, dynamic> innerData = jsonDecode(resData['data'] as String);
        final Map<String, dynamic> ruleJson = jsonDecode(innerData['ruleJson'] as String? ?? '{}');
        // 3. 跳转到发起成功展示页
        if (!mounted) return;
        QccStorage.removeData(_storageKey);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MultiSigInitiatedPage(
              txHash: resData['txHash'],
              type: MultiSigPageType.createRule,
              owners: List<String>.from(ruleJson['owners'] ?? []),
              threshold: ruleJson['threshold'] ?? 0,
            ),
          ),
        );
      } else {
        // 【修复】非 200 状态码原来完全没有反馈
        Tools.showToast(context, "服务器返回异常状态码: ${response.statusCode}");
      }
    } catch (e) {
      LogObj.log("创建多签失败: $e");
      if (loadingShown && Navigator.canPop(context)) {
        Navigator.pop(context); // 确保出错时关闭 Loading
      }
      if (mounted) {
        Tools.showToast(context, "操作失败: $e");
      }
    } finally {
      statusNotifier.dispose();
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
