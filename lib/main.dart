import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_constants.dart';
import 'data/native_bridge.dart';
import 'state/app_state.dart';
import 'state/settings_controller.dart';
import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';

/// 应用入口。
///
/// 启动流程：加载设置 → 构建 [AppState]（读取存储卷、恢复两列路径）→ 渲染。
/// 初始化在 `runApp` 之前完成，因此首帧即为可用界面，不会出现闪烁的空白页。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 内容延伸到系统栏下方，配合 M3 的沉浸式观感。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0x00000000),
      statusBarColor: Color(0x00000000),
    ),
  );

  // 允许横竖屏：宽屏时自动切换为并排双列布局。
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final SettingsController settings = await SettingsController.load();
  final AppState appState = await AppState.create(settings: settings);

  // 按设置请求最高刷新率；失败不影响启动。
  if (settings.highRefreshEnabled) {
    await appState.requestMaxRefreshRate();
  }

  runApp(PrismApp(appState: appState));
}

/// 根 Widget。
///
/// 监听 [AppState] 以便设置变化（主题模式、取色开关、种子色）能立即反映到
/// 整个应用；Monet 配色由 [DynamicColorBuilder] 提供，在 Android 12 以下或
/// 原生通道不可用时自动退回内置种子色。
class PrismApp extends StatelessWidget {
  const PrismApp({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState state, Widget? child) {
          return _ThemedApp(state: state);
        },
      ),
    );
  }
}

/// 根据当前设置构建主题与路由的应用外壳。
///
/// 单独抽成 widget 而不是内联闭包，既让类型更明确，也避免主题变化时
/// 重建整棵 provider 子树。
class _ThemedApp extends StatelessWidget {
  const _ThemedApp({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = state.settings;
    final bool wantsDynamic = settings.dynamicColorEnabled && state.androidSdk >= 31;
    final Color seed = settings.seedColor;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final bool hasDynamic =
            wantsDynamic && lightDynamic != null && darkDynamic != null;

        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: settings.materialThemeMode,
          theme: AppTheme.light(
            seedColor: seed,
            dynamicScheme: hasDynamic ? lightDynamic : null,
          ),
          darkTheme: AppTheme.dark(
            seedColor: seed,
            dynamicScheme: hasDynamic ? darkDynamic : null,
          ),
          builder: (BuildContext context, Widget? widget) {
            // 限制字体缩放范围，避免极端设置下列表行高被撑破。
            final MediaQueryData data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(
                textScaler: data.textScaler.clamp(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 1.4,
                ),
              ),
              child: widget ?? const SizedBox.shrink(),
            );
          },
          home: HomePage(appState: state),
        );
      },
    );
  }
}

/// 便于测试注入原生桥接的工厂。
NativeBridge createNativeBridge() => NativeBridge();
