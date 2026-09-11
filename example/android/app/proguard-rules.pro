# 保留 liboqs 的所有类和成员
-keep class org.openquantumsafe.** { *; }

# 保护原生方法名不被混淆
-keepclasseswithmembernames class * {
    native <methods>;
}

# 显式保留 liboqs 相关的库加载逻辑
-keep class * implements oqs.** { *; }