#ifndef FLUTTER_PLUGIN_QCC_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_QCC_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace qcc_flutter {

class QccFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  QccFlutterPlugin();

  virtual ~QccFlutterPlugin();

  // Disallow copy and assign.
  QccFlutterPlugin(const QccFlutterPlugin&) = delete;
  QccFlutterPlugin& operator=(const QccFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace qcc_flutter

#endif  // FLUTTER_PLUGIN_QCC_FLUTTER_PLUGIN_H_
