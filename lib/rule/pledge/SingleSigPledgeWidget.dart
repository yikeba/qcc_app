import 'package:flutter/material.dart';
import '../../utile/LogObj.dart';
import '../../utile/Tools.dart';
import '../../utile/QccObj.dart';
import '../../qccwallet/QccActiveWallet.dart'; // 引入活跃钱包管理
import '../../views/setting/AppTranslator.dart';

class SingleSigPledgeWidget extends StatefulWidget {
  const SingleSigPledgeWidget({super.key});

  @override
  State<SingleSigPledgeWidget> createState() => _SingleSigPledgeWidgetState();
}

class _SingleSigPledgeWidgetState extends State<SingleSigPledgeWidget> {
  String _currentAddress = "";
  // 按照 Java 案例，金额为 100,000 QCC (内部计算需乘以 1e9 或使用精密单位)
  final double _pledgeAmount = 100000.0;

  @override
  void initState() {
    super.initState();
    _loadActiveWallet();
  }

  /// 加载当前单签活跃钱包地址
  void _loadActiveWallet() {
    final active = QccObj.activeWallet;
    if (active != null) {
      setState(() {
        _currentAddress = active.address;
      });
    } else {
      // 如果没有活跃钱包，从读取列表兜底
      final wallets = QccObj.readWallets();
      if (wallets.isNotEmpty) {
        setState(() {
          _currentAddress = wallets[0].address;
        });
      }
    }
  }

  /// 执行质押发起逻辑
  void _handlePledgeSubmit() {
    if (_currentAddress.isEmpty) {
      Tools.showToast(context, "未发现可用钱包地址");
      return;
    }

    // 预留执行逻辑入口
    LogObj.log("发起单签质押交易:");
    LogObj.log("发起地址: $_currentAddress");
    LogObj.log("质押金额: $_pledgeAmount QCC");

    // 提示用户
    Tools.showToast(context, "正在构造质押规则，请稍候...");

    // TODO: 调用您的执行逻辑，例如：
    // doPledgeAction(address: _currentAddress, amount: _pledgeAmount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("个人单签质押"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("发起质押地址"),
            _buildAddressCard(),

            const SizedBox(height: 24),

            _buildSectionTitle("固定质押金额"),
            _buildAmountCard(),

            const SizedBox(height: 32),

            _buildNoticeBox(),

            const Spacer(),

            // 确定发起按钮
            ElevatedButton(
              onPressed: _handlePledgeSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Trans("确定质押发起",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Trans(title, style: const TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
    );
  }

  // 显示当前地址卡片
  Widget _buildAddressCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.blueAccent),
        title: Text(_currentAddress.isEmpty ? "读取中..." : _currentAddress,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Trans("当前活跃钱包地址"),
      ),
    );
  }

  // 显示金额卡片（不可编辑，确保合规）
  Widget _buildAmountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("100,000", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text("QCC", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 规则说明小贴士
  Widget _buildNoticeBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(child: Trans("质押后资产将被公链协议锁定，仅用于满足稳定币发行权限。",
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey))),
        ],
      ),
    );
  }
}