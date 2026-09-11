import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MultiSigFileStorage {

  // 获取文件路径
  static Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  static const String _fileName = 'multisig_tasks.json';
  // MultiSigFileStorage.dart
  static Future<void> saveTask(Map<String, dynamic> logResponse) async {
    try {
      final File file = await _getLogFile();
      List<dynamic> taskList = [];
      if (await file.exists()) {
        taskList = jsonDecode(await file.readAsString());
      }

      // 只存储最基础的标识，确保 RecordPage 能发起查询
      String hash = logResponse['txHash'];
      if (taskList.any((t) => t['txHash'] == hash)) return;

      taskList.add({'txHash': hash});
      await file.writeAsString(jsonEncode(taskList));
    } catch (e) {
      print("存储 Hash 失败: $e");
    }
  }
  /// 获取所有任务供 RecordPage 使用
  static Future<List<dynamic>> getAllTasks() async {
    try {
      final File file = await _getLogFile();
      if (!await file.exists()) return [];
      String content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      return [];
    }
  }

  // 更新状态（例如上链成功后）
  static Future<void> updateStatus(String txHash, String newStatus) async {
    final File file = await _getLogFile();
    if (!await file.exists()) return;

    List<dynamic> records = jsonDecode(await file.readAsString());
    for (var item in records) {
      if (item['txHash'] == txHash) {
        item['status'] = newStatus;
        break;
      }
    }
    await file.writeAsString(jsonEncode(records));
  }

  // 新增：删除单条记录
  static Future<void> deleteTask(String txHash) async {
    try {
      final File file = await _getLogFile(); // 使用你类中定义的正确方法名
      if (!await file.exists()) return;
      String content = await file.readAsString();
      if (content.isEmpty) return;
      List<dynamic> records = jsonDecode(content);
      // 移除匹配 txHash 的项
      records.removeWhere((item) => item['txHash'] == txHash);
      // 写回文件
      await file.writeAsString(jsonEncode(records));
    } catch (e) {
      print("删除多签记录失败: $e");
    }
  }


  // 在 MultiSigFileStorage 类中追加
  static Future<void> saveConfirmedAccount(Map<String, dynamic> accountData) async {
    try {
      final File file = await _getLogFile(); // 复用记录文件或另开 account_list.json
      List<dynamic> records = await getAllTasks();

      // 结构化存储：确保包含 M 地址、去重后的 owners 和 threshold
      Map<String, dynamic> account = {
        'multiAddress': accountData['multiaddress'],
        'owners': List<String>.from(accountData['owners']).toSet().toList(), // 强制去重修复
        'threshold': accountData['threshold'],
        'txHash': accountData['txHash'],
        'syncTime': DateTime.now().millisecondsSinceEpoch,
      };

      // 更新原有 PENDING 记录为 SUCCESS 并同步 M 地址
      for (var item in records) {
        if (item['txHash'] == account['txHash']) {
          item['status'] = 'SUCCESS';
          item['multiAddress'] = account['multiAddress'];
          break;
        }
      }
      await file.writeAsString(jsonEncode(records));
    } catch (e) {
      print("持久化多签账户失败: $e");
    }
  }
}