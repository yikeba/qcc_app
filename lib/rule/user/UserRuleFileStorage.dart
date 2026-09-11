import 'dart:convert';
import '../../../utile/QccStorage.dart';
import '../../../utile/LogObj.dart';

class UserRuleFileStorage {
  static const String _storageKey = "qcc_user_rules_history";

  /// 【新增】读落盘用的原始顺序（旧的在前，chronological）。
  /// saveRuleTask()/deleteTask() 都应该在这份原始顺序上做增删，不要用
  /// getAllRules() 那份已经 reversed 过的展示顺序——见下面 saveRuleTask()
  /// 里的说明。
  static Future<List<dynamic>> _readRaw() async {
    String? data = await QccStorage.getRawkeyuData(_storageKey);
    if (data == null || data.isEmpty) return [];
    try {
      return jsonDecode(data) as List;
    } catch (e) {
      return [];
    }
  }

  /// 保存规则任务记录
  /// 会解析公链返回的 data 字符串，提取 ruleName 作为关键标识
  static Future<void> saveRuleTask(Map<String, dynamic> responseData) async {
    try {
      // 【修复，重要】原来这里调 getAllRules()——那个方法本来是给界面展示
      // 用的，已经把落盘顺序 reversed（最新的在前）过一次；这里却拿它当
      // "落盘用的原始数据"去追加、再原样写回存储，等于把"展示顺序"当成了
      // "落盘顺序"。第一次调用看不出问题，但只要再保存第二笔，下次
      // getAllRules() 会在一份已经被搅乱过的数据上再 reverse 一次——不是
      // 单纯"最新的在前/在后"颠倒，而是中间的顺序被反复打乱。改成单独维护
      // 一份 chronological（旧的在前）的原始列表，只有 getAllRules() 读出来
      // 给界面用的时候才做 reverse。
      final List<dynamic> raw = await _readRaw();

      Map<String, dynamic> task = {
        'txHash': responseData['txHash'],
        'timestamp': responseData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'status': responseData['status'],
      };

      // 按照你的建议：深度解析返回内容中的 ruleName
      if (responseData['data'] != null) {
        try {
          var innerData = jsonDecode(responseData['data']);
          task['ruleName'] = innerData['ruleName'] ?? "UnknownRule";
          task['from'] = innerData['from'];
          task['ruleJson'] = innerData['ruleJson'];
        } catch (e) {
          LogObj.log("解析 RuleName 失败: $e");
          task['ruleName'] = "QCC Rule";
        }
      } else {
        task['ruleName'] = responseData['ruleName'] ?? "QCC Rule";
      }

      // 【修复】原来"已存在同 txHash 就整个跳过不存"——如果以后需要给同一笔
      // 交易补充字段（比如后续加一个真正的链上确认状态），永远合并不进去，
      // 记录会一直停留在最早那次可能不完整的数据上。改成"已存在就合并
      // 更新"，和 MultiSigFileStorage.saveTask() 保持一致的做法。
      final int existingIndex =
      raw.indexWhere((e) => e is Map && e['txHash'] == task['txHash']);
      if (existingIndex != -1) {
        final Map<String, dynamic> merged = Map<String, dynamic>.from(raw[existingIndex] as Map);
        merged.addAll(task);
        raw[existingIndex] = merged;
      } else {
        raw.add(task);
      }

      // 调用你提供的 saveRawData
      await QccStorage.saveRawData(_storageKey, jsonEncode(raw));
      LogObj.log("✅ 规则记录 [${task['ruleName']}] 已存入本地缓存");
    } catch (e) {
      LogObj.log("保存规则记录异常: $e");
    }
  }

  /// 获取所有本地规则历史 (最新的在前，供列表页展示用)
  static Future<List<dynamic>> getAllRules() async {
    final List<dynamic> raw = await _readRaw();
    return raw.reversed.toList();
  }

  /// 【新增】删除一条本地规则记录——配合"规则交易中心"列表页的删除按钮，
  /// 用法对齐 MultiSigFileStorage.deleteTask()。
  static Future<void> deleteTask(String txHash) async {
    try {
      final List<dynamic> raw = await _readRaw();
      raw.removeWhere((e) => e is Map && e['txHash'] == txHash);
      await QccStorage.saveRawData(_storageKey, jsonEncode(raw));
    } catch (e) {
      LogObj.log("删除规则记录失败: $e");
    }
  }
}