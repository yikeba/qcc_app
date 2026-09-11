#include "include/qcc_flutter/qcc_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "qcc_flutter_plugin.h"

void QccFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  qcc_flutter::QccFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
