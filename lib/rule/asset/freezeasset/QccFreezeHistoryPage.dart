import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../views/setting/AppTranslator.dart';
import 'AssetFreezeRule.dart';

class QccFreezeHistoryPage extends StatefulWidget {
  const QccFreezeHistoryPage({super.key});

  @override
  State<QccFreezeHistoryPage> createState() => _QccFreezeHistoryPageState();
}

class _QccFreezeHistoryPageState extends State<QccFreezeHistoryPage> {
  List<FreezeRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final list = await AssetFreezeStorage.getAllRecords();
    setState(() {
      _records = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Trans("管控明细 (单签)"),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? _buildEmpty()
          : ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: _records.length,
        itemBuilder: (context, index) => _buildRecordCard(_records[index]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Trans("暂无管控记录", style: TextStyle(color: Colors.grey)));
  }

  Widget _buildRecordCard(FreezeRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: record.isFrozen ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(record.isFrozen ? Icons.lock : Icons.lock_open,
                          size: 14, color: record.isFrozen ? Colors.red : Colors.green),
                      const SizedBox(width: 4),
                      Text(record.isFrozen ? "已执行冻结" : "已执行解冻",
                          style: TextStyle(color: record.isFrozen ? Colors.red : Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Text(record.assetId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(height: 24),
            _infoRow("目标地址", record.targetAddress, isAddr: true),
            const SizedBox(height: 8),
            _infoRow("交易哈希", record.txHash, isAddr: true),
            const SizedBox(height: 8),
            _infoRow("操作时间", DateTime.fromMillisecondsSinceEpoch(record.timestamp).toString().substring(0, 19)),

            const SizedBox(height: 15),
            // 快速解冻/冻结按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // 返回到操作页并自动填入参数
                  Navigator.pop(context, record);
                },
                child: Trans(record.isFrozen ? "去解冻" : "再次冻结"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isAddr = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 70, child: Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: isAddr ? 'monospace' : null,
                  color: isAddr ? Colors.blueGrey : Colors.black87
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis
          ),
        ),
      ],
    );
  }
}