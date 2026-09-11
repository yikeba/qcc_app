import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utile/Tools.dart';
import '../../utile/QccObj.dart';
import '../../views/setting/AppTranslator.dart';
import '../user/multiple/multicreat/QccMultiSigService.dart';


class AssetMultiSigProposalPage extends StatefulWidget {
  final String txHash;

  const AssetMultiSigProposalPage({super.key, required this.txHash});

  @override
  State<AssetMultiSigProposalPage> createState() => _AssetMultiSigProposalPageState();
}

class _AssetMultiSigProposalPageState extends State<AssetMultiSigProposalPage> {
  bool _isLoading = true;
  _AssetDetail? _assetDetail; // ✅ 使用页面私有的资产模型
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  // ✅ 核心：通过 Service 拿到原始 Map，在页面内进行资产特有的二次解析
  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    try {
      // 1. 调用通用接口获取原始包
      final wrapper = await QccMultiSigService.fetchTask(widget.txHash);
      if (wrapper == null) throw "无法从节点获取提案信息";
      // 2. 调用私有解析器，不影响其他多签业务
      final detail = _parseAssetSpecific(wrapper);
      if (mounted) {
        setState(() {
          _assetDetail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ✅ 私有解析器：专门处理 AsseIdRule (资产发行规则)
  _AssetDetail _parseAssetSpecific(MultiSigTaskWrapper wrapper) {
    final bool isConfirmed = wrapper.isConfirmed;
    final Map<String, dynamic> rawData = wrapper.data;

    // A. 提取 Rule 数据块 (内存池和链上路径不同)
    Map<String, dynamic> ruleBlock = isConfirmed
        ? rawData  // 链上：data 就是规则本身
        : (rawData['ruleData'] ?? rawData); // 内存：嵌套在 ruleData 字段下

    // B. 解析 ruleJson (资产的核心参数在这里)
    String ruleJsonStr = ruleBlock['ruleJson'] ?? "{}";
    Map<String, dynamic> assetMeta = {};
    try {
      assetMeta = jsonDecode(ruleJsonStr);
    } catch (_) {}

    return _AssetDetail(
      assetId: assetMeta['assetId'] ?? "Unknown",
      owner: assetMeta['owner'] ?? "---",
      precision: assetMeta['precision'] ?? 0,
      initialSupply: assetMeta['initialSupply'],
      threshold: isConfirmed ? 0 : (rawData['threshold'] ?? 0),
      currentCount: isConfirmed ? 0 : (rawData['currentCount'] ?? 0),
      isConfirmed: isConfirmed,
      signedOwners: wrapper.signedOwners,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Trans("多签资产提案详情"),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTask),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_assetDetail == null) return Center(child: Trans(_error ?? "数据解析失败"));

    final detail = _assetDetail!;
    double displaySupply = (detail.initialSupply is String ? num.parse(detail.initialSupply) : (detail.initialSupply ?? 0)) / pow(10, detail.precision);
    bool hasSigned = detail.signedOwners.contains(QccObj.activeWallet?.address);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 状态图标
          Icon(
            detail.isConfirmed ? Icons.verified_user : Icons.hourglass_empty,
            color: detail.isConfirmed ? Colors.green : Colors.orange,
            size: 64,
          ),
          const SizedBox(height: 12),
          Trans(detail.isConfirmed ? "规则已生效 (On-chain)" : "多签提案签署中 (Mempool)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: detail.isConfirmed ? Colors.green : Colors.orange)),

          const SizedBox(height: 32),

          // 资产信息卡片
          _buildInfoCard(detail.assetId, displaySupply, detail.precision, detail.owner),

          const SizedBox(height: 20),

          // 进度条 (仅未生效时显示)
          if (!detail.isConfirmed)
            _buildProgressSection(detail.currentCount, detail.threshold, hasSigned),

          const SizedBox(height: 32),

          // Hash 复制
          _buildHashSection(widget.txHash),
        ],
      ),
    );
  }

  // --- UI 组件封装 (保持原有的视觉风格) ---
  Widget _buildInfoCard(String id, double supply, int p, String owner) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          _row("资产代码", id),
          const Divider(height: 24),
          _row("发行总量", "${_formatValue(supply, p)} $id"),
          const Divider(height: 24),
          _row("精度", "$p 位"),
          const Divider(height: 24),
          _row("多签持有地址", owner, isAddr: true),
        ],
      ),
    );
  }

  Widget _buildProgressSection(int current, int threshold, bool hasSigned) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Trans("当前签署进度"),
              Text("$current / $threshold", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: threshold > 0 ? current / threshold : 0,
            backgroundColor: Colors.orange.withOpacity(0.1),
            color: Colors.orange,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          if (hasSigned)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  const Trans("您已完成对此资产的签署", style: TextStyle(color: Colors.green, fontSize: 11)),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildHashSection(String hash) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Trans("提案哈希 (TxHash)", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: hash));
            Tools.showToast(context, "Hash 已复制");
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(child: Text(hash, style: const TextStyle(fontFamily: 'monospace', fontSize: 10))),
                const Icon(Icons.copy, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool isAddr = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: isAddr ? 'monospace' : null, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  String _formatValue(double val, int p) {
    String str = val.toStringAsFixed(p);
    if (!str.contains('.')) return str;
    return str.replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
  }
}

// ✅ 专门用于资产提案的私有数据模型，不修改公共 Service 对象
class _AssetDetail {
  final String assetId;
  final String owner;
  final int precision;
  final dynamic initialSupply;
  final int threshold;
  final int currentCount;
  final bool isConfirmed;
  final List<String> signedOwners;

  _AssetDetail({
    required this.assetId,
    required this.owner,
    required this.precision,
    required this.initialSupply,
    required this.threshold,
    required this.currentCount,
    required this.isConfirmed,
    required this.signedOwners,
  });
}