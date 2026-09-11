import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
// 【绝对路径，见文件末尾改动说明】this file 本身全是相对导入，但我不知道
// 它在项目里的确切深度到 home/，所以这一行沿用了本 session 多次核实过的
// package: 绝对路径，而不是硬猜相对 ../ 层数——Dart 允许同一个文件里混用
// 相对/绝对 import，不影响编译。
import 'package:qcc_flutter/home/QccExplorerService.dart';
import '../../../procotol/EntityData.dart';
import '../../../procotol/QccPacket.dart';
import '../../../procotol/QccDataProtocol.dart';
import '../../../qccwallet/QccWallet.dart';
import '../../../qccwallet/QccActiveWallet.dart';
import '../../../utile/QccObj.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart'; // 导入插件
import 'package:image_picker/image_picker.dart';

import '../../views/setting/AppTranslator.dart';
import '../../views/setting/QccPassDialog.dart';
import '../../views/toolviews/QccLoading.dart';
import 'EntityDataFileStorage.dart';
import 'EntityDataRecordsPage.dart';

class QccDataBroadcastPage extends StatefulWidget {
  final QccWallet? initialWallet; // 接收传入的钱包
  const QccDataBroadcastPage({super.key, this.initialWallet});
  @override
  State<QccDataBroadcastPage> createState() => _QccDataBroadcastPageState();
}

class _QccDataBroadcastPageState extends State<QccDataBroadcastPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  late QccWallet? _currentWallet; // 当前使用的钱包
  Uint8List? _selectedFileBytes;
  String _fileName = "";

  int _currentByteSize = 0;
  String _localHash = "";
  double _gasFee = 0.0;
  int _shards = 1;

  // ---- 本轮新增：可选择发布地址 + 实时 Gas 费率 ----
  List<QccWallet> _localWallets = [];
  Map<String, String> _walletNames = {};

  Map<String, dynamic>? _gasRateData; // 能解析成 Map 就存这里，供通用展示
  String? _gasRateRaw; // 解析不出结构就存原始文本，方便你核对真实字段名
  bool _isLoadingGasRate = false;
  String? _gasRateError;

  // 🐛 FIX：拿到 GasRuleObj.java 源码后核实——单包上限是 256KB
  // (`public long dataMaxSize = 1024 * 256;`)，不是之前按 "EntityData.java
  // 里 MAX_PAYLOAD_SIZE" 猜测/核对出来的 1MB。这是本次唯一确认要改的数字，
  // 已经把下面所有用到"1MB上限"的地方(拦截判断+提示文案)都换掉了。
  //
  // 【顺带做的加强】dataMaxSize 这个字段挂在 GasRuleObj 上，本身是
  // governable=true 的规则对象——理论上未来可能被治理调整，不一定永远是
  // 256KB。所以这里没有简单写死 256*1024 就完事，而是优先用
  // _loadGasRate() 实时查到的 dataMaxSize(如果 /v1/gasRate 返回里有这个
  // 字段)，查不到或者还没查回来时，才退回到下面这个"已知创世值"当兜底。
  // 这样以后规则真的被治理调整了，App 不用等下一次版本发布就能跟上。
  static const int _fallbackMaxPayloadSize = 1024 * 256; // 256KB，GasRuleObj 创世默认值
  static const double _fallbackGFactor = 1.0; // GasRuleObj.gFactor 创世默认值

  int? _liveMaxPayloadSize; // 从 /v1/gasRate 实时查到的 dataMaxSize，查不到时为 null
  double? _liveGFactor; // 从 /v1/gasRate 实时查到的 gFactor，查不到时为 null

  int get _maxPayloadSize => _liveMaxPayloadSize ?? _fallbackMaxPayloadSize;

  @override
  void initState() {
    super.initState();
    _currentWallet = widget.initialWallet; // 初始化
    _tabController = TabController(length: 2, vsync: this);
    _textController.addListener(_updateMetricsFromText);
    _loadLocalWallets();
    _loadGasRate();
  }

  /// 加载本机全部单签钱包，供"发布方地址"下拉选择；如果外部没有传入
  /// initialWallet，就回退到当前激活钱包/本机第一个钱包。
  Future<void> _loadLocalWallets() async {
    final names = await QccStorage.getAllWalletNames();
    final wallets = QccObj.readWallets();
    if (!mounted) return;
    setState(() {
      _walletNames = names;
      _localWallets = wallets;
      if (_currentWallet == null && wallets.isNotEmpty) {
        final active = QccObj.activeWallet;
        _currentWallet = (active != null && wallets.any((w) => w.address == active.address))
            ? active
            : wallets.first;
      }
    });
  }

  /// 实时查询 QCC 公链 Gas 费率——对应 GasRateContext.java 的
  /// GET /v1/gasRate（不带任何参数，全局唯一一份费率快照）。
  ///
  /// 【假设，需要你确认】GasRateContext.java 源码本身没有展示
  /// @WebServlet 的 URL 映射，这里按同一批查询接口(PledgeContext ->
  /// /v1/pledge/{address})的命名习惯猜的路径，如果实际不是 /v1/gasRate，
  /// 告诉我改一下就行。
  ///
  /// 【本轮更新】上一版这里"不敢猜字段名去乘算总费用"，现在拿到了
  /// GasRuleObj.java 源码——它没有用 @JSONField 改名，fastjson2 默认
  /// 序列化会直接用 Java 字段名当 JSON key，所以这里认为 data 字段解析出来
  /// 的 Map 里应该能直接按 "gFactor"、"dataMaxSize" 这两个字面量键名取值。
  /// 如果实际返回的 JSON 结构不是"GasRuleObj 整个对象"（比如只返回了算好
  /// 的费率数字，或者字段被包了一层），下面这段解析会静默拿不到值、自动
  /// 退回创世默认值，不会报错，但费用/上限就会跟真实规则脱节，建议你拿到
  /// 真实返回后告诉我核对一下。
  Future<void> _loadGasRate() async {
    if (mounted) {
      setState(() {
        _isLoadingGasRate = true;
        _gasRateError = null;
      });
    }
    try {
      final resp = await http.get(Uri.parse("${QccExplorerService.baseUrl}/v1/gasRate"));
      final outer = jsonDecode(resp.body);
      Map<String, dynamic>? parsedMap;
      String? rawText;

      if (outer is Map && outer['ok'] == true) {
        final data = outer['data'];
        if (data is String) {
          try {
            final inner = jsonDecode(data);
            if (inner is Map) {
              parsedMap = Map<String, dynamic>.from(inner);
              rawText = const JsonEncoder.withIndent('  ').convert(inner);
            } else {
              rawText = data;
            }
          } catch (_) {
            rawText = data;
          }
        } else if (data is Map) {
          parsedMap = Map<String, dynamic>.from(data);
          rawText = const JsonEncoder.withIndent('  ').convert(data);
        } else {
          rawText = data?.toString();
        }
      } else {
        if (!mounted) return;
        setState(() {
          _gasRateError = "查询失败: ${resp.body}";
          _isLoadingGasRate = false;
        });
        return;
      }

      // 🐛 FIX：从查到的 Map 里提取 gFactor / dataMaxSize，供
      // _calculateDataGas() / _maxPayloadSize 使用；取不到就保持 null，
      // 用类里定义的创世默认值兜底，不影响页面正常使用。
      double? liveG;
      int? liveMax;
      if (parsedMap != null) {
        final gf = parsedMap['gFactor'];
        if (gf is num && gf > 0) liveG = gf.toDouble();
        final dm = parsedMap['dataMaxSize'];
        if (dm is num && dm > 0) liveMax = dm.toInt();
      }

      if (!mounted) return;
      setState(() {
        _gasRateData = parsedMap;
        _gasRateRaw = rawText;
        _isLoadingGasRate = false;
        _liveGFactor = liveG;
        _liveMaxPayloadSize = liveMax;
      });
      // 上限/费率可能在用户已经选好文件之后才查回来，重新算一次避免显示滞后。
      _updateMetrics(_currentByteSize);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gasRateError = "查询异常: $e";
        _isLoadingGasRate = false;
      });
    }
  }

  void _pickPublisherAddress() {
    if (_localWallets.length <= 1) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Trans("选择发布方地址", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _localWallets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = _localWallets[i];
                    final bool isSelected = _currentWallet?.address == w.address;
                    final String? nick = _walletNames[w.address];
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? Colors.blue : Colors.grey),
                      title: Text(nick ?? "未命名钱包", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      trailing: QccActiveWallet(w.address, "QCC", fontSize: 12, fontColor: Colors.black87),
                      onTap: () {
                        setState(() => _currentWallet = w);
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 核心逻辑：实时计算字节、是否超限和 Gas。
  // 🐛 FIX：上限改用 _maxPayloadSize（256KB 创世值，或 /v1/gasRate 查到的
  // 实时 dataMaxSize），不再用 EntityData.maxPayloadSize（之前核对成
  // 1MB，跟 GasRuleObj.java 里的 256KB 对不上——这次以 GasRuleObj 为准，
  // 如果 EntityData.dart 里那个常量也确实写的是 1MB，麻烦你那边也一并
  // 改一下源头，不然别处如果还引用了那个常量，还是会用错值）。
  //
  // "_shards"这个字段名是历史遗留——EntityData.java 里完全没有任何
  // 分片/多包上链的逻辑，SendDataTest.java 也是整包一次性 POST，所以这里
  // 只保留"是否超过单包上限"的语义(超限时 _shards>1，仅用于禁用提交按钮
  // 和提示，不代表真的会分片发送)。
  void _updateMetrics(int byteSize) {
    setState(() {
      _currentByteSize = byteSize;
      _shards = byteSize > _maxPayloadSize ? 2 : (byteSize > 0 ? 1 : 0);
      _gasFee = _calculateDataGas(byteSize);
    });
  }

  /// 🐛 FIX：原来是"1KB=0.001 QCC"的占位线性公式，未核实过真实计费规则。
  /// 现在拿到 GasRuleObj.java 源码了，这里逐行照抄它的 calculateDataGas()：
  ///   - 超过上限(或负数)直接判无效，返回 -1
  ///   - 按 1KB 向上取整计费
  ///   - <=10KB：每 KB 0.001 QCC
  ///   - <=24KB：固定 0.015 QCC（"普惠商业区"，不再逐 KB 累加）
  ///   - >24KB：0.015 + 超出部分每 KB 0.1 QCC（资源收费区，涨得很快——
  ///     256KB 满额大概是 23 QCC 左右，量级远高于普通转账的 0.001 QCC，
  ///     这也是下面你问的"存证费用很高"这句话的真实数字依据）
  /// 全部再乘以 gFactor（治理棘轮系数，优先用实时查到的值，查不到用创世
  /// 默认值 1.0 兜底）。
  double _calculateDataGas(int byteSize) {
    final maxSize = _maxPayloadSize;
    if (byteSize < 0 || byteSize > maxSize) return -1;
    final gFactor = _liveGFactor ?? _fallbackGFactor;
    final kb = (byteSize + 1023) ~/ 1024; // 向上取整到 KB，对应 Java (byteSize+1023L)/1024L
    if (kb <= 10) return kb * 0.001 * gFactor;
    if (kb <= 24) return 0.015 * gFactor;
    final extraKb = kb - 24;
    return (0.015 + extraKb * 0.1) * gFactor;
  }

  void _updateMetricsFromText() {
    final bytes = utf8.encode(_textController.text);
    _updateMetrics(bytes.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Trans("后量子存证发布", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          // 【本次新增入口】"明细中心"——查看本机全部存证发布记录，
          // 对应你这次的要求"增加一个明细中心来显示发布信息明细"。
          IconButton(
            tooltip: Tools.getTra("发布明细"),
            icon: const Icon(Icons.receipt_long, color: Colors.black87),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EntityDataRecordsPage()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue.shade800,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue.shade800,
          tabs: [
            Tab(text: Tools.getTra("文本存证")),
            Tab(text: Tools.getTra("文件存证")),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildPublisherCard(),
          _buildGasRateCard(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTextMode(),
                _buildFileMode(),
              ],
            ),
          ),
          _buildBottomControlPanel(),
        ],
      ),
    );
  }

  /// 发布方地址卡片——本轮改造：从"只读展示"改成"可点击切换"，本机有
  /// 多个钱包时点一下弹出选择列表(_pickPublisherAddress())，同时把该
  /// 地址的 QCC 余额直接摆出来，方便发布前一眼看出够不够付这笔(偏贵的)
  /// 存证 Gas。
  Widget _buildPublisherCard() {
    final String? nick = _currentWallet == null ? null : _walletNames[_currentWallet!.address];
    final bool canSwitch = _localWallets.length > 1;
    return InkWell(
      onTap: canSwitch ? _pickPublisherAddress : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet, size: 20, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Trans("发布方地址 (Publisher)", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (canSwitch) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.swap_horiz, size: 13, color: Colors.blueGrey),
                      ],
                    ],
                  ),
                  Text(
                    _currentWallet?.address ?? "未选择钱包",
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Monospace'),
                  ),
                  if (nick != null)
                    Text(nick, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (_currentWallet != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("QCC 余额", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  QccActiveWallet(_currentWallet!.address, "QCC", fontSize: 13, fontColor: Colors.black87),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 实时 Gas 费率卡片——对应新增的 GasRateContext.java 查询接口。
  /// 展示服务端返回的原始费率结构(能解析出 Map 就逐个 key 展示，解析不出来
  /// 就展示原始文本)，同时下面的"预估 Gas"已经改用 GasRuleObj 真实公式。
  Widget _buildGasRateCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_gas_station_outlined, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Trans("实时 Gas 费率", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange))),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: _isLoadingGasRate
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, color: Colors.deepOrange),
                onPressed: _isLoadingGasRate ? null : _loadGasRate,
              ),
            ],
          ),
          if (_gasRateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_gasRateError!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            )
          else if (_gasRateData != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: _gasRateData!.entries
                    .map((e) => Text("${e.key}: ${e.value}", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87)))
                    .toList(),
              ),
            )
          else if (_gasRateRaw != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_gasRateRaw!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54)),
              ),
        ],
      ),
    );
  }

  // --- 文本模式 UI ---
  Widget _buildTextMode() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: Tools.getTra("在此输入要永久记录的数据内容..."),
                border: InputBorder.none,
              ),
            ),
          ),
          const Divider(),
          _buildTagInput(),
        ],
      ),
    );
  }

  // --- 文件模式 UI ---
  Widget _buildFileMode() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade100, width: 2),
        ),
        child: _selectedFileBytes == null
            ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drive_folder_upload, size: 48, color: Colors.blue.shade200),
            const SizedBox(height: 16),
            const Text("请选择上链素材", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 【已定稿】图片上传保留（不移除相册入口）。256KB 限制前端先拦
                // （见 _maxPayloadSize / _calculateDataGas，超限直接禁用发布按钮），
                // 公链端 GasRuleObj.calculateDataGas() 对超过 dataMaxSize 的字节数
                // 本身也会返回 -1 兜底，前后端双重限制，不是只有前端一道拦截。
                _quickActionButton(Icons.photo_library, "相册图片", () => _handlePickMedia(ImageSource.gallery)),
                _quickActionButton(Icons.insert_drive_file, "本地文件", _pickFile),
              ],
            ),
            const SizedBox(height: 15),
            // 🐛 FIX：原来写死"1MB"，现在跟着 _maxPayloadSize 动态显示
            // (256KB 创世值，或治理调整后查到的实时值)。
            Trans("支持 ${(_maxPayloadSize / 1024).toStringAsFixed(0)}KB 以内的图片、PDF 或文档", style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        )
            : _buildSelectedFilePreview(), // 选中后的预览状态
      ),
    );
  }

  Widget _buildSelectedFilePreview() {
    // 判断是否为图片（根据文件名后缀或字节头，这里简单用后缀判断）
    bool isImage = _fileName.toLowerCase().endsWith('.jpg') ||
        _fileName.toLowerCase().endsWith('.jpeg') ||
        _fileName.toLowerCase().endsWith('.png') ||
        _fileName.toLowerCase().endsWith('.gif');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 顶部文件状态头
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("已就绪载荷", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
            InkWell(
              onTap: () => setState(() { _selectedFileBytes = null; _fileName = ""; _currentByteSize = 0; }),
              child: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 15),

        // 2. 预览区域
        Container(
          width: double.infinity,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: isImage
              ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _selectedFileBytes!,
              fit: BoxFit.contain, // 保持比例预览图片
            ),
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file, size: 48, color: Colors.blue.shade200),
              const SizedBox(height: 10),
              Text(_fileName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            ],
          ),
        ),

        const SizedBox(height: 15),

        // 3. 文件元数据
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("字节大小 (Raw Bytes)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text("${(_currentByteSize / 1024).toStringAsFixed(2)} KB", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const Icon(Icons.check_circle, color: Colors.blue, size: 24),
            ],
          ),
        ),

        const SizedBox(height: 15),

        // 4. 操作按钮：允许更换或者直接执行上链流程中的"喂养"
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickFile, // 重新选择文件
                child: Trans("更换文件"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _onFinalSubmit, // 直接触发之前的解耦发送流程
                child: Trans("立即上链"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(radius: 25, backgroundColor: Colors.blue.shade50, child: Icon(icon, color: Colors.blue)),
          const SizedBox(height: 8),
          Trans(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
  Widget _buildTagInput() {
    return Row(
      children: [
        const Icon(Icons.label_important_outline, size: 18, color: Colors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _tagController,
            decoration: InputDecoration(
              hintText: Tools.getTra("数据标签 (如: identity_verify)"),
              border: InputBorder.none,
              hintStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _handlePickMedia(ImageSource source) async {
    try {
      final XFile? media = await _picker.pickImage(
        source: source,
        imageQuality: 70, // 自动轻微压缩，更容易控制在上限内
      );

      if (media != null) {
        final Uint8List bytes = await media.readAsBytes();
        if (bytes.length > _maxPayloadSize) {
          Tools.showToast(context, "文件太大 (${(bytes.length / 1024).toStringAsFixed(1)}KB)，请重新选择");
          return;
        }
        setState(() {
          _selectedFileBytes = bytes;
          _fileName = media.name;
        });
        _updateMetrics(bytes.length);
      }
    } catch (e) {
      LogObj.log("媒体选择错误: $e");
    }
  }

  // --- 底部核心控制面板 ---
  Widget _buildBottomControlPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statusItem("大小", "${(_currentByteSize / 1024).toStringAsFixed(2)} KB"),
                _statusItem("分片", "$_shards"),
                // 🐛 FIX：不再是占位公式——已接入 GasRuleObj.calculateDataGas()
                // 的真实计费公式（乘以实时/兜底 gFactor）。_gasFee 为 -1 时
                // (理论上不该出现，因为按钮已经在超限时被禁用)显示"—"。
                _statusItem("预估 Gas", _gasFee < 0 ? "—" : "${_gasFee.toStringAsFixed(4)} QCC"),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                // 【修复，本轮沿用】原来只判断 _currentByteSize>0，超过上限
                // 也能点提交，一路弹密码框/loading后才在 toBytes() 里抛异常
                // ——现在提前在按钮上就拦住，且上限已改成 _maxPayloadSize。
                onPressed: (_currentByteSize > 0 && _currentByteSize <= _maxPayloadSize) ? _onFinalSubmit : null,
                child: Trans("签名并广播至全球节点", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
      ],
    );
  }

  void _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // 关键：直接读取字节到内存，适合小文件
      );

      if (result != null && result.files.single.bytes != null) {
        PlatformFile file = result.files.single;

        // 🐛 FIX：检查大小限制改用 _maxPayloadSize（256KB，对应
        // GasRuleObj.java 的 dataMaxSize，之前错核对成了 EntityData 的 1MB）。
        if (file.size > _maxPayloadSize) {
          Tools.showToast(context, "文件大小超过 ${_maxPayloadSize ~/ 1024}KB 限制");
          return;
        }
        setState(() {
          _selectedFileBytes = file.bytes; // 拿到 Uint8List
          _fileName = file.name;
          _updateMetrics(file.size); // 更新显示的字节数和 Gas
        });

        Tools.showToast(context, "已选择文件: $_fileName");
      }
    } catch (e) {
      LogObj.log("文件选择出错: $e");
    }
  }

  // 逻辑切换入口
  void _onFinalSubmit() {
    if (_tabController.index == 0) {
      _handleTextPublish();
    } else {
      _handleFilePublish();
    }
  }

// 文本处理逻辑
  void _handleTextPublish() {
    String text = _textController.text.trim();
    if (text.isEmpty) {
      Tools.showToast(context, "请输入文字内容");
      return;
    }
    Uint8List payload = Uint8List.fromList(utf8.encode(text));
    _performPublish(payload);
  }

// 文件处理逻辑
  void _handleFilePublish() {
    if (_selectedFileBytes == null) {
      Tools.showToast(context, "请先选择一个文件(<${_maxPayloadSize ~/ 1024}KB)");
      return;
    }
    _performPublish(_selectedFileBytes!);
  }

  void _performPublish(Uint8List sendata) async {
    // 【提前拦截，回应"十万次"批量场景】超过协议上限就不要再弹密码框/走
    // 完整流程了，否则会一路走到 toBytes() 里才抛异常，浪费一次密码交互。
    // 🐛 FIX：上限改用 _maxPayloadSize。
    if (sendata.length > _maxPayloadSize) {
      Tools.showToast(context, "数据大小超过 ${_maxPayloadSize ~/ 1024}KB 上限，无法发布");
      return;
    }

    // 1. 获取输入内容并校验
    final activeWallet = _currentWallet ?? QccObj.activeWallet;
    if (activeWallet == null) return;
    // 2. 验证支付密码
    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    // 3. 启动通用 Loading
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

    // 【修复，之前这段 try/catch 整体被注释掉】任何一步(钱包恢复失败/
    // 密码错误/签名异常/网络异常)抛出，loading 都必须被关掉一次，否则会
    // 永久卡死——这是本 session 里 QccTxFlow.run() 专门解决过的同一类问题，
    // 这个页面走的是二进制 octet-stream 提交(不是 QccTxFlow.run() 假设的
    // JSON POST)，没法直接复用它，所以在这里单独补上同样的 try/catch。
    try {
      // ---- A. 还原钱包 ----
      QccWallet? wallet = await QccStorage.restoreWallet(context, activeWallet.address, password);
      if (wallet == null || wallet.address != activeWallet.address) {
        throw Exception("钱包恢复错误，请检查密码");
      }

      // ---- B. 构造 EntityData ----
      statusNotifier.value = TxStep.building;
      EntityData eData = EntityData();
      eData.from = wallet.address;
      eData.assetId = "QCCData";
      // 【待你确认，见我这次回复正文】开发者推广地址 fromdev——
      // EntityData.java 里这个字段会参与 id 与签名计算，SendDataTest.java
      // 里取的是 demoUtil.fromdev，但目前这个 Flutter App 里没有告诉我
      // 它应该来自哪里(固定值/构建配置/当前钱包的推广关系...)，暂时留空
      // (null)，这是协议允许的合法取值(getPayloadForHash() 里 null 按
      // 空字符串处理)，不影响签名/验签的正确性，只是发布时不会带上任何
      // 推广归属信息。
      eData.fromdev = null;
      eData.timestamp = DateTime.now().millisecondsSinceEpoch;
      eData.payload = sendata;

      // ---- C. 签名 + 编码（协议层统一处理，含子isolate耗时计算）----
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await QccDataProtocol.encodeEntityData(
        data: eData,
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // ---- D. 构建整个 Packet 的二进制流并提交 ----
      statusNotifier.value = TxStep.submitting;
      Uint8List binaryData = packet.toBytes();

      String url = "https://tx.qccio.com/v1/data";
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/octet-stream"},
        body: binaryData,
      );

      if (Navigator.canPop(context)) Navigator.pop(context); // 关闭 Loading
      if (response.statusCode == 200) {
        LogObj.log("发布成功，返回内容:${response.body},返回错误${response.statusCode}");

        // 【本次新增】服务端 200 不等于业务成功——真正的业务结果在
        // response.body 里的 status 字段("ACCEPTED"才是真成功，参考你
        // 贴的真实返回)，这里先解析出来，txHash 也从这里取，而不是
        // 自己在本地算一个(id 计算规则以服务端回显为准更保险)。
        Map<String, dynamic>? resData;
        try {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) resData = decoded;
        } catch (_) {
          resData = null;
        }
        final String status = (resData?['status'] ?? '').toString();
        final String? txHash = resData?['txHash']?.toString();
        final String serverMsg = (resData?['msg'] ?? '').toString();

        // 【在清空输入框之前】先把这次发布的摘要信息取出来，
        // 否则 preview/fileName 在 setState 清空后就取不到了。
        final bool isFileMode = _tabController.index != 0;
        String preview;
        if (isFileMode) {
          preview = _fileName;
        } else {
          try {
            final String t = utf8.decode(sendata);
            preview = t.length > 80 ? "${t.substring(0, 80)}..." : t;
          } catch (_) {
            preview = "(二进制内容)";
          }
        }

        if (status == "ACCEPTED" && txHash != null && txHash.isNotEmpty) {
          // ---- 本机落一条发布记录 ----
          await EntityDataFileStorage.saveTask({
            "txHash": txHash,
            "from": eData.from,
            "assetId": eData.assetId,
            "fromdev": eData.fromdev,
            "timestamp": eData.timestamp,
            "mode": isFileMode ? "file" : "text",
            "fileName": isFileMode ? _fileName : "",
            "preview": preview,
            "payloadSize": sendata.length,
            "status": status,
            "serverMsg": serverMsg,
            "savedAt": DateTime.now().millisecondsSinceEpoch,
          });

          if (mounted) {
            _showPublishSuccessDialog(txHash: txHash, serverMsg: serverMsg, size: sendata.length);
          }
        } else {
          // 状态码 200 但业务状态不是 ACCEPTED（理论上不该出现，兜底处理，
          // 不弹哈希弹窗，避免把一个还没确认成功的哈希当成"已发布"记下来）。
          Tools.showToast(context, serverMsg.isNotEmpty ? "⚠️ $serverMsg" : "✅ 可信数据发布成功");
        }

        _textController.clear();
        setState(() {
          _selectedFileBytes = null;
          _fileName = "";
        });
        _updateMetrics(0);
      } else {
        LogObj.log("发布失败，返回内容:${response.body},返回错误${response.statusCode}");
        Tools.showToast(context, "❌ 发布失败: ${response.statusCode}");
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      LogObj.log("上链异常: $e");
      Tools.showToast(context, "执行出错: $e");
    }
  }

  /// 发布成功弹窗——显著展示 txHash + 一键复制，
  /// 对应你的原话:"需要增加一个发布成功弹出显示hash"。
  void _showPublishSuccessDialog({
    required String txHash,
    required String serverMsg,
    required int size,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text("存证数据发布成功"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("交易哈希 (txHash)：", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  txHash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Text("数据大小：${(size / 1024).toStringAsFixed(2)} KB"),
              if (serverMsg.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text("服务端消息：$serverMsg"),
              ],
              const SizedBox(height: 4),
              const Text(
                "该记录已保存到本机发布记录中。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: txHash));
                Tools.showToast(context, "已复制 txHash");
              },
              child: const Text("复制哈希"),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("确定"),
            ),
          ],
        );
      },
    );
  }
}