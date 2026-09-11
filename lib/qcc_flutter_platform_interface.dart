import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qcc_flutter_method_channel.dart';

abstract class QccFlutterPlatform extends PlatformInterface {
  /// Constructs a QccFlutterPlatform.
  QccFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static QccFlutterPlatform _instance = MethodChannelQccFlutter();

  /// The default instance of [QccFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelQccFlutter].
  static QccFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [QccFlutterPlatform] when
  /// they register themselves.
  static set instance(QccFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

}
