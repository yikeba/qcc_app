import 'package:flutter/material.dart';

import '../../utile/Tools.dart';
import '../../views/setting/AppTranslator.dart';
import 'UserRuleFileStorage.dart';
import 'ruledev/DeveloperRuleSuccessPage.dart';
import 'rulemerchan/MerchantRuleSuccessPage.dart';
import 'rulepay/PayCallRuleSuccessPage.dart';
import 'QccRuleInitiatedPage.dart';

class UserRuleCenterPage extends StatefulWidget {
  const UserRuleCenterPage({super.key});

  @override
  State<UserRuleCenterPage> createState() => _UserRuleCenterPageState();
}

class _UserRuleCenterPageState extends State<UserRuleCenterPage> {
  List<Map<String, dynamic>> _records = [];
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    _handleRefresh();
  }

  Future<void> _handleRefresh() async {
    try {
      final List<dynamic> raw = await UserRuleFileStorage.getAllRules();
      if (mounted) {
        setState(() {
          _records = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isInit = false;
        });
      }
    } catch (e) {
      debugPrint("QCC DEBUG_: $e");
    }
  }

  Future<void> _handleDelete(String txHash) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("移除记录"),
        content: Trans("是否从本地列表中移除此条记录？（不会影响链上数据）"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Trans("取消")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Trans("确定", style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await UserRuleFileStorage.deleteTask(txHash);
      if (mounted) {
        setState(() {
          _records.removeWhere((r) => r['txHash'] == txHash);
        });
        Tools.showToast(context, "已移除");
      }
    }
  }

  void _onTapDetail(Map<String, dynamic> record) {
    final String ruleName = (record['ruleName'] ?? "").toString();
    Widget page;
    switch (ruleName) {
      case 'DeveloperRule':
        page = DeveloperRuleSuccessPage(ruleData: record);
        break;
      case 'MerchantRule':
        page = MerchantRuleSuccessPage(ruleData: record);
        break;
      case 'PayCallRule':
        page = PayCallRuleSuccessPage(ruleData: record);
        break;
      default:
      // 未识别的规则类型（以后新增的规则、或者解析失败落回 "QCC Rule"/
      // "UnknownRule" 的记录）——用通用详情页兜底，至少能看到业务类型和
      // Hash，不会因为找不到对应页面直接报错。
        page = QccRuleInitiatedPage(ruleData: record);
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  /// 规则名 -> (展示标题, 图标, 主题色)。未识别的类型统一走"未知规则"。
  _RuleDisplayMeta _metaFor(String ruleName) {
    switch (ruleName) {
      case 'DeveloperRule':
        return _RuleDisplayMeta("开发者奖励规则", Icons.code, Colors.blueAccent);
      case 'MerchantRule':
        return _RuleDisplayMeta("商户到付规则", Icons.storefront_rounded, Colors.orange);
      case 'PayCallRule':
        return _RuleDisplayMeta("支付回调规则", Icons.notifications_active_rounded, Colors.indigo);
      default:
        return _RuleDisplayMeta("QCC 规则交易", Icons.rule_folder_outlined, Colors.blueGrey);
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return "";
    final int? millis = ts is int ? ts : int.tryParse(ts.toString());
    if (millis == null) return "";
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Trans("规则交易中心"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: _handleRefresh,
          )
        ],
      ),
      body: _isInit
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _records.length,
          itemBuilder: (context, index) => _buildItemRow(_records[index]),
        ),
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> record) {
    final String txHash = (record['txHash'] ?? "").toString();
    final _RuleDisplayMeta meta = _metaFor((record['ruleName'] ?? "").toString());
    final String hashShort = txHash.length > 12
        ? "${txHash.substring(0, 6)}...${txHash.substring(txHash.length - 6)}"
        : txHash;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
          onPressed: () => _handleDelete(txHash),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Icon(meta.icon, color: meta.color),
              title: Trans(meta.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(
                "Hash: $hashShort  ${_formatTimestamp(record['timestamp'])}",
                style: const TextStyle(fontSize: 10),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _onTapDetail(record),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(child: Trans("暂无本地规则交易记录", style: const TextStyle(color: Colors.grey)));
  }
}

class _RuleDisplayMeta {
  final String title;
  final IconData icon;
  final Color color;
  const _RuleDisplayMeta(this.title, this.icon, this.color);
}