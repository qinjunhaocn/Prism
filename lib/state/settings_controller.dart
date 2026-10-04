import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/file_entry.dart';

/// 主题模式：跟随系统 / 常亮 / 常暗。
enum AppThemeMode {
  system,
  light,
  dark,
}

/// 主题色调来源。
enum ColorSource {
  /// 从壁纸动态取色（Android 12+ Monet）。
  monet,

  /// 使用应用内置种子色。
  seed,
}

/// 列表展示形式。
enum ViewMode {
  list,
  grid,
}

/// 全局设置，持久化到 SharedPreferences。
///
/// 作为 [ChangeNotifier] 暴露给 UI；所有 setter 都立即写盘（异步、不阻塞）。
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs);

  final SharedPreferences _prefs;

  static const String _kThemeMode = 'theme_mode';
  static const String _kColorSource = 'color_source';
  static const String _kSeedColor = 'seed_color';
  static const String _kDynamicColor = 'dynamic_color';
  static const String _kViewMode = 'view_mode';
  static const String _kShowHidden = 'show_hidden';
  static const String _kSortLeft = 'sort_left';
  static const String _kSortRight = 'sort_right';
  static const String _kLeftPath = 'left_path';
  static const String _kRightPath = 'right_path';
  static const String _kBookmarks = 'bookmarks';
  static const String _kHighRefresh = 'high_refresh';
  static const String _kThumbnails = 'thumbnails';
  static const String _kConfirmDelete = 'confirm_delete';
  static const String _kListDensity = 'list_density';

  /// 加载设置。
  static Future<SettingsController> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SettingsController._(prefs);
  }

  /// 主题模式。
  AppThemeMode get themeMode => AppThemeMode.values.firstWhere(
        (AppThemeMode value) => value.name == _prefs.getString(_kThemeMode),
        orElse: () => AppThemeMode.system,
      );

  /// 主题色调来源。
  ColorSource get colorSource => ColorSource.values.firstWhere(
        (ColorSource value) => value.name == _prefs.getString(_kColorSource),
        orElse: () => ColorSource.monet,
      );

  /// 内置种子色（[ColorSource.seed] 时生效）。
  Color get seedColor => Color(_prefs.getInt(_kSeedColor) ?? 0xFF6750A4);

  /// 是否启用动态取色。
  bool get dynamicColorEnabled => _prefs.getBool(_kDynamicColor) ?? true;

  /// 列表/网格展示。
  ViewMode get viewMode => ViewMode.values.firstWhere(
        (ViewMode value) => value.name == _prefs.getString(_kViewMode),
        orElse: () => ViewMode.list,
      );

  /// 是否显示隐藏文件。
  bool get showHidden => _prefs.getBool(_kShowHidden) ?? false;

  /// 左侧栏排序规则。
  SortSpec get leftSort => SortSpec.deserialize(_prefs.getString(_kSortLeft));

  /// 右侧栏排序规则。
  SortSpec get rightSort => SortSpec.deserialize(_prefs.getString(_kSortRight));

  /// 左侧栏初始路径。
  String? get leftPath => _prefs.getString(_kLeftPath);

  /// 右侧栏初始路径。
  String? get rightPath => _prefs.getString(_kRightPath);

  /// 是否请求最高刷新率。
  bool get highRefreshEnabled => _prefs.getBool(_kHighRefresh) ?? true;

  /// 是否生成缩略图。
  bool get thumbnailsEnabled => _prefs.getBool(_kThumbnails) ?? true;

  /// 删除前是否二次确认。
  bool get confirmDelete => _prefs.getBool(_kConfirmDelete) ?? true;

  /// 列表紧凑程度：0 紧凑，1 标准，2 宽松。
  int get listDensity => _prefs.getInt(_kListDensity) ?? 1;

  /// 书签路径列表。
  List<String> get bookmarks {
    final String? raw = _prefs.getString(_kBookmarks);
    if (raw == null || raw.isEmpty) {
      return <String>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        return decoded.whereType<String>().toList();
      }
    } on FormatException {
      return <String>[];
    }
    return <String>[];
  }

  /// 当前主题的 [ThemeMode]。
  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// 是否为暗色（跟随系统时需要 [platformBrightness]）。
  bool isDark(Brightness platformBrightness) => switch (themeMode) {
        AppThemeMode.system => platformBrightness == Brightness.dark,
        AppThemeMode.light => false,
        AppThemeMode.dark => true,
      };

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setColorSource(ColorSource source) async {
    await _prefs.setString(_kColorSource, source.name);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    await _prefs.setInt(_kSeedColor, color.toARGB32());
    notifyListeners();
  }

  Future<void> setDynamicColorEnabled(bool enabled) async {
    await _prefs.setBool(_kDynamicColor, enabled);
    notifyListeners();
  }

  Future<void> setViewMode(ViewMode mode) async {
    await _prefs.setString(_kViewMode, mode.name);
    notifyListeners();
  }

  Future<void> setShowHidden(bool value) async {
    await _prefs.setBool(_kShowHidden, value);
    notifyListeners();
  }

  Future<void> setLeftSort(SortSpec sort) async {
    await _prefs.setString(_kSortLeft, sort.serialize());
    notifyListeners();
  }

  Future<void> setRightSort(SortSpec sort) async {
    await _prefs.setString(_kSortRight, sort.serialize());
    notifyListeners();
  }

  Future<void> setPanePath({required bool isLeft, required String path}) async {
    await _prefs.setString(isLeft ? _kLeftPath : _kRightPath, path);
    notifyListeners();
  }

  Future<void> setHighRefreshEnabled(bool enabled) async {
    await _prefs.setBool(_kHighRefresh, enabled);
    notifyListeners();
  }

  Future<void> setThumbnailsEnabled(bool enabled) async {
    await _prefs.setBool(_kThumbnails, enabled);
    notifyListeners();
  }

  Future<void> setConfirmDelete(bool value) async {
    await _prefs.setBool(_kConfirmDelete, value);
    notifyListeners();
  }

  Future<void> setListDensity(int value) async {
    await _prefs.setInt(_kListDensity, value.clamp(0, 2));
    notifyListeners();
  }

  /// 添加书签；已存在则忽略。
  Future<void> addBookmark(String path) async {
    final List<String> current = bookmarks;
    final String normalized = path;
    if (current.contains(normalized)) {
      return;
    }
    current.add(normalized);
    await _prefs.setString(_kBookmarks, jsonEncode(current));
    notifyListeners();
  }

  /// 移除书签。
  Future<void> removeBookmark(String path) async {
    final List<String> current = bookmarks;
    if (!current.remove(path)) {
      return;
    }
    await _prefs.setString(_kBookmarks, jsonEncode(current));
    notifyListeners();
  }

  /// 切换书签状态。
  Future<void> toggleBookmark(String path) async {
    if (bookmarks.contains(path)) {
      await removeBookmark(path);
    } else {
      await addBookmark(path);
    }
  }
}
