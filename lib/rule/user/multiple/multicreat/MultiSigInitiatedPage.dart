import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../utile/Tools.dart';
import '../../../../views/setting/AppTranslator.dart';
import 'QccMultiSigCenterPage.dart';

// 定义业务类型
enum MultiSigPageType { createRule, transfer, append }

class MultiSigInitiatedPage extends StatelessWidget {
  final String txHash;
  final List<String> owners;
  final int threshold;
  final MultiSigPageType type;
  final bool isFinish;

  // 额外参数
  final String? toAddress;
  final String? amount;
  final String? assetId;
  final String? multiAddress; // 成功后生成的地址

  // 【新增】已经完成签署的地址子集（owners 是全部参与地址，signedOwners 是
  // 其中已经签过的那部分）。不传时按 isFinish 兜底：已完成就当全部签了，
  // 未完成就当一个都没签——保证老调用点不用改也能正常显示。
  final List<String>? signedOwners;

  const MultiSigInitiatedPage({
    super.key,
    required this.txHash,
    required this.owners,
    required this.threshold,
    this.type = MultiSigPageType.transfer,
    this.isFinish = false,
    this.toAddress,
    this.amount,
    this.assetId,
    this.multiAddress,
    this.signedOwners,
  });

  @override
  Widget build(BuildContext context) {
    bool isTransfer = type == MultiSigPageType.transfer;

    // 【新增】谁签了、谁没签——不传 signedOwners 时按 isFinish 兜底
    // （已完成视为全签了，未完成视为一个都没签，避免老调用点崩）。
    final Set<String> signedSet = (signedOwners ?? (isFinish ? owners : const <String>[])).toSet();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Trans(isFinish
            ? (isTransfer ? "多签转账已达成" : "多签地址已生成")
            : (isTransfer ? "发起多签转账成功" : "发起多签规则成功")),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            // 1. 顶部状态图标
            Icon(
              isFinish ? Icons.check_circle : Icons.hourglass_top_rounded,
              size: 72,
              color: isFinish ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 16),

            // 【新增】把交易哈希单独提到最前面、做成醒目的独立卡片。
            // 原来 Hash 只是"通用详情"卡片里普通的一行（isAddress=true 还会被
            // 截断成 "24b276...02b45bf" 的缩写显示），追随签署的人恰恰最需要
            // 完整、准确地拿到这个 Hash，之前的展示方式很容易被忽略、也不方便
            // 核对完整内容，所以单独拉出来一张卡片：全文本可选中 + 明显的复制按钮。
            _buildHashCard(context),
            const SizedBox(height: 16),

            // 2. 核心信息卡片（原来这里也有一行 Hash，现在已经挪到上面的
            // _buildHashCard 里，这里不再重复显示，避免同一个 Hash 出现两次）
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  // 如果是规则生成成功，醒目显示多签地址
                  if (!isTransfer && isFinish && multiAddress != null) ...[
                    Trans("多签地址", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Tools.copytext(context, multiAddress!),
                      child: Text(
                        multiAddress!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                  ],

                  // 通用详情行（Hash 已移到上方独立卡片，这里不再重复）
                  // 【修复】原来这里写死 "$threshold / $threshold"——不管有没有
                  // 完成，永远显示成"满进度"（比如 2/2），完全反映不出真实签署
                  // 进度。改成"已签署人数 / 门槛"。
                  _infoRow("签署进度 (Threshold)", "${signedSet.length} / $threshold", context: context),

                  if (isTransfer) ...[
                    const SizedBox(height: 12),
                    _infoRow("收款地址", toAddress ?? "--", context: context, isAddress: true),
                    const SizedBox(height: 12),
                    _infoRow("转账金额", "$amount ${assetId ?? 'QCC'}", context: context),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 【新增】逐个列出参与签署的地址，并标出每个地址是否已签署——
            // 之前只显示一个笼统的 "threshold/threshold" 数字，2 人以上的多签
            // 场景完全看不出"具体是谁签了、谁还没签"。owners 是几个地址，这里
            // 就列几行；不局限于 2 个，3 个、5 个都按同样的方式逐行展示。
            _buildOwnersCard(context, signedSet),

            const SizedBox(height: 20),

            // 3. 签署邀请区 (仅在未完成时显示)
            if (!isFinish) ...[
              Trans("邀请伙伴签署", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              // 二维码保留：目前扫码进不了任何流程（追随页面还是靠手动粘贴 Hash），
              // 先按你的要求保留这个入口，等以后追随签署页支持"扫码识别 Hash"了，
              // 这里不用改，直接就能接上。
              QrImageView(
                data: txHash,
                version: QrVersions.auto,
                size: 180.0,
              ),
              const SizedBox(height: 12),
              const Text("请伙伴在“多签中心 -> 追随转账”中扫描或粘贴此 Hash",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],

            const SizedBox(height: 40),

            // 4. 操作按钮
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  /// 【新增】参与签署地址列表：owners 有几个就列几行，每行标出这个地址
  /// 是否已经签署（对照 signedSet）。threshold < owners.length 的场景下
  /// （比如 2-of-3），即使不是每个地址都要签，也能一眼看出当前状态。
  Widget _buildOwnersCard(BuildContext context, Set<String> signedSet) {
    if (owners.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Trans(
                "参与签署地址 (${signedSet.length}/${owners.length})",
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < owners.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _buildOwnerRow(context, owners[i], signedSet.contains(owners[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildOwnerRow(BuildContext context, String address, bool signed) {
    return Row(
      children: [
        Icon(
          signed ? Icons.check_circle : Icons.hourglass_bottom,
          size: 16,
          color: signed ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => Tools.copytext(context, address),
            child: Text(
              address,
              style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: Colors.black87),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Trans(
          signed ? "已签署" : "待签署",
          style: TextStyle(fontSize: 11.5, color: signed ? Colors.green : Colors.orange),
        ),
      ],
    );
  }

  /// 【新增】醒目的 Hash 卡片：全文本展示（可选中）+ 独立复制按钮。
  Widget _buildHashCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Trans(
                  "交易哈希 (Hash) · 追随签署需要此值",
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 用 SelectableText 展示完整哈希，而不是像下方通用详情行那样
          // 缩写成 "24b276...02b45bf"——追随签署时对方需要核对/粘贴完整值。
          SelectableText(
            txHash,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Colors.black87, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: txHash));
                Tools.showToast(context, "Hash 已复制");
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Trans("复制 Hash"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        if (!isFinish)
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: txHash));
              Tools.showToast(context, "Hash 已复制");
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Trans("复制交易哈希发送给伙伴"),
          ),
        const SizedBox(height: 16),
        // 【新增】原来只有"完成并返回首页"这一个出口，它是
        // `Navigator.of(context).popUntil((route) => route.isFirst)`，
        // 会一路弹回 App 的根页面，并不会停在"多签管理中心"的列表上——
        // 用户创建/追随完之后，并不会直接看到这笔记录已经进了列表，
        // 得自己再手动点回"多签管理中心"才能看到。这里加一个显式入口，
        // 直接跳到多签列表页，保证"能看到这笔交易进了明细"。
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const QccMultiSigCenterPage()),
                  (route) => route.isFirst,
            );
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            side: const BorderSide(color: Colors.blue),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Trans("查看多签交易明细"),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            side: BorderSide(color: Colors.grey[400]!),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Trans("完成并返回首页", style: TextStyle(color: Colors.grey[700])),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value, {bool isAddress = false, required BuildContext context}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Trans(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(width: 20),
        Expanded(
          child: GestureDetector(
            onTap: () => Tools.copytext(context, value),
            child: Text(
              isAddress && value.length > 20
                  ? "${value.substring(0, 8)}...${value.substring(value.length - 8)}"
                  : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}