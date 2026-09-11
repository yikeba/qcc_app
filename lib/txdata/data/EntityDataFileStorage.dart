import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 本机存证发布记录——完全照抄 MultiSigFileStorage.dart/PledgeFileStorage.dart
/// 的落盘模式（单个 JSON 数组文件，按 txHash 去重合并）。
///
/// 【为什么需要这个】/v1/data 发布成功后，服务端只返回一个 txHash，用户
/// 没有任何地方能再看到"我发过哪些存证"——这里在本机落一份记录，方便
/// 之后做"发布记录"列表、复制历史 txHash、核对是否重复发布等。
/// 【和 PledgeFileStorage 的差别】这里不需要 updateStatus 这种"后续状态
/// 会变化"的语义——存证发布是一次性动作，不像质押 lock 之后还有 unlock，
/// 所以只保留 saveTask/getAllTasks/getTasksForAddress/deleteTask。
class EntityDataFileStorage {
  static const String _fileName = 'entitydata_records.json';

  static Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  /// 保存一条发布记录。要求至少带上 txHash，否则无法记录/查询。
  /// 常见字段：txHash, from, assetId, fromdev, timestamp, mode("text"|"file"),
  /// fileName, preview, payloadSize, status, serverMsg, savedAt。
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
      print("存储存证发布记录失败: $e");
    }
  }

  /// 全部本机发布记录，供"发布记录"列表页使用。
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

  /// 只取某个本机地址发布过的记录。
  static Future<List<Map<String, dynamic>>> getTasksForAddress(String address) async {
    final all = await getAllTasks();
    return all.where((t) => (t['from'] ?? '').toString() == address).toList();
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
      print("删除存证发布记录失败: $e");
    }
  }
}
