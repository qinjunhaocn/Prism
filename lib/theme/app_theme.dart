import 'package:flutter/material.dart';

import '../state/settings_controller.dart';

/// 应用主题构建。
///
/// Material Design 3 风格：所有配色均由 ColorScheme 派生，
/// 支持壁纸动态取色（Monet）与内置种子色两种来源。
abstract final class AppTheme {
  /// 内置种子色候选，供用户手动挑选。
  static const List<SeedColorOption> seedOptions = <SeedColorOption>[
    SeedColorOption('Prism 紫', Color(0xFF6750A4)),
    SeedColorOption('海洋蓝', Color(0xFF0061A4)),
    SeedColorOption('松林绿', Color(0xFF00696D)),
    SeedColorOption('珊瑚橙', Color(0xFF8B5000)),
    SeedColorOption('莓果红', Color(0xFFB3261E)),
    SeedColorOption('青柠绿', Color(0xFF4C662B)),
    SeedColorOption('薰衣草', Color(0xFF7D5260)),
    SeedColorOption('石墨灰', Color(0xFF44474E)),
  ];

  /// 亮色主题。
  static ThemeData light({
    required Color seedColor,
    ColorScheme? dynamicScheme,
    bool useMaterial3 = true,
  }) {
    final ColorScheme scheme = dynamicScheme ?? ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _build(scheme, useMaterial3: useMaterial3);
  }

  /// 暗色主题。
  static ThemeData dark({
    required Color seedColor,
    ColorScheme? dynamicScheme,
    bool useMaterial3 = true,
  }) {
    final ColorScheme scheme = dynamicScheme ?? ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _build(scheme, useMaterial3: useMaterial3);
  }

  /// 根据配色方案构建完整主题。
  static ThemeData _build(ColorScheme scheme, {required bool useMaterial3}) {
    final bool isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: useMaterial3,
      colorScheme: scheme,
      // 关闭 splash 相关的额外动画层，滚动时更省 GPU。
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.none,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 3,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
      textTheme: _textTheme(scheme, isDark),
      extensions: const <ThemeExtension<Object?>>[],
    );
  }

  /// 文本样式：基于 M3 字阶做小幅调整，保证中文可读性。
  static TextTheme _textTheme(ColorScheme scheme, bool isDark) {
    return TextTheme(
      titleLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: scheme.onSurface),
      bodyMedium: TextStyle(color: scheme.onSurface),
      bodySmall: TextStyle(color: scheme.onSurfaceVariant),
      labelLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: scheme.onSurfaceVariant),
      labelSmall: TextStyle(color: scheme.onSurfaceVariant),
    );
  }

  /// 与主题模式对应的中文名。
  static String themeModeLabel(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '浅色',
        AppThemeMode.dark => '深色',
      };
}

/// 内置种子色选项。
class SeedColorOption {
  const SeedColorOption(this.label, this.color);

  final String label;
  final Color color;
}
