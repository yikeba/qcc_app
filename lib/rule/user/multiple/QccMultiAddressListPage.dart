
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import 'multicreat/MultiSigAddressStorage.dart';
import 'QccMultiSig.dart';

class QccMultiAddressListPage extends StatefulWidget {
  const QccMultiAddressListPage({super.key});

  @override
  State<QccMultiAddressListPage> createState() => _QccMultiAddressListPageState();
}

class _QccMultiAddressListPageState extends State<QccMultiAddressListPage> {
  List<MultiSigAccount> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 确保读取前 init 成功
    final validAccounts = await MultiSigAddressStorage.getAllAccounts();
    //LogObj.log("QCC DEBUG_: UI 层获取到的账户列表长度: ${validAccounts.length}");

    if (mounted) {
      setState(() {
        _accounts = validAccounts;
        _isLoading = false;
      });
    }
  }

  // --- 核心删除逻辑 ---
  Future<void> _handleDeleteAccount(MultiSigAccount account) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("移除地址"),
        content: Trans("是否从本地列表中移除此多签地址？"),
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
      // 1. 调用存储类执行删除 (根据 multiAddress 唯一标识删除)
      await MultiSigAddressStorage.deleteAccount(account.multiAddress);

      // 2. 更新 UI 状态
      setState(() {
        _accounts.removeWhere((element) => element.multiAddress == account.multiAddress);
      });
      Tools.showToast(context, "地址已移除");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 蓝白背景
      appBar: AppBar(
        title: Trans("多签地址管理"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
          ? _buildEmpty()
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final account = _accounts[index];
          return _buildAccountItemRow(account);
        },
      ),
    );
  }

  // 构建带删除按钮的行
  Widget _buildAccountItemRow(MultiSigAccount account) {
    return Row(
      children: [
        // 左侧显式删除按钮
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 24),
          onPressed: () => _handleDeleteAccount(account),
        ),
        // 右侧地址详情卡片
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
            ),
            child: Column(
              children: [
                _buildExpandableAccountCard(account), // 您原来的卡片详情 UI
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableAccountCard(MultiSigAccount account) {
    // 为当前多签地址创建余额显示实例
    // 假设 assetId 为 "QCC"，你也可以根据业务需求调整
    final walletHelper = QccActiveWallet(
        account.multiAddress,
        "QCC",
        fontSize: 14.0,
        fontColor: Colors.blueAccent
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: const Icon(Icons.account_balance_wallet, color: Colors.blue, size: 20),
        ),
        // 标题：显示 M 地址
        title: Text(
          account.multiAddress,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
        ),
        // 副标题：左侧显示进度，右侧显示余额
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${AppTranslationManager.instance.getTranslatedSync("进度")}: ${account.actualSignerCount}/${account.maxCount}",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              // --- 接入点：调用 QccActiveWallet 的余额显示组件 ---
              walletHelper,
            ],
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blueGrey.withOpacity(0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("单签成员序列 (审计存证):", style: TextStyle(fontSize: 11, color: Colors.grey)),
                const Divider(),
                ...account.addrs.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String addr = entry.value;
                  bool isAudit = account.owners.length >= account.maxCount;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(isAudit ? Icons.verified_user : Icons.person_outline,
                            size: 14, color: isAudit ? Colors.green : Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(child: SelectableText(addr, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          onPressed: () => Tools.copytext(context, addr),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Tools.copytext(context, account.multiAddress),
                        icon: const Icon(Icons.copy, size: 14),
                        label: Trans("复制多签"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () { /* TODO: 跳转转账 */ },
                        icon: const Icon(Icons.send, size: 14),
                        label: Trans("发起转账"),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Trans("暂无已生效的多签地址", style: const TextStyle(color: Colors.grey)));
  }
}