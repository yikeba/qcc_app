import 'dart:math';

import 'package:flutter/material.dart';
import '../views/setting/AppTranslator.dart';
import 'asset/QccFinanceRuleListPage.dart';
import 'user/QccUserRulePage.dart';
// 【本轮接入】质押规则列表页——放在和 asset/、user/ 同级的 pledge/ 子
// 目录下，QccPledgeRuleListPage.dart 是该目录的顶层入口（内部再分单签
// pledge/single/ 和多签 pledge/multi/ 两个子目录，见该文件头部注释）。
import 'pledge/QccPledgeRuleListPage.dart';

/// QCC 规则管理中心
///
/// 布局分层:
///  - 协议声明区 (Hero): 说明"无智能合约"这一核心事实, 深蓝/古金品牌色
///  - 业务参与区: 用户 / 资产 / 质押 三类可发起规则, 响应式 1~3 列
///  - 公链协议区: 创世 / 系统 两类只读规则, 压缩为单行信息条
class QccRuleManagerPage extends StatelessWidget {
  const QccRuleManagerPage({super.key});

  // 断点与栅格
  static const double _maxContent = 1080; // 内容最大宽度, PC 端居中留白
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        title: Trans("QCC 规则管理中心"),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _P.navy,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = constraints.maxWidth;
          final isWide = screenW >= 720;
          final hPad = isWide ? 28.0 : 16.0;
          final contentW = min(screenW, _maxContent) - hPad * 2;

          // 可发起卡片: 3 列 / 2 列 / 1 列
          final cols = contentW >= 880 ? 3 : (contentW >= 600 ? 2 : 1);
          final cardW = cols == 1
              ? contentW
              : (contentW - _gap * (cols - 1)) / cols - 0.01;

          // 只读条: 窄屏单列, 其余两列
          final roCols = contentW >= 460 ? 2 : 1;
          final roW = roCols == 1
              ? contentW
              : (contentW - _gap * (roCols - 1)) / roCols - 0.01;

          return Scrollbar(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, isWide ? 24 : 16, hPad, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContent),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProtocolHero(compact: !isWide),
                      SizedBox(height: isWide ? 32 : 24),

                      // ---------- 1. 业务参与 ----------
                      const _SectionHeader(
                        title: "业务参与",
                        subtitle: "任何地址均可签名发起, 上链后原生执行",
                        accent: _P.blue,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: _gap,
                        runSpacing: _gap,
                        children: [
                          SizedBox(
                            width: cardW,
                            child: _RuleCard(
                              title: "用户规则",
                              code: "UserRule",
                              desc: "声明地址行为: 商户 Gas 到付、开发者奖励申请、Webhook 回调、地址终止。",
                              icon: Icons.person_outline,
                              color: _P.blue,
                              onTap: () => _openUserRule(context),
                            ),
                          ),
                          SizedBox(
                            width: cardW,
                            child: _RuleCard(
                              title: "资产规则",
                              code: "AsseIdRule",
                              desc: "定义或更新容器 ID: 发行资产、增发、白名单、冻结、控制权转移。支持多签联合发起。",
                              icon: Icons.account_balance_outlined,
                              color: _P.teal,
                              onTap: () => _openFinanceRule(context),
                            ),
                          ),
                          SizedBox(
                            width: cardW,
                            child: _RuleCard(
                              title: "质押规则",
                              code: "PledgeRule",
                              desc: "锁仓参与共识与收益分配: 超级节点质押、授权质押(按 tag 归属利息)、稳定币质押与解押。",
                              icon: Icons.lock_clock_outlined,
                              color: _P.violet,
                              isNew: true,
                              onTap: () => _openPledgeRule(context),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isWide ? 34 : 28),
                      // ---------- 2. 公链协议 (只读) ----------
                      const _SectionHeader(
                        title: "公链协议",
                        subtitle: "共识层写死, 不可通过交易修改, 仅供查阅",
                        accent: _P.gold,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: _gap,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: roW,
                            child: _ReadonlyBar(
                              title: "创世规则",
                              code: "GodRule",
                              icon: Icons.auto_awesome_outlined,
                              onTap: () => _showProtocolSheet(context, _genesisDoc),
                            ),
                          ),
                          SizedBox(
                            width: roW,
                            child: _ReadonlyBar(
                              title: "系统规则",
                              code: "SystemRule",
                              icon: Icons.settings_suggest_outlined,
                              onTap: () => _showProtocolSheet(context, _systemDoc),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),
                      Center(
                        child: Trans(
                          "所有规则均参与 executeHash 共识计算",
                          style: TextStyle(fontSize: 11, color: _P.body.withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- 导航 ----------------

  void _openUserRule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QccUserRulePage()),
    );
  }

  void _openFinanceRule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QccFinanceRuleListPage()),
    );
  }

  void _openPledgeRule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QccPledgeRuleListPage()),
    );
  }

  // ---------------- 只读协议详情 ----------------

  /// 窄屏走 BottomSheet(拇指可达), 宽屏走居中 Dialog
  void _showProtocolSheet(BuildContext context, _ProtocolDoc doc) {
    final isWide = MediaQuery.of(context).size.width >= 720;
    if (isWide) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _ProtocolDetailView(doc: doc),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: _ProtocolDetailView(doc: doc, showGrabber: true),
        ),
      );
    }
  }
}

// ============================================================
// 协议声明 Hero
// ============================================================

class _ProtocolHero extends StatelessWidget {
  final bool compact;
  const _ProtocolHero({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 26, vertical: compact ? 18 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_P.navy, _P.navySoft],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _P.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.hexagon_outlined, color: _P.gold, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Trans(
                  "QCC 不运行智能合约",
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Trans(
                  "所有业务由原子规则原生执行, 规则即协议。",
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    height: 1.5,
                    color: Colors.white.withOpacity(0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 分区标题
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  const _SectionHeader({required this.title, required this.subtitle, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Trans(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _P.title,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Trans(subtitle, style: const TextStyle(fontSize: 12, color: _P.body)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 可发起规则卡片 (带桌面端 hover 反馈)
// ============================================================

class _RuleCard extends StatefulWidget {
  final String title;
  final String code;
  final String desc;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isNew;

  const _RuleCard({
    required this.title,
    required this.code,
    required this.desc,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isNew = false,
  });

  @override
  State<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends State<_RuleCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? widget.color.withOpacity(0.45) : _P.line,
          ),
          boxShadow: [
            BoxShadow(
              color: _hover
                  ? widget.color.withValues(alpha: 0.13)
                  : Colors.black.withValues(alpha: 0.035),
              blurRadius: _hover ? 16 : 8,
              offset: Offset(0, _hover ? 6 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 22),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Trans(
                                    widget.title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _P.title,
                                    ),
                                  ),
                                ),
                                if (widget.isNew) ...[
                                  const SizedBox(width: 6),
                                  _Pill(text: "新增", color: widget.color),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.code,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: "monospace",
                                color: _P.body.withOpacity(0.85),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 140),
                        offset: Offset(_hover ? 0.18 : 0, 0),
                        child: Icon(
                          Icons.arrow_forward_ios,
                          size: 13,
                          color: _hover ? widget.color : _P.line,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Trans(
                    widget.desc,
                    style: const TextStyle(fontSize: 12.5, color: _P.body, height: 1.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 只读协议信息条 (单行, 大幅压缩纵向空间)
// ============================================================

class _ReadonlyBar extends StatelessWidget {
  final String title;
  final String code;
  final IconData icon;
  final VoidCallback onTap;

  const _ReadonlyBar({
    required this.title,
    required this.code,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _P.goldTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _P.gold.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: _P.gold),
              const SizedBox(width: 10),
              Flexible(
                child: Trans(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _P.navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  code,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: "monospace",
                    color: _P.navy.withOpacity(0.5),
                  ),
                ),
              ),
              const Spacer(),
              const _Pill(text: "只读", color: _P.navy),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 17, color: _P.navy.withOpacity(0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 协议详情内容
// ============================================================

class _ProtocolDetailView extends StatelessWidget {
  final _ProtocolDoc doc;
  final bool showGrabber;
  const _ProtocolDetailView({required this.doc, this.showGrabber = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGrabber)
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: _P.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 18, color: _P.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Trans(
                  doc.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _P.title,
                  ),
                ),
              ),
              const _Pill(text: "共识层锁定", color: _P.gold),
            ],
          ),
        ),
        const Divider(height: 1, color: _P.line),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            itemCount: doc.rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final row = doc.rows[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Trans(
                      row.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _P.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Trans(
                      row.value,
                      style: const TextStyle(fontSize: 12.5, color: _P.body, height: 1.6),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, color: _P.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Trans(
                  "本页仅展示协议摘要, 完整规则以链上数据为准",
                  style: TextStyle(fontSize: 11, color: _P.body.withOpacity(0.8)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Trans("关闭"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProtocolDoc {
  final String title;
  final List<_DocRow> rows;
  const _ProtocolDoc(this.title, this.rows);
}

class _DocRow {
  final String label;
  final String value;
  const _DocRow(this.label, this.value);
}

// TODO(确认): 以下文案数值请与链上创世/系统规则实际配置核对后定稿
const _genesisDoc = _ProtocolDoc("创世规则 · GodRule", [
  _DocRow("发行总量", "2.1 亿 QCC, 9 位精度, 不可增发、不可销毁，不可 冻结。"),
  _DocRow("开发者奖励池", "创世一次性注入 5000 万 QCC, 此后由交易手续费循环回补。"),
  _DocRow("奖励申请", "申请需缴纳 100 QCC Gas, 返利比例固定 30%。"),
  _DocRow("共识奖励", "原子共识奖励总额于创世锁定, 不可通过任何交易调整。"),
  _DocRow("初始节点", "创世节点定义写入创世容器, 全网校验一致。"),
]);

const _systemDoc = _ProtocolDoc("系统规则 · SystemRule", [
  _DocRow("Gas 调节", "依据网络实际交易密度自动调整, 只降不升, 不设人工干预通道。"),
  _DocRow("容器生成", "数据驱动: 有交易才生成容器, 无交易不出块。"),
  _DocRow("网络同步", "P2P 强共识主从拓扑, 仅当前 leader 监听同步端口。"),
  _DocRow("Gas 回流", "所有扣除的 Gas 100% 进入系统地址、利息池或开发者奖励池, 无凭空消失。"),
  _DocRow("升级治理", "协议升级逻辑与投票规则由系统规则集定义。"),
]);

// ============================================================
// 通用小标签
// ============================================================

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Trans(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ============================================================
// 调色板 (QCC 品牌: 深蓝 #0B1F3A / 古金 #C9A227)
// ============================================================

class _P {
  static const navy = Color(0xFF0B1F3A);
  static const navySoft = Color(0xFF1B3A5C);
  static const gold = Color(0xFFC9A227);
  static const goldTint = Color(0xFFFBF7EC);
  static const bg = Color(0xFFF4F6FA);
  static const line = Color(0xFFE3E8F0);
  static const title = Color(0xFF0F172A);
  static const body = Color(0xFF64748B);
  static const blue = Color(0xFF2563EB);
  static const teal = Color(0xFF0D9488);
  static const violet = Color(0xFF6D4AFF);
}