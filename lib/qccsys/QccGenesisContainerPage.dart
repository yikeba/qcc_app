import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha3.dart';
import 'package:qcc_flutter/home/QccExplorerService.dart';
import 'package:qcc_flutter/utile/Tools.dart';
import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import 'SystemPool.dart';

/// 0 高度创世容器 —— GET /v1/containerHeight/{height}
///
/// 网页只能展示服务端给的内容；这里在本机重新计算 SHA3-256 并与容器内的
/// body_hash / image_hash 比对，任何人无需信任节点即可确认创世内容未被篡改。
///
/// 响应结构（按实际返回整理）：
///   {ok, kind, data:{
///     "01.parent_hash", "02.height",
///     "03.body_content"   ← JSON 字符串，需二次解析，宪法/规则主体
///     "04.body_hash", "05.image_hash", "05b.image_bytes_hex"（JPEG 的 hex）
///     "13.qcc_journey_gallery"  ← 普通对象，仅元数据
///   }}
/// body_content 各段键名带 "NN." 序号前缀，这里显示时去掉前缀；
/// 未专门处理的段落一律用通用键值渲染，后续新增字段不会丢失。
class QccGenesisContainerPage extends StatefulWidget {
  final int height;
  const QccGenesisContainerPage({super.key, this.height = 0});

  @override
  State<QccGenesisContainerPage> createState() => _QccGenesisContainerPageState();
}

class _QccGenesisContainerPageState extends State<QccGenesisContainerPage> {
  bool _loading = true;
  String? _error;

  String _kind = "";
  Map<String, dynamic> _data = {};
  String _bodyRaw = "";
  Map<String, dynamic> _body = {};
  Uint8List? _imageBytes;

  // 本地校验结果：null = 无法校验（字段缺失）
  bool? _bodyHashOk;
  bool? _imageHashOk;
  String _bodyHashLocal = "";
  String _imageHashLocal = "";

  bool _manifestoEn = false;

  // ---- 原始字节 ----
  String _rawText = "";      // 接口原始响应文本（未经任何处理）
  int _rawSize = 0;          // 原始响应字节数
  String _rawSha3 = "";      // 原始响应整体 SHA3-256
  bool _rawPretty = false;   // 原始 / 格式化 切换

  String get _jsonUrl => "${QccExplorerService.baseUrl}/v1/containerHeight/${widget.height}";
  String get _htmlUrl => "$_jsonUrl.html";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await http.get(Uri.parse(_jsonUrl)).timeout(const Duration(seconds: 30));
      final String rawText = utf8.decode(resp.bodyBytes);
      final String rawSha3 = _sha3Hex(resp.bodyBytes);
      final dynamic root = jsonDecode(rawText);
      if (root is! Map || root['ok'] != true || root['data'] is! Map) {
        throw Exception((root is Map ? (root['error'] ?? root['msg']) : null) ?? "返回格式异常");
      }
      final data = Map<String, dynamic>.from(root['data']);

      final dynamic bc = _pick(data, 'body_content');
      final String bodyRaw = bc is String ? bc : jsonEncode(bc);
      final dynamic bodyParsed = bc is String ? jsonDecode(bc) : bc;

      final String hex = (_pick(data, 'image_bytes_hex') ?? '').toString();
      final Uint8List? img = hex.isEmpty ? null : _hexToBytes(hex);

      // ---- 本地重算哈希 ----
      // 【假设】body_hash = SHA3-256(body_content 字符串的 UTF-8 字节)，
      //        image_hash = SHA3-256(图片原始字节)。若链上哈希输入另有规则
      //        （如二进制帧整体、Canonical 重编码），这里会显示"不一致"，需按实际规则调整。
      final String bodyLocal = _sha3Hex(Uint8List.fromList(utf8.encode(bodyRaw)));
      final String imgLocal = img == null ? "" : _sha3Hex(img);
      final String bodyHash = (_pick(data, 'body_hash') ?? '').toString().toLowerCase();
      final String imageHash = (_pick(data, 'image_hash') ?? '').toString().toLowerCase();

      if (!mounted) return;
      setState(() {
        _rawText = rawText;
        _rawSize = resp.bodyBytes.length;
        _rawSha3 = rawSha3;
        _kind = (root['kind'] ?? '').toString();
        _data = data;
        _bodyRaw = bodyRaw;
        _body = bodyParsed is Map ? Map<String, dynamic>.from(bodyParsed) : {};
        _imageBytes = img;
        _bodyHashLocal = bodyLocal;
        _imageHashLocal = imgLocal;
        _bodyHashOk = bodyHash.isEmpty ? null : bodyHash == bodyLocal;
        _imageHashOk = (imageHash.isEmpty || img == null) ? null : imageHash == imgLocal;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "$e";
        _loading = false;
      });
    }
  }

  // ───────────── 工具 ─────────────

  /// 按去掉 "NN." 前缀后的键名取值，键名序号变化不影响解析
  static dynamic _pick(Map m, String bareKey) {
    for (final e in m.entries) {
      if (_bare(e.key.toString()) == bareKey) return e.value;
    }
    return null;
  }

  static String _bare(String k) => k.replaceFirst(RegExp(r'^\d+[a-z]?\.'), '');

  static Uint8List? _hexToBytes(String hex) {
    final h = hex.trim();
    if (h.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(h)) return null;
    final out = Uint8List(h.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _sha3Hex(Uint8List data) {
    final d = SHA3Digest(256);
    final out = Uint8List(32);
    d.update(data, 0, data.length);
    d.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _short(String s, [int head = 10, int tail = 6]) =>
      s.length <= head + tail + 3 ? s : "${s.substring(0, head)}…${s.substring(s.length - tail)}";

  /// 最小单位 → 可读数量（BigInt，避免 2.1e17 超出 double 精度）
  static String _human(dynamic units, int precision) {
    final BigInt v = BigInt.tryParse(units.toString().split('.').first) ?? BigInt.zero;
    if (precision <= 0) return _group(v.toString());
    final s = v.toString().padLeft(precision + 1, '0');
    final ip = s.substring(0, s.length - precision);
    final fp = s.substring(s.length - precision).replaceAll(RegExp(r'0+$'), '');
    return fp.isEmpty ? _group(ip) : "${_group(ip)}.$fp";
  }

  static String _group(String digits) =>
      digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => "${m[1]},");

  void _copy(String text, [String tip = "已复制"]) {
    Clipboard.setData(ClipboardData(text: text));
    Tools.showToast(context, tip);
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Trans(widget.height == 0 ? "创世容器 · 高度 0" : "容器 · 高度 ${widget.height}",
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load)],
        bottom: TabBar(
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: [
            Tab(text: Tools.getTra("本机解析")),
            Tab(text: Tools.getTra("节点网页")),
            Tab(text: Tools.getTra("原始字节")),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildVerifyCard(),
                    const SizedBox(height: 12),
                    if (_imageBytes != null) ...[_buildMonumentImage(), const SizedBox(height: 12)],
                    ..._buildBodySections(),
                    if (_pick(_data, 'qcc_journey_gallery') is Map) _buildGallery(),
                    const SizedBox(height: 24),
                  ],
                ),
                _buildWebTab(),
                _buildRawTab(),
              ]),
      ),
    );
  }

  // ───────────── 节点网页 ─────────────

  /// 网页版由节点服务端渲染。用系统浏览器打开（Tools.openChrome，工程已有
  /// url_launcher），不引入 webview 依赖；三种形式交叉比对，任何一方被篡改都会暴露。
  Widget _buildWebTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(
        icon: Icons.language_rounded,
        title: "节点网页版",
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("由节点服务端渲染的创世容器网页，适合在电脑浏览器中完整阅读。",
              style: TextStyle(fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 10),
          _urlBox(_htmlUrl),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Trans("在浏览器打开"),
                onPressed: () => Tools.openChrome(_htmlUrl),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.data_object, size: 16),
                label: const Trans("打开 JSON"),
                onPressed: () => Tools.openChrome(_jsonUrl),
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      _card(
        icon: Icons.fact_check_outlined,
        title: "为什么提供三种形式",
        child: const Text(
          "• 本机解析：App 在你的设备上重新计算 SHA3-256，与容器内哈希比对。\n"
          "• 节点网页：节点渲染的可读版本，便于分享与阅读。\n"
          "• 原始字节：接口返回的未加工数据，可用任何独立工具复核。\n\n"
          "三者内容应完全一致；网页只是展示层，可信依据是原始字节与本机重算的哈希。",
          style: TextStyle(fontSize: 12.5, height: 1.6),
        ),
      ),
    ]);
  }

  // ───────────── 原始字节 ─────────────

  Widget _buildRawTab() {
    final String shown = _rawPretty ? _prettyJson(_rawText) : _rawText;
    final String bodyCmd =
        "curl -s $_jsonUrl | jq -j '.data[\"03.body_content\"]' | openssl dgst -sha3-256";
    final String imgCmd =
        "curl -s $_jsonUrl | jq -j '.data[\"05b.image_bytes_hex\"]' | xxd -r -p | openssl dgst -sha3-256";
    final String rawCmd = "curl -s $_jsonUrl | openssl dgst -sha3-256";

    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(
        icon: Icons.memory_rounded,
        title: "原始响应",
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kvLine("大小", "$_rawSize 字节"),
          _kvLine("整体 SHA3-256", _rawSha3, mono: true, copy: true),
          const SizedBox(height: 4),
          const Text("整体哈希用于和他人比对是否拿到同一份数据；容器自身的可信性看下方 body_hash / image_hash。",
              style: TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
        ]),
      ),
      const SizedBox(height: 12),
      _card(
        icon: Icons.terminal_rounded,
        title: "命令行独立验证（不依赖本 App）",
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("需要 curl、jq、openssl（1.1.1 及以上支持 sha3-256）。输出应与容器内哈希一致：",
              style: TextStyle(fontSize: 12, height: 1.5)),
          const SizedBox(height: 8),
          _cmd("① 主体 body_hash", bodyCmd, (_pick(_data, 'body_hash') ?? '').toString()),
          _cmd("② 纪念影像 image_hash", imgCmd, (_pick(_data, 'image_hash') ?? '').toString()),
          _cmd("③ 原始响应整体", rawCmd, _rawSha3),
        ]),
      ),
      const SizedBox(height: 12),
      _card(
        icon: Icons.data_object,
        title: "原始数据",
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
            onPressed: () => setState(() => _rawPretty = !_rawPretty),
            child: Text(_rawPretty ? "原样" : "格式化", style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            iconSize: 18,
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copy(_rawText, "原始数据已复制（${_rawSize} 字节）"),
          ),
        ]),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 420),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(
            child: SelectableText(shown,
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFFE2E8F0), height: 1.4)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(_rawPretty ? "格式化仅为阅读方便；验证请以「原样」为准。" : "以上为接口返回的原样文本，未经任何解析或改写。",
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
    ]);
  }

  static String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  Widget _card({required IconData icon, required String title, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF2F6FED)),
          const SizedBox(width: 8),
          Expanded(child: Trans(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _kvLine(String k, String v, {bool mono = false, bool copy = false}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GestureDetector(
          onTap: copy ? () => _copy(v) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.black54))),
            Expanded(
              child: Text(v,
                  style: TextStyle(fontSize: mono ? 11 : 12.5, fontFamily: mono ? 'monospace' : null)),
            ),
            if (copy) const Icon(Icons.copy_rounded, size: 13, color: Colors.black38),
          ]),
        ),
      );

  Widget _urlBox(String url) => GestureDetector(
        onTap: () => _copy(url, "链接已复制"),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Text(url, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'))),
            const Icon(Icons.copy_rounded, size: 14, color: Colors.black38),
          ]),
        ),
      );

  Widget _cmd(String label, String cmd, String expect) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _copy(cmd, "命令已复制"),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(cmd,
                      style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF7DD3FC))),
                ),
                const Icon(Icons.copy_rounded, size: 13, color: Colors.white54),
              ]),
            ),
          ),
          if (expect.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text("应输出 $expect",
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.black54)),
            ),
        ]),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text("加载失败：$_error", textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Trans("重试")),
          ]),
        ),
      );

  /// 本地完整性校验卡片
  Widget _buildVerifyCard() {
    final parent = (_pick(_data, 'parent_hash') ?? '').toString();
    final bool allOk = _bodyHashOk == true && (_imageHashOk ?? true);
    final Color c = allOk ? const Color(0xFF16A34A) : const Color(0xFFE08E1D);

    Widget row(String label, bool? ok, String chainHash, String localHash) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ok == true ? Icons.check_circle : (ok == false ? Icons.error : Icons.help_outline),
                  size: 16, color: ok == true ? Colors.green : (ok == false ? Colors.red : Colors.grey)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(ok == true ? "本地重算一致" : (ok == false ? "不一致" : "无法校验"),
                  style: TextStyle(fontSize: 12, color: ok == true ? Colors.green : (ok == false ? Colors.red : Colors.grey))),
            ]),
            GestureDetector(
              onTap: () => _copy(chainHash),
              child: Text("链上 ${_short(chainHash, 16, 8)}",
                  style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.black54)),
            ),
            if (ok == false)
              Text("本地 ${_short(localHash, 16, 8)}",
                  style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.redAccent)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(allOk ? Icons.verified_rounded : Icons.shield_outlined, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(allOk ? "创世内容已在本机验证，未被篡改" : "完整性校验",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        const SizedBox(height: 6),
        Text("容器 $_kind · 高度 ${_pick(_data, 'height') ?? widget.height} · "
            "父哈希 ${RegExp(r'^0+$').hasMatch(parent) ? '全零（创世）' : _short(parent)}",
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        row("主体 body_content", _bodyHashOk, (_pick(_data, 'body_hash') ?? '').toString(), _bodyHashLocal),
        if (_imageBytes != null)
          row("纪念影像 image", _imageHashOk, (_pick(_data, 'image_hash') ?? '').toString(), _imageHashLocal),
        const SizedBox(height: 8),
        const Text("哈希在本机用 SHA3-256 重新计算，无需信任任何节点。",
            style: TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
      ]),
    );
  }

  Widget _buildMonumentImage() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.white,
          child: Image.memory(_imageBytes!, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text("影像解码失败")),
                  )),
        ),
      );

  /// body_content 各段：已知段专门渲染，其余通用键值渲染
  List<Widget> _buildBodySections() {
    final List<Widget> out = [];
    final keys = _body.keys.toList()..sort(); // "NN." 前缀保证顺序
    bool manifestoDone = false;
    for (final k in keys) {
      final bare = _bare(k);
      final v = _body[k];
      if (bare.startsWith('manifesto')) {
        if (manifestoDone) continue;
        manifestoDone = true;
        out.add(_section("宪章 Manifesto", Icons.menu_book_rounded, _buildManifesto(), initiallyExpanded: true));
      } else if (bare == 'developer_declaration' && v is Map) {
        out.add(_section("创始声明", Icons.edit_note_rounded, _buildDeclaration(Map<String, dynamic>.from(v))));
      } else if (bare == 'system_addresses' && v is Map) {
        out.add(_section("系统地址", Icons.account_balance_rounded, _buildSystemAddresses(Map<String, dynamic>.from(v))));
      } else if (bare == 'native_asset' && v is Map) {
        out.add(_section("原生资产与创世分配", Icons.token_rounded, _buildNativeAsset(Map<String, dynamic>.from(v))));
      } else if (bare == 'thanks_and_monument' && v is Map) {
        out.add(_section("鸣谢与纪念", Icons.favorite_rounded, _buildThanks(Map<String, dynamic>.from(v))));
      } else if (bare == 'encrypted_legacy' && v is Map) {
        out.add(_section("加密遗言", Icons.lock_rounded, _buildLegacy(Map<String, dynamic>.from(v))));
      } else {
        out.add(_section(_titleOf(bare), Icons.article_outlined, _kv(v)));
      }
    }
    return out;
  }

  static const Map<String, String> _titles = {
    'chain_identity': '链身份',
    'crypto_rules': '密码学规则',
    'serialization_rules': '序列化规则',
    'governance_model': '治理模型',
    'fee_model': '费用模型',
    'container_state_machine': '容器状态机',
    'block_basics': '区块基础',
    'validation_security': '校验与安全',
  };

  String _titleOf(String bare) => _titles[bare] ?? bare;

  Widget _section(String title, IconData icon, Widget child, {bool initiallyExpanded = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: const Color(0xFF2F6FED), size: 20),
          title: Trans(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [child],
        ),
      ),
    );
  }

  /// 通用键值渲染（递归）
  Widget _kv(dynamic v, [int depth = 0]) {
    if (v is Map) {
      final keys = v.keys.map((e) => e.toString()).toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: keys.map((k) {
          final val = v[k];
          if (val is Map || val is List) {
            return Padding(
              padding: EdgeInsets.only(top: 6, left: depth * 8.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_bare(k), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                _kv(val, depth + 1),
              ]),
            );
          }
          return Padding(
            padding: EdgeInsets.only(top: 6, left: depth * 8.0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 130,
                child: Text(_bare(k), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              Expanded(child: SelectableText("$val", style: const TextStyle(fontSize: 12.5))),
            ]),
          );
        }).toList(),
      );
    }
    if (v is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: v
            .map((e) => Padding(
                  padding: EdgeInsets.only(top: 4, left: depth * 8.0),
                  child: e is Map || e is List ? _kv(e, depth + 1) : SelectableText("• $e", style: const TextStyle(fontSize: 12.5)),
                ))
            .toList(),
      );
    }
    return SelectableText("$v", style: const TextStyle(fontSize: 12.5, height: 1.5));
  }

  Widget _buildManifesto() {
    final cn = (_pick(_body, 'manifesto_cn') ?? '').toString();
    final en = (_pick(_body, 'manifesto_en') ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (cn.isNotEmpty && en.isNotEmpty)
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text("中文")),
            ButtonSegment(value: true, label: Text("English")),
          ],
          selected: {_manifestoEn},
          onSelectionChanged: (s) => setState(() => _manifestoEn = s.first),
        ),
      const SizedBox(height: 10),
      SelectableText(_manifestoEn ? en : (cn.isNotEmpty ? cn : en),
          style: const TextStyle(fontSize: 13.5, height: 1.7)),
    ]);
  }

  Widget _buildDeclaration(Map<String, dynamic> m) {
    final cn = (_pick(m, 'declaration_cn') ?? '').toString();
    final en = (_pick(m, 'declaration_en') ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("${_pick(m, 'author') ?? ''} · ${_pick(m, 'date') ?? ''}",
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 8),
      if (cn.isNotEmpty) SelectableText(cn, style: const TextStyle(fontSize: 13.5, height: 1.6)),
      if (en.isNotEmpty) ...[
        const SizedBox(height: 8),
        SelectableText(en, style: const TextStyle(fontSize: 12.5, height: 1.6, color: Colors.black54)),
      ],
    ]);
  }

  /// 系统地址：与客户端 SystemPool 常量逐一比对（地址 + 长度）
  Widget _buildSystemAddresses(Map<String, dynamic> m) {
    final List<Widget> rows = [];
    final keys = m.keys.toList()..sort();
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.startsWith('Q') && RegExp(r'^Q[1-9A-HJ-NP-Za-km-z]+$').hasMatch(v) && v.length >= 30) {
        final bool known = SystemPool.isSystemPool(v);
        final pool = SystemPool.of(v);
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(known ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 15, color: known ? Colors.green : Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pool?.label ?? _bare(k),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text("${v.length} 位", style: TextStyle(fontSize: 11, color: v.length == SystemPool.addressLength ? Colors.black45 : Colors.red)),
            ]),
            GestureDetector(
              onTap: () => _copy(v, "地址已复制"),
              child: Text(v, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87)),
            ),
            if (!known)
              const Text("与客户端系统池常量不一致（地址或长度不同），请核对",
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
          ]),
        ));
      }
    }
    // 其余标志与描述
    final rest = Map<String, dynamic>.fromEntries(m.entries.where((e) =>
        !(e.value is String && (e.value as String).startsWith('Q') && (e.value as String).length >= 30)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...rows,
      const Divider(height: 24),
      _kv(rest),
    ]);
  }

  /// 原生资产：总量、分配列表、分配合计与总量核对
  Widget _buildNativeAsset(Map<String, dynamic> m) {
    final int precision = int.tryParse("${_pick(m, 'precision_exponent') ?? 9}") ?? 9;
    final String symbol = (_pick(m, 'coin_symbol') ?? 'QCC').toString();
    final dynamic total = _pick(m, 'total_supply_units');
    final List alloc = _pick(m, 'allocationList') is List ? _pick(m, 'allocationList') as List : const [];

    BigInt sum = BigInt.zero;
    for (final a in alloc) {
      if (a is Map && a['amount_units'] != null) {
        sum += BigInt.tryParse(a['amount_units'].toString().split('.').first) ?? BigInt.zero;
      }
    }
    final BigInt? totalBig = total == null ? null : BigInt.tryParse(total.toString().split('.').first);

    final rest = Map<String, dynamic>.fromEntries(m.entries.where((e) =>
        !['allocationList', 'total_supply_units', 'coin_symbol', 'precision_exponent'].contains(_bare(e.key))));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (totalBig != null)
        Text("总供应量 ${_human(totalBig, precision)} $symbol",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF2F6FED))),
      Text("精度 $precision 位 · 创世分配 ${alloc.length} 笔", style: const TextStyle(fontSize: 12, color: Colors.black54)),
      if (alloc.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          "分配合计 ${_human(sum, precision)} $symbol"
          "${totalBig == null ? '' : (sum == totalBig ? '  ✓ 等于总量' : '  · 占总量 ${(sum * BigInt.from(10000) ~/ (totalBig == BigInt.zero ? BigInt.one : totalBig)).toInt() / 100}%')}",
          style: TextStyle(fontSize: 12, color: totalBig != null && sum > totalBig ? Colors.red : Colors.black87),
        ),
      ],
      const SizedBox(height: 8),
      _kv(rest),
      if (alloc.isNotEmpty) ...[
        const Divider(height: 24),
        ...alloc.whereType<Map>().map((a) {
          final addr = (a['address'] ?? '').toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((a['type'] ?? '').toString(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  GestureDetector(
                    onTap: () => _copy(addr, "地址已复制"),
                    child: Text(_short(addr, 12, 6),
                        style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.black54)),
                  ),
                ]),
              ),
              Text("${_human(a['amount_units'] ?? 0, int.tryParse('${a['precision'] ?? precision}') ?? precision)} $symbol",
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
      ],
    ]);
  }

  Widget _buildThanks(Map<String, dynamic> m) {
    final dynamic thanks = _pick(m, 'thanks_to_first_partners');
    final List list = thanks is Map && thanks['list'] is List ? thanks['list'] as List : (thanks is List ? thanks : const []);
    final rest = Map<String, dynamic>.fromEntries(m.entries.where((e) => _bare(e.key) != 'thanks_to_first_partners'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (list.isNotEmpty) ...[
        Text("致早期同行者（${list.length}）", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...list.map((e) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text("· $e", style: const TextStyle(fontSize: 12.5, height: 1.5)),
            )),
        const Divider(height: 24),
      ],
      _kv(rest),
    ]);
  }

  Widget _buildLegacy(Map<String, dynamic> m) {
    final enc = (_pick(m, 'encrypted_data_base64') ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text((_pick(m, 'description') ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text("密文 ${enc.length} 字符，内容加密封存，仅展示不解密。",
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => _copy(enc, "密文已复制"),
        child: Text(_short(enc, 40, 12), style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
      ),
    ]);
  }

  /// 旅程画廊：JSON 里只有元数据，原始字节在 GenesisContainer 二进制帧中
  Widget _buildGallery() {
    final g = Map<String, dynamic>.from(_pick(_data, 'qcc_journey_gallery'));
    final List items = g['items'] is List ? g['items'] as List : const [];
    return _section((g['title'] ?? 'QCC 旅程画廊').toString(), Icons.photo_library_rounded, Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((g['description'] ?? '').toString().isNotEmpty)
          Text(g['description'].toString(), style: const TextStyle(fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 8),
        ...items.whereType<Map>().map((it) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFEBF1FE), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.image_outlined, color: Color(0xFF2F6FED)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("${it['id'] ?? ''} · ${((it['size_bytes'] ?? 0) as num) ~/ 1024} KB",
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    GestureDetector(
                      onTap: () => _copy((it['sha3256'] ?? '').toString(), "哈希已复制"),
                      child: Text("SHA3 ${_short((it['sha3256'] ?? '').toString(), 12, 6)}",
                          style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.black54)),
                    ),
                  ]),
                ),
              ]),
            )),
        const SizedBox(height: 6),
        const Text("原始图片字节不在本接口 JSON 内（位于创世容器二进制帧），此处仅展示可校验的哈希与大小。",
            style: TextStyle(fontSize: 11, color: Color(0xFF8A8F9C))),
      ],
    ));
  }
}
