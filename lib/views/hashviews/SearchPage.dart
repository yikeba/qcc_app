import 'package:flutter/material.dart';
import '../../home/QccExplorerService.dart'; // 使用统一的资源服务
import 'QccDetailPage.dart';
import 'QccDataMeta.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isSearching = false;

  void doSearch() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      // 1. 统一调用 fetchDetail，它会返回 QccDataMeta 对象
      // 如果输入的是 URL，fetchDetail 内部应支持解析出 Hash
      String targetHash = input;
      if (input.startsWith("http")) {
        targetHash = input.split('/').last; // 简单的从 URL 提取 Hash 逻辑
      }

      // 2. 获取包含身份识别（交易/数据）的 Meta 对象
      final QccDataMeta meta = await QccExplorerService.fetchDetail(targetHash);

      if (mounted) {
        // 3. 跳转详情页，只传一个 meta 对象
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QccDetailPage(meta: meta),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("解析失败: 无法找到该哈希或格式错误")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("QCC 链上搜索")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "输入交易哈希 (Hash) 或 存证地址",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _controller.clear(),
                ),
              ),
              onSubmitted: (_) => doSearch(), // 支持键盘回车搜索
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: _isSearching ? null : doSearch,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSearching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("查询并解析数据"),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              "支持自动识别：\n1. 链上转账交易明细\n2. 存证图片、文档、JSON内容",
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            )
          ],
        ),
      ),
    );
  }
}