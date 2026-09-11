import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'AppTranslator.dart';

class QccPassDialog {
  static Future<String?> show(BuildContext context, {bool isSetMode = false}) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'pay_pass_dialog',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _PassDialogContent(isSetMode: isSetMode),
      transitionBuilder: (context, anim, __, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(curve), child: child),
        );
      },
    );
  }
}

class _PassDialogContent extends StatefulWidget {
  final bool isSetMode;
  const _PassDialogContent({required this.isSetMode});

  @override
  State<_PassDialogContent> createState() => _PassDialogContentState();
}

class _PassDialogContentState extends State<_PassDialogContent> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();

  String _firstInput = "";
  bool _isConfirming = false;
  String? _errorText;

  /// true = 兼容旧版纯数字模式（勾选后临时放宽）
  bool _legacyNumericMode = false;

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── 校验 ──────────────────────────────────────────────
  bool _isValid(String val) {
    if (val.length != 6) return false;
    if (_legacyNumericMode) {
      return RegExp(r'^\d{6}$').hasMatch(val); // 纯数字
    }
    return val.contains(RegExp(r'[a-zA-Z]')); // 至少1位字母
  }

  String get _validationHint {
    if (_legacyNumericMode) return "请输入 6 位数字密码";
    return "密码须包含至少 1 位字母";
  }

  // ── 标题 / 副标题 ──────────────────────────────────────
  String get _title {
    if (!widget.isSetMode) return "验证支付密码";
    return _isConfirming ? "请再次输入以确认" : "设置支付密码";
  }

  String get _subtitle {
    if (!widget.isSetMode) {
      return _legacyNumericMode
          ? "请输入原 6 位数字密码以完成操作"
          : "请输入 6 位密码（数字 + 字母）以完成操作";
    }
    return _legacyNumericMode
        ? "兼容模式：6 位纯数字，下次升级将强制含字母"
        : "6 位密码，需有數字及英文字母，請務必牢記";
  }

  // ── Build ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
   // final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Theme.of(context).dialogBackgroundColor.withOpacity(0.93),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420), // 加宽
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18), // 加大内边距
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 8),
                    _buildSubtitle(context),
                    const SizedBox(height: 22),
                    _buildPinput(context),
                    _buildError(),
                    const SizedBox(height: 14),
                    _buildLegacyToggle(context), // 兼容模式勾选
                    const SizedBox(height: 18),
                    _buildButtons(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 顶部标题行 ─────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.lock_rounded, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DefaultTextStyle(
            style: (Theme.of(context).textTheme.titleMedium ?? const TextStyle())
                .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
            child: Trans(_title),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  // ── 副标题 ────────────────────────────────────────────
  Widget _buildSubtitle(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Trans(
        _subtitle,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.75),
        ),
      ),
    );
  }

  // ── 错误提示 ──────────────────────────────────────────
  Widget _buildError() {
    if (_errorText == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Trans(
          _errorText!,
          style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
        ),
      ),
    );
  }

  // ── 兼容模式勾选 ───────────────────────────────────────
  Widget _buildLegacyToggle(BuildContext context) {
    // 确认阶段不显示切换，避免用户中途改模式导致二次确认逻辑混乱
    if (_isConfirming) return const SizedBox.shrink();

    return InkWell(
      onTap: () {
        setState(() {
          _legacyNumericMode = !_legacyNumericMode;
          _errorText = null;
          _pinController.clear();
          // 切换键盘类型需要重建 Pinput，clear 触发即可
        });
        _focusNode.requestFocus();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _legacyNumericMode,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (v) {
                  setState(() {
                    _legacyNumericMode = v ?? false;
                    _errorText = null;
                    _pinController.clear();
                  });
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Trans(
                "暂时使用 6 位纯数字（旧版兼容，下次升级将强制含字母）",
                style: TextStyle(
                  fontSize: 12,
                  color: _legacyNumericMode
                      ? Colors.orange.shade700
                      : Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PIN 输入框 ─────────────────────────────────────────
  Widget _buildPinput(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final defaultTheme = PinTheme(
      width: 50,   // 加大格子
      height: 58,
      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
    );

    return Pinput(
      key: ValueKey(_legacyNumericMode), // 切换模式时强制重建，刷新键盘类型
      length: 6,
      controller: _pinController,
      focusNode: _focusNode,
      autofocus: true,
      keyboardType: _legacyNumericMode
          ? TextInputType.number   // 旧版：数字键盘
          : TextInputType.text,    // 新版：全键盘
      obscureText: true,
      obscuringCharacter: "•",
      defaultPinTheme: defaultTheme,
      focusedPinTheme: defaultTheme.copyWith(
        decoration: defaultTheme.decoration!.copyWith(
          border: Border.all(color: primary.withOpacity(0.85), width: 1.8),
        ),
      ),
      submittedPinTheme: defaultTheme,
      errorPinTheme: defaultTheme.copyWith(
        decoration: defaultTheme.decoration!.copyWith(
          border: Border.all(color: Colors.redAccent, width: 1.4),
        ),
      ),
      separatorBuilder: (index) => const SizedBox(width: 10),
      hapticFeedbackType: HapticFeedbackType.lightImpact,
      onChanged: (val) {
        if (_errorText != null) setState(() => _errorText = null);
      },
      onCompleted: _handleComplete,
    );
  }

  // ── 底部按钮 ──────────────────────────────────────────
  Widget _buildButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Trans("取消"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              final val = _pinController.text;
              if (val.length < 6) {
                setState(() => _errorText = "请输入 6 位密码");
                _focusNode.requestFocus();
                return;
              }
              if (!_isValid(val)) {
                setState(() => _errorText = _validationHint);
                _focusNode.requestFocus();
                return;
              }
              _handleComplete(val);
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Trans(widget.isSetMode ? "继续" : "确认"),
          ),
        ),
      ],
    );
  }

  // ── 核心逻辑 ──────────────────────────────────────────
  void _handleComplete(String val) {
    if (val.length != 6) {
      setState(() => _errorText = "请输入 6 位密码");
      _focusNode.requestFocus();
      return;
    }
    if (!_isValid(val)) {
      setState(() => _errorText = _validationHint);
      _focusNode.requestFocus();
      return;
    }

    if (widget.isSetMode && !_isConfirming) {
      setState(() {
        _firstInput = val;
        _isConfirming = true;
        _errorText = null;
        _pinController.clear();
      });
      _focusNode.requestFocus();
      return;
    }

    if (widget.isSetMode && _isConfirming) {
      if (val == _firstInput) {
        Navigator.pop(context, val);
      } else {
        setState(() {
          _errorText = "两次密码不一致，请重新设置";
          _isConfirming = false;
          _firstInput = "";
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
      return;
    }

    // 验证模式直接返回
    Navigator.pop(context, val);
  }
}