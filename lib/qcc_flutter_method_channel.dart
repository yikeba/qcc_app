import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qcc_flutter_platform_interface.dart';

/// An implementation of [QccFlutterPlatform] that uses method channels.
class MethodChannelQccFlutter extends QccFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('qcc_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
