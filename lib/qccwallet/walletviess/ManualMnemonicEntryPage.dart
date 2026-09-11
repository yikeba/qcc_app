import 'dart:developer' as LogObj;

import 'package:flutter/material.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip39/src/wordlists/english.dart' as english_list;
import '../../views/setting/AppTranslator.dart';
import 'MnemonicFixer.dart';
import 'QccWalletFactory.dart';

class ManualMnemonicEntryPage extends StatefulWidget {
  const ManualMnemonicEntryPage({super.key});

  @override
  State<ManualMnemonicEntryPage> createState() => _ManualMnemonicEntryPageState();
}

class _ManualMnemonicEntryPageState extends State<ManualMnemonicEntryPage> {
  // 必须成对定义控制器和焦点节点
  final List<TextEditingController> _controllers = List.generate(24, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(24, (_) => FocusNode());
  final List<String> _allBip39Words = english_list.WORDLIST;
  final List<bool> _isWordValid = List.generate(24, (_) => false);

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 24; i++) {
      _controllers[i].addListener(() => _validateSingleWord(i));
    }
  }

  void _validateSingleWord(int index) {
    // 实时过滤空格进行校验
    String cleanWord = _controllers[index].text.trim().toLowerCase();
    bool isValid = _allBip39Words.contains(cleanWord);
    if (_isWordValid[index] != isValid) {
      setState(() => _isWordValid[index] = isValid);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    super.dispose();
  }

  // 显示规则说明对话框
  void _showRules() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("QCC 助记词生成规则"),
        content: const SingleChildScrollView(
          child: ListBody(
            children: [
              Trans("1. 必须由 24 个标准 BIP39 英文单词组成。"),
              Trans("2. 每个单词输入后，边框变绿表示有效，红色表示单词不在词库中。"),
              Trans("3. 系统会自动过滤多余的空格。"),
              Trans("4. 注意：第 24 个词是校验位，由前 23 个词计算得出，不可随意组合。"),
              Trans("\n建议：若多次尝试失败，请使用“自动生成”功能。"),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("知道了"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("人工生产 24 词"),
        actions: [
          IconButton(onPressed: _showRules, icon: const Icon(Icons.help_outline))
        ],
      ),
      body: Column(
        children: [
          GestureDetector(
            onTap: _showRules,
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.blue.withOpacity(0.1),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Icon(Icons.info, size: 16, color: Colors.blue), Text(" 点击查看助记词输入规则", style: TextStyle(color: Colors.blue, fontSize: 12))],
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, childAspectRatio: 2.8, crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: 24,
              itemBuilder: (context, index) => _buildAutocompleteField(index),
            ),
          ),
          _buildActionBottom(),
        ],
      ),
    );
  }

  Widget _buildAutocompleteField(int index) {
    return RawAutocomplete<String>(
      textEditingController: _controllers[index],
      focusNode: _focusNodes[index], // 修复关键：传入对应的 FocusNode
      optionsBuilder: (textValue) {
        String input = textValue.text.trim().toLowerCase();
        if (input.length < 1) return const Iterable<String>.empty();
        return _allBip39Words.where((w) => w.startsWith(input)).take(5);
      },
      onSelected: (selection) {
        _controllers[index].text = selection;
        _validateSingleWord(index);
        FocusScope.of(context).nextFocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        bool isValid = _isWordValid[index];
        bool hasText = controller.text.isNotEmpty;

        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            prefixText: "${index + 1}. ",
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: !hasText ? Colors.grey : (isValid ? Colors.green : Colors.red)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: isValid ? Colors.green : Colors.blue, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: SizedBox(
              width: 150,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(options.elementAt(i)),
                  onTap: () => onSelected(options.elementAt(i)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionBottom() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        onPressed: _isWordValid.every((v) => v) ? _validateAndCreate : null,
        child: Trans("确认并生成钱包"),
      ),
    );
  }

  void _validateAndCreate() async {
    List<String> inputWords = _controllers.map((c) => c.text.trim().toLowerCase()).toList();

    // 1. 弹出滚动检测框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("正在智能检测并匹配合法校验位...", style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
    // 2. 执行智能修正
    final result = await MnemonicFixer.smartFix(inputWords);
    Navigator.pop(context); // 关闭检测框
    if (result.isSuccess) {
      if (result.changedIndices.isNotEmpty) {
        // 3. 如果有修改，弹出对比确认框
        _showConfirmFixDialog(result);
      } else {
        String mnustr="";
        for (var i in result.changedIndices) {
          mnustr = result.words[i];
        }
        final wallet=await QccWalletFactory.createByImport(context, mnustr);
        Navigator.pop(context); // 关掉展示页
        LogObj.log("返回人工生成24个助记词创建的钱包${wallet!.address}");
        Navigator.pop(context, wallet); // 返回钱包对象
      }
    } else {
      _showErrorDialog("无法修正此组合，请确保前 23 个单词准确无误。");
    }
  }

  // 确认修改弹窗
  void _showConfirmFixDialog(FixResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("智能修正建议"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("为了符合 BIP39 算法规则，系统建议微调以下单词："),
            const SizedBox(height: 10),
            // 列出被修改的单词
            ...result.changedIndices.map((index) => Text(
              "第 ${index + 1} 个: ${result.words[index]}",
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () async {
              String mnustr="";
              for (var i in result.changedIndices) {
                mnustr = result.words[i];
              }
              final wallet=await QccWalletFactory.createByImport(context, mnustr);
              Navigator.pop(context); // 关掉展示页
              LogObj.log("返回人工生成24个助记词创建的钱包${wallet!.address}");
              Navigator.pop(context, wallet); // 返回钱包对象
            },
            child: Trans("接受修正并生成地址"),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Trans("校验失败"),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("确定"))],
      ),
    );
  }

}