// 【新增，用于修复"提案人和追随人不在同一个节点，签署永远无法完成"这个 bug】
//
// 背景（对照你给的 MtxRuleServlet.java / MultiSingManager.java /
// MtxQueryServlet.java 三个后端文件）：
// QCC 创建多签规则（ruleName == "MultiSignature"）时，服务端在
// MultiSingManager 里用一个纯内存的 ConcurrentHashMap
// （pendingSessions / pendingTXSessions / pendingUniversalSessions）保存
// "待签署会话"，Key 是 txHash。这个 Map 只存在于收到这次创建请求的那一台
// 节点的 JVM 内存里，节点之间完全不同步。追加签署
// （ruleName == "MultiSigAppend"）靠 MultiSingManager.addPacket(txHash, ...)
// 去同一个 Map 里查这个会话——如果追随签署的人提交追加签名时，
// QccNodeManager 恰好帮他选了另一个健康节点，那台节点的 pendingSessions
// 根本没有这个 txHash，服务端会直接返回 404
// "MultiSig session not found (invalid txHash or already completed)"，
// 签名永远凑不齐，多签规则/多签转账永远无法完成。
//
// 这是"服务端多节点对等 + 待签会话只存在单节点内存"两者的天然冲突，彻底根治
// 需要后端把会话状态做跨节点同步或落库，属于后端改造范围（如果以后后端做了
// 这个同步，这层客户端适配可以直接下线，不影响任何其他逻辑）。在那之前，
// 客户端能做的适配是：创建方把 hash 分享给追随者时，把"当时这笔交易实际提交
// 到了哪个节点"一起带上；追随者的客户端解析出这个节点信息后，优先用它去
// 提交追加签名/查询状态，而不是重新用 QccNodeManager.currentBaseUrl()
// 现选一个可能不同的"当前最健康节点"。
class MultiSigShareCode {
  static const String _sep = '#';

  /// 编码：把 txHash 和创建/追加时实际提交到的节点 baseUrl
  /// （例如 "https://1.2.3.4:8443"）拼成一个可复制/可扫码的字符串。
  /// nodeBaseUrl 为空时退化成纯 hash（兼容老逻辑/老版本分享出来的文本）。
  static String encode(String txHash, String? nodeBaseUrl) {
    if (nodeBaseUrl == null || nodeBaseUrl.isEmpty) return txHash;
    return "$txHash$_sep$nodeBaseUrl";
  }

  /// 解码：从粘贴/扫码得到的文本里拆出 (hash, nodeBaseUrl)。
  ///
  /// 兼容两种情况：
  /// 1) 旧格式 / 用户手动摘抄的纯 64 位十六进制 hash —— nodeBaseUrl 返回
  ///    null，调用方应该退回旧逻辑（QccNodeManager.currentBaseUrl()），
  ///    这种情况下依然可能撞上"跨节点会话查不到"的问题，但至少从现在起
  ///    新创建的多签任务不会再有这个问题。
  /// 2) 新格式 "hash#nodeBaseUrl" —— 正常拆出两部分。
  ///
  /// 格式异常（比如 hash 段不是 64 位十六进制）时，原样把整段文本当作
  /// hash 返回，交给调用方原有的 hash 格式校验去拦截、提示用户。
  static ({String hash, String? nodeBaseUrl}) decode(String raw) {
    final String text = raw.trim();
    final int idx = text.indexOf(_sep);
    if (idx <= 0) {
      return (hash: text, nodeBaseUrl: null);
    }
    final String hashPart = text.substring(0, idx);
    final String nodePart = text.substring(idx + 1).trim();
    final RegExp hashRegex = RegExp(r'^[a-fA-F0-9]{64}$');
    if (!hashRegex.hasMatch(hashPart) || nodePart.isEmpty) {
      return (hash: text, nodeBaseUrl: null);
    }
    return (hash: hashPart, nodeBaseUrl: nodePart);
  }
}
