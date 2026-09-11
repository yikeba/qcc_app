import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:url_launcher/url_launcher.dart';

class QccMailWebView extends StatefulWidget {
  final String html;

  const QccMailWebView({super.key, required this.html});

  @override
  State<QccMailWebView> createState() => _QccMailWebViewState();
}

class _QccMailWebViewState extends State<QccMailWebView> {
  // WebView 内容实际高度（动态撑开）
  double _webViewHeight = 400;
  bool _isLoading = true;
  InAppWebViewController? _controller;

  String _wrap(String html) {
    // 如果已经是完整 HTML 文档，直接注入响应式补丁
    bool isFullDoc = html.trimLeft().toLowerCase().startsWith('<!doctype') ||
        html.trimLeft().toLowerCase().startsWith('<html');

    if (isFullDoc) {
      // 注入 viewport meta 和自适应样式
      String injected = html.replaceFirst(
        RegExp(r'</head>', caseSensitive: false),
        '''
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<style>
  body { margin:0 !important; padding:12px !important; }
  img  { max-width:100% !important; height:auto !important; }
  table { max-width:100% !important; word-break:break-word; }
  * { box-sizing:border-box; }
</style>
</head>''',
      );
      return injected;
    }

    // 片段 HTML，包裹完整结构
    return """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <style>
    html, body {
      margin: 0;
      padding: 12px;
      font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif;
      font-size: 15px;
      line-height: 1.6;
      color: #222;
      background: white;
      word-break: break-word;
      overflow-wrap: break-word;
    }
    img {
      max-width: 100% !important;
      height: auto !important;
      display: block;
    }
    table {
      max-width: 100% !important;
      width: 100% !important;
      border-collapse: collapse;
    }
    td, th {
      word-break: break-word;
    }
    a {
      color: #1a73e8;
      word-break: break-all;
    }
    * { box-sizing: border-box; }
  </style>
</head>
<body>
  $html
</body>
</html>
""";
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          // 动态高度：内容撑开后更新
          height: _webViewHeight,
          child: InAppWebView(
            initialData: InAppWebViewInitialData(
              data: _wrap(widget.html),
              mimeType: "text/html",
              encoding: "utf-8",
            ),

            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              // 禁止用户缩放（保证排版稳定）
              supportZoom: false,
              // 禁止横向滚动条（内容宽度自适应）
              horizontalScrollBarEnabled: false,
              verticalScrollBarEnabled: true,
              transparentBackground: false,
              // 禁止 WebView 内部滚动，由外层 ScrollView 控制
              disableVerticalScroll: false,
              // 启用 shouldOverrideUrlLoading 回调（否则部分平台不触发）
              useShouldOverrideUrlLoading: true,
              // 允许 https 页面里加载 http 图片等混合内容（邮件图床常见）
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            ),

            onWebViewCreated: (controller) {
              _controller = controller;
            },

            onLoadStop: (controller, url) async {
              setState(() => _isLoading = false);
              // 获取内容真实高度，动态调整 SizedBox
              await _updateHeight(controller);
            },

            onScrollChanged: (controller, x, y) async {
              // 防止内容撑大后高度不够
              await _updateHeight(controller);
            },

            shouldOverrideUrlLoading: (controller, action) async {
              final urlRequest = action.request;
              final url = urlRequest.url?.toString() ?? "";

              // ⚠️ 关键：这个回调对页面里的 <img>/css/js 等子资源加载也会触发。
              // 只拦「用户主动点击的主框架导航」，否则会把图片请求也 CANCEL 掉，
              // 导致内联/外链图片显示成占位框。
              final bool isMainFrame = action.isForMainFrame ?? true;
              final bool isUserClick =
                  action.navigationType == NavigationType.LINK_ACTIVATED;

              // 子资源（图片、样式、脚本等）：一律放行，让 WebView 正常加载
              if (!isMainFrame) {
                return NavigationActionPolicy.ALLOW;
              }

              // mailto: / tel: 等协议：外部处理
              if (url.startsWith("mailto:") || url.startsWith("tel:")) {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                return NavigationActionPolicy.CANCEL;
              }

              // 用户点击的 http/https 链接：用外部浏览器打开，阻止 WebView 内跳转
              if (url.startsWith("http") && isUserClick) {
                LogObj.log("打开外部链接: $url");
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  debugPrint("无法打开链接: $url");
                }
                return NavigationActionPolicy.CANCEL;
              }

              // 其余（含首次 data: 文档加载、非点击触发的主框架请求）放行
              return NavigationActionPolicy.ALLOW;
            },

            onReceivedError: (controller, request, error) {
              debugPrint("WebView error: ${error.description}");
            },
          ),
        ),

        // 加载中遮罩
        if (_isLoading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  /// 动态获取页面内容高度并更新 SizedBox
  Future<void> _updateHeight(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: "document.body.scrollHeight",
      );
      if (result != null) {
        double newHeight = double.tryParse(result.toString()) ?? _webViewHeight;
        // 加一点 padding，防止内容被截断
        newHeight += 20;
        if ((newHeight - _webViewHeight).abs() > 5) {
          setState(() => _webViewHeight = newHeight);
        }
      }
    } catch (e) {
      debugPrint("获取 WebView 高度失败: $e");
    }
  }
}



class QccFullScreenMailPage extends StatelessWidget {
  final String subject;
  final String html;

  const QccFullScreenMailPage({
    super.key,
    required this.subject,
    required this.html
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          subject,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        // 自带返回按钮
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // 这里的 body 直接撑满，不再需要 SizedBox 限制高度
      body: QccMailWebView(html: html),
    );
  }
}