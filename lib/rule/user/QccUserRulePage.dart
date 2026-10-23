import 'dart:math';

import 'package:flutter/material.dart';

import 'package:qcc_flutter/rule/user/multiple/multicreat/QccMultiSigManagerPage.dart';
import 'package:qcc_flutter/rule/user/ruledev/DeveloperRuleWidget.dart';
import 'package:qcc_flutter/rule/user/ruleend/AddressEndWidget.dart';
import 'package:qcc_flutter/rule/user/rulemerchan/MerchantRuleWidget.dart';
import 'package:qcc_flutter/rule/user/rulepay/PayCallRuleWidget.dart';
import 'package:qcc_flutter/rule/user/ruletag/TagRuleWidget.dart';
import 'package:qcc_flutter/rule/user/ruletag/TagTransferWidget.dart';
import '../../views/setting/AppTranslator.dart';
import '../../../utile/Tools.dart';
import 'package:qcc_flutter/rule/user/UserRuleCenterPage.dart';

/// QCC 用户规则 (RuleType.UserRule)
///
/// 【菜单调整，本次】
///   1. "标签规则" → 改名为"标签创建规则交易"并接入 TagRuleWidget
///      （原来只是占位磁贴，现在真正可以点开注册标签了）
///   2. 新增"标签转移权利规则交易"，接入 TagTransferWidget
///   3. 原来的"规则状态"(UserRuleStatusWidget) 磁贴取消，改成指向本次
///      新建的、功能更完整的"规则交易中心"(UserRuleCenterPage)——支持
///      Developer/Merchant/PayCall/TagRule/TagTransfer/AddressEnd 全部
///      六种规则交易的本地记录浏览。如果你的本意是"规则状态"这块彻底
///      不要了、不需要保留任何入口，把这条 _Entry 删掉即可，就这一处改动。
///   4. "地址终止" → 改名为"地址终止规则交易"，接入 AddressEndWidget
///      （原来同样只是占位，现在真正对接了那个带四道确认关卡的高危页面）
///
/// 关于命名是否都要带"交易"二字：QCC 架构上确实"一切皆交易"，但这一层
/// 信息在页面标题("QCC 用户规则")、顶部提示条("用户规则由普通地址发起,
/// 声明地址行为")、以及每个磁贴长按提示里的 UserType code 已经交代得很
/// 清楚了，磁贴正文没必要七个入口全都再重复一遍"规则交易"四个字——那样
/// 反而会让紧凑的方格菜单显得啰嗦、扫视效率变低。所以这里保留
/// "开发者申请/商户到付/支付回调/多签规则"这几个已经很简洁的命名不动，
/// 只在你点名要改的这三个上使用完整的"XX规则交易"表述——恰好这三个里有
/// 两个是"改变资产/身份归属"级别的严肃操作(标签转移、地址终止)，用更正式
/// 完整的名称提醒用户"这是一笔正式的链上规则交易"是合理的。磁贴高度本来
/// 就是 IntrinsicHeight 自适应，长标题自动换行不会溢出，不用担心排版。
///
/// UserType 六个子类型(现为八个: Developer/Merchant/PayCall/MultiSignature/
/// TagRule/TagTransfer/AddressEnd) + 规则交易中心, 单页扁平网格, 不分组。
/// 磁贴高度由 IntrinsicHeight 决定(同行等高), 不写死数值,
/// 避免系统字体放大或中文换行导致 RenderFlex overflow。
class QccUserRulePage extends StatelessWidget {
  const QccUserRulePage({super.key});

  static const double _maxContent = 1000;
  static const double _gap = 9;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        title: Trans("QCC 用户规则"),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _P.navy,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = constraints.maxWidth;
          final hPad = screenW >= 720 ? 18.0 : 12.0;
          final contentW = min(screenW, _maxContent) - hPad * 2;

          final int cols = contentW >= 860
              ? 4
              : contentW >= 520
              ? 3
              : 2;

          return Scrollbar(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContent),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HintBar(),
                      const SizedBox(height: 14),
                      _buildGrid(context, cols),
                      const SizedBox(height: 18),
                      Center(
                        child: Trans(
                          "规则由本地址私钥签名发起, 即刻生效, 参与 executeHash 共识",
                          style: TextStyle(fontSize: 10.5, color: _P.body.withValues(alpha: 0.7)),
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

  /// 手动分行 + IntrinsicHeight: 同行等高, 整体高度自适应内容
  Widget _buildGrid(BuildContext context, int cols) {
    final rows = <Widget>[];
    for (var i = 0; i < _entries.length; i += cols) {
      final slice = _entries.sublist(i, min(i + cols, _entries.length));
      final cells = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0) cells.add(const SizedBox(width: _gap));
        cells.add(Expanded(
          child: j < slice.length
              ? _EntryTile(entry: slice[j], onTap: () => _open(context, slice[j]))
              : const SizedBox.shrink(), // 补位, 保证末行列宽一致
        ));
      }
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ));
      if (i + cols < _entries.length) rows.add(const SizedBox(height: _gap));
    }
    return Column(children: rows);
  }

  void _open(BuildContext context, _Entry e) {
    if (e.warning != null) {
      _confirmThenOpen(context, e);
      return;
    }
    _push(context, e);
  }

  void _confirmThenOpen(BuildContext context, _Entry e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber_rounded, color: _P.danger, size: 26),
        title: Trans(e.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Trans(
          e.warning!,
          style: const TextStyle(fontSize: 13, height: 1.6, color: _P.body),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Trans("取消")),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _P.danger),
            onPressed: () {
              Navigator.pop(context);
              _push(context, e);
            },
            child: Trans("我已了解, 继续"),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, _Entry e) {
    final builder = e.builder;
    if (builder == null) {
      Tools.showToast(context, "${e.title} 开发中...");
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) {
          final child = builder(ctx);
          // 目标本身若是完整 Page(自带 Scaffold/AppBar), 不再外套一层
          if (e.selfScaffold) return child;
          return Scaffold(
            appBar: AppBar(title: Trans(e.title), centerTitle: true),
            body: child,
          );
        },
      ),
    );
  }
}

// ============================================================
// 数据定义
// ============================================================

class _Entry {
  final String title;

  /// 磁贴上唯一的一行副文案, 保持极短(建议 ≤ 8 个汉字)
  final String hint;

  /// 长按/悬停提示里展示的完整说明
  final String desc;

  /// UserType 枚举值, 只出现在长按提示中, 不占磁贴版面
  final String code;

  final IconData icon;
  final Color color;

  /// 非空则点击前弹出不可逆确认
  final String? warning;

  /// null 表示页面尚未实现
  final WidgetBuilder? builder;

  /// 目标是否已自带 Scaffold
  final bool selfScaffold;

  const _Entry({
    required this.title,
    required this.hint,
    required this.desc,
    required this.code,
    required this.icon,
    required this.color,
    this.warning,
    this.builder,
    this.selfScaffold = false,
  });

  bool get ready => builder != null;
}

final List<_Entry> _entries = [
  _Entry(
    title: "开发者申请",
    hint: "20% Gas 返利",
    desc: "注册开发者地址, 资金交易/字节存证交易触发时按 Gas 费用 20% 由系统"
        "原子级返还奖励(规则交易本身不计入奖励范围)。",
    code: "DeveloperRule",
    icon: Icons.code_rounded,
    color: _P.blue,
    builder: (_) => DeveloperRuleWidget(),
  ),
  _Entry(
    title: "商户到付",
    hint: "收款方付 Gas",
    desc: "Gas 倒置: 声明本地址收款时由我方承担手续费, 支持指定资产。",
    code: "MerchantRule",
    icon: Icons.storefront_rounded,
    color: _P.amber,
    builder: (_) => MerchantRuleWidget(),
  ),
 /* _Entry(
    title: "支付回调(待测试)",
    hint: "Webhook 通知",
    desc: "收款成功后自动向指定 URL 推送 JSON 状态通知。",
    code: "PayCallRule",
    icon: Icons.hub_rounded,
    color: _P.violet,
    builder: (_) => PayCallRuleWidget(),
  ),*/
  _Entry(
    title: "多签规则",
    hint: "联合签署",
    desc: "创建多签控制地址, 所有登记签名人须 100% 联合签署方可发起交易。",
    code: "MultiSignature",
    icon: Icons.groups_2_outlined,
    color: _P.teal,
    builder: (_) => QccMultiSigManagerPage(),
  ),
  _Entry(
    title: "标签创建规则交易",
    hint: "声明名称所属",
    desc: "全网唯一的标签命名资产登记, 可用作去中心化应用的鉴权凭证/命名"
        "空间划分/去中心化域名解析。标签一旦注册成功即归属本地址。",
    code: "TagRule",
    icon: Icons.sell_outlined,
    color: _P.indigo,
    builder: (_) => TagRuleWidget(),
  ),
  _Entry(
    title: "标签转移权利规则交易",
    hint: "转让标签归属",
    desc: "将本地址名下已注册的标签名称资产整体转让给另一地址, push式转移"
        "(受让方无需签名), 转让一经确认不可撤销。",
    code: "TagTransfer",
    icon: Icons.swap_horiz_rounded,
    color: _P.indigo,
    builder: (_) => TagTransferWidget(),
  ),
  _Entry(
    title: "地址终止规则交易",
    hint: "不可逆",
    desc: "标记地址死亡, 此后该地址收发交易均被拒绝, 已发布协议随之永久固化。",
    code: "AddressEnd",
    icon: Icons.block_rounded,
    color: _P.danger,
    warning: "地址终止后, 该地址将无法再发起或接收任何交易, 且没有任何恢复途径。请确认资产已全部转出。",
    builder: (_) => AddressEndWidget(),
  ),
  _Entry(
    title: "规则交易中心",
    hint: "全部本地记录",
    desc: "查看本地址已发起的全部用户规则交易(开发者/商户/支付回调/标签"
        "创建/标签转移/地址终止)本地记录及回看详情。",
    code: "State",
    icon: Icons.fact_check_outlined,
    color: _P.slate,
    builder: (_) => const UserRuleCenterPage(),
    // UserRuleCenterPage 自带 Scaffold + AppBar("规则交易中心"), 不再外套
    selfScaffold: true,
  ),
];

// ============================================================
// 顶部提示条
// ============================================================

class _HintBar extends StatelessWidget {
  const _HintBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _P.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _P.navy.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _P.navy, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Trans(
              "用户规则由普通地址发起, 声明地址行为, 不锁定资产。长按可查看详细说明。",
              style: const TextStyle(fontSize: 11.5, color: _P.body, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 入口磁贴 (紧凑: 图标 + 标题 + 一行副文案)
// ============================================================

class _EntryTile extends StatefulWidget {
  final _Entry entry;
  final VoidCallback onTap;
  const _EntryTile({required this.entry, required this.onTap});

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final ready = e.ready;
    final isDanger = e.warning != null;

    return Tooltip(
      // 完整说明与链上枚举名收进长按/悬停提示, 不占磁贴版面
      message: "${e.code}\n${e.desc}",
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white, height: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: _P.navy.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          decoration: BoxDecoration(
            color: isDanger ? _P.dangerTint : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover
                  ? e.color.withValues(alpha: 0.45)
                  : (isDanger ? _P.danger.withValues(alpha: 0.20) : _P.line),
            ),
            boxShadow: [
              BoxShadow(
                color: _hover ? e.color.withOpacity(0.10) : Colors.black.withOpacity(0.025),
                blurRadius: _hover ? 12 : 5,
                offset: Offset(0, _hover ? 4 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 11, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: e.color.withValues(alpha: ready ? 0.10 : 0.07),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(e.icon, color: e.color, size: 16),
                        ),
                        const Spacer(),
                        if (!ready)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _P.slate.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Trans(
                      e.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ready ? _P.title : _P.body,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Trans(
                      ready ? e.hint : "开发中",
                      style: const TextStyle(fontSize: 10.5, color: _P.body, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 调色板 (与 QccRuleManagerPage 一致: 深蓝 #0B1F3A / 古金 #C9A227)
// ============================================================

class _P {
  static const navy = Color(0xFF0B1F3A);
  static const bg = Color(0xFFF4F6FA);
  static const line = Color(0xFFE3E8F0);
  static const title = Color(0xFF0F172A);
  static const body = Color(0xFF64748B);
  static const blue = Color(0xFF2563EB);
  static const teal = Color(0xFF0D9488);
  static const violet = Color(0xFF7C3AED);
  static const indigo = Color(0xFF4F46E5);
  static const amber = Color(0xFFD97706);
  static const slate = Color(0xFF64748B);
  static const danger = Color(0xFFBE123C);
  static const dangerTint = Color(0xFFFDF5F7);
}