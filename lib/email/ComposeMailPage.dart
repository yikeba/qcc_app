import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'MailUtils.dart';

class ComposeMailPage extends StatefulWidget {
  // 增加可选的构造参数，用于处理“回复”逻辑
  final String? presetTo;
  final String? presetSubject;
  final String? presetBody;

  ComposeMailPage({this.presetTo, this.presetSubject, this.presetBody});

  @override
  _ComposeMailPageState createState() => _ComposeMailPageState();
}

class _ComposeMailPageState extends State<ComposeMailPage> {
  // 使用 late 声明，在 initState 中初始化
  late TextEditingController _toController;
  late TextEditingController _subjectController;
  late TextEditingController _bodyController;

  bool _isSending = false;
  final String sendApiUrl = "http://192.131.142.226:8081/v1/mail/send";

  @override
  void initState() {
    super.initState();
    // 核心修改：如果是回复，自动填入之前传过来的数据
    _toController = TextEditingController(text: widget.presetTo ?? "");
    _subjectController = TextEditingController(text: widget.presetSubject ?? "");

    // 如果是回复，正文通常留出顶部给用户写新内容，下面跟着原始邮件
    _bodyController = TextEditingController(text: widget.presetBody ?? "");

    // 💡 小细节：如果是回复，光标应该自动定位在正文最前面，方便用户直接打字
    if (widget.presetBody != null && widget.presetBody!.isNotEmpty) {
      _bodyController.selection = TextSelection.collapsed(offset: 0);
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendMail() async {
    String to = _toController.text.trim();
    String subject = _subjectController.text.trim();
    String body = _bodyController.text;

    if (to.isEmpty || subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("收件人和主题不能为空")));
      return;
    }

    setState(() => _isSending = true);

    try {
      final response = await Dio().post(sendApiUrl, data: {
        "from": MailUtils.getMailfrom(),
        "to": to,
        "subject": subject,
        "body": body,
      });

      if (response.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🚀 邮件投递成功")));
        Navigator.pop(context, true); // 发送成功返回 true，通知列表刷新
      } else {
        throw Exception("发送失败");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 发送异常: $e")));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.presetTo != null ? "回复邮件" : "写邮件",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        actions: [
          _isSending
              ? Container(width: 50, padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(onPressed: _sendMail, icon: Icon(Icons.send, color: Colors.blueAccent)),
        ],
      ),
      body: Column(
        children: [
          // 收件人行
          _buildRow(label: "至:", controller: _toController, isEmail: true),
          Divider(height: 1),
          // 主题行
          _buildRow(label: "主题:", controller: _subjectController),
          Divider(height: 1),
          // 正文
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _bodyController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: "输入内容...",
                  border: InputBorder.none,
                ),
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({required String label, required TextEditingController controller, bool isEmail = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
              decoration: InputDecoration(border: InputBorder.none),
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}