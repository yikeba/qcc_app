import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/home/QccQueryService.dart';

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

import '../../home/QccTxStatusService.dart';
import '../../views/setting/AppTranslator.dart';
import '../../views/setting/QccPassDialog.dart';
import '../../views/toolviews/QccLoading.dart';
import 'EntityDataFileStorage.dart';
import 'EntityDataRecordsPage.dart';
import 'EntityDataTxConfirmDialog.dart';

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
  /// 即将上链的 payload 的 SHA3-256（小写 hex）。空串表示当前无内容。
  /// 这个值必须由**实际要发送的字节**算出，不能由 String 再编码一次。
  String _payloadSha3 = "";
  String _localHash = "";
  double _gasFee = 0.0; // 本地公式估算值（即时，不依赖网络）
  int _shards = 1;

  List<QccWallet> _localWallets = [];
  Map<String, String> _walletNames = {};

  // ---- 费率总览：/v1/query/gas.quote（不带参数）----
  GasQuote? _gasRule; // 链上规则总览；null 表示尚未取到，按创世默认值说明
  bool _isLoadingGasRate = false;
  bool _gasCardExpanded = false;
  bool _showRawRule = false;
  String? _gasRateError;

  // ---- 按字节报价：/v1/query/gas.quote?byteSize=N ----
  // 服务端报价才是扣费权威；本地公式只用于输入时即时显示。
  // 输入时防抖 + 序号丢弃过期响应，避免每敲一个字都打一次执行层。
  Timer? _quoteDebounce;
  int _quoteSeq = 0;
  double? _serverGas;
  int _serverQuoteBytes = -1; // _serverGas 对应的字节数，与 _currentByteSize 不一致即视为过期
  bool _isQuoting = false;
  String? _quoteError;

  // GasRuleObj 创世默认值，链上查不到时兜底
  static const int _fallbackMaxPayloadSize = 1024 * 256; // 256KB
  static const double _fallbackGFactor = 1.0;

  int? _liveMaxPayloadSize;
  double? _liveGFactor;

  int get _maxPayloadSize => _liveMaxPayloadSize ?? _fallbackMaxPayloadSize;

  bool get _gasIsServer => _serverGas != null && _serverQuoteBytes == _currentByteSize;
  double get _displayGas => _gasIsServer ? _serverGas! : _gasFee;

  /// 服务端报价与本地公式不一致 —— 通常意味着 gas.quote 字段名/单位假设错了，
  /// 或者链上规则已被治理调整而本地公式没跟上。
  bool get _gasMismatch =>
      _gasIsServer && _gasFee >= 0 && (_serverGas! - _gasFee).abs() > 1e-9;

  @override
  void initState() {
    super.initState();
    _currentWallet = widget.initialWallet; // 初始化
    _tabController = TabController(length: 2, vsync: this);
    _textController.addListener(_updateMetricsFromText);
    _loadLocalWallets();
    _loadGasRate();
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
    _textController.removeListener(_updateMetricsFromText);
    _textController.dispose();
    _tagController.dispose();
    _tabController.dispose();
    super.dispose();
  }

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

  /// 费率总览：GET /v1/query/gas.quote（QueryContext → 执行层）。
  /// 取 gFactor / dataMaxSize 供本地即时估算与上限拦截。
  Future<void> _loadGasRate() async {
    if (mounted) {
      setState(() {
        _isLoadingGasRate = true;
        _gasRateError = null;
      });
    }
    try {
      final q = await QccQueryService.gasQuoteOverview();
      if (!mounted) return;
      setState(() {
        _gasRule = q;
        _isLoadingGasRate = false;
        _liveGFactor = (q.gFactor != null && q.gFactor! > 0) ? q.gFactor : null;
        _liveMaxPayloadSize = (q.dataMaxSize != null && q.dataMaxSize! > 0) ? q.dataMaxSize : null;
      });
      // 上限/费率可能在用户已经选好内容之后才查回来，重算一次
      _updateMetrics(_currentByteSize, raw: _currentPayloadBytes());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gasRateError = "查询失败: $e";
        _isLoadingGasRate = false;
      });
    }
  }

  /// 当前标签页实际要发送的字节，用于重算 hash。
  Uint8List? _currentPayloadBytes() {
    if (_tabController.index == 0) {
      return Uint8List.fromList(utf8.encode(_textController.text));
    }
    return _selectedFileBytes;
  }

  void _scheduleServerQuote(int byteSize) {
    _quoteDebounce?.cancel();
    if (byteSize <= 0 || byteSize > _maxPayloadSize) {
      _quoteSeq++; // 作废在途请求
      if (_serverGas != null || _quoteError != null || _isQuoting) {
        setState(() {
          _serverGas = null;
          _serverQuoteBytes = -1;
          _quoteError = null;
          _isQuoting = false;
        });
      }
      return;
    }
    _quoteDebounce = Timer(const Duration(milliseconds: 400), () => _fetchServerQuote(byteSize));
  }

  Future<void> _fetchServerQuote(int byteSize) async {
    final int seq = ++_quoteSeq;
    if (mounted) setState(() { _isQuoting = true; _quoteError = null; });
    try {
      final q = await QccQueryService.gasQuoteBytes(byteSize);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _isQuoting = false;
        if (q.rejected) {
          _serverGas = null;
          _serverQuoteBytes = -1;
          _quoteError = q.reason ?? "链上判定 byteSize 越界";
        } else if (q.gas == null) {
          _serverGas = null;
          _serverQuoteBytes = -1;
          _quoteError = "gas.quote 返回中无 quote.gasQcc";
        } else {
          _serverGas = q.gas;
          _serverQuoteBytes = byteSize;
        }
      });
    } catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _isQuoting = false;
        _serverGas = null;
        _serverQuoteBytes = -1;
        _quoteError = "$e";
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

  /// 实时计算字节、是否超限、本地 Gas 估算，并触发服务端报价（防抖）。
  void _updateMetrics(int byteSize, {Uint8List? raw}) {
    setState(() {
      _currentByteSize = byteSize;
      _shards = byteSize > _maxPayloadSize ? 2 : (byteSize > 0 ? 1 : 0);
      _gasFee = _calculateDataGas(byteSize);
      _payloadSha3 = (raw == null || raw.isEmpty) ? "" : qccSha3Hex(raw);
    });
    _scheduleServerQuote(byteSize);
  }

  /// 本地即时估算 —— 逐行照抄 GasRuleObj.calculateDataGas()。
  /// 仅用于输入时即时显示；扣费以 gas.quote 服务端报价为准。
  double _calculateDataGas(int byteSize) {
    final maxSize = _maxPayloadSize;
    if (byteSize < 0 || byteSize > maxSize) return -1;
    final gFactor = _liveGFactor ?? _fallbackGFactor;
    final kb = (byteSize + 1023) ~/ 1024;
    if (kb <= 10) return kb * 0.001 * gFactor;
    if (kb <= 24) return 0.015 * gFactor;
    final extraKb = kb - 24;
    return (0.015 + extraKb * 0.1) * gFactor;
  }

  void _updateMetricsFromText() {
    // 必须用未经 trim 的原文，与 _handleTextPublish 送出去的字节完全一致
    final bytes = Uint8List.fromList(utf8.encode(_textController.text));
    _updateMetrics(bytes.length, raw: bytes);
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
          // 切换标签后字节/hash/报价要跟着当前标签的内容走
          onTap: (_) {
            final b = _currentPayloadBytes();
            _updateMetrics(b?.length ?? 0, raw: b);
          },
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

  /// QCC 金额的展示格式：最多 6 位小数，去掉末尾的 0。
  /// 0.001 * gFactor 这类 double 运算会产生 0.0010000000000000002，必须格式化后再展示。
  String _fmtQcc(double v) {
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// 说明当前内容落在哪一档、需要付多少费用。没有内容时返回 null。
  String? _currentFeeSentence() {
    final n = _currentByteSize;
    if (n <= 0) return null;
    if (n > _maxPayloadSize) {
      return "当前内容 ${(n / 1024).toStringAsFixed(1)} KB，超过单笔上限 ${_maxPayloadSize ~/ 1024} KB，无法发布。";
    }
    final kb = (n + 1023) ~/ 1024;
    final tier = kb <= 10 ? "小数据档" : (kb <= 24 ? "一口价档" : "按量加价档");
    final src = _gasIsServer ? "链上报价" : "本地估算";
    return "当前内容按 $kb KB 计费，属于$tier，需支付 ${_fmtQcc(_displayGas)} QCC（$src）。";
  }

  /// 存证计费说明卡片。
  ///
  /// 价格由 gFactor 和 dataMaxSize 按 GasRuleObj.calculateDataGas() 的同一公式
  /// 现场算出，不读取 dataTiers 里的描述字符串：一是那些字符串存在 double 拼接
  /// 产生的尾数问题，二是 tier() 的字段名我没看到。
  /// 卡片默认折叠成一行，避免压缩下方的输入区；点击后展开完整说明。
  Widget _buildGasRateCard() {
    final double g = _gasRule?.gFactor ?? _liveGFactor ?? _fallbackGFactor;
    final int maxKb = _maxPayloadSize ~/ 1024;
    final double fullFee = _calculateDataGas(_maxPayloadSize);
    final String? current = _currentFeeSentence();
    final String summary = current ??
        "按数据大小收费：10 KB 内每 KB ${_fmtQcc(0.001 * g)} QCC，"
            "11–24 KB 一口价 ${_fmtQcc(0.015 * g)} QCC，更大按 KB 加价。";

    const TextStyle body = TextStyle(fontSize: 12, color: Colors.black87, height: 1.5);
    const TextStyle note = TextStyle(fontSize: 11, color: Colors.black54, height: 1.4);

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
          InkWell(
            onTap: () => setState(() => _gasCardExpanded = !_gasCardExpanded),
            child: Row(
              children: [
                const Icon(Icons.local_gas_station_outlined, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Trans("存证计费说明", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange))),
                Icon(_gasCardExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.deepOrange),
                const SizedBox(width: 8),
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
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(
              fontSize: 12,
              fontWeight: current != null ? FontWeight.bold : FontWeight.normal,
              color: (current != null && _currentByteSize > _maxPayloadSize) ? Colors.red : Colors.black87,
            ),
          ),
          if (_gasRateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text("$_gasRateError（以下按创世默认规则说明）", style: const TextStyle(fontSize: 11, color: Colors.red)),
            ),
          if (_gasCardExpanded) ...[
            const Divider(height: 14),
            const Text("存证按数据大小收费，不足 1 KB 按 1 KB 计：", style: body),
            Text("• 10 KB 以内：每 KB ${_fmtQcc(0.001 * g)} QCC，10 KB 共 ${_fmtQcc(0.01 * g)} QCC", style: body),
            Text("• 11–24 KB：一口价 ${_fmtQcc(0.015 * g)} QCC，不再按 KB 累加", style: body),
            Text(
              "• 24 KB 以上：${_fmtQcc(0.015 * g)} QCC 起，超出部分每 KB 加 ${_fmtQcc(0.1 * g)} QCC"
                  "${fullFee >= 0 ? "；$maxKb KB 满额为 ${_fmtQcc(fullFee)} QCC" : ""}",
              style: body,
            ),
            const SizedBox(height: 6),
            Text("单笔存证最大 $maxKb KB，超过会被链上拒绝。", style: note),
            Text(
              g == 1.0
                  ? "当前价格系数为 1，即创世标准价。"
                  : "当前治理价格系数为 ×${_fmtQcc(g)}，以上价格已乘以该系数。",
              style: note,
            ),
            if (_gasRule?.ruleGasQcc != null)
              Text("作为对比，一笔普通转账的手续费为 ${_fmtQcc(_gasRule!.ruleGasQcc!)} QCC。", style: note),
            Text(
              _gasRule != null ? "以上规则来自链上实时查询，扣费以链上为准。" : "尚未取到链上规则，以上为创世默认值。",
              style: note,
            ),
            if (_gasRule != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _showRawRule = !_showRawRule),
                child: Text(
                  _showRawRule ? "收起原始返回" : "查看原始返回",
                  style: const TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline),
                ),
              ),
              if (_showRawRule)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_gasRule!.raw),
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black54),
                  ),
                ),
            ],
          ],
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
                _quickActionButton(Icons.photo_library, "相册图片", () => _handlePickMedia(ImageSource.gallery)),
                _quickActionButton(Icons.insert_drive_file, "本地文件", _pickFile),
              ],
            ),
            const SizedBox(height: 15),
            Trans("支持 ${(_maxPayloadSize / 1024).toStringAsFixed(0)}KB 以内的图片、PDF 或文档", style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        )
            : _buildSelectedFilePreview(),
      ),
    );
  }

  Widget _buildSelectedFilePreview() {
    bool isImage = _fileName.toLowerCase().endsWith('.jpg') ||
        _fileName.toLowerCase().endsWith('.jpeg') ||
        _fileName.toLowerCase().endsWith('.png') ||
        _fileName.toLowerCase().endsWith('.gif');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("已就绪载荷", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
            InkWell(
              // 原来只把 _currentByteSize 置 0，Gas/hash/报价不会跟着清掉
              onTap: () {
                setState(() { _selectedFileBytes = null; _fileName = ""; });
                _updateMetrics(0);
              },
              child: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 15),

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
              fit: BoxFit.contain,
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

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("字节大小 (Raw Bytes)", style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("$_currentByteSize bytes  (${(_currentByteSize / 1024).toStringAsFixed(2)} KB)",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text("SHA3-256  ${_payloadSha3.isEmpty ? "—" : _payloadSha3}",
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.check_circle, color: Colors.blue, size: 24),
            ],
          ),
        ),

        const SizedBox(height: 15),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickFile,
                child: Trans("更换文件"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _onFinalSubmit,
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
        imageQuality: 70,
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
        _updateMetrics(bytes.length, raw: bytes);
      }
    } catch (e) {
      LogObj.log("媒体选择错误: $e");
    }
  }

  // --- 底部核心控制面板 ---
  Widget _buildBottomControlPanel() {
    final String gasLabel = _gasIsServer ? "Gas (链上报价)" : "Gas (本地估算)";
    final String gasValue = _displayGas < 0 ? "—" : "${_displayGas.toStringAsFixed(4)} QCC";

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
                _statusItem("大小", "$_currentByteSize B"),
                _statusItem("分片", "$_shards"),
                _statusItem(gasLabel, gasValue, trailing: _isQuoting
                    ? const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                )
                    : null),
              ],
            ),
            if (_gasMismatch)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "⚠️ 链上报价 ${_serverGas!.toStringAsFixed(4)} 与本地公式 ${_gasFee.toStringAsFixed(4)} 不一致，以链上为准",
                  style: const TextStyle(fontSize: 10, color: Colors.orange),
                ),
              )
            else if (_quoteError != null && _currentByteSize > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "链上报价失败，当前显示本地估算：$_quoteError",
                  style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_currentByteSize > 0 && _currentByteSize <= _maxPayloadSize) ? _onFinalSubmit : null,
                child: Trans("签名并广播至全球节点", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusItem(String label, String value, {Widget? trailing}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            if (trailing != null) trailing,
          ],
        ),
      ],
    );
  }

  void _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        PlatformFile file = result.files.single;

        if (file.size > _maxPayloadSize) {
          Tools.showToast(context, "文件大小超过 ${_maxPayloadSize ~/ 1024}KB 限制");
          return;
        }
        setState(() {
          _selectedFileBytes = file.bytes;
          _fileName = file.name;
        });
        _updateMetrics(file.bytes!.length, raw: file.bytes!);

        Tools.showToast(context, "已选择文件: $_fileName");
      }
    } catch (e) {
      LogObj.log("文件选择出错: $e");
    }
  }

  void _onFinalSubmit() {
    if (_tabController.index == 0) {
      _handleTextPublish();
    } else {
      _handleFilePublish();
    }
  }

  void _handleTextPublish() {
    final String raw = _textController.text;
    if (raw.trim().isEmpty) {
      Tools.showToast(context, "请输入文字内容");
      return;
    }
    final Uint8List payload = Uint8List.fromList(utf8.encode(raw));
    _performPublish(payload);
  }

  void _handleFilePublish() {
    if (_selectedFileBytes == null) {
      Tools.showToast(context, "请先选择一个文件(<${_maxPayloadSize ~/ 1024}KB)");
      return;
    }
    _performPublish(_selectedFileBytes!);
  }

  /// 发布前确认：真实字节 + 链上按字节报价的费用。
  Future<bool?> _confirmPayload(Uint8List sendata, GasQuote? quote, String? quoteErr) {
    final String hex = qccSha3Hex(sendata);
    final int n = sendata.length;
    String edge(Iterable<int> b) => b.join(',');
    final String head = edge(sendata.take(16));
    final String tail = edge(sendata.skip(n > 16 ? n - 16 : 0));

    final double local = _calculateDataGas(n);
    final bool hasServer = quote?.gas != null;
    final String feeText = hasServer
        ? "${quote!.gas!.toStringAsFixed(4)} QCC（链上报价）"
        : "${local.toStringAsFixed(4)} QCC（本地估算）";

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认上链内容", style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("字节数  $n", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text("Gas 费用  $feeText", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              if (hasServer && quote!.tier != null)
                Text("计费档位  ${quote.tier}  (${quote.kb ?? '-'} KB)",
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              if (!hasServer && quoteErr != null)
                Text("链上报价失败：$quoteErr", style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
              if (hasServer && local >= 0 && (quote!.gas! - local).abs() > 1e-9)
                Text("本地公式为 ${local.toStringAsFixed(4)} QCC，与链上不一致，扣费以链上为准",
                    style: const TextStyle(fontSize: 10, color: Colors.orange)),
              const SizedBox(height: 8),
              const Text("SHA3-256", style: TextStyle(fontSize: 11, color: Colors.grey)),
              SelectableText(hex, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              const SizedBox(height: 10),
              const Text("首 16 字节", style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(head, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
              const SizedBox(height: 6),
              const Text("末 16 字节", style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text(tail, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
              const SizedBox(height: 10),
              const Text(
                "上链的就是这些字节,不会再做任何裁剪或转换。请与本地文件核对后再继续。",
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: hex));
              Tools.showToast(context, "已复制 SHA3-256");
            },
            child: const Text("复制 hash"),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("取消")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("确认上链")),
        ],
      ),
    );
  }

  void _performPublish(Uint8List sendata) async {
    if (sendata.length > _maxPayloadSize) {
      Tools.showToast(context, "数据大小超过 ${_maxPayloadSize ~/ 1024}KB 上限，无法发布");
      return;
    }

    // ---- 0a. 按真实字节数向执行层取一次权威报价 ----
    // 不复用防抖缓存：提交时的字节数必须与报价字节数严格一致。
    GasQuote? quote;
    String? quoteErr;
    try {
      quote = await QccQueryService.gasQuoteBytes(sendata.length);
    } catch (e) {
      quoteErr = "$e";
    }
    if (!mounted) return;
    if (quote != null && quote.rejected) {
      Tools.showToast(context, "链上拒绝：${quote.reason ?? '超过 dataMaxSize'}");
      return;
    }

    // ---- 0b. 发布前字节 + 费用核对 ----
    final bool? go = await _confirmPayload(sendata, quote, quoteErr);
    if (go != true) return;

    final activeWallet = _currentWallet ?? QccObj.activeWallet;
    if (activeWallet == null) return;
    String? password = await QccPassDialog.show(context);
    if (password == null) return;
    final statusNotifier = ValueNotifier<TxStep>(TxStep.restoring);
    QccLoading.show(context, statusNotifier);

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
      eData.fromdev = "QQxDj4tZrVA77PA3U1wW91kcmMigkcj5HN";
      eData.timestamp = DateTime.now().millisecondsSinceEpoch;
      eData.payload = sendata;

      // ---- C. 签名 + 编码 ----
      statusNotifier.value = TxStep.signing;
      final QccPacket packet = await QccDataProtocol.encodeEntityData(
        data: eData,
        privateKeyHex: wallet.privateKey!,
        publicKeyHex: wallet.pubkey!,
      );

      // ---- D. 提交 ----
      statusNotifier.value = TxStep.submitting;
      Uint8List binaryData = packet.toBytes();

      String url = "${QccExplorerService.baseUrl}/v1/data";
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/octet-stream"},
        body: binaryData,
      );

      if (Navigator.canPop(context)) Navigator.pop(context); // 关闭 Loading
      if (response.statusCode == 200) {
        LogObj.log("发布成功，返回内容:${response.body},返回错误${response.statusCode}");

        Map<String, dynamic>? resData;
        try {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) resData = decoded;
        } catch (_) {
          resData = null;
        }
        // 服务端返回格式：{"status":"accepted","code":"ACCEPTED","txHash":..,"msg":..}
        // status 是小写、code 是大写。原来用 status=="ACCEPTED" 判断永远不成立，
        // 每次都走 else 分支，既不落记录也不弹哈希。现在以 code 为准，兼容 status。
        final String acceptCode = (resData?['code'] ?? resData?['status'] ?? '').toString().toUpperCase();
        final String? txHash = resData?['txHash']?.toString();
        final String serverMsg = (resData?['msg'] ?? '').toString();

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

        if (acceptCode == "ACCEPTED" && txHash != null && txHash.isNotEmpty) {
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
            // 发布时看到的费用：链上报价优先，否则本地估算；gasSource 标明来源
            "gas": quote?.gas ?? _calculateDataGas(sendata.length),
            "gasSource": quote?.gas != null ? "chain" : "local",
            // 受理 ≠ 上链：先记为 pending，轮询出结果后改为 confirmed/failed
            "status": "pending",
            "acceptCode": acceptCode,
            "serverMsg": serverMsg,
            "savedAt": DateTime.now().millisecondsSinceEpoch,
          });

          if (mounted) {
            _showTxConfirmDialog(txHash: txHash, serverMsg: serverMsg, size: sendata.length);
          }
        } else {
          // 200 但未受理：不能提示"成功"
          Tools.showToast(context, "⚠️ 未被受理${serverMsg.isNotEmpty ? "：$serverMsg" : ""}");
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

  /// 受理后的上链确认弹窗：轮询 /v1/hash/{txHash}，出结果后写回本机记录。
  void _showTxConfirmDialog({
    required String txHash,
    required String serverMsg,
    required int size,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // 只能点"关闭"退出，避免误触打断轮询
      builder: (_) => EntityDataTxConfirmDialog(
        txHash: txHash,
        size: size,
        serverMsg: serverMsg,
        onFinal: (st) => EntityDataFileStorage.saveTask(QccTxStatusService.toRecordPatch(txHash, st)),
      ),
    );
  }
}

/// SHA3-256 → 小写 hex。
/// 【假设，需要你确认】用的是 pointycastle 的 SHA3Digest(256)。如果项目里
/// 已有自己的 SHA3 实现，改成调用那一个 —— 全项目只应有一个 SHA3-256 实现。
String qccSha3Hex(Uint8List data) {
  final d = SHA3Digest(256);
  final out = Uint8List(32);
  d.update(data, 0, data.length);
  d.doFinal(out, 0);
  final sb = StringBuffer();
  for (final b in out) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}