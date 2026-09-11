import 'package:bip39/bip39.dart' as bip39;
import 'package:bip39/src/wordlists/english.dart' as english_list;

class MnemonicFixer {
  // 核心方法：尝试修正助记词
  static Future<FixResult> smartFix(List<String> inputWords) async {
    List<String> fixedWords = List.from(inputWords);
    List<int> changedIndices = [];
    final allWords = english_list.WORDLIST;

    // 1. 第一步：修正所有不在词库的单词（拼写检查）
    for (int i = 0; i < 24; i++) {
      if (!allWords.contains(fixedWords[i])) {
        // 简单的逻辑：如果单词不对，暂时标记并尝试找一个相似的，这里演示先标记
        changedIndices.add(i);
      }
    }

    // 2. 第二步：如果拼写都对但校验失败，尝试修正第 24 个词（校验位）
    String currentMnemonic = fixedWords.join(" ");
    if (!bip39.validateMnemonic(currentMnemonic)) {
      // 暴力尝试：保持前 23 个词不变，循环 2048 个单词找能过校验的第 24 个词
      String prefix = fixedWords.sublist(0, 23).join(" ");
      for (String candidate in allWords) {
        String testMnemonic = "$prefix $candidate";
        if (bip39.validateMnemonic(testMnemonic)) {
          fixedWords[23] = candidate;
          if (!changedIndices.contains(23)) changedIndices.add(23);
          break;
        }
      }
    }

    bool success = bip39.validateMnemonic(fixedWords.join(" "));
    return FixResult(success, fixedWords, changedIndices);
  }
}

class FixResult {
  final bool isSuccess;
  final List<String> words;
  final List<int> changedIndices; // 记录哪些位置被程序修改了
  FixResult(this.isSuccess, this.words, this.changedIndices);
}