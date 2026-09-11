import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/utile/QccStorage.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'EntityDataFileStorage.dart';

/// 存证发布 —— 明细中心。
///
/// 【对应你的要求】"需要增加一个明细中心来显示发布信息明细"：
/// EntityDataFileStorage 落盘之后一直没有查看入口，这个页面就是那个入口——
/// 列表页展示本机全部存证发布记录（按保存时间倒序），点一条进详情弹窗看
/// 完整字段（完整 txHash / assetId / 发布地址 / fromdev / 大小 / 内容预览 /
/// 服务端消息 / 时间），并支持复制 txHash、删除单条本机记录。
///
/// 【和 PledgeRecordsWidget 的差别】质押那边是嵌在 TabBar 里的一个标签页
/// （因为质押 Hub 页本身就是多标签结构），存证发布这边只有"文本/文件"两个
/// 标签，明细属于独立诉求，所以这里做成一个完整的 Scaffold 页面，从
/// QccDataBroadcastPage 的 AppBar 用一个历史图标入口跳转进来，而不是塞进
/// 现有 TabBar（会破坏原来"文本/文件"两栏的语义）。
class EntityDataRecordsPage extends StatefulWidget {
  const EntityDataRecordsPage({super.key});

  @override
  State<EntityDataRecordsPage> createState() => _EntityDataRecordsPageState();
}

class _EntityDataRecordsPageState extends State<EntityDataRecordsPage> {
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
    final all = await EntityDataFileStorage.getAllTasks();
    // 优先按"保存时间"倒序——这是本机记录真实落盘的时间，比业务 timestamp
    // 更贴近"最近发布在最上面"的直觉；旧记录如果没有 savedAt 就退回用
    // timestamp，保证不会因为字段缺失而排序报错。
    all.sort((a, b) {
      final int ta = ((a['savedAt'] ?? a['timestamp']) as num?)?.toInt() ?? 0;
      final int tb = ((b['savedAt'] ?? b['timestamp']) as num?)?.toInt() ?? 0;
      return tb.compareTo(ta);
    });
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _records = all;
      _isLoading = false;
    });
  }

  String _formatTime(dynamic millis) {
    final int? ts = (millis as num?)?.toInt();
    if (ts == null || ts == 0) return "-";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}";
  }

  Future<void> _confirmDelete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Trans("删除本地记录"),
        content: Text("只删除本机缓存的这条发布明细，不影响链上真实数据。\ntxHash: ${r['txHash']}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Trans("取消")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Trans("删除")),
        ],
      ),
    );
    if (ok == true) {
      await EntityDataFileStorage.deleteTask((r['txHash'] ?? '').toString());
      _load();
    }
  }

  void _copyHash(String txHash) {
    Clipboard.setData(ClipboardData(text: txHash));
    Tools.showToast(context, "已复制 txHash");
  }

  void _showDetail(Map<String, dynamic> r) {
    final String txHash = (r['txHash'] ?? '').toString();
    final String from = (r['from'] ?? '').toString();
    final String? nick = _walletNames[from];
    final String assetId = (r['assetId'] ?? '-').toString();
    final String fromdev = (r['fromdev'] ?? '').toString();
    final String mode = (r['mode'] ?? '').toString();
    final String fileName = (r['fileName'] ?? '').toString();
    final String preview = (r['preview'] ?? '').toString();
    final int size = ((r['payloadSize'] ?? 0) as num).toInt();
    final String status = (r['status'] ?? '').toString();
    final String serverMsg = (r['serverMsg'] ?? '').toString();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Trans("发布明细"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("交易哈希 (txHash)：", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    txHash,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                _detailRow("发布地址", nick != null ? "$nick ($from)" : from),
                _detailRow("资产 ID", assetId),
                _detailRow("推广地址 fromdev", fromdev.isEmpty ? "(空)" : fromdev),
                _detailRow("类型", mode == "file" ? "文件存证" : "文本存证"),
                if (mode == "file") _detailRow("文件名", fileName.isEmpty ? "-" : fileName),
                _detailRow("大小", "${(size / 1024).toStringAsFixed(2)} KB"),
                _detailRow("状态", status.isEmpty ? "-" : status),
                if (serverMsg.isNotEmpty) _detailRow("服务端消息", serverMsg),
                _detailRow("发布时间", _formatTime(r['timestamp'])),
                _detailRow("本机保存时间", _formatTime(r['savedAt'])),
                const SizedBox(height: 10),
                const Text("内容预览：", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preview.isEmpty ? "(无预览)" : preview,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _copyHash(txHash),
              child: const Text("复制哈希"),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("关闭"),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(text: "$label：", style: const TextStyle(color: Colors.black54)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Trans("发布明细中心", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _load();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "本机暂无存证发布明细。\n发布一条存证数据后会自动出现在这里。",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
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
    final String txHash = (r['txHash'] ?? '').toString();
    final String from = (r['from'] ?? '').toString();
    final String? nick = _walletNames[from];
    final String mode = (r['mode'] ?? '').toString();
    final bool isFile = mode == "file";
    final String preview = (r['preview'] ?? '').toString();
    final int size = ((r['payloadSize'] ?? 0) as num).toInt();
    final String status = (r['status'] ?? '').toString();

    return InkWell(
      onTap: () => _showDetail(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildTypePill(isFile),
                const SizedBox(width: 8),
                Text(
                  status.isEmpty ? "ACCEPTED" : status,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                ),
                const Spacer(),
                Text(_formatTime(r['savedAt'] ?? r['timestamp']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () => _confirmDelete(r),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isFile ? "文件: ${(r['fileName'] ?? '-')}" : (preview.isEmpty ? "(无内容预览)" : preview),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              "${(size / 1024).toStringAsFixed(2)} KB  ·  ${nick != null ? "$nick ($from)" : from}",
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueGrey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text("txHash: $txHash", style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildTypePill(bool isFile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: (isFile ? Colors.indigo : Colors.blue).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(
        isFile ? "文件存证" : "文本存证",
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: (isFile ? Colors.indigo : Colors.blue).shade700),
      ),
    );
  }
}
