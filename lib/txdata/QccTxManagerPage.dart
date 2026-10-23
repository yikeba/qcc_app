import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qcc_flutter/txdata/txloan/LoanHubPage.dart';
import 'Multi/MultiSigTransferHubPage.dart';
import '../views/setting/AppTranslator.dart';
import '../../utile/Tools.dart';
import 'inherit/InheritHubPage.dart';
import 'node/NodeWeightPurchaseWidget.dart';

/// QCC 综合交易
///
/// 扁平九宫格, 不分组。手机两列, 平板/桌面三列。
/// 撤销不设独立入口 —— 是否可撤销取决于订单当前状态,
/// 由「交易明细」进入详情后判断并执行(cancel / cancelloan)。
///
/// 磁贴高度由 IntrinsicHeight 决定(同行等高), 不写死数值,
/// 避免中文换行或系统字体放大导致 RenderFlex overflow。
class QccTxManagerPage extends StatelessWidget {
  const QccTxManagerPage({super.key});

  static const double _maxContent = 900;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        title: Trans("QCC 综合交易"),
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
          final int cols = contentW >= 560 ? 3 : 2;

          return Scrollbar(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContent),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGrid(context, cols),
                      const SizedBox(height: 16),
                      Center(
                        child: Trans(
                          "订单能否撤销以交易明细中的状态为准",
                          style: TextStyle(fontSize: 10.5, color: _P.body.withValues(alpha: 0.65)),
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

  /// 手动分行 + IntrinsicHeight: 同行等高, 高度随内容自适应
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

  /// 磁贴上的一行副文案, 保持极短(建议 ≤ 7 个汉字)
  final String hint;

  /// 长按/悬停提示中的完整说明
  final String desc;

  /// 链上类型标识, 只出现在长按提示中, 不占磁贴版面
  final String code;

  final IconData icon;
  final Color color;
  final WidgetBuilder? builder;
  final bool selfScaffold;

  const _Entry({
    required this.title,
    required this.hint,
    required this.desc,
    required this.code,
    required this.icon,
    required this.color,
    this.builder,
    this.selfScaffold = false,
  });

  bool get ready => builder != null;
}

final List<_Entry> _entries = [

/*  _Entry(
    title: "单签转账",
    hint: "普通转账",
    desc: "挂出兑换单并锁定卖出资产, 等待对手方碰撞成交。",
    code: "open · MatchType.dex",
    icon: Icons.swap_horiz_rounded,
    color: _P.indigo,
    // builder: (_) => DexOrderPage(),
  ),*/
  _Entry(
    title: "多签转账",
    hint: "原生与代币",
    desc: "多签转账执行：提案 / 签署 / 明细",
    code: "TranType.transaction / pay",
    icon: Icons.north_east_rounded,
    color: _P.blue,
    builder: (_) => const MultiSigTransferHubPage(),
    selfScaffold: true,
  ),

  _Entry(
    title: "借贷",
    hint: "借款与还款",
    desc: "抵押资产借出与归还赎回。借款、还款、借贷状态查询(含核销)在二级菜单中选择。",
    code: "TranType.loan / repay / cancelloan",
    icon: Icons.handshake_outlined,
    color: _P.teal,
    builder: (_) => const LoanHubPage(),
    selfScaffold: true,
  ),
  _Entry(
    title: "继承",
    hint: "定时移交(开发中)",
    desc: "锁定资产并指定继承地址, 以容器时间为唯一到期依据。创建信托、继承中心(领取/撤销)在二级菜单中选择。",
    code: "open · MatchType.inherit",
    icon: Icons.family_restroom_outlined,
    color: _P.gold,
    builder: (_) => const InheritHubPage(),
    selfScaffold: true,
  ),
  _Entry(
    title: "节点权重",
    hint: "1 QCC 换 1 分钟",
    desc: "为指定节点购买时间权重, 该节点成为 leader 时一次性核销。消耗型购买, 提交后不可撤销, 未核销不过期。",
    code: "open · MatchType.nodeweight",
    icon: Icons.speed_rounded,
    color: _P.rose,
    builder: (_) => const NodeWeightPurchaseWidget(),
    // selfScaffold 留 false（默认）——这个功能只有一张购买表单，没有 Tab，
    // 直接让 QccTxManagerPage._open() 自动包一层 Scaffold+AppBar 就够了，
    // 不用像 Loan/Inherit 那样自己起 Hub 页面。
  ),
  _Entry(
    title: "交易明细",
    hint: "查询与撤销",
    desc: "本地址全部交易与过程实例列表。进入订单详情后依据当前状态判断可否撤销, 并在详情内执行 cancel / cancelloan。",
    code: "TranType.cancel / cancelloan",
    icon: Icons.receipt_long_outlined,
    color: _P.slate,
    // builder: (_) => TxHistoryPage(),
  ),
];

// ============================================================
// 入口磁贴 (图标与文字同行, 淡色底, 无边框重量感)
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

    return Tooltip(
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
            color: e.color.withValues(alpha: _hover ? 0.11 : 0.055),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: e.color.withValues(alpha: _hover ? 0.35 : 0.12),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              splashColor: e.color.withValues(alpha: 0.12),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(e.icon, color: e.color, size: 19),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Trans(
                            e.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: ready ? _P.title : _P.body,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Trans(
                            ready ? e.hint : "开发中",
                            style: TextStyle(
                              fontSize: 10,
                              color: _P.body.withValues(alpha: 0.85),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
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
// 调色板 (与 QccRuleManagerPage / QccUserRulePage 一致)
// ============================================================

class _P {
  static const navy = Color(0xFF0B1F3A);
  static const gold = Color(0xFFB08900);
  static const bg = Color(0xFFF4F6FA);
  static const title = Color(0xFF0F172A);
  static const body = Color(0xFF64748B);
  static const blue = Color(0xFF2563EB);
  static const teal = Color(0xFF0D9488);
  static const violet = Color(0xFF7C3AED);
  static const indigo = Color(0xFF4F46E5);
  static const amber = Color(0xFFC2650A);
  static const green = Color(0xFF15803D);
  static const rose = Color(0xFFBE123C);
  static const slate = Color(0xFF64748B);
}