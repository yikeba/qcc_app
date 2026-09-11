import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:qcc_flutter/utile/Tools.dart';

import '../../home/QccExplorerService.dart';
import '../setting/AppTranslator.dart';
import 'QccAnnouncementModel.dart';

class QccAssetAnnouncementPage extends StatefulWidget {
  final String address; // 资产发行地址
  const QccAssetAnnouncementPage({super.key, required this.address});

  @override
  State<QccAssetAnnouncementPage> createState() => _QccAssetAnnouncementPageState();
}

class _QccAssetAnnouncementPageState extends State<QccAssetAnnouncementPage> {
  bool _isLoading = true;
  List<QccAnnouncementModel> _announcements = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      // 1. 获取 Hashes 列表
      final res = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/assetdata/${widget.address}"));
      if (res.statusCode != 200) throw "网络异常";

      final data = jsonDecode(res.body);
      if (data['ok'] != true || data['data'] == null) {
        setState(() => _isLoading = false);
        return;
      }

      List<dynamic> hashes = data['data']['hashes'] ?? [];

      // 2. 并发读取每个 Hash 的内容
      List<Future<QccAnnouncementModel?>> tasks = hashes.map((h) => _fetchSingleHash(h)).toList();
      final results = await Future.wait(tasks);

      setState(() {
        _announcements = results.whereType<QccAnnouncementModel>().toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<QccAnnouncementModel?> _fetchSingleHash(String hash) async {
    try {
      final res = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/hash/$hash"));
      if (res.statusCode != 200) return null;

      final root = jsonDecode(res.body);
      // 注意：API 返回的 data 是一个 String 嵌套 JSON
      final innerDataStr = root['data'];
      final innerData = jsonDecode(innerDataStr);
      final tx = jsonDecode(innerData['tx']); // 再次解析 tx 字符串

      final List<dynamic> payload = tx['payload'] ?? [];
      String content = QccAnnouncementModel.decodePayload(payload);
      String date = innerData['confirmDateUTC'] ?? "未知时间";

      return QccAnnouncementModel(
        hash: hash,
        rawContent: content,
        time: date,
        isError: content.startsWith("[解析失败"),
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(title: const Trans("资产公告存证"), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
          ? _buildEmpty()
          : _buildList(),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final item = _announcements[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: () => _showDetail(item),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 头部：状态、时间、外链 ---
                  Row(
                    children: [
                      const Icon(Icons.verified_user, color: Colors.blue, size: 16),
                      const SizedBox(width: 4),
                      Text(item.time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Spacer(),
                      // ✅ 新增：浏览器查看原始数据链接
                      _buildBrowserLink(item.hash),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // --- 内容摘要 ---
                  Text(
                    item.summary,
                    style: TextStyle(
                      fontSize: 14,
                      color: item.isError ? Colors.red : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- Hash 显示 ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "Hash: ${item.hash.substring(0, 64)}...",
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ 组件：浏览器链接按钮
  Widget _buildBrowserLink(String hash) {
    return Material(
      color: Colors.transparent,
      child:Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                child:Trans(
                    "原始Url",
                    style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)
                ),
                onTap: () {
                  String _url= "${QccExplorerService.baseUrl}/v1/hash/$hash";
                  Tools.copytext(context, _url);
                },
              ),
              const SizedBox(width: 20),
              InkWell(
                child:Trans(
                    "原始存证",
                    style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)
                ),
                onTap: () {
                  String _url= "${QccExplorerService.baseUrl}/v1/hash/$hash";
                  Tools.openChrome(_url);
                },
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 12, color: Colors.blue.shade700),
            ],
          ),
      ),
    );
  }


  void _showDetail(QccAnnouncementModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(margin: const EdgeInsets.all(12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Trans("公告正文", style: TextStyle(fontWeight: FontWeight.bold))),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  SelectableText(
                    item.rawContent,
                    style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                  ),
                  const SizedBox(height: 30),
                  Text("存证Hash: ${item.hash}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => const Center(child: Trans("该资产暂无公告存证数据"));
}