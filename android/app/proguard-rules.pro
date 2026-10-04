# Prism 的 ProGuard/R8 规则。
#
# Flutter 引擎与插件的入口由 Flutter Gradle Plugin 自动保留，
# 这里只补充反射相关的必要豁免。

# 保留 Flutter embedding 入口。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# 本应用的 MethodChannel 宿主。
-keep class com.voxyn.prism.MainActivity { *; }

# dynamic_color 插件通过反射调用平台实现。
-keep class io.material.plugins.dynamic_color.** { *; }

# shared_preferences / path_provider 的 Android 实现。
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# 保留注解与泛型签名，避免 Gson/反射类库出现问题。
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# 忽略缺失的可选依赖告警。
-dontwarn io.flutter.**
-dontwarn androidx.**
