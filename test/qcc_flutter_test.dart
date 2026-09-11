import 'package:flutter_test/flutter_test.dart';
import 'package:qcc_flutter/qcc_flutter.dart';
import 'package:qcc_flutter/qcc_flutter_platform_interface.dart';
import 'package:qcc_flutter/qcc_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockQccFlutterPlatform
    with MockPlatformInterfaceMixin
    implements QccFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final QccFlutterPlatform initialPlatform = QccFlutterPlatform.instance;

  test('$MethodChannelQccFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelQccFlutter>());
  });

  test('getPlatformVersion', () async {
    QccFlutter qccFlutterPlugin = QccFlutter();
    MockQccFlutterPlatform fakePlatform = MockQccFlutterPlatform();
    QccFlutterPlatform.instance = fakePlatform;

    expect(await qccFlutterPlugin.getPlatformVersion(), '42');
  });
}
