import 'package:flutter/material.dart';

import 'GmailStyleMailList.dart';
import 'ComposeMailPage.dart';

/// 邮箱首页外壳。把列表包进 Scaffold，补上标题栏和写信悬浮按钮。
/// 启动页 case "email" 改成 push 这个页面。
class QccMailHomePage extends StatefulWidget {
  final String user;
  const QccMailHomePage({super.key, required this.user});

  @override
  State<QccMailHomePage> createState() => _QccMailHomePageState();
}

class _QccMailHomePageState extends State<QccMailHomePage> {
  // 用 key 触发列表重建（写信返回后刷新）
  Key _listKey = UniqueKey();

  void _reloadList() => setState(() => _listKey = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Qccio 存证邮箱',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: GmailStyleMailList(key: _listKey, user: widget.user),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1F2933),
        onPressed: () async {
          final sent = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ComposeMailPage()),
          );
          if (sent == true) _reloadList(); // 发送成功后刷新列表
        },
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}