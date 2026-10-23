import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qcc_flutter/utile/LogObj.dart';
import 'package:qcc_flutter/home/QccTxStatusService.dart';

import '../../../home/QccExplorerService.dart';
import '../../../utile/QccStorage.dart';
import '../../../utile/Tools.dart';
import '../../../views/setting/AppTranslator.dart';
import '../UserRuleFileStorage.dart';

/// GET /v1/address/{address} —— 地址 end 状态查询（Java TxAddressEndTest.END_QUERY_URL）。
///
/// 【假设】Java 测试只用 body.contains("\"ended\":true") 判定，没有给出完整结构。
/// 这里宽松解析：依次在顶层、data（对象或 JSON 字符串）里找 bool 字段 ended。
/// 返回 null 表示查询失败或结构无法识别，调用方不能把 null 当成"未终止"。
class AddressEndQuery {
  AddressEndQuery._();

  static Future<bool?> isEnded(String address) async {
    try {
      final resp = await http
          .get(Uri.parse("${QccExplorerService.baseUrl}/v1/address/$address"))
          .timeout(const Duration(seconds: 15));
      final dynamic body = jsonDecode(utf8.decode(resp.bodyBytes));
      return _findEnded(body);
    } catch (e) {
      LogObj.log("AddressEnd 状态查询异常: $e");
      return null;
    }
  }

  static bool? _findEnded(dynamic node) {
    if (node is Map) {
      if (node['ended'] is bool) return node['ended'] as bool;
      dynamic d = node['data'];
      if (d is String) {
        try {
          d = jsonDecode(d);
        } catch (_) {
          return null;
        }
      }
      if (d is Map && d['ended'] is bool) return d['ended'] as bool;
    }
    return null;
  }
}

/// AddressEnd 详情页 —— 刻意不用"庆祝"风格。
///
/// 两层确认，和 Tag 详情页同一思路：
///   1. /v1/hash/{txHash}：交易已上链
///   2. /v1/address/{address}：ended == true，地址确已被全网终止
class AddressEndSuccessPage extends StatefulWidget {
  final Map<String, dynamic> ruleData;

  const AddressEndSuccessPage({super.key, required this.ruleData});

  @override
  State<AddressEndSuccessPage> createState() => _AddressEndSuccessPageState();
}

class _AddressEndSuccessPageState extends State<AddressEndSuccessPage> {
  Map<String, String> _walletNames = {};

  late String _chainStatus;
  int? _blockHeight;
  String? _chainMsg;
  bool _checking = false;

  bool? _ended; // /v1/address 复核结果；null = 未查或查询失败
  bool _queryingEnd = false;

  String _txHash = "";
  String _address = "";

  @override
  void initState() {
    super.initState();
    _parse();
    _chainStatus = (widget.ruleData['chainStatus'] ?? 'pending').toString();
    final bh = widget.ruleData['blockHeight'];
    _blockHeight = bh is num ? bh.toInt() : int.tryParse("${bh ?? ''}");
    _chainMsg = widget.ruleData['chainMsg']?.toString();
    _loadWalletNames();

    if (_chainStatus == 'confirmed') {
      _queryEnded();
    } else if (_txHash.isNotEmpty) {
      _check(silent: true);
    }
  }

  void _parse() {
    final ruleData = widget.ruleData;
    _txHash = (ruleData['txHash'] ?? ruleData['id'] ?? "").toString();
    _address = (ruleData['from'] ?? "").toString();
    try {
      Map<String, dynamic>? innerParams;
      if (ruleData['data'] != null) {
        var inner = jsonDecode(ruleData['data']);
        _address = (inner['from'] ?? _address).toString();
        innerParams = inner['ruleJson'] != null ? jsonDecode(inner['ruleJson']) : inner;
      } else if (ruleData['ruleJson'] != null) {
        innerParams = jsonDecode(ruleData['ruleJson']);
      }
      if (innerParams != null) _address = (innerParams['address'] ?? _address).toString();
    } catch (e) {
      LogObj.log("AddressEndSuccessPage 解析失败: $e");
    }
  }

  Future<void> _loadWalletNames() async {
    final names = await QccStorage.getAllWalletNames();
    if (!mounted) return;
    setState(() => _walletNames = names);
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final st = await QccTxStatusService.checkOnce(_txHash);
      if (!mounted) return;
      setState(() {
        _chainStatus = st.state.name;
        if (st.blockHeight != null) _blockHeight = st.blockHeight;
        _chainMsg = st.message;
      });
      if (st.isFinal) {
        // 【假设】saveRuleTask 按 txHash/id 合并已有记录
        await UserRuleFileStorage.saveRuleTask({
          ...widget.ruleData,
          'chainStatus': st.state.name,
          if (st.blockHeight != null) 'blockHeight': st.blockHeight,
          if (st.message != null) 'chainMsg': st.message,
        });
      }
      if (st.state == TxChainState.confirmed) _queryEnded();
      if (!silent && mounted && !st.isFinal) {
        Tools.showToast(context, "尚未上链${st.message != null ? '（${st.message}）' : ''}");
      }
    } catch (e) {
      if (!silent && mounted) Tools.showToast(context, "查询失败：$e", isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _queryEnded() async {
    if (_address.isEmpty || _queryingEnd) return;
    setState(() => _queryingEnd = true);
    final ended = await AddressEndQuery.isEnded(_address);
    if (!mounted) return;
    setState(() {
      _ended = ended;
      _queryingEnd = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool confirmed = _chainStatus == 'confirmed';
    final bool failed = _chainStatus == 'failed';

    IconData headIcon;
    Color headColor;
    String headTitle;
    String headSub;
    if (failed) {
      headIcon = Icons.error_outline;
      headColor = Colors.orange;
      headTitle = "终止交易上链失败";
      headSub = "${_chainMsg ?? '未知原因'}。地址未被终止，仍可正常使用。";
    } else if (!confirmed) {
      headIcon = Icons.hourglass_top_rounded;
      headColor = Colors.orange;
      headTitle = "终止交易已受理，等待上链";
      headSub = "上链后此地址将被全网永久终止";
    } else if (_ended == true) {
      headIcon = Icons.block_rounded;
      headColor = Colors.red;
      headTitle = "此地址已被全网标记为死亡地址";
      headSub = "此地址此后将无法再签发任何交易，操作已不可撤销。";
    } else if (_ended == false) {
      headIcon = Icons.help_outline;
      headColor = Colors.orange;
      headTitle = "交易已上链，但地址未显示为已终止";
      headSub = "索引可能尚未同步，请稍后刷新；若持续如此请核对链上执行结果";
    } else {
      headIcon = Icons.block_rounded;
      headColor = Colors.red;
      headTitle = "终止交易已上链";
      headSub = _queryingEnd ? "正在复核地址终止状态…" : "终止状态复核失败，可稍后刷新";
    }

    final String? nick = _walletNames[_address];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans(confirmed && _ended == true ? "地址状态：已终止" : "地址终止详情"),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: "刷新",
            icon: (_checking || _queryingEnd)
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: Colors.black87),
            onPressed: (_checking || _queryingEnd) ? null : () => confirmed ? _queryEnded() : _check(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(headIcon, color: headColor, size: 70),
            const SizedBox(height: 16),
            Text(headTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: headColor)),
            const SizedBox(height: 8),
            Text(headSub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD9D9)),
              ),
              child: Column(
                children: [
                  _infoRow(context, "规则名称", "AddressEnd"),
                  const Divider(height: 32),
                  if (nick != null && nick.isNotEmpty) ...[
                    _infoRow(context, "钱包备注", nick),
                    const Divider(height: 32),
                  ],
                  _infoRow(context, "终止地址", _address, isAddr: true, canCopy: true),
                  if (widget.ruleData['gas'] is num) ...[
                    const Divider(height: 32),
                    _infoRow(context, "手续费", "${widget.ruleData['gas']} QCC"),
                  ],
                  const Divider(height: 32),
                  _infoRow(context, "链上状态", confirmed ? "已上链" : (failed ? "失败" : "等待上链"),
                      valueColor: confirmed ? Colors.red : Colors.orange),
                  if (confirmed) ...[
                    const Divider(height: 32),
                    _infoRow(context, "终止状态",
                        _ended == true ? "已终止" : (_ended == false ? "未终止" : "未知"),
                        valueColor: _ended == true ? Colors.red : Colors.orange),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildHashSection(context, _txHash),

            if (confirmed && _txHash.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text("链上查询"),
                  onPressed: () => QccTxStatusService.openChainUrl(context, _txHash),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value,
      {bool isAddr = false, bool canCopy = false, Color? valueColor}) {
    String displayValue = value;
    if (isAddr && value.length > 20) {
      displayValue = "${value.substring(0, 10)}...${value.substring(value.length - 10)}";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: canCopy
                ? () {
              Clipboard.setData(ClipboardData(text: value));
              Tools.showToast(context, "已复制到剪贴板");
            }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: valueColor ?? (canCopy ? Colors.redAccent : Colors.black87),
                    ),
                  ),
                ),
                if (canCopy) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 14, color: Colors.redAccent),
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHashSection(BuildContext context, String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Trans("交易哈希", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: hash));
            Tools.showToast(context, "哈希已复制");
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                    child: Text(hash,
                        style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontFamily: 'monospace'))),
                const Icon(Icons.copy, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }
}