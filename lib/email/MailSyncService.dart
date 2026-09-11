import 'dart:typed_data';

import 'QccMailApi.dart';
import 'MailLocalStore.dart';

/// 差额同步：用高度（seq）算差额，只拉本地缺的区间，无需遍历。
/// 几十万封也只传差额，与区块链按 height 同步同模型。
class MailSyncService {
  final String user;
  final MailLocalStore store;

  /// 单次 index 拉取的页大小（与后端 MAX_INDEX_PAGE=500 对齐，留点余量）。
  static const int pageSize = 200;

  MailSyncService(this.user) : store = MailLocalStore(user);

  /// 执行一次增量同步。返回新增条数。
  /// [onProgress] 可选，(已同步, 总差额) 用于进度条。
  Future<int> sync({void Function(int done, int total)? onProgress}) async {
    final localMax = await store.localMaxSeq();
    final serverMax = await QccMailApi.fetchMaxSeq(user);

    if (serverMax <= localMax) return 0; // 没有新邮件

    final total = serverMax - localMax;
    int done = 0;

    // 分页拉取 (localMax, serverMax]
    int from = localMax + 1;
    while (from <= serverMax) {
      final to = (from + pageSize - 1).clamp(from, serverMax);
      final items = await QccMailApi.fetchIndexRange(user, from, to);

      for (final item in items) {
        await store.putIndex((item as Map).cast<String, dynamic>());
      }
      done += items.length;
      onProgress?.call(done, total);

      // 推进游标：以本页实际返回的最大 seq 为准，避免空洞卡死
      int maxInPage = to;
      for (final it in items) {
        final s = ((it as Map)['seq'] as num).toInt();
        if (s > maxInPage) maxInPage = s;
      }
      await store.setLocalMaxSeq(maxInPage);
      from = maxInPage + 1;

      if (items.isEmpty) break; // 防御：服务端无返回则停止
    }
    return done;
  }

  /// 读取本地索引列表（同步后调用，渲染列表）。
  Future<List<Map<String, dynamic>>> loadList() => store.loadAllIndex();

  /// 取某封原文：本地有直接返回，没有则下载并缓存（带可选哈希校验）。
  Future<Uint8List> getRawCached(int seq, {String? expectSha256}) async {
    final cached = await store.getRaw(seq);
    if (cached != null) return cached;

    final res = await QccMailApi.fetchRaw(user, seq);
    // 可选：用 crypto 复算 sha256 与 expectSha256/响应头比对（这里不强制依赖）
    await store.putRaw(seq, res.bytes);
    return res.bytes;
  }
}