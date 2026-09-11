import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart'; // 【假设新增依赖】用于桌面端保存文件对话框，请在 pubspec.yaml 中添加 file_picker
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于复制 Hash
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/qccwallet/QccWallet.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/utile/QccTransferUtil.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/views/myasset/AssetUtil.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../utile/QccObj.dart';
import '../../utile/QccStorage.dart';
import '../../utile/Tools.dart';
import '../data/QccAssetAnnouncementPage.dart';
import '../setting/AppTranslator.dart';
import '../setting/QccPassDialog.dart';
import '../toolviews/QccLoading.dart';
import 'QccAssetService.dart';
import 'QccAsset.dart';

// --- 统一设计 Token：颜色 / 圆角 / 阴影，避免散落的硬编码颜色值 ---
class _Palette {
  static const Color primary = Color(0xFF2F6FED);      // 主色调（原来到处是 Colors.blue）
  static const Color primarySoft = Color(0xFFEBF1FE);
  static const Color bg = Color(0xFFF6F7FB);
  static const Color cardBorder = Color(0xFFEDEFF3);
  static const Color textPrimary = Color(0xFF1A1D29);
  static const Color textSecondary = Color(0xFF8A8F9C);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFE08E1D);
  static const Color danger = Color(0xFFE0463D);

  static List<BoxShadow> cardShadow = [
    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
  ];
}

class QccAssetManagerPage extends StatefulWidget {
  const QccAssetManagerPage({super.key});

  @override
  State<QccAssetManagerPage> createState() => _QccAssetManagerPageState();
}

class _QccAssetManagerPageState extends State<QccAssetManagerPage> {
  int _selectedSegment = 0; // 0: 关注, 1: 搜索, 2: 地址, 3: 质押
  List<QccAsset> _allAssets = [];
  List<QccAsset> _displayAssets = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // 地址 -> 昵称 映射缓存；启动时一次性异步加载完毕，build 阶段只做同步查表
  Map<String, String> _walletNames = {};

  // --- 质押相关变量 ---
  Map<String, List<dynamic>> _pledgeDataMap = {}; // 核心数据源
  bool _isPledgeLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadWalletNames();
    _startPledgePolling();
  }

  Future<void> _loadWalletNames() async {
    // 【假设】QccStorage.getAllWalletNames() 即此前讨论的地址->昵称映射读取方法，
    // 请确认实际所在类名是否为 QccStorage，如不是请替换
    final names = await QccStorage.getAllWalletNames();
    if (mounted) {
      setState(() {
        _walletNames = names;
      });
    }
  }

  @override
  void dispose() {

    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final assets = await QccAssetService().fetchAllAssets();
    setState(() {
      _allAssets = assets;
      _displayAssets = assets;
      _isLoading = false;
    });
  }

  // --- 逻辑层：请求与解析 ---
  void _startPledgePolling() {
    _fetchPledgeStatus();
  }

  Future<void> _fetchPledgeStatus() async {
    final wallets = QccObj.readWallets();
    if (wallets.isEmpty) return;

    if (_pledgeDataMap.isEmpty) setState(() => _isPledgeLoading = true);

    try {
      final futures = wallets.map((w) => _fetchSingleAddressPledge(w.address)).toList();
      await Future.wait(futures); // 内部已通过 setState 更新

      if (mounted) {
        setState(() => _isPledgeLoading = false);
      }
    } catch (e) {
      debugPrint("质押数据同步异常: $e");
      if (mounted) setState(() => _isPledgeLoading = false);
    }
  }

  Future<void> _fetchSingleAddressPledge(String address) async {
    try {
      final url = Uri.parse('${QccExplorerService.baseUrl}/v1/pledge/$address');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['ok'] == true && root['data'] != null) {
          String dataStr = root['data'];
          List<dynamic> pledgeList = [];
          if (dataStr.isNotEmpty && dataStr != "[]") {
            pledgeList = json.decode(dataStr); // 二次解析
          }
          _pledgeDataMap[address] = pledgeList;
          debugPrint("地址 $address 解析到 ${pledgeList.length} 条质押数据");
        }
      }
    } catch (e) {
      debugPrint("地址 $address 请求失败: $e");
    }
  }

  // --- UI 层：渲染 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _Palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Trans("我的资产管理", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_selectedSegment == 1 ? 114 : 64),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _Palette.cardBorder, width: 1)),
            ),
            child: Column(
              children: [
                _buildSegmentSelector(),
                if (_selectedSegment == 1) _buildSearchBox(),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_selectedSegment), child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedSegment) {
      case 0:
        final followed = _allAssets.where((a) => a.isFollowing).toList();
        return followed.isEmpty ? _buildEmptyState("暂无关注资产") : _buildAssetListView(followed);
      case 1:
        return _buildAssetListView(_displayAssets);
      case 2:
        return _buildAddressManager();
      case 3:
        return _buildPledgeManager();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPledgeManager() {
    final allWallets = QccObj.readWallets();
    if (allWallets.isEmpty) return _buildEmptyState("暂无可用地址");

    // ✅ 核心优化：过滤掉没有质押记录的地址
    final pledgedWallets = allWallets.where((w) {
      final pledges = _pledgeDataMap[w.address];
      return pledges != null && pledges.isNotEmpty;
    }).toList();

    // 如果正在加载且目前没有数据，显示加载指示器
    if (_isPledgeLoading && _pledgeDataMap.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }

    // ✅ 如果没有任何地址有质押记录，显示空状态
    if (pledgedWallets.isEmpty) {
      return _buildEmptyState("当前所有地址均无质押记录");
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pledgedWallets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final wallet = pledgedWallets[index];
        final address = wallet.address;
        final List<dynamic> pledges = _pledgeDataMap[address] ?? [];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _Palette.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              // 既然已经过滤了无质押地址，这里默认展开显示详情
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              iconColor: _Palette.primary,
              collapsedIconColor: _Palette.textSecondary,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _Palette.primarySoft, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.account_balance_wallet_rounded, color: _Palette.primary, size: 18),
              ),
              title: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w700)
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _Palette.primarySoft, borderRadius: BorderRadius.circular(6)),
                      child: Trans(
                        "${pledges.length} 笔质押",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Palette.primary),
                      ),
                    ),
                  ],
                ),
              ),
              children: pledges.map((item) => _buildPledgeDetailItem(item)).toList(),
            ),
          ),
        );
      },
    );
  }

  // 每一笔具体的质押详细内容
  Widget _buildPledgeDetailItem(dynamic item) {
    final String hash = item['credentialHash'] ?? "N/A";
    String amount = item['amount']?.toString() ?? "0";
    LogObj.log("质押状态json:$item");
    String assetId=item["assetId"];
    amount=QccAssetService().getHumanAmount(assetId, amount);
    // --- 新增：解析 pledgeJson 获取到期时间 ---
    String expiryText = "unLock";
    bool isLocked = false;

    try {
      if (item['pledgeJson'] != null && item['pledgeJson'].toString().isNotEmpty) {
        final Map<String, dynamic> pJson = json.decode(item['pledgeJson']);
        if (pJson.containsKey('unlockTime')) {
          int unlockTimestamp = pJson['unlockTime']; // 毫秒级时间戳
          DateTime expiryDate = DateTime.fromMillisecondsSinceEpoch(unlockTimestamp);

          // 格式化时间显示
          expiryText = "${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}";

          // 判断是否还在锁定中
          if (expiryDate.isAfter(DateTime.now())) {
            isLocked = true;
          } else {
            expiryText += " (已到期)";
          }
        }
      }
    } catch (e) {
      debugPrint("解析 pledgeJson 出错: $e");
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _Palette.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("质押金额", style: TextStyle(color: _Palette.textSecondary, fontSize: 12)),
              Text(amount, style: TextStyle(fontWeight: FontWeight.w700, color: _Palette.primary, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          // --- 显示到期时间：状态用徽章而非纯色文字，视觉更清晰 ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Trans("到期时间", style: TextStyle(color: _Palette.textSecondary, fontSize: 12)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isLocked ? _Palette.warning : _Palette.success).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                    expiryText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isLocked ? _Palette.warning : _Palette.success,
                    )
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text("CREDENTIAL HASH", style: TextStyle(color: _Palette.textSecondary, fontSize: 10, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(ClipboardData(text: hash));
              Tools.showToast(context, "Hash copy");
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _Palette.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(hash, style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF3A3F4B)))),
                  const SizedBox(width: 6),
                  Icon(Icons.copy_rounded, size: 14, color: _Palette.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // --- 其他原有组件 ---

  Widget _buildSegmentSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CupertinoSlidingSegmentedControl<int>(
        backgroundColor: _Palette.bg,
        thumbColor: _Palette.primary,
        groupValue: _selectedSegment,
        children: {
          0: _segmentLabel("关注", 0),
          1: _segmentLabel("搜索", 1),
          2: _segmentLabel("地址", 2),
          3: _segmentLabel("质押(待开发)", 3),
        },
        onValueChanged: (val) {
          if (val != null) {
            setState(() => _selectedSegment = val);
            if (val == 3) _fetchPledgeStatus();
          }
        },
      ),
    );
  }

  Widget _segmentLabel(String text, int index) {
    final bool selected = _selectedSegment == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Trans(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : _Palette.textSecondary,
        ),
      ),
    );
  }

  Widget _buildAddressManager() {
    final wallets = QccObj.readWallets();
    if (wallets.isEmpty) return _buildEmptyState("暂无可用地址");
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: wallets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final w = wallets[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _Palette.cardShadow,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _Palette.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.account_balance_wallet_outlined, color: _Palette.primary, size: 18),
            ),
            title: Text(w.address, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Trans("测试网", style: TextStyle(color: _Palette.textSecondary, fontSize: 11)),
                  if ((_walletNames[w.address] ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      _walletNames[w.address]!,
                      style: TextStyle(color: _Palette.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            // --- 导出按钮：加背景色圆形容器，提升可点性与视觉分量 ---
            trailing: Material(
                color: _Palette.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min, // 关键：让 Row 按内容收缩，而非撑满
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _tempRemove(w),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.delete_forever_outlined, color: _Palette.danger, size: 18),
                      ),
                    ),
                    SizedBox(width: 20,),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _handleExportAndRemove(w,_walletNames[w.address]!),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.exit_to_app_rounded, color: _Palette.danger, size: 18),
                      ),
                    ),
                  ],
                )
            ),
          ),
        );
      },
    );
  }
  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    bool isDestructive = false,
  }) async {
    return await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(content),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Trans("取消"),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: isDestructive,
            child: Text(confirmText),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ?? false;
  }

  //临时提高删除本地钱包信息
  _tempRemove(QccWallet wallet) async {
    // 1. 风险提示
    bool confirmRisk = await _showConfirmDialog(
      title: "删除警告",
      content: "临时提供删除本地钱包地址，新版本地址为34位统一字符串长度Q开头",
      confirmText: "确定删除",
      isDestructive: true,
    );
    if(confirmRisk) {
      QccStorage.delSingleWallet(wallet);
      Tools.showToast(context, "完成删除本地钱包:${wallet.address}");
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }


  Future<void> _handleExportAndRemove(QccWallet wallet,String name) async {
    final String address = wallet.address;
    String showstr="导出操作将显示您的敏感数据。生成二维码后，该地址将从本地彻底删除。请务必确认您已做好备份！";
    if(Platform.isMacOS || Platform.isWindows){
      showstr="导出操作将显示您的敏感数据。生成二进制文件，该地址将从本地彻底删除。请务必确认您已做好备份！";
    }
    // 1. 风险提示
    bool confirmRisk = await _showConfirmDialog(
      title: "安全警告",
      content: showstr,
      confirmText: "确定导出",
      isDestructive: true,
    );
    if (!confirmRisk) return;
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    String? password = await QccPassDialog.show(context);

    if (password == null) {
      Tools.showToast(context, "支付密码错误，无法还原钱包");
      return;
    }
    // --- 关键优化：在所有耗时操作开始前，立即弹出唯一一次 Loading ---
    _showDynamicLoading(context, statusNotifier);
    // ---- A. 还原钱包 (子线程计算) ----
    // 逻辑：先切状态，再跑耗时任务
    statusNotifier.value = TxStep.restoring;
    statusNotifier.value = TxStep.signing;
    QccWallet? souwallet=await QccStorage.restoreWallet(context,address,password);
    if(souwallet!=null){
      if(souwallet.address!= address){
        if (Navigator.canPop(context)) Navigator.pop(context);
        Tools.showToast(context, "支付密码错误，不是对应到处钱包");
        return;
      }
    }
    if (Navigator.canPop(context)) Navigator.pop(context);
    // 3. 获取加密数据（模拟你的还原过程）
    // 假设 QccStorage 是你定义的存储类
    String? encryptedData = await QccStorage.getRawData(address);
    if (encryptedData == null) {
      Tools.showToast(context, "找不到钱包数据");
      return;
    }
    // D. 恢复验证码输入 (用户导出时自己设置的那个)
    String? customVerifyCode = await Assetutil.showTextInputDialog(
        context,
        "请出入6以上导出密码",
        "设置导出密码",
        "导出密码是您迁徙冷钱包对24个助记词进行加密处理的密钥\r\n 完成助记词QR-AES加密处理 \r\n 在导入恢复需要用于解密使用\r\n 请务必切记"
    );
    if (customVerifyCode == null || customVerifyCode.length < 6) {
      Tools.showToast(context, "请设置至少6位验证码");
      return;
    }
    if(customVerifyCode == password){
      Tools.showToast(context, "为了你的数据钱包安全，导出密码不能和支付密码一致,请重新输入导出密码");
      return;
    }
    bool finalConfirm = await _showConfirmDialog(
      title: "最后确认",
      content: "点击生成后，地址将立即删除。确定继续？",
      confirmText: "生成并删除",
      isDestructive: true,
    );

    if (!finalConfirm) {
      Tools.showToast(context, "取消返回主钱包");
      return;
    }
    // 7. 显示二维码弹窗
    String qrdata = await QccTransferUtil.encodeToQrData(
        mnemonic:encryptedData,
        paymentPassword: password,
        exportCode: customVerifyCode
    );

    if(Platform.isMacOS || Platform.isWindows){
      // 桌面端：不走二维码展示流程，直接弹出系统保存对话框导出二进制文件
      bool exported = await _exportBinaryFileDesktop(qrdata, address);
      if (!exported) return; // 用户取消保存，钱包不删除
      QccStorage.delSingleWallet(wallet);
      QccObj.removeWallet(wallet);
      Tools.showToast(context, "本地数据已彻底销毁");
      if (Navigator.canPop(context)) Navigator.pop(context);
    }else{
      _showQRCodeDialog(qrdata,address, name,onShowAndDestroy:() async {
        QccStorage.delSingleWallet(wallet);
        QccObj.removeWallet(wallet);
        Tools.showToast(context, "本地数据已彻底销毁");
      } ,);
    }



  }

  /// 桌面端(Mac/Windows)导出：将 qrdata 内容写为二进制文件，文件名取地址昵称(无昵称则用地址本身)
  /// 返回 true 表示用户已选择路径并成功写入；返回 false 表示用户取消
  Future<bool> _exportBinaryFileDesktop(String qrdata, String address) async {
    // 直接用启动时加载好的 _walletNames 缓存查昵称，避免再次异步读取
    final String? nickname = _walletNames[address];
    final String rawName = (nickname != null && nickname.trim().isNotEmpty) ? nickname.trim() : address;
    // 文件名合法化：去掉路径分隔符及 Windows/Mac 文件名非法字符
    final String safeName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

    // 【假设】导出内容直接使用 qrdata 字符串的 UTF-8 字节作为"二进制文件"内容。
    // 如果 qrdata 实际上是 Base64 编码后的密文，且你希望文件里存的是解码后的真实二进制，
    // 请改为: final bytes = base64Decode(qrdata);
    final Uint8List bytes = Uint8List.fromList(utf8.encode(qrdata));

    String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出钱包备份文件',
      fileName: '$safeName.qccbak',
    );

    if (savePath == null) {
      // 用户取消了保存对话框
      return false;
    }

    try {
      final file = File(savePath);
      await file.writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint("写入导出文件失败: $e");
      if (mounted) Tools.showToast(context, "文件写入失败: $e");
      return false;
    }
  }


  void _showQRCodeDialog(String data, String name,String address, {required Future<void> Function() onShowAndDestroy}) {
    bool isContentVisible = false;
    bool isDestroyed = false; // 内部状态，记录是否已触发删除

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // 强制用户必须点击按钮关闭，防止误触导致没看到二维码就关了
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  // const Icon(Icons.warning_rounded, color: Colors.orange, size: 40),
                  Trans("切记一定截图，截图..." ,style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 18),
                  Text("name:$name"),
                  const SizedBox(height: 10),
                  Text("Wallet:$address"),
                  const SizedBox(height: 10),
                  const Trans("最后一步：备份并销毁", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  _buildSecurityNote(), // 之前的安全提示组件
                  const SizedBox(height: 20),
                  // --- 二维码显示/销毁触发区 ---
                  GestureDetector(
                    onTap: () async {
                      if (!isContentVisible) {
                        // 1. 触发删除回调
                        await onShowAndDestroy();
                        // 2. 更新内部 UI 状态
                        setModalState(() {
                          isContentVisible = true;
                          isDestroyed = true;
                        });
                      }
                    },
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: isContentVisible ? Colors.white : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isContentVisible ? Colors.blue[100]! : Colors.grey[300]!),
                        boxShadow: isContentVisible ? [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 10)] : [],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 二维码
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Opacity(
                              opacity: isContentVisible ? 1.0 : 0.01,
                              child: QrImageView(
                                data: data,
                                version: QrVersions.auto,
                                size: 200,
                                gapless: true,
                                errorStateBuilder: (cxt, err) => const Center(child: Icon(Icons.error_outline, color: Colors.red)),
                              ),
                            ),
                          ),
                          // 遮罩提示层
                          if (!isContentVisible)
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.touch_app, color: Colors.blue, size: 40),
                                const SizedBox(height: 12),
                                const Trans("点击查看二维码", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Trans("并立即销毁本地钱包", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  // 状态显示
                  if (isDestroyed)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_delete, color: Colors.redAccent, size: 14),
                        SizedBox(width: 4),
                        Trans("本地数据已抹除", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: isContentVisible ? Colors.blue : Colors.grey[300],
                      onPressed: isContentVisible ? () => Navigator.pop(context) : null,
                      child: const Trans("确认已截图，关闭"),
                    ),
                  ),
                ],
              ),
            );
          }
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          _buildNoteItem(Icons.lock_outline, "数据已进行高强度加密，二维码本身不包含明文密码。"),
          const SizedBox(height: 8),
          _buildNoteItem(Icons.verified_user_outlined, "导入恢复时，必须输入原支付密码和导出密码。"),
          const SizedBox(height: 8),
          _buildNoteItem(Icons.phonelink_lock, "此备份仅限在Qcc原生钱包App中恢复。"),
          const SizedBox(height: 8),
          _buildNoteItem(Icons.delete_forever, "生成此二维码后，本地钱包信息将立即彻底销毁。"),
        ],
      ),
    );
  }

  Widget _buildNoteItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.amber[800]),
        const SizedBox(width: 8),
        Expanded(
          child: Trans(
            text,
            style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.4),
          ),
        ),
      ],
    );
  }





  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: "搜索 assetId ...",
          hintStyle: TextStyle(color: _Palette.textSecondary, fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: _Palette.textSecondary),
          filled: true,
          fillColor: _Palette.bg,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _Palette.primary, width: 1.2),
          ),
        ),
        onChanged: (val) {
          setState(() {
            _displayAssets = _allAssets.where((a) => a.assetId.toLowerCase().contains(val.toLowerCase())).toList();
          });
        },
      ),
    );
  }

  Widget _buildAssetListView(List<QccAsset> assets) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: assets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final asset = assets[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _Palette.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 第一部分：基本信息与发行量 ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: _Palette.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.token_rounded, color: _Palette.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(asset.assetId, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _Palette.textPrimary)),
                          const SizedBox(height: 6),
                          // 增加：发行总量显示
                          Row(
                            children: [
                              Text("Total Supply  ", style: TextStyle(color: _Palette.textSecondary, fontSize: 11.5)),
                              Text(
                                asset.getHumanAmount(asset.initialSupply),
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: _Palette.warning),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // --- Type / Precision 改为标签芯片，比纯文字更易扫读 ---
                          Row(
                            children: [
                              _infoChip("Type · ${asset.type}"),
                              const SizedBox(width: 6),
                              _infoChip("精度 · ${asset.precision}"),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: asset.isFollowing ? _Palette.warning.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _toggleFollow(asset),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(asset.isFollowing ? Icons.star_rounded : Icons.star_border_rounded,
                              color: asset.isFollowing ? _Palette.warning : _Palette.textSecondary, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Divider(height: 1, thickness: 1, color: _Palette.cardBorder),
                ),

                // --- 第二部分：发行地址 (全显 + 可复制) ---
                // ... 在 _buildAssetListView 的 itemBuilder 内部

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center, // 改为居中对齐，让标签和地址水平视觉更统一
                  children: [
                    Icon(Icons.link_rounded, size: 14, color: _Palette.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Issuer Address",
                              style: TextStyle(fontSize: 10, color: _Palette.textSecondary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          SelectableText(
                            asset.address,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF3A3F4B),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // ✅ 资产公告标签 (替代原 Wordpress 图标)
                    Material(
                      color: _Palette.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        // ✅ 在资产列表的公告标签 onTap 中加入跳转逻辑
                        onTap: () {
                          LogObj.log("跳转资产公告列表: ${asset.assetId} - ${asset.address}");
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QccAssetAnnouncementPage(
                                address: asset.address, // 传入当前资产的发行地址
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.campaign_rounded, size: 14, color: _Palette.primary),
                              const SizedBox(width: 4),
                              Trans(
                                "公告",
                                style: TextStyle(
                                  color: _Palette.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 复制按钮
                    Material(
                      color: _Palette.bg,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: asset.address));
                          Tools.showToast(context, "Address Copied");
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(Icons.copy_rounded, size: 16, color: _Palette.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _Palette.bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: _Palette.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _Palette.bg, shape: BoxShape.circle),
            child: Icon(Icons.inbox_rounded, color: _Palette.textSecondary, size: 28),
          ),
          const SizedBox(height: 14),
          Trans(msg, style: TextStyle(color: _Palette.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  void _toggleFollow(QccAsset asset) async {
    setState(() => asset.isFollowing = !asset.isFollowing);
    await QccAssetService().saveFollowStatus(_allAssets);
    if (mounted) Tools.showToast(context, asset.isFollowing ? "已列入关注" : "已取消关注");
  }



  void _showDynamicLoading(BuildContext context, ValueNotifier<TxStep> notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: ValueListenableBuilder<TxStep>(
            valueListenable: notifier,
            builder: (context, step, _) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                title: const Text("🛡️ 抗量子安全", style: TextStyle(fontSize: 16)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 25),
                    // 使用你定义的 _stepMsgs
                    Text(
                      "请稍候...",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const SizedBox(height: 15),
                    Trans(
                      "安全提示：正在核对支付密码，由于量子安全需要稍等数十秒到数分钟",
                      //textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}