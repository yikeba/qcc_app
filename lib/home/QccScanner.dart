import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/cupertino.dart';

import '../views/setting/AppTranslator.dart';

class QccScanner {
  /// 调起相机扫描二维码并返回结果
  static Future<String?> scan(BuildContext context) async {
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const _ScannerPage(),
      ),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  // 控制相机相关操作
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // 在 _ScannerPageState 中
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Trans("扫描二维码", style: TextStyle(color: Colors.white)),
        actions: [
          // ✅ 适配 7.2.0 的闪光灯控制
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller, // 监听整个 controller 的状态
            builder: (context, state, child) {
              // 从 state 中获取 torchState
              final TorchState torchState = state.torchState;
              switch (torchState) {
                case TorchState.on:
                  return IconButton(
                    icon: const Icon(Icons.flash_on, color: Colors.yellow),
                    onPressed: () => controller.toggleTorch(),
                  );
                case TorchState.off:
                  return IconButton(
                    icon: const Icon(Icons.flash_off, color: Colors.white),
                    onPressed: () => controller.toggleTorch(),
                  );
                case TorchState.unavailable:
                  return const Icon(Icons.flash_off, color: Colors.grey);
                case TorchState.auto:
                  // TODO: Handle this case.
                  throw UnimplementedError();
              }
            },
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (_isPopped) return; // 如果已经返回了，直接拦截后续触发
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String? code = barcodes.first.displayValue; // 7.x 推荐使用 displayValue 或 rawValue
            if (code != null) {
              _isPopped = true; // 锁定，确保只执行一次
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
  bool _isPopped = false; // 添加一个标记位，防止重复 pop

}

// 简单的遮罩层形状类
class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderLength;
  final double borderRadius;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 1.0,
    this.borderLength = 40,
    this.borderRadius = 0,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;
    final boxWidth = cutOutSize;
    final boxHeight = cutOutSize;

    final left = (width - boxWidth) / 2;
    final top = (height - boxHeight) / 2;

    // 绘制半透明背景
    final backgroundPaint = Paint()..color = Colors.black54;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, boxWidth, boxHeight), Radius.circular(borderRadius))),
      ),
      backgroundPaint,
    );

    // 绘制四个边角
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // 左上角
    canvas.drawPath(Path()..moveTo(left, top + borderLength)..lineTo(left, top)..lineTo(left + borderLength, top), borderPaint);
    // 右上角
    canvas.drawPath(Path()..moveTo(left + boxWidth - borderLength, top)..lineTo(left + boxWidth, top)..lineTo(left + boxWidth, top + borderLength), borderPaint);
    // 左下角
    canvas.drawPath(Path()..moveTo(left, top + boxHeight - borderLength)..lineTo(left, top + boxHeight)..lineTo(left + borderLength, top + boxHeight), borderPaint);
    // 右下角
    canvas.drawPath(Path()..moveTo(left + boxWidth - borderLength, top + boxHeight)..lineTo(left + boxWidth, top + boxHeight)..lineTo(left + boxWidth, top + boxHeight - borderLength), borderPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}