import 'package:flutter/material.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import 'QccGenesisContainerPage.dart';
import 'QccSystemPoolPage.dart';

/// QCC 系统根 · 公开验证 —— 入口菜单。
///
/// 收纳两项"关系到整条链根基"的公开数据：
///   1. 创世容器（高度 0）：链的规则与初始状态，本机重算哈希可自证未被篡改
///   2. 系统资金池：四个无私钥协议地址的实时余额
/// 两者都无需钱包、无需信任任何节点，任何人可独立核对。
class QccSysRootPage extends StatelessWidget {
  const QccSysRootPage({super.key});

  static const Color _ink = Color(0xFF1A1D29);
  static const Color _sub = Color(0xFF5A6070);
  static const Color _muted = Color(0xFF8A8F9C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Trans("系统根 · 公开验证", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHero(),
          const SizedBox(height: 18),
          _entry(
            context,
            icon: Icons.all_inclusive_rounded,
            color: const Color(0xFF2F6FED),
            tag: "高度 0",
            title: "创世容器",
            subtitle: "整条链的起点与宪法",
            desc: "链身份、密码学与共识规则、创世分配、宪章与纪念影像，全部写入高度 0，永不可改。"
                "App 在本机重新计算 SHA3-256，即可证明你看到的内容与创世时完全一致。",
            points: const ["本机解析", "节点网页", "原始字节"],
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const QccGenesisContainerPage())),
          ),
          const SizedBox(height: 12),
          _entry(
            context,
            icon: Icons.account_balance_rounded,
            color: const Color(0xFF16A34A),
            tag: "实时",
            title: "系统资金池",
            subtitle: "协议持有、无人可动用的资金",
            desc: "系统池、开发者奖励池、利息分配池、节点质押池——四个不由任何密钥派生的协议地址，"
                "资金只按协议规则出入。余额实时取自链上，任何人可随时核对。",
            points: const ["无私钥", "只按规则出入", "实时余额"],
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const QccSystemPoolPage())),
          ),
          const SizedBox(height: 24),
          _buildPrinciple(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF2F3E5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_user_rounded, color: Color(0xFF7DD3FC), size: 22),
            SizedBox(width: 8),
            Trans("链的信任根，向所有人公开",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          SizedBox(height: 10),
          Trans(
            "QCC 没有管理员后门。链从哪里开始、协议资金有多少，"
            "不需要相信任何人的说法——无需钱包、无需信任节点，你可以亲自验证。",
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String tag,
    required String title,
    required String subtitle,
    required String desc,
    required List<String> points,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Trans(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                        child: Trans(tag, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Trans(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ]),
              const SizedBox(height: 12),
              Trans(desc, style: const TextStyle(fontSize: 12.5, height: 1.55, color: _sub)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: points
                    .map((p) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7FB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_rounded, size: 12, color: color),
                            const SizedBox(width: 3),
                            Trans(p, style: const TextStyle(fontSize: 11, color: _sub)),
                          ]),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrinciple() {
    return const Column(
      children: [
        Trans("不要相信，去验证", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _sub)),
        SizedBox(height: 2),
        Text("Don't trust. Verify.", style: TextStyle(fontSize: 11, color: _muted, letterSpacing: 0.5)),
      ],
    );
  }
}
