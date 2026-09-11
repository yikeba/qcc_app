import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:qcc_flutter/home/WalletInitPage.dart';
import 'package:qcc_flutter/qcc_flutter.dart';
import 'package:liboqs/liboqs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LibOQS.init(); // Recommended at app startup
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WalletInitPage(freeId: "admin",)
    );
  }
}
