// 【新增】多签（创建 / 追加签署 / 查询状态）专用的固定节点。
//
// 背景：QCC 链上其他普通交易都是通过 QccNodeManager 在多个对等节点之间自动
// 挑选、故障转移的。但多签的"待签会话"——对照 MultiSingManager.java 里的
// pendingSessions / pendingTXSessions / pendingUniversalSessions——是纯内存
// ConcurrentHashMap，只存在于【当初收到创建请求的那一台节点】的 JVM 里，
// 节点之间完全不同步。如果创建、追加签署、查询状态这几步被 QccNodeManager
// 分配到了不同节点，后续请求会直接查不到会话（服务端返回 404 "session not
// found"），签名永远凑不齐。
//
// 按你的决定：多签相关的这几类请求不再走 QccNodeManager 的动态选择/故障
// 转移，统一固定打这一个节点/域名，从根源上避免"发起人和追随人不在同一
// 节点"的问题——比之前用 MultiSigShareCode 把节点信息编码进分享文本里再解析
// 简单得多，MultiSigShareCode.dart 现在已经没有地方引用了，可以直接删掉。
//
// 取舍：这个固定节点变成了"仅多签这一类操作"的单点依赖——如果它挂了，
// 所有用户的多签创建/追加/查询都会失败，且没有自动切换。好在
// MultiSingManager.java 里会话本身就有 24 小时过期（expiry = now + 24h），
// 风险窗口是有界的；如果这个域名背后由后端做了多机 + 会话状态同步/共享
// 存储的高可用，客户端这边完全不用跟着改。
//
// 【待确认】这里先沿用了之前 QccMultiSigService.dart 里原有的默认值
// "https://tx.qccio.com"。如果你想固定用另一个域名/IP，改这一处常量即可，
// 所有引用的地方（创建页、追随页、状态查询）都会跟着生效。
class MultiSigNode {
  static const String baseUrl = "https://tx.qccio.com";
}
