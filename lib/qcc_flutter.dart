
import 'qcc_flutter_platform_interface.dart';

class QccFlutter {
  Future<String?> getPlatformVersion() {
    return QccFlutterPlatform.instance.getPlatformVersion();
  }
}
