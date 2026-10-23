import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart'; // 【新增依赖】获取物理显示器尺寸，需要在 pubspec.yaml 添加
import 'package:window_manager/window_manager.dart'; // 【新增依赖】设置原生窗口大小/居中，需要在 pubspec.yaml 添加
import 'package:qcc_flutter/email/MailUtils.dart';
import 'package:qcc_flutter/qccwallet/QccActiveWallet.dart';
import 'package:qcc_flutter/qccwallet/WalletUtil.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccObj.dart';
import 'package:qcc_flutter/views/setting/QccSettingPage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../email/QccMailHomePage.dart';
import '../qccsys/QccSysRootPage.dart';
import '../qccwallet/QccWallet.dart';
import '../qccwallet/walletviess/CreateWalletRouterPage.dart';
import '../rule/QccRuleManagerPage.dart';
import '../rule/user/multiple/multicreat/QccMultiSigManagerPage.dart';
import '../txdata/data/QccDataBroadcastPage.dart';
import '../txdata/tx/QccTransferPage.dart';
import '../txdata/QccTxManagerPage.dart';
import '../views/dex/QccMarketListPage.dart';
import '../views/dex/QccMatchManagerPage.dart';
import '../views/dex/QccOpenDataManager.dart';
import '../views/myasset/QccAssetService.dart';
import '../views/setting/AppTranslator.dart';
import '../utile/QccStorage.dart';
import '../views/hashviews/QccAddressManagerPage.dart';
import '../views/myasset/QccAssetManagerPage.dart';



class WalletInitPage extends StatefulWidget {
  final String freeId;
  const WalletInitPage({super.key,required this.freeId});

  @override
  State<WalletInitPage> createState() => _WalletInitPageState();
}

class _WalletInitPageState extends State<WalletInitPage> {
  bool isloading=false;

  // ✅ 新增：地址 -> 名称 映射缓存，避免每次 build 都读存储
  Map<String, String> _walletNames = {};

  // 模拟判断本地是否有钱包
  @override
  void initState() {
    super.initState();
    MailUtils.emailid=widget.freeId;

    // ✅ 新增：Mac/Win 桌面端启动时，把"原生窗口"本身设置成屏幕物理尺寸的比例并居中，
    // 而不是在 Flutter 内部再缩小内容。这样窗口大小才真正跟你的显示器分辨率挂钩，
    // 13/14 寸小屏和大屏 Mac 拿到的窗口比例是一致的，不会出现"明明屏幕很大却缩得很小"的问题。
    _configureDesktopWindow();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      await _checkLocalWallet();
      await  QccAssetService().initFollowAssets();
      QccOpenDataManager.syncFromNetwork();
      isloading=true;
      if(mounted){
        setState(() {
        });
      }
    });

  }

  // 【新增依赖 - 请确认】需要在 pubspec.yaml 里加 window_manager 和 screen_retriever 两个包
  // （screen_retriever 通常是 window_manager 的依赖，但直接调用 screenRetriever.getPrimaryDisplay()
  // 需要显式依赖它）。
  //
  // 【重要提醒】window_manager 官方文档建议 `windowManager.ensureInitialized()` 在 main() 里
  // runApp() 之前调用，这样窗口在显示前就已经是目标大小，不会有"先出现小窗口、再跳变到大窗口"的
  // 闪烁感。我这里没有 main.dart，所以把调用放在了这个页面的 initState 里做兜底，能生效，
  // 但会有一次明显的窗口尺寸跳变。如果你能把下面这段逻辑挪到 main.dart 的 main() 函数最前面
  // （runApp 之前），体验会更好，我可以帮你整理成 main.dart 需要的样子。
  Future<void> _configureDesktopWindow() async {
    if (!(Platform.isMacOS || Platform.isWindows)) return;
    try {
      await windowManager.ensureInitialized();
      final Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final Size screenSize = primaryDisplay.size;

      // 窗口占屏幕的比例：横向 75%，纵向 80%，比之前的"内部卡片 70%"观感更接近常见桌面应用
      final double targetWidth = screenSize.width * 0.75;
      final double targetHeight = screenSize.height * 0.80;

      final windowOptions = WindowOptions(
        size: Size(targetWidth, targetHeight),
        center: true,
        minimumSize: const Size(960, 640), // 避免窗口被手动拖得过小导致布局挤压
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setSize(Size(targetWidth, targetHeight));
        await windowManager.setMinimumSize(const Size(960, 640));
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      LogObj.log("桌面窗口尺寸设置失败: $e");
    }
  }

  Future<void> _checkLocalWallet() async {
    // 1. 从存储中拿到所有以 'qcc_vault_' 为前缀的地址列表
    // 此时不需要密码，只是扫描 Key 的名称
    List<String> addresses = await QccStorage.getAllStoredAddresses();
    for(String add in addresses){
      LogObj.log("检测到本地钱包: $add");
    }

    if (addresses.isEmpty) {
      LogObj.log("本地未检测到钱包数据");
      // ✅ 修复：之前这里直接 return，如果是"从有钱包变成全部删除"的重新加载场景，
      // QccObj.activeWallet / wallets 缓存不会被清空，页面会停留在旧的 _buildMainAppView()。
      // 这里显式清空状态，才能正确回退到 _buildOnboardingView()。
      if (mounted) {
        setState(() {
          QccObj.setWallets([]);
          QccObj.activeWallet = null;
          _walletNames = {};
        });
      }
      return;
    }
    LogObj.log("检测到本地钱包数量: ${addresses.length}");
    // 2. 将地址转换为钱包对象（此时不含助记词，用于列表显示和余额查询）
    List<QccWallet> watchOnlyWallets = addresses.map((addr) {
      // 假设你的 QccWallet 有个构造函数可以只接收 address
      // 如果没有，可以先用 null 占位助记词，或者在 QccWallet 类中增加 watchOnly 工厂方法
      return QccWallet.watchOnly(addr);
    }).toList();

    // ✅ 新增：同步加载地址对应的名称索引（无需密码，纯本地明文索引）
    final names = await QccStorage.getAllWalletNames();

    // ✅ 修复：重新加载时如果原来的 activeWallet 地址依然存在，保留原选中项，
    // 而不是每次都强制跳回第一个地址（比如用户之前手动切换到了第 3 个钱包，
    // 从资产页返回后不应该又跳回第 1 个）
    final String? prevActiveAddress = QccObj.activeWallet?.address;
    final bool prevStillExists = prevActiveAddress != null && addresses.contains(prevActiveAddress);
    final QccWallet nextActiveWallet = prevStillExists
        ? watchOnlyWallets.firstWhere((w) => w.address == prevActiveAddress)
        : watchOnlyWallets.first;

    // 3. 更新全局状态
    if (mounted) {
      setState(() {
        QccObj.setWallets(watchOnlyWallets);
        QccObj.activeWallet = nextActiveWallet;
        _walletNames = names;
      });
    }
    // 此时 UI 会因为 activeWallet 不为 null 而自动切换到 _buildMainAppView()
    LogObj.log("已加载观察模式钱包: ${QccObj.activeWallet?.address}");
  }

  // ✅ 新增：单独刷新名称索引（新建/导入钱包后调用，防止拿到旧缓存）
  Future<void> _refreshWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (mounted) {
      setState(() => _walletNames = names);
    }
  }

  // ✅ 新增：统一的名称获取入口，未命名时兜底为地址缩写
  String _nameFor(String address) {
    return _walletNames[address] ?? QccStorage.shortAddress(address);
  }


  @override
  Widget build(BuildContext context) {
    if(!isloading){
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    // 如果没有钱包，显示创建/导入引导界面；否则返回主菜单骨架
    // ✅ 修正：不再用 MediaQuery(窗口尺寸) 的 70% 在 Flutter 内部套一层"卡片"，
    // 那样等于在一个本来就很小的默认窗口里二次缩小。真正的窗口大小在 initState
    // 里通过 window_manager 直接设置成了屏幕物理尺寸的比例，这里内容正常铺满窗口即可。
    return QccObj.activeWallet == null ? _buildOnboardingView() : _buildMainAppView();
  }

  // --- 核心 Widget 1: 引导界面 ---
  Widget _buildOnboardingView() {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.black]),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Trans("QCC 后量子加密钱包", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), shrink: true, maxLines: 2),
            const SizedBox(height: 10),
            Trans("基于 ML-DSA-87(Dilithium5) 算法保护您的资产", style: const TextStyle(color: Colors.white70), shrink: true, maxLines: 2),
            const SizedBox(height: 60),
            // 修改 WalletInitPage.dart 中的按钮
            _actionButton("生成新钱包", Colors.blueAccent, () async {
              // 1. 跳转并等待结果
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateWalletRouterPage()),
              );
              // 2. 衔接点：如果返回了有效的钱包对象，则调用处理函数
              if (result != null && result is QccWallet) {
                LogObj.log(" 生产钱包地址:${result.address}");
                _handleNewWallet(result);
              }
            }),
            const SizedBox(height: 20),
            // 导入方式：移动端支持"扫码 + 文件"两种；Mac/Win 摄像头对准二维码体验差，只保留文件导入
            if (!(Platform.isMacOS || Platform.isWindows)) ...[
              _actionButton("导入二维码恢复", Colors.white24, () async {
                bool ok = await Walletutil.handleScanRestore(context);
                // ✅ 恢复成功后钱包已写入本地存储，但 QccObj 缓存还是旧的，
                // 必须重新扫描本地存储 + 刷新名称缓存，才能让新钱包生效并切到主界面
                if (ok && mounted) {
                  await _checkLocalWallet();
                  _refreshWalletNames();
                }
              }),
              const SizedBox(height: 20),
            ],
            _actionButton("导入文件恢复", Colors.white24, () async {
              bool ok = await Walletutil.handleFileRestore(context);
              if (ok && mounted) {
                await _checkLocalWallet();
                _refreshWalletNames();
              }
            }),
          ],
        ),
      ),
    );
  }

  void _handleNewWallet(QccWallet newWallet) {
    setState(() {
      QccObj.insertWallet(newWallet);
      QccObj.activeWallet = newWallet;
      _checkLocalWallet();
    });
    // ✅ 新增：新钱包创建/导入时命名弹窗已经把名称写入 QccStorage，
    // 这里主动拉一次最新映射，避免主界面还在用旧缓存导致名称显示不出来
    _refreshWalletNames();
    // 提示用户
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Trans("钱包创建成功：${newWallet.address.substring(0, 8)}..."),
        backgroundColor: Colors.green,
      ),
    );

  }

  Widget _actionButton(String text, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: onTap,
        child: Trans(text, style: const TextStyle(color: Colors.white, fontSize: 16), shrink: true),
      ),
    );
  }



  void _doTransfer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QccTransferPage(assetId: _selectedAssetId),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildMainAppView() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () async {
            final res = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateWalletRouterPage()),
            );
            if (res != null) _handleNewWallet(res);
          },
        ),
        title: Trans("QCC 资产管理", shrink: true),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            onPressed: _doTransfer,
            child: Trans("转账", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue), shrink: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWalletCard(), // 钱包卡片（支持左右滑动切换或下拉）
          // 2. 这里的分割线或标题（可选）
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Trans("功能服务", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), shrink: true),
            ),
          ),
          // 3. 加入功能矩阵
          // 注意：内部使用了 Expanded，确保它占据剩余空间
          _buildFunctionGrid(),
          // 4. 如果底部还有备案信息或版本号（可选）
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Trans("QCC Network v0.0.9", style: const TextStyle(color: Colors.grey, fontSize: 10), shrink: true),
          )
        ],
      ),
    );
  }



  bool _isWalletListExpanded = false; // 在 State 类中定义这个变量

  Widget _buildWalletCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.all(12),
      height: _isWalletListExpanded ? 300 : 145, // 展开后的尺寸
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade900, Colors.blue.shade700],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 固定最大宽度，翻译超长时截断，不影响右侧按钮
                Flexible(
                  child: Text(
                    "QCC Chain",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                _buildQuickAction(
                  icon: Icons.history,
                  label: "交易记录",
                  onTap: () => _navToExplorer(0), // 0 表示交易 Tab
                ),
                Container(width: 1, height: 18, color: Colors.white24),
                _buildQuickAction(
                  icon: Icons.storage,
                  label: "链上数据",
                  onTap: () => _navToExplorer(1), // 1 表示数据 Tab
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    _isWalletListExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                  onPressed: () => setState(() => _isWalletListExpanded = !_isWalletListExpanded),
                )
              ],
            ),
          ),
          Expanded(
            child: _isWalletListExpanded ? _buildExpandedList() : _buildSingleActiveView(),
          ),
        ],
      ),
    );
  }

  // 辅助构建按钮
  Widget _buildQuickAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            // 限制最大宽度 + shrink，翻译超长时自动缩小，不撑开父 Row
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 52),
              child: Trans(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 2,
                shrink: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

// 跳转逻辑
  void _navToExplorer(int initialTab) {
    String address="";
    if(QccObj.activeWallet!=null){
      address=QccObj.activeWallet!.address;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QccAddressManagerPage(
          address: address,
          initialTabIndex: initialTab,
        ),
      ),
    );
  }


  Widget _buildExpandedList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: QccObj.readWallets().length,
      separatorBuilder: (context, index) => Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        final wallet = QccObj.getWalletIndex(index);
        bool isActive = QccObj.activeWallet?.address == wallet.address;
        return InkWell(
          onTap: () {
            setState(() {
              QccObj.activeWallet = wallet;
              _isWalletListExpanded = false; // 选中后自动折叠
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.circle_outlined,
                    color: isActive ? Colors.greenAccent : Colors.white30, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ 名称作为主标题
                      Text(
                        _nameFor(wallet.address),
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // ✅ 地址降级为副标题，字号更小、颜色更浅
                      Text(
                        wallet.address,
                        style: TextStyle(
                          color: isActive ? Colors.white70 : Colors.white38,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(QccWallet wallet) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.copy, color: Colors.white, size: 20),
          onPressed: () => Tools.copytext(context, wallet.address),
        ),
        const SizedBox(width: 5),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white24,
            foregroundColor: Colors.white,
            elevation: 0,
            // 1. 核心：设置最小尺寸，高度设为 28 或 30 比较合适
            minimumSize: const Size(60, 30),
            // 2. 移除多余的内边距
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // 3. 紧凑布局
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15), // 圆角根据高度调整
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QccTransferPage(
                  assetId: _selectedAssetId,
                ),
                fullscreenDialog: true,
              ),
            );
          },
          child: Trans("转账", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), shrink: true),
        )
      ],
    );
  }

  String _selectedAssetId = "QCC";

  Widget _buildSingleActiveView() {
    final wallet = QccObj.activeWallet;
    if (wallet == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // const SizedBox(height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _nameFor(wallet.address),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    // ✅ 地址：次要信息，缩小并降低透明度
                    Text(
                      wallet.address,
                      style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5), // 间距
              // ✅ 二维码图标按钮 (触发弹窗)
              GestureDetector(
                onTap: () => _showRecieveQRCodeDialog(wallet.address, name: _nameFor(wallet.address)), // 弹出收款二维码
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white12, // 微微发亮，突出可点击
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.qr_code, color: Colors.white, size: 16), // 图标颜色设为白色适配背景
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              QccActiveWallet(wallet.address, _selectedAssetId, fontSize:16,onAssetChanged: (value) {
                _selectedAssetId = value;
              },),
              const Spacer(),
              _buildActionButtons(wallet),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ✅ name 为可选参数：有名称时在"收款地址"标题下方多显示一行
  void _showRecieveQRCodeDialog(String address, {String? name}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许全屏
      backgroundColor: Colors.transparent, // 背景透明，方便做圆角
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 适应内容高度
          children: [
            // 1. 顶部指示条
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            // 2. 标题
            const Trans("收款地址", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
            if (name != null && name.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(name, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: 12),
            Text(address, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontFamily: 'monospace')),

            const SizedBox(height: 24),

            // 3. 二维码展示区
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
              ),
              child: QrImageView(
                data: address, // 直接传入明文地址
                version: QrVersions.auto,
                size: 200,
                gapless: true,
                // embeddedImage: const AssetImage('assets/images/logo_sm.png'), // 可选：添加 Logo
                embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(40, 40)),
                errorStateBuilder: (cxt, err) => const Center(child: Icon(Icons.error_outline, color: Colors.red)),
              ),
            ),

            const SizedBox(height: 24),

            // 4. 操作按钮区
            Row(
              children: [
                // 复制地址
                Expanded(
                  child: CupertinoButton(
                    color: Colors.blue[50],
                    padding: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 6),
                        Trans("复制地址", style: TextStyle(fontSize: 14, color: Colors.blue[700])),
                      ],
                    ),
                    onPressed: () {
                      Tools.copytext(context, address); // 假设你已有复制工具类
                      Navigator.pop(context); // 复制后关闭
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // 关闭
                Expanded(
                  child: CupertinoButton(
                    color: Colors.grey[300],
                    padding: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close, size: 16, color: Colors.grey[700]),
                        const SizedBox(width: 6),
                        Trans("关闭", style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                      ],
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFunctionGrid() {
    final bool isDesktop = Platform.isMacOS || Platform.isWindows;
    // 修改列表，加入唯一的 name 标识
    final List<WalletFunction> functions = [
      WalletFunction("我的资产", "assets", Icons.account_balance_wallet, Colors.orange),
      WalletFunction("数据上链", "data_broadcast", Icons.data_exploration, Colors.redAccent),
      WalletFunction("综合交易", "qcc_tx", Icons.price_change, Colors.purple),
      WalletFunction("现货交易", "spot_trade", Icons.verified_user_rounded, Colors.cyan),
      //  WalletFunction("多签管理", "multi_sig", Icons.groups_rounded, Colors.brown),
      WalletFunction("规则管理", "rules", Icons.gavel_rounded, Colors.teal),
      // 本地资源图片替代 icon；图片加载失败时自动退回 icon
      // 路径必须与插件 pubspec.yaml 里声明的完全一致（assets/qcc.jpeg），
      // 读取时由 _buildFunctionIcon 带上 package: 'qcc_flutter'
      WalletFunction("QCC 信息", "qccinfo", Icons.verified_user_outlined, const Color(0xFF1E293B),
          image: "assets/qcc.jpeg"),
      // ✅ QCC 邮箱：仅 debug / profile 模式显示，release 模式下菜单项不出现
      if(widget.freeId=="admin")
        WalletFunction("QCC邮箱", "email", Icons.email_outlined, Colors.blue),
      WalletFunction("去中心化交易所", "dex_token", Icons.data_exploration, Colors.deepPurpleAccent),
      WalletFunction("钱包设置", "settings", Icons.settings, Colors.amber),
    ];

    return Expanded(
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // ✅ 桌面端窗口更宽敞：屏幕大，一屏放得下，禁用滚动物理效果，
        // 保证整个功能菜单完整展示、不需要上下拖动；移动端保持原来的可滚动行为
        // ✅ 修复：之前 4 列会拆成 3 行 (4+4+1)，配合禁用滚动，超出可用高度的第 3 行
        // （"钱包设置"）会被直接裁掉、完全看不见也滑不到。改成 5 列后 9 个正好排成
        // 5+4 两行，更容易在一屏内放下；同时不再彻底禁用滚动——万一窗口被拖得很小
        // 装不下，也还能滚动看到，不会出现菜单项彻底消失的情况。
        physics: isDesktop ? const ClampingScrollPhysics() : null,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isDesktop ? 5 : 3,        // 桌面端横向空间更多，改用 5 列(9个=5+4两行)
          mainAxisSpacing: 15,      // 上下间距
          crossAxisSpacing: 15,     // 左右间距
          childAspectRatio: isDesktop ? 1.3 : 0.9,    // 桌面端卡片更扁一点，行高更矮，更容易两行放下
        ),
        itemCount: functions.length,
        itemBuilder: (context, index) {
          final item = functions[index];
          return InkWell(
            onTap: () => _onFunctionTap(item),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFunctionIcon(item),
                  const SizedBox(height: 10),
                  Trans(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87), shrink: true, maxLines: 2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  /// 功能图标：有 image 用本地资源图片，否则用 icon。
  /// 两种情况外框尺寸一致（52×52 圆形 = icon 28 + 内边距 12×2），宫格对齐不变。
  Widget _buildFunctionIcon(WalletFunction item) {
    final Widget iconCircle = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(item.icon, color: item.color, size: 28),
    );
    if (item.image == null) return iconCircle;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: item.color.withValues(alpha: 0.15), width: 1),
      ),
      child: ClipOval(
        child: Image.asset(
          item.image!,
          // ✅ 关键：本页面在 qcc_flutter 插件里，资源打包在插件包内，
          // 宿主 App 运行时实际路径是 packages/qcc_flutter/assets/qcc.jpeg，
          // 不指定 package 会去宿主 App 自己的 assets 里找，必然找不到。
          package: WalletFunction.assetPackage,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          // 资源未声明或路径写错时不报红屏，退回 icon；同时打日志便于排查
          errorBuilder: (_, error, ___) {
            LogObj.log("功能图标加载失败: packages/${WalletFunction.assetPackage}/${item.image} -> $error");
            return iconCircle;
          },
        ),
      ),
    );
  }

  void _onFunctionTap(WalletFunction item) {
    // 使用 item.name 进行逻辑分流
    switch (item.name) {
      case "assets":
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const QccAssetManagerPage()),
        ).then((_) {
          // ✅ 新增：资产管理页可以删除/导出钱包地址，返回本页时必须重新扫描本地存储，
          // 否则 QccObj 里的钱包列表和 activeWallet 还是进入该页面之前的旧缓存。
          if (mounted) {
            _checkLocalWallet();
            _refreshWalletNames();
          }
        });
        break;

      case "data_broadcast":
        if (QccObj.activeWallet == null) {
          Tools.showToast(context, "请先创建或选择一个钱包");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QccDataBroadcastPage(initialWallet: QccObj.activeWallet),
          ),
        );
        break;
      case "email" :
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QccMailHomePage(user: MailUtils.getMailfrom()),
          ),
        );
        break;
      case "qcc_tx":
        if (QccObj.activeWallet == null) {
          Tools.showToast(context, "请先创建或选择一个钱包");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccTxManagerPage()),
        );
        break;
      case "multi_sig":
        if (QccObj.activeWallet == null) {
          Tools.showToast(context, "请先创建或选择一个钱包");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccMultiSigManagerPage()),
        );
        break;

      case "rules":
        if (QccObj.activeWallet == null) {
          Tools.showToast(context, "请先创建或选择一个钱包");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccRuleManagerPage()),
        );
        break;

      case "settings":
        if (QccObj.activeWallet == null) {
          Tools.showToast(context, "请先创建或选择一个钱包");
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccSettingPage()),
        ).then((_) {
          // ✅ 设置页里可以扫码/文件导入新钱包，返回本页时同样需要重新扫描本地存储
          if (mounted) {
            _checkLocalWallet();
            _refreshWalletNames();
          }
        });
        break;
      case "qccinfo":
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccSysRootPage()),
        );
        break;
      case "spot_trade":
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => QccMatchManagerPage()),
        );

      case "dex_token" :
        Navigator.push(context, MaterialPageRoute(builder: (context) => const QccMarketListPage()));

      default:
      // 未匹配到的 name 提示正在开发中
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${item.title} ${Tools.getTra("功能正在开发中...")}"))
        );
    }
  }
}


class WalletFunction {
  final String title;
  final String name;
  final IconData icon;
  final Color color;
  final Widget? targetPage;
  /// 可选：本地资源图片路径（需在 pubspec.yaml 的 flutter.assets 中声明）。
  /// 设置后优先显示图片，icon 作为加载失败时的兜底。
  final String? image;

  /// 资源所在的包名 = 插件 pubspec.yaml 的 name
  static const String assetPackage = "qcc_flutter";

  WalletFunction(this.title,this.name,this.icon, this.color, {this.targetPage, this.image});
}