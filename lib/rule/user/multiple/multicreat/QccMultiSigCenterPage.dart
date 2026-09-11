import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/txdata/tx/QccTransaction.dart';
import 'package:qcc_flutter/utile/JsonUtil.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import '../../../../txdata/tx/TransferSuccessPage.dart';
import '../../../../utile/Tools.dart';
import '../../../../views/myasset/QccAssetService.dart';
import '../../../../views/setting/AppTranslator.dart';
import '../QccMultiSig.dart';
import '../QccMultiSigData.dart';
import 'MultiSigAddressStorage.dart';
import 'MultiSigInitiatedPage.dart';
import '../MultiSigFileStorage.dart';
import 'QccMultiSigService.dart';
class QccMultiSigCenterPage extends StatefulWidget {
  const QccMultiSigCenterPage({super.key});
  @override
  State<QccMultiSigCenterPage> createState() => _QccMultiSigCenterPageState();
}

class _QccMultiSigCenterPageState extends State<QccMultiSigCenterPage> {
  List<String> _localHashes = [];
  bool _isInit = true;
  final Map<String, Future<MultiSigTaskWrapper?>> _taskFutures = {};

  // 【新增】原来 _handleRefresh() 只把 txHash 摘出来存进 _localHashes，
  // 本地记录里其他字段（尤其是 MultiSigFileStorage.saveConfirmedAccount 写的
  // status='SUCCESS' + multiAddress）全部被丢弃。这些字段是"链上/内存都
  // 查不到时兜底展示"必需的信息（见 _buildItemRow 里的
  // fetchTaskWithLocalFallback），所以这里额外按 hash 存一份完整记录。
  Map<String, Map<String, dynamic>> _localRecords = {};

  @override
  void initState() {
    super.initState();
    _handleRefresh();
  }

  Future<void> _handleRefresh() async {
    try {
      final List<dynamic> tasks = await MultiSigFileStorage.getAllTasks();
      if (mounted) {
        setState(() {
          final Map<String, Map<String, dynamic>> byHash = {};
          for (final e in tasks) {
            if (e is Map) {
              final String h = (e['txHash'] ?? "").toString().trim();
              if (h.length > 10) byHash[h] = Map<String, dynamic>.from(e);
            } else if (e is String) {
              final String h = e.trim();
              if (h.length > 10 && !byHash.containsKey(h)) byHash[h] = {'txHash': h};
            }
          }
          _localRecords = byHash;
          _localHashes = byHash.keys.toList().reversed.toList();
          _taskFutures.clear();
          _isInit = false;
        });
      }
    } catch (e) {
      debugPrint("QCC DEBUG_: $e");
    }
  }

  // 修改 QccMultiSigCenterPage.dart 中的算法
  Map<String, dynamic> _calculateProgress(MultiSigTaskWrapper task) {
    // 1. 最高标准判定：如果 status 为 SUCCESS，代表已上链
    bool isConfirmedOnChain = task.data['status'] == 'SUCCESS' || task.isConfirmed;
    // 2. 类型判定逻辑：
    // 如果已上链且包含 fromMulti，则是多签转账；
    // 如果 data 中包含 amount 或 txType == 'pay'，也是转账。
    bool isTransfer = task.type == MultiSigTaskType.transaction ||
        task.data['fromMulti'] != null ||
        task.data['txType'] == 'pay';

    if (isConfirmedOnChain) {
      return {
        'current': 1,
        'threshold': 1,
        'isFinish': true,
        'isTransfer': isTransfer,
        // 【修复】原来只读 fromMulti（转账类型才有这个字段），"规则"类型
        // 完成后（包括本地兜底记录）根本没有 fromMulti，一直拿到空字符串。
        // 补上 multiAddress 兜底。
        'mAddr': task.data['fromMulti'] ?? task.data['multiAddress'] ?? ""
      };
    }

    // 3. 内存池待签逻辑
    int threshold = 0;
    try {
      var rule = task.data['ruleJson'] != null
          ? jsonDecode(task.data['ruleJson'].toString())
          : task.data;
      threshold = rule['threshold'] ?? 0;
    } catch (_) {}

    // 【修复，重要】原来这里写的是 `task.signedOwners.length - (threshold - 1)`。
    // 待签阶段 task.data（MultiSingManager.getSession() 返回）里
    // signedOwners 本来就是"已经签了的地址列表"本身（比如 threshold=2 时，
    // 刚发起、只有发起人签了一次，signedOwners 长度就是 1），不需要再减
    // (threshold-1) 去做任何换算——例子里 threshold=2、signedOwners 长度=1，
    // 按原公式算出来是 1-(2-1)=0，界面就一直显示成 "0/2"，而后端其实已经
    // 有 1 个人签了，应该显示 "1/2"。这里直接去重后取长度即可；后端返回的
    // currentCount 字段本来就是同一个值，如果存在就优先用它，更贴近后端的
    // 权威计数。
    int actualCount = task.data['currentCount'] is int
        ? task.data['currentCount']
        : task.signedOwners.toSet().length;

    return {
      'current': actualCount,
      'threshold': threshold,
      'isFinish': actualCount >= threshold && threshold > 0,
      'isTransfer': isTransfer,
      'mAddr': task.data['multiAddress']
    };
  }

  // 修改 QccMultiSigCenterPage.dart 中的 _onTapDetail 方法
  void _onTapDetail(MultiSigTaskWrapper task) {
    final prog = _calculateProgress(task);

    // 判定：如果已经完成上链，且是转账类型
    if ( (task.type == MultiSigTaskType.transaction || task.data['fromMulti'] != null)) {
      // 构造一个 QccTransactionData 对象给 TransferSuccessPage 使用
      QccTransaction txData;
      if(task.data.containsKey("data")){
        Map txmap=JsonUtil.strtoMap(task.data["data"]);
        txData = QccTransaction(
          from: txmap['fromMulti'] ?? "",
          to: txmap['to'] ?? "",
          //amount: (task.data['amount'] ?? 0) / 100000000.0,
          amount: QccAssetService().getHumanAmountNum(
              txmap['assetId'], txmap['amount']),
          assetId: txmap['assetId'] ?? "QCC",
          txHash: task.txHash,
          type: "multitransaction",
          timestamp: txmap['timestamp'] ?? DateTime
              .now()
              .millisecondsSinceEpoch,
          status: '',
        );
      }else {
        txData = QccTransaction(
          from: task.data['fromMulti'] ?? "",
          to: task.data['to'] ?? "",
          //amount: (task.data['amount'] ?? 0) / 100000000.0,
          amount: QccAssetService().getHumanAmountNum(
              task.data['assetId'], task.data['amount']),
          assetId: task.data['assetId'] ?? "QCC",
          txHash: task.txHash,
          type: "multitransaction",
          timestamp: task.data['timestamp'] ?? DateTime
              .now()
              .millisecondsSinceEpoch,
          status: '',
        );
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TransferSuccessPage(transaction: txData),
        ),
      );
    } else {
      // 如果是“多签规则生成”或者是“还在签署中”的转账，进入多签专用页
      //
      // 【修复，重要】task.data 在这里有三种不同的形状，不能一概用
      // QccMultiSigData.fromJson() 去解：
      //   - 已上链（含 'ruleJson' 字段）：task.data 是 RuleData 原始格式，
      //     形如 {chain, from, timestamp, ruleJson(字符串), ruleName,
      //     ruleAppendJson(字符串), txHash, ...}——QccMultiSigData.fromJson()
      //     就是按这个形状写的，继续用它没问题。
      //   - 还在 leader 内存里等待签署：task.data 是
      //     MultiSingManager.getSession()/getTxSession() 返回的"待签会话
      //     摘要"，形如 {kind, txHash, expiry, expiryInSeconds, threshold,
      //     owners, currentCount, signedOwners}——没有 ruleJson。
      //   - 【新增】mtxquery + 链上查询都失败、靠本地缓存兜底展示的记录
      //     （fetchTaskWithLocalFallback 构造的）：isConfirmed 是 true，
      //     但同样没有 ruleJson，只有顶层的 status/multiAddress/owners/
      //     threshold（owners/threshold 大概率是空的——本地当初只存了
      //     地址和状态）。如果这里继续按 task.isConfirmed 分流，会把这种
      //     记录也送进 QccMultiSigData.fromJson()，因为没有 ruleJson/from/
      //     ruleName 直接崩溃或拿到全空数据。
      //
      // 改成按"有没有 ruleJson"分流（和 _checkAndSaveAccount 保持一致）：
      // 有 ruleJson 就是标准已上链形状，继续走原来的解析；没有 ruleJson
      // 的（待签内存形状 + 本地兜底形状）统一从顶层字段取，多签地址取不到
      // 就是空字符串，不强行伪造。
      LogObj.log("多签地址显示:${task.data}");
      List<String> owners;
      int threshold;
      String multiAddress;
      // 【新增】除了"全体参与地址"(owners)，还要单独拿到"已签署的地址"
      // (signedOwners)，这样详情页才能逐个地址标出谁签了、谁还没签——
      // 而不是只笼统显示一个 "threshold/threshold" 的数字。
      List<String> signedOwnersList;
      if (task.data['ruleJson'] != null) {
        QccMultiSigData multiSig = QccMultiSigData.fromJson(task.data);
        owners = multiSig.ruleJson.owners;
        threshold = multiSig.ruleJson.threshold;
        multiAddress = multiSig.ruleJson.multiaddress;
        // 已上链 = 规则已经生效，owners 里能拿到的都视为已完成签署
        // （后端目前不区分"候选人"和"已签名人"两个字段，这里按最终生效的
        // owners 全部标记为已签）。
        signedOwnersList = owners;
      } else {
        owners = List<String>.from(task.data['owners'] ?? [])
            .map((e) => e.toString())
            .toSet()
            .toList();
        threshold = task.data['threshold'] ?? 0;
        // 待签阶段/本地兜底形状都没有 ruleJson——multiaddress 从顶层字段
        // 直接取；待签阶段这里本来就是空，兜底形状则是本地存过的真实地址。
        multiAddress = (task.data['multiaddress'] ?? task.data['multiAddress'] ?? '').toString();
        signedOwnersList = task.signedOwners.toSet().toList();
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MultiSigInitiatedPage(
            txHash: task.txHash,
            owners: owners,
            signedOwners: signedOwnersList,
            threshold: threshold,
            isFinish: prog['isFinish'],
            multiAddress: multiAddress,
            type: task.type == MultiSigTaskType.transaction ? MultiSigPageType.transfer : MultiSigPageType.createRule,
          ),
        ),
      );
    }
  }

  // 在 QccMultiSigCenterPage 的列表渲染或刷新逻辑中
  void _checkAndSaveAccount(MultiSigTaskWrapper task) {
    // 1. 提取多签地址（和阈值——一起从同一个已解析的 rule 里取，不要分开取）
    String? mAddr;
    int? threshold;
    if (task.data['ruleJson'] != null) {
      try {
        var rule = jsonDecode(task.data['ruleJson'].toString());
        mAddr = rule['multiaddress'] ?? rule['multiAddress'];
        // 【修复】原来这里单独去读 task.data['threshold']——但已上链的
        // RuleData 顶层根本没有 threshold 这个字段（threshold 是包在
        // ruleJson 字符串里面的），顶层取不到永远回退到写死的 3，
        // 存进 MultiSigAddressStorage 的阈值就一直是错的。改成和地址一样，
        // 从已经解析出来的 rule 里取。
        threshold = rule['threshold'];
      } catch(_) {}
    }

    // 2. 如果地址出现了，且是 Confirmed 状态，就存为正式资产
    if (mAddr != null && mAddr.startsWith('M') && task.isConfirmed) {
      MultiSigAddressStorage.saveConfirmedAccount(MultiSigAccount(
        multiAddress: mAddr,
        owners: task.signedOwners, // 这里的 5 个地址序列直接存，保留审计存证
        threshold: threshold ?? 3,
        txHash: task.txHash, createTime: null,
      ));
    }
  }

  // --- 核心方法：执行删除逻辑 (不依赖载入状态) ---
  Future<void> _handleDelete(String hash) async {
    // 弹出提示告知客户
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("移除记录"),
        content: Trans("是否从本地列表中移除此条记录？（不会影响链上数据）"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Trans("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Trans("确定", style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MultiSigFileStorage.deleteTask(hash); // 彻底从本地存储删除
      if (mounted) {
        setState(() {
          _localHashes.remove(hash);
          _taskFutures.remove(hash); // 清理缓存
          _localRecords.remove(hash);
        });
        Tools.showToast(context, "已移除");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trans = AppTranslationManager.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 蓝白背景
      appBar: AppBar(
        title: Trans("多签管理中心"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: _handleRefresh,
          )
        ],
      ),
      body: _isInit
          ? const Center(child: CircularProgressIndicator())
          : _localHashes.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _localHashes.length,
          itemBuilder: (context, index) {
            final hash = _localHashes[index];
            // 重点：外层包裹 Row，左侧固定放置删除按钮
            return _buildItemRow(hash, trans);
          },
        ),
      ),
    );
  }

  // 构建带删除按钮的行
  Widget _buildItemRow(String hash, AppTranslationManager trans) {
    return Row(
      children: [
        // 1. 左侧删除按钮：无论状态如何，始终可点击
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
          onPressed: () => _handleDelete(hash),
        ),
        // 2. 右侧主体：FutureBuilder 承载任务详情
        Expanded(
          child: FutureBuilder<MultiSigTaskWrapper?>(
            // 【修复】原来这里直接调 fetchTask(hash)——mtxquery 查不到、链上
            // 也查不到（节点暂时不可达、IPv6 不通、链上索引还没同步过来）
            // 就直接判定成"加载失败或记录已失效"，即便这条记录其实早就
            // 完成、本地也已经写过 status='SUCCESS'+multiAddress，也照样
            // 显示成一条错误提示。改成 fetchTaskWithLocalFallback：查询失败
            // 时，如果本地记录已经标记完成，就用本地记录兜底展示，而不是
            // 报错。
            future: _taskFutures.putIfAbsent(
                hash, () => QccMultiSigService.fetchTaskWithLocalFallback(hash, _localRecords[hash])),
            builder: (context, snapshot) {
              // 处理加载中或解析失败的情况，依然允许显示并删除
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildSimpleLoadingTile(hash);
              }

              if (!snapshot.hasData || snapshot.data == null) {
                return _buildErrorTile(hash, trans);
              }

              final task = snapshot.data!;
              // --- 关键点：数据加载完成后，自动调用检查方法 ---
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _checkAndSaveAccount(task);
              });
              final prog = _calculateProgress(task);
              bool isFinish = prog['isFinish'] ?? false;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Icon(
                    isFinish ? Icons.check_circle : Icons.hourglass_bottom,
                    color: isFinish ? Colors.green : Colors.blueAccent,
                  ),
                  /* title: Text(
                    task.type == MultiSigTaskType.transaction ? trans.getTranslatedSync("多签转账") : trans.getTranslatedSync("多签规则"),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),*/
                  subtitle: Text("Hash: ${hash.substring(0, 6)}...${hash.substring(hash.length - 6)}", style: const TextStyle(fontSize: 10)),
                  // 在 ListTile 中修改 title
                  title: Builder(builder: (context) {
                    final prog = _calculateProgress(task);
                    String title = prog['isTransfer'] ? "多签转账" : "多签规则";
                    return Trans(title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    );
                  }),
// 修改 trailing 的显示，防止出现 1/0
                  trailing: Builder(builder: (context) {
                    final prog = _calculateProgress(task);
                    if (prog['isFinish']) {
                      return const Icon(Icons.done_all, color: Colors.green);
                    }
                    return Text(
                      "${prog['current']}/${prog['threshold']}",
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    );
                  }),
                  onTap: () => _onTapDetail(task),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 加载中的占位，左侧依然有删除按钮
  Widget _buildSimpleLoadingTile(String hash) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text("Loading Hash: ${hash.substring(0, 8)}...", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  // 解析失败的占位（比如网络超时），允许用户直接删除
  Widget _buildErrorTile(String hash, AppTranslationManager trans) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Text("${trans.getTranslatedSync("加载失败或记录已失效")}: ${hash.substring(0, 8)}...", style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Trans("暂无已生效的多签地址", style: const TextStyle(color: Colors.grey)));
  }
}