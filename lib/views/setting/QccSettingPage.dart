import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qcc_flutter/qccnodemap/QccNodeListWidget.dart';
import 'package:qcc_flutter/qccwallet/WalletUtil.dart';

import '../../utile/Tools.dart'; // 【路径假设】沿用其他 views 子目录里 Tools.dart 的相对路径写法，如实际不在这里请帮我改一下
import 'AppTranslator.dart';
import 'FontSizeSettingPage.dart';
import 'LanguageSettingPage.dart';

// 【本次改动，对应"qcc_flutter 是插件，package_info_plus 读不到插件自己版本号"】
// package_info_plus 的 PackageInfo.fromPlatform() 读的是"当前正在运行的宿主 App"
// 自己的原生打包元数据，读不到 qcc_flutter 这个插件本身 pubspec.yaml 里的 version——
// 这也解释了之前为什么会读出一个跟这个插件毫无关系的"VQcc"。所以撤掉
// package_info_plus 这条路，改成读 AppVersion.dart 里手动维护的常量，不再需要
// 异步读取，也不再需要 StatefulWidget，改回最初的 StatelessWidget。
// 如果 pubspec.yaml 里以后加了 package_info_plus 依赖但已经没有别处在用，
// 可以一并从 pubspec.yaml 里删掉。
class QccSettingPage extends StatelessWidget {
  const QccSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取全局管理实例
    final manager = AppTranslationManager.instance;
    final fontManager = FontManager.instance;
    final bool isDesktop = Platform.isMacOS || Platform.isWindows;
    return Scaffold(
      appBar: AppBar(
        title: const Trans("Qcc客户端设置"),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                "V${AppVersion.version}",
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          return ListView(
            children: [
              // 1. 语言翻译分流
              SettingTile(
                title: "语言设置",
                subtitle: manager.supportedLanguages[manager.targetLanguage] ?? "English",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) =>  LanguageSettingPage()),
                  );
                },
              ),
              const Divider(height: 1),
              // 2. 字号大小分流 (跳转到你之前做的那个直观设置页)
              SettingTile(
                title: "字号大小",
                subtitle: "${fontManager.fontSize}%",
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => FontSizeSettingPage())
                  );
                },
              ),
              const Divider(height: 1),
              SettingTile(
                title: "当前节点",
                subtitle: "Qcc测试网络节点",
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => QccNodeListWidget())
                  );
                },
              ),
              const Divider(height: 1),
              // 3. 钱包导入：移动端支持"扫码 + 文件"两种；Mac/Win 摄像头对准二维码体验差，只保留文件导入
              // 注：这里不需要手动刷新首页钱包缓存 —— WalletInitPage 在 push 本设置页时
              // 已经用 .then() 监听了返回，回到首页会自动重新扫描本地存储、刷新 activeWallet/名称缓存
              if (!isDesktop) ...[
                SettingTile(
                  title: "钱包导入",
                  subtitle: "扫码二维码导入Qcc钱包",
                  onTap: () async {
                    bool ok = await Walletutil.handleScanRestore(context);
                    if (ok) {
                      Tools.showToast(context, "钱包导入成功");
                    }
                  },
                ),
                const Divider(height: 1),
              ],
              SettingTile(
                title: "钱包导入",
                subtitle: isDesktop ? "选择本地备份文件导入Qcc钱包" : "选择本地备份文件导入",
                onTap: () async {
                  bool ok = await Walletutil.handleFileRestore(context);
                  if (ok) {
                    Tools.showToast(context, "钱包导入成功");
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }


}


class SettingTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingTile({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Trans(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}


/// 【新增文件，替代 package_info_plus 方案】
/// qcc_flutter 这个工程本身是以"插件(plugin)"形式存在的——package_info_plus 的
/// PackageInfo.fromPlatform() 只能读取"当前正在运行的宿主 App"自己打包时写进
/// 原生元数据(macOS 的 Info.plist / Android 的 AndroidManifest 等)里的版本号，
/// 它没办法反过来读取某一个被引用的 Flutter 插件/package 自己 pubspec.yaml
/// 里声明的 version 字段。之前设置页读出来的"VQcc"，其实读到的是宿主壳工程
/// 自己的包信息(或者宿主工程 Info.plist 里被错误配置的字段)，跟 qcc_flutter
/// 这个插件本身的版本号毫无关系——所以这条路走不通，得手动维护。
///
/// ⚠️ 假设/需要你确认：这里假设你希望每次发版时手动同步改这一个常量就够了
/// （跟 pubspec.yaml 的 version 字段保持一致，目前是 0.8.1）。如果你们有统一的
/// 发版脚本/CI 会自动生成版本号文件，把这个文件换成那边生成的即可，只要保留
/// `AppVersion.version` 这个静态字段名，调用方(QccSettingPage.dart)不用改。
class AppVersion {
  static const String version = "0.8.2";
}