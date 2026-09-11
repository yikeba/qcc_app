import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 本机质押记录本地缓存——完全照抄 MultiSigFileStorage.dart 的落盘模式
/// （单个 JSON 数组文件，按 txHash 去重合并）。
///
/// 【为什么需要这个，之前没有征求你意见就先设计了，这里明确标出来】
/// 解押/吊销都需要用户提供"原 lock 交易的 txHash"（普通/超级节点质押填
/// PledgeRules.credentialHash；授权质押填 AuthorizedPledge.revokeHash），
/// 但没有任何一个 Java 测试文件表明有"查询我发起过哪些质押"这样的列表
/// 接口——PledgeContext.java 的 GET /v1/pledge/{address} 更像是"按
/// address+tag+hash 三要素查一条鉴权记录是否有效"，不是"列出这个地址名下
/// 全部质押"的列表接口。要求用户自己手抄/记住一串 txHash 去解押体验上不
/// 现实，所以这里在本机落一份"我发起过哪些质押 lock"的记录，解押页面直接
/// 从这里选择，而不是要求手填 hash。
/// 【需要你确认】如果链上其实有专门的"我的质押列表"查询接口，这个本地
/// 缓存应该只是兜底/离线展示，真正列表应该优先用服务端返回的——请告诉我
/// 对应的 Context/Controller 源码。
class PledgeFileStorage {
  static const String _fileName = 'pledge_tasks.json';

  static Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  /// 保存一次质押发起(lock)记录。要求至少带上 txHash，否则无法记录/查询。
  /// 常见字段：txHash, address, assetId, amount, protocol(PledgetType 或
  /// 空串), tag(仅授权质押), to(仅授权质押), timestamp, status。
  static Future<void> saveTask(Map<String, dynamic> record) async {
    try {
      final File file = await _getLogFile();
      List<dynamic> taskList = [];
      if (await file.exists()) {
        taskList = jsonDecode(await file.readAsString());
      }

      final String hash = (record['txHash'] ?? '').toString();
      if (hash.isEmpty) return;

      final int existingIndex = taskList.indexWhere((t) => t is Map && t['txHash'] == hash);
      if (existingIndex != -1) {
        final Map<String, dynamic> merged = Map<String, dynamic>.from(taskList[existingIndex] as Map);
        merged.addAll(record);
        taskList[existingIndex] = merged;
      } else {
        taskList.add(Map<String, dynamic>.from(record));
      }
      await file.writeAsString(jsonEncode(taskList));
    } catch (e) {
      print("存储质押记录失败: $e");
    }
  }

  /// 全部本机质押记录，供记录列表/解押选择页使用。
  static Future<List<Map<String, dynamic>>> getAllTasks() async {
    try {
      final File file = await _getLogFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final List<dynamic> raw = jsonDecode(content);
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 只取某个本机地址发起过的质押记录（列表页按地址过滤用）。
  static Future<List<Map<String, dynamic>>> getTasksForAddress(String address) async {
    final all = await getAllTasks();
    return all.where((t) => (t['address'] ?? '').toString() == address).toList();
  }

  /// 更新状态（比如解押/吊销后标记为 UNLOCKED）。
  static Future<void> updateStatus(String txHash, String newStatus) async {
    try {
      final File file = await _getLogFile();
      if (!await file.exists()) return;
      final List<dynamic> records = jsonDecode(await file.readAsString());
      for (var item in records) {
        if (item['txHash'] == txHash) {
          item['status'] = newStatus;
          break;
        }
      }
      await file.writeAsString(jsonEncode(records));
    } catch (e) {
      print("更新质押记录状态失败: $e");
    }
  }

  static Future<void> deleteTask(String txHash) async {
    try {
      final File file = await _getLogFile();
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.isEmpty) return;
      final List<dynamic> records = jsonDecode(content);
      records.removeWhere((item) => item['txHash'] == txHash);
      await file.writeAsString(jsonEncode(records));
    } catch (e) {
      print("删除质押记录失败: $e");
    }
  }
}
