import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../utile/LogObj.dart';
import '../../utile/Tools.dart';
import '../../home/QccExplorerService.dart';
import '../../views/setting/AppTranslator.dart';
import '../user/multiple/multicreat/MultiSigAddressStorage.dart';
import '../user/multiple/QccMultiSig.dart';

class QccPledgeCenterWidget extends StatefulWidget {
  const QccPledgeCenterWidget({super.key});

  @override
  State<QccPledgeCenterWidget> createState() => _QccPledgeCenterWidgetState();
}

class _QccPledgeCenterWidgetState extends State<QccPledgeCenterWidget> {
  List<MultiSigAccount> _accounts = [];
  List<dynamic> _allPledgeOrders = []; // 汇总所有地址的质押明细
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAndFetchData();
  }

  /// 1. 严格参考案例：读取本地多签地址并批量查询接口
  Future<void> _loadAndFetchData() async {
    setState(() => _isLoading = true);
    _allPledgeOrders.clear();

    try {
      // 从本地存储获取所有多签账户
      final list = await MultiSigAddressStorage.getAllAccounts();
      if (!mounted) return;

      setState(() {
        _accounts = list;
      });

      // 遍历所有本地多签地址，拉取质押信息
      for (var account in _accounts) {
        await _fetchPledgeByAddress(account.multiAddress);
      }

      // (可选) 如果需要，也可以把当前单签钱包地址的质押也查一下
      // await _fetchPledgeByAddress(QccObj.activeWallet!.address);

    } catch (e) {
      LogObj.log("加载质押数据中心失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 2. 核心 API 请求：读取是否有质押
  Future<void> _fetchPledgeByAddress(String address) async {
    try {
      final url = "${QccExplorerService.baseUrl}/v1/pledge/$address";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        Map<String, dynamic> res = jsonDecode(response.body);
        if (res['ok'] == true && res['data'] != null) {
          List decodedData = jsonDecode(res['data']);
          // 注入所属地址，方便 UI 识别是哪个多签账户的质押
          for (var item in decodedData) {
            item['_ownerAddress'] = address;
            _allPledgeOrders.add(item);
          }
        }
      }
    } catch (e) {
      LogObj.log("查询地址 $address 质押失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("质押订单明细"),
        actions: [
          IconButton(onPressed: _loadAndFetchData, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _allPledgeOrders.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allPledgeOrders.length,
        itemBuilder: (context, index) => _buildOrderCard(_allPledgeOrders[index]),
      ),
    );
  }

  /// 3. 订单明细卡片（支持解压操作入口）
  Widget _buildOrderCard(Map<String, dynamic> item) {
    double amount = (item['amount'] ?? 0) / 1e9;
    String txHash = item['credentialHash'] ?? "";
    String ownerAddr = item['_ownerAddress'] ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Text("${amount.toStringAsFixed(2)} ${item['assetId']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                const SizedBox(width: 8),
                _statusTag(item['actionType']),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("所属地址: ${_shortAddr(ownerAddr)}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
            trailing: item['actionType'] == "lock"
                ? ElevatedButton(
              onPressed: () => _gotoUnlockProposal(item),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
              child: Trans("解除质押"),
            )
                : const Icon(Icons.check_circle_outline, color: Colors.green),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("凭证: ${_shortAddr(txHash)}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                Text("版本: ${item['version']}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statusTag(String? type) {
    bool isLock = type == "lock";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLock ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(isLock ? "已质押" : "已解押",
          style: TextStyle(color: isLock ? Colors.orange : Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  /// 4. 跳转逻辑：发起解押提案
  void _gotoUnlockProposal(Map<String, dynamic> item) {
    // 找到对应的多签账户对象，以便传递给发起页
    final account = _accounts.firstWhere((element) => element.multiAddress == item['_ownerAddress']);

   /* Tools.showConfirmDialog(
        context,
        title: "发起解押申请",
        content: "系统将为该地址发起解押提案，所有成员签署通过后，${item['amount'] / 1e9} QCC 将解锁至余额。确认继续？",
        onConfirm: () {
          // 逻辑：跳转到多签发起页，并预设 actionType 为 unlock, credentialHash 为当前 ID
          LogObj.log("准备为地址 ${account.multiAddress} 发起解押逻辑...");
          // 此处通常 Navigator.push(context, ...) 跳转到您的多签发起 Widget
        }
    );*/
  }

  String _shortAddr(String addr) {
    if (addr.length < 12) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 6)}";
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Trans("本地关联地址暂无质押记录", style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}