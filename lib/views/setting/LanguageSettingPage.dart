import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'AppTranslator.dart';

class LanguageSettingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final manager = AppTranslationManager.instance;
    return Scaffold(
      appBar: AppBar(title: const Trans("选择语言")),
      body: ListView(
        children: manager.supportedLanguages.entries.map((e) {
          bool isSelected = manager.targetLanguage == e.key;
          return ListTile(
            title: Text(e.value),
            trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
            onTap: () {
              manager.changeLanguage(e.key); // 内部已集成 shared_preferences
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}