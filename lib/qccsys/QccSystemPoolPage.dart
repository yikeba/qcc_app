import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';
import 'SystemPool.dart';

/// 系统资金池公开看板 —— 任何人（无需钱包）随时查看四个协议保留池的实时余额。
///
/// 余额统一走 QccActiveWallet → GET /v1/balance/{address}，与查询普通地址完全相同，
/// 不另写 HTTP 请求。系统池地址是公开常量，余额本就链上可查，这里只是把它集中展示，
/// 让用户、审计方、监管方一眼看到协议资金的去向与规模。
class QccSystemPoolPage extends StatefulWidget {
  const QccSystemPoolPage({super.key});

  @override
  State<QccSystemPoolPage> createState() => _QccSystemPoolPageState();
}

class _QccSystemPoolPageState extends State<QccSystemPoolPage> {
  /// 刷新计数：改变 key 让各 QccActiveWallet 重建、重新拉取余额。
  /// 【假设】QccActiveWallet 在 initState 时拉取余额；若它内部有自己的刷新机制，
  /// 换成调用那个方法更好。
  int _refreshTick = 0;
  DateTime _updatedAt = DateTime.now();

  static const Map<SystemPool, _PoolInfo> _info = {
    SystemPool.system: _PoolInfo(
      Icons.account_balance_rounded,
      Color(0xFF2F6FED),
      "协议级系统资金池，承接链上手续费等系统收入，由协议规则统一调度。",
    ),
    SystemPool.devReward: _PoolInfo(
      Icons.code_rounded,
      Color(0xFF16A34A),
      "开发者奖励的资金来源。已注册开发者的应用发起交易时，公链按该笔 Gas 的 20% 原子结算给 fromdev。",
    ),
    SystemPool.interest: _PoolInfo(
      Icons.percent_rounded,
      Color(0xFFE08E1D),
      "质押利息的分配来源，按协议规则向质押人发放。",
    ),
    SystemPool.nodePledge: _PoolInfo(
      Icons.hub_rounded,
      Color(0xFF7C3AED),
      "超级节点质押资金的托管地址，余额即当前节点质押总额。",
    ),
  };

  Future<void> _refresh() async {
    setState(() {
      _refreshTick++;
      _updatedAt = DateTime.now();
    });
    // 给子组件拉取留出时间，避免下拉指示器瞬间收回
    await Future.delayed(const Duration(milliseconds: 600));
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(t.hour)}:${two(t.minute)}:${two(t.second)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Trans("系统资金池", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildIntro(),
            const SizedBox(height: 16),
            ...SystemPool.values.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPoolCard(p),
                )),
            const SizedBox(height: 4),
            Center(
              child: Text("更新于 ${_fmtTime(_updatedAt)} · 下拉刷新",
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF1FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, size: 20, color: Color(0xFF2F6FED)),
          SizedBox(width: 10),
          Expanded(
            child: Trans(
              "以下为 QCC 协议保留的系统地址，不由任何密钥派生，任何人都无法动用，"
              "资金只能由协议规则出入。余额实时取自链上，公开透明，任何人可随时核对。",
              style: TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF1A1D29)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolCard(SystemPool p) {
    final info = _info[p]!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: info.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(info.icon, color: info.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Trans(p.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(p.labelEn, style: const TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
                  ],
                ),
              ),
              _badge("无私钥", info.color),
            ],
          ),
          const SizedBox(height: 14),
          // 余额：统一 /v1/balance 接口
          KeyedSubtree(
            key: ValueKey("${p.name}_$_refreshTick"),
            child: QccActiveWallet(p.address, "QCC", fontSize: 24, fontColor: info.color),
          ),
          const SizedBox(height: 10),
          Trans(info.desc, style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF5A6070))),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(ClipboardData(text: p.address));
              Tools.showToast(context, "地址已复制");
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(p.address,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF3A3F4B))),
                  ),
                  const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF8A8F9C)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Trans(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _PoolInfo {
  final IconData icon;
  final Color color;
  final String desc;
  const _PoolInfo(this.icon, this.color, this.desc);
}
