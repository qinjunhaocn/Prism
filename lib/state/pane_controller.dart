import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/app_constants.dart';
import '../core/file_utils.dart';
import '../data/file_repository.dart';
import '../data/models/file_entry.dart';
import 'settings_controller.dart';

/// 单个文件面板（列）的状态与行为。
///
/// 双列文件管理器的每一列都是一个 [PaneController]，左右两列完全对等，
/// 因此任意一列都可以作为「源」或「目标」，也支持互相复制/移动。
///
/// 关键设计：
/// * 目录列举是异步的，并且用 [_loadToken] 做竞态保护 —— 快速连续切换目录时，
///   只有最后一次请求的结果会被应用，避免旧结果覆盖新界面。
/// * 选择集使用 [Set] 存储路径，O(1) 命中判断，滚动时无需遍历列表。
/// * 隐藏项过滤、排序规则来自全局设置，但每列各自维护排序。
class PaneController extends ChangeNotifier {
  PaneController({
    required this.repository,
    required this.settings,
    required this.isLeft,
    required String initialPath,
  }) : _path = FileUtils.normalize(initialPath);

  /// 只读文件系统访问。
  final FileRepository repository;

  /// 全局设置（隐藏项、视图模式、排序持久化）。
  final SettingsController settings;

  /// 是否为左列。
  final bool isLeft;

  final List<String> _history = <String>[];
  int _historyIndex = -1;

  String _path;
  List<FileEntry> _entries = const <FileEntry>[];
  int _hiddenCount = 0;
  bool _loading = false;
  String? _error;
  int _loadToken = 0;
  bool _disposed = false;

  /// 当前选中路径集合。
  final Set<String> _selection = <String>{};

  /// 最近一次被点击的路径，用于「范围选择」锚点。
  String? _anchorPath;

  /// 目录内条目统计（异步填充，用于状态栏）。
  final Map<String, int> _childCounts = <String, int>{};

  // ---------------------------------------------------------------- 只读状态

  /// 当前目录绝对路径。
  String get path => _path;

  /// 当前目录名。
  String get title => FileUtils.baseName(_path);

  /// 当前目录条目（已排序，未过滤隐藏项 —— 过滤在 [visibleEntries]）。
  List<FileEntry> get entries => _entries;

  /// 被隐藏的条目数。
  int get hiddenCount => _hiddenCount;

  /// 是否正在加载。
  bool get loading => _loading;

  /// 加载错误；成功时为 null。
  String? get error => _error;

  /// 当前选中数量。
  int get selectionCount => _selection.length;

  /// 是否有选中项。
  bool get hasSelection => _selection.isNotEmpty;

  /// 选中路径的不可变副本。
  Set<String> get selection => Set<String>.unmodifiable(_selection);

  /// 当前排序规则。
  SortSpec get sort => isLeft ? settings.leftSort : settings.rightSort;

  /// 当前视图模式。
  ViewMode get viewMode => settings.viewMode;

  /// 是否显示隐藏项。
  bool get showHidden => settings.showHidden;

  /// 是否可以后退。
  bool get canGoBack => _historyIndex > 0;

  /// 是否可以前进。
  bool get canGoForward => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  /// 是否已在根目录。
  bool get isAtRoot => _path == AppConstants.rootPath;

  /// 是否可以返回上级。
  bool get canGoUp => !isAtRoot;

  /// 面包屑路径段（从根到当前目录）。
  List<BreadcrumbSegment> get breadcrumbs {
    final List<BreadcrumbSegment> segments = <BreadcrumbSegment>[];
    if (_path == AppConstants.rootPath) {
      return <BreadcrumbSegment>[
        BreadcrumbSegment(name: '/', path: AppConstants.rootPath),
      ];
    }
    segments.add(BreadcrumbSegment(name: '/', path: AppConstants.rootPath));
    final List<String> parts = _path.split('/').where((String part) => part.isNotEmpty).toList();
    String accumulated = '';
    for (final String part in parts) {
      accumulated = '$accumulated/$part';
      segments.add(BreadcrumbSegment(name: part, path: accumulated));
    }
    return segments;
  }

  /// 应用隐藏项过滤后的可见条目。
  ///
  /// 每次访问都会重建列表，因此调用方应缓存到局部变量后再用于构建。
  List<FileEntry> get visibleEntries {
    if (showHidden) {
      return _entries;
    }
    return _entries.where((FileEntry entry) => !entry.isHidden).toList(growable: false);
  }

  /// 目录中选中项占用的总字节数。
  int get selectedBytes {
    int total = 0;
    for (final FileEntry entry in _entries) {
      if (_selection.contains(entry.path) && !entry.isDirectory) {
        total += entry.size;
      }
    }
    return total;
  }

  /// 已选中的条目列表。
  List<FileEntry> get selectedEntries =>
      _entries.where((FileEntry entry) => _selection.contains(entry.path)).toList();

  /// 目录的已知子项数量；未统计时返回 null。
  int? childCountOf(String path) => _childCounts[path];

  // ------------------------------------------------------------------ 导航

  /// 首次加载（不写入历史）。
  Future<void> initialize() async {
    await _load(_path, pushHistory: true, resetHistory: true);
  }

  /// 打开目录（写入历史）。
  Future<void> open(String target) async {
    final String normalized = FileUtils.normalize(target);
    if (normalized == _path) {
      await refresh();
      return;
    }
    await _load(normalized, pushHistory: true);
  }

  /// 进入子目录。
  Future<void> openChild(FileEntry entry) async {
    if (!entry.isDirectory) {
      return;
    }
    await open(entry.path);
  }

  /// 返回上级目录。
  Future<void> goUp() async {
    if (!canGoUp) {
      return;
    }
    await open(FileUtils.parentOf(_path));
  }

  /// 后退。
  Future<void> goBack() async {
    if (!canGoBack) {
      return;
    }
    _historyIndex--;
    await _load(_history[_historyIndex], pushHistory: false);
  }

  /// 前进。
  Future<void> goForward() async {
    if (!canGoForward) {
      return;
    }
    _historyIndex++;
    await _load(_history[_historyIndex], pushHistory: false);
  }

  /// 跳回根目录。
  Future<void> goRoot() => open(AppConstants.rootPath);

  /// 刷新当前目录，保留选择集中仍然存在的条目。
  Future<void> refresh() async {
    await _load(_path, pushHistory: false);
  }

  /// 重新排序当前列表（不重新读取目录）。
  void applySort(SortSpec spec) {
    final List<FileEntry> sorted = List<FileEntry>.of(_entries);
    spec.apply(sorted);
    _entries = sorted;
    _notify();
  }

  /// 切换排序字段。
  Future<void> toggleSort(SortField field) async {
    final SortSpec next = sort.toggle(field);
    applySort(next);
    if (isLeft) {
      await settings.setLeftSort(next);
    } else {
      await settings.setRightSort(next);
    }
  }

  // ------------------------------------------------------------------ 加载

  /// 加载目录内容。
  Future<void> _load(
    String target, {
    required bool pushHistory,
    bool resetHistory = false,
  }) async {
    final String normalized = FileUtils.normalize(target);
    final int token = ++_loadToken;

    _loading = true;
    _error = null;
    _notify();

    final DirectoryListing listing = await repository.listDirectory(
      normalized,
      showHidden: true,
      sort: sort,
    );

    // 竞态保护：期间又发起了新的加载，丢弃本次结果。
    if (token != _loadToken || _disposed) {
      return;
    }

    if (!listing.isOk) {
      _loading = false;
      _error = listing.error;
      _entries = const <FileEntry>[];
      _hiddenCount = 0;
      _selection.clear();
      _notify();
      return;
    }

    _path = normalized;
    _entries = listing.entries;
    _hiddenCount = listing.hiddenCount;
    _loading = false;
    _error = null;
    _anchorPath = null;
    _pruneSelection();

    if (resetHistory) {
      _history
        ..clear()
        ..add(normalized);
      _historyIndex = 0;
    } else if (pushHistory) {
      // 截断前进分支后再追加。
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      if (_history.isEmpty || _history.last != normalized) {
        _history.add(normalized);
        _historyIndex = _history.length - 1;
      }
    } else if (_historyIndex >= 0 && _historyIndex < _history.length) {
      _history[_historyIndex] = normalized;
    }

    await settings.setPanePath(isLeft: isLeft, path: normalized);
    _notify();
    unawaited(_prefetchChildCounts());
  }

  /// 移除已不存在的选择项，避免刷新后残留幽灵选中。
  void _pruneSelection() {
    if (_selection.isEmpty) {
      return;
    }
    final Set<String> alive = _entries.map((FileEntry entry) => entry.path).toSet();
    _selection.removeWhere((String path) => !alive.contains(path));
  }

  /// 后台统计目录子项数量，用于「包含 N 项」提示。
  ///
  /// 只统计当前可见的目录，且限制并发，避免拖慢主线程。
  Future<void> _prefetchChildCounts() async {
    final List<FileEntry> directories = _entries
        .where((FileEntry entry) => entry.isDirectory && entry.isReadable)
        .take(AppConstants.statConcurrency)
        .toList();
    if (directories.isEmpty) {
      return;
    }
    bool changed = false;
    for (final FileEntry directory in directories) {
      if (_disposed || _path != FileUtils.parentOf(directory.path)) {
        return;
      }
      if (_childCounts.containsKey(directory.path)) {
        continue;
      }
      final int count = await repository.countChildren(directory.path, showHidden: true);
      if (_disposed) {
        return;
      }
      _childCounts[directory.path] = count;
      changed = true;
    }
    if (changed && !_disposed) {
      _notify();
    }
  }

  // ------------------------------------------------------------------ 选择

  /// 判断某路径是否选中。
  bool isSelected(String path) => _selection.contains(path);

  /// 切换单个条目的选中状态。
  void toggleSelection(String path) {
    if (!_selection.remove(path)) {
      _selection.add(path);
      _anchorPath = path;
    }
    _notify();
  }

  /// 选中单个条目（清空其他选择）。
  void selectOnly(String path) {
    _selection
      ..clear()
      ..add(path);
    _anchorPath = path;
    _notify();
  }

  /// 处理点击：支持长按多选模式下的范围选择。
  ///
  /// [shift] 为 true 时从锚点到目标做范围选择。
  void selectRange(String path, {bool additive = false}) {
    final List<FileEntry> visible = visibleEntries;
    final int targetIndex = visible.indexWhere((FileEntry entry) => entry.path == path);
    if (targetIndex < 0) {
      return;
    }
    if (!additive) {
      _selection.clear();
    }
    final String? anchor = _anchorPath;
    if (anchor == null) {
      _selection.add(path);
      _anchorPath = path;
      _notify();
      return;
    }
    final int anchorIndex = visible.indexWhere((FileEntry entry) => entry.path == anchor);
    if (anchorIndex < 0) {
      _selection.add(path);
      _anchorPath = path;
      _notify();
      return;
    }
    final int start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final int end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    for (int i = start; i <= end; i++) {
      _selection.add(visible[i].path);
    }
    _notify();
  }

  /// 全选当前可见条目。
  void selectAll() {
    for (final FileEntry entry in visibleEntries) {
      _selection.add(entry.path);
    }
    _notify();
  }

  /// 反选。
  void invertSelection() {
    final Set<String> inverted = <String>{};
    for (final FileEntry entry in visibleEntries) {
      if (!_selection.contains(entry.path)) {
        inverted.add(entry.path);
      }
    }
    _selection
      ..clear()
      ..addAll(inverted);
    _notify();
  }

  /// 清空选择。
  void clearSelection() {
    if (_selection.isEmpty) {
      return;
    }
    _selection.clear();
    _anchorPath = null;
    _notify();
  }

  /// 选中指定路径集合。
  void setSelection(Iterable<String> paths) {
    _selection
      ..clear()
      ..addAll(paths);
    _notify();
  }

  // ------------------------------------------------------------------ 搜索

  /// 在当前目录下递归搜索。
  ///
  /// 返回一个单订阅流；调用方通过取消订阅停止搜索。
  Stream<SearchHit> search(
    String query, {
    bool useRegex = false,
    bool searchDirectories = true,
    bool Function()? isCancelled,
  }) {
    return repository.search(
      _path,
      query: query,
      useRegex: useRegex,
      showHidden: showHidden,
      searchDirectories: searchDirectories,
      isCancelled: isCancelled,
    );
  }

  // ------------------------------------------------------------------ 通知

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    super.dispose();
  }
}

/// 面包屑路径段。
class BreadcrumbSegment {
  const BreadcrumbSegment({required this.name, required this.path});

  final String name;
  final String path;

  /// 根目录段。
  bool get isRoot => path == AppConstants.rootPath;
}

/// 面板的轻量只读视图，供不需要写权限的组件使用。
class PaneSnapshot {
  const PaneSnapshot({
    required this.path,
    required this.title,
    required this.entries,
    required this.loading,
    required this.error,
    required this.selectionCount,
  });

  final String path;
  final String title;
  final List<FileEntry> entries;
  final bool loading;
  final String? error;
  final int selectionCount;
}

/// 用于在列表中快速查找条目的辅助容器。
///
/// 大目录（数千项）下按路径查找会比线性扫描快得多。
class EntryIndex {
  EntryIndex(Iterable<FileEntry> entries)
      : _map = HashMap<String, FileEntry>.fromEntries(
          entries.map((FileEntry entry) => MapEntry<String, FileEntry>(entry.path, entry)),
        );

  final HashMap<String, FileEntry> _map;

  FileEntry? operator [](String path) => _map[path];

  int get length => _map.length;

  Iterable<FileEntry> get values => _map.values;
}
