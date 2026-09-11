import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../utile/Tools.dart';
import '../../utile/QccObj.dart';
import '../../utile/LogObj.dart';
import '../../home/QccExplorerService.dart';
import '../setting/AppTranslator.dart';

class QccWaterWidget extends StatefulWidget {
  const QccWaterWidget({super.key});

  @override
  State<QccWaterWidget> createState() => _QccWaterWidgetState();
}

class _QccWaterWidgetState extends State<QccWaterWidget> {
  final TextEditingController _addressController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 默认填入当前选中的钱包地址
    if (QccObj.activeWallet != null) {
      _addressController.text = QccObj.activeWallet!.address;
    }
  }

  /// ✅ 核心：调用测试网放水接口
  Future<void> _claimTestQcc() async {
    String address = _addressController.text.trim();
    if (address.isEmpty) {
      Tools.showToast(context, "请先输入或选择地址");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = "${QccExplorerService.baseUrl}/v1/water/$address";
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        String dataStr = res['data'] ?? "";
        if (dataStr.contains("cooldown")) {
          // 处理冷却逻辑
          _showCooldownDialog(dataStr);
        } else if (res['ok'] == true) {
          // 处理成功逻辑
          LogObj.log("放水返回:$res");
          Tools.showToast(context, "领取成功: 200 QCC 已发放到账");
          // 延迟关闭页面，让用户看清提示
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        Tools.showToast(context, "请求失败: ${response.statusCode}");
      }
    } catch (e) {
      LogObj.log("水龙头领取异常: $e");
      Tools.showToast(context, "network time out");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 弹出冷却时间提示
  void _showCooldownDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Trans("领取限制"),
        content: Text(msg, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("确定"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 使用 Scaffold 作为顶层，自带返回按钮和 Material 环境
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Trans("获取测试币", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildFaucetCard(),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Trans("说明：此功能仅供开发者在 QCC 测试网进行调试使用，领取的 QCC 不具备实际价值。",
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建水龙头交互卡片
  Widget _buildFaucetCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.opacity, color: Colors.blueAccent, size: 28),
              SizedBox(width: 10),
              Text("QCC Faucet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 20),
          const Trans("接收地址", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // ✅ 地址输入与选择行
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      hintText: "input QCC address",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 15),
                    ),
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                ),
                _buildWalletPicker(),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // 提交按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _claimTestQcc,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Trans("免费领取 200 QCC", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// 钱包选择下拉菜单
  Widget _buildWalletPicker() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.vertical_align_bottom, color: Colors.blueAccent),
      onSelected: (addr) => setState(() => _addressController.text = addr),
      itemBuilder: (context) {
        if (QccObj.readWallets().isEmpty) {
          return [const PopupMenuItem(enabled: false, child: Trans("暂无本地钱包"))];
        }
        return QccObj.readWallets().map((w) {
          return PopupMenuItem<String>(
            value: w.address,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Wallet", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text("${w.address.substring(0, 10)}...", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}