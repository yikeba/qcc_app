import 'package:flutter/material.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import '../../procotol/PledgetType.dart';
import 'util/PledgeFileStorage.dart';

/// 我的质押记录——本机全部质押/授权 lock 记录的只读汇总视图。
///
/// 【定位说明】这不是链上"质押列表"接口的展示（没有找到这样的接口，见
/// PledgeFileStorage.dart 头部说明），只是本机 PledgeFileStorage 落盘记录的
/// 汇总入口，方便用户在"发起质押"之外，快速看一眼自己名下有哪些还没解押
/// 的质押/授权。真正的解押/吊销操作仍在对应的"普通质押/超级节点质押/
/// 授权质押"标签页里做（那几个页面各自从这份存储里按条件筛选出可解押的
/// 记录），这里只做展示 + 允许删除一条本地记录（比如记错、测试数据）。
///
/// 🐛 FIX（数量显示）：三个提交端（Common/Authorized/SuperNode）现在存进
/// PledgeFileStorage 的 amount 都是换算后的最小单位（跟提交给链上的值一致，
/// 见各自 _handleSubmit 里的注释），这里原来直接把这个最小单位数字展示出来，
/// 会让用户以为自己质押的是一个天文数字。暂时用 _formatAmount() 做一个
/// "假设 precision=9"的除法兜底显示——这跟 QccAssetService.getAmountRaw()
/// 换算时用的精度是同一套（对话里确认过 1 QCC = 1e9 最小单位）。
/// ⚠️ 注意：getAmountRaw() 是按 assetId 查精度的，理论上不同资产精度可能不同；
/// 目前没有拿到 QccAssetService.dart 源码确认是否所有资产都固定 9 位精度，
/// 所以这只是一个"多数情况下正确"的兜底显示，不是权威转换。如果 QccAssetService
/// 里有现成的反向换算方法（把最小单位转回可读数量），把 _formatAmount() 换成
/// 调用那个方法会更准确。
class PledgeRecordsWidget extends StatefulWidget {
  const PledgeRecordsWidget({super.key});

  @override
  State<PledgeRecordsWidget> createState() => _PledgeRecordsWidgetState();
}

class _PledgeRecordsWidgetState extends State<PledgeRecordsWidget> {
  List<Map<String, dynamic>> _records = [];
  Map<String, String> _walletNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = await QccStorage.getAllWalletNames();
    final localAddrs = QccObj.readWallets().map((e) => e.address).toSet();
    final all = await PledgeFileStorage.getAllTasks();
    // 只展示本机地址发起的记录——避免"本机曾经查看过别人分享的记录"混进来
    // （目前实现里只有本机自己 lock 时才会写入，这一步过滤是双保险）。
    final mine = all.where((t) => localAddrs.contains((t['address'] ?? '').toString())).toList();
    mine.sort((a, b) => ((b['timestamp'] ?? 0) as num).compareTo((a['timestamp'] ?? 0) as num));
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _records = mine;
      _isLoading = false;
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("删除本地记录"),
        content: Text("只删除本机缓存的这条记录，不影响链上真实状态。\ntxHash: ${r['txHash']}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("删除")),
        ],
      ),
    );
    if (ok == true) {
      await PledgeFileStorage.deleteTask((r['txHash'] ?? '').toString());
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text("本机暂无质押记录。\n在其它标签页发起质押/授权后会自动出现在这里。", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _buildRecordTile(_records[i]),
    );
  }

  Widget _buildRecordTile(Map<String, dynamic> r) {
    final String protocol = (r['protocol'] ?? '').toString();
    final String status = (r['status'] ?? 'LOCKED').toString();
    final bool unlocked = status == 'UNLOCKED';
    final String address = (r['address'] ?? '').toString();
    final String? nick = _walletNames[address];
    final String txHash = (r['txHash'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: unlocked ? Colors.grey.shade200 : Colors.indigo.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusPill(unlocked),
              const SizedBox(width: 8),
              Text(PledgetType.label(protocol), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                onPressed: () => _confirmDelete(r),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text("资产: ${r['assetId'] ?? '-'}  ·  数量: ${_formatAmount(r['amount'])}", style: const TextStyle(fontSize: 12, color: Colors.black87)),
          if ((r['tag'] ?? '').toString().isNotEmpty) Text("标签: ${r['tag']}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(nick != null ? "$nick ($address)" : address, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey)),
          const SizedBox(height: 4),
          Text("txHash: $txHash", style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey)),
        ],
      ),
    );
  }

  /// 兜底把最小单位数字换算回可读数量（假设 precision=9）。见文件头注释：
  /// 这不是权威换算，只是防止界面上直接显示 180000000000 这种数字。
  String _formatAmount(dynamic raw) {
    if (raw == null) return '-';
    final n = raw is num ? raw : num.tryParse(raw.toString());
    if (n == null) return raw.toString();
    final display = n / 1000000000;
    // 去掉多余的尾随 0，但保留必要的小数位。
    String s = display.toStringAsFixed(9);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  Widget _buildStatusPill(bool unlocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: (unlocked ? Colors.grey : Colors.green).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(unlocked ? "已解押" : "质押中", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: unlocked ? Colors.grey.shade700 : Colors.green.shade700)),
    );
  }
}