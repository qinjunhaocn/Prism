import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_constants.dart';
import '../core/file_utils.dart';
import '../data/file_operations.dart';
import '../data/file_repository.dart';
import '../data/models/device_info.dart';
import '../data/models/file_entry.dart';
import '../data/native_bridge.dart';
import '../data/thumbnail_cache.dart';
import 'file_clipboard.dart';
import 'pane_controller.dart';
import 'settings_controller.dart';

/// 双列文件管理器的总控状态。
///
/// 负责：
/// * 持有左右两个 [PaneController] 与共享的剪贴板、缩略图缓存；
/// * 协调跨面板操作（复制到另一列、移动到另一列）；
/// * 维护存储卷列表与设备信息；
/// * 暴露正在进行的操作进度，供 UI 展示。
class AppState extends ChangeNotifier {
  AppState(
    this._left,
    this._right, {
    required this.settings,
    required this.repository,
    required this.operations,
    required this.bridge,
    required this.clipboard,
    required this.thumbnails,
  });

  /// 构造并初始化全部状态。
  ///
  /// 首次启动时左右两列分别落到「内部存储」与「根目录」，
  /// 之后使用上次退出时的路径。
  static Future<AppState> create({
    required SettingsController settings,
    NativeBridge? bridge,
  }) async {
    final NativeBridge nativeBridge = bridge ?? NativeBridge();
    const FileRepository repository = FileRepository();
    const FileOperationService operations = FileOperationService();
    final ThumbnailCache thumbnails = ThumbnailCache();
    final FileClipboard clipboard = FileClipboard();

    final List<StorageVolume> volumes = await nativeBridge.listStorageVolumes();
    final String defaultLeft = _defaultLeftPath(volumes);
    final String defaultRight = _defaultRightPath(volumes);

    final PaneController left = PaneController(
      repository: repository,
      settings: settings,
      isLeft: true,
      initialPath: _resolveStartPath(settings.leftPath, volumes, defaultLeft),
    );
    final PaneController right = PaneController(
      repository: repository,
      settings: settings,
      isLeft: false,
      initialPath: _resolveStartPath(settings.rightPath, volumes, defaultRight),
    );

    final AppState state = AppState(
      left,
      right,
      settings: settings,
      repository: repository,
      operations: operations,
      bridge: nativeBridge,
      clipboard: clipboard,
      thumbnails: thumbnails,
    );

    state._volumes = volumes;
    await Future.wait<void>(<Future<void>>[left.initialize(), right.initialize()]);
    await state.refreshDeviceInfo();
    return state;
  }

  final SettingsController settings;
  final FileRepository repository;
  final FileOperationService operations;
  final NativeBridge bridge;
  final FileClipboard clipboard;
  final ThumbnailCache thumbnails;

  final PaneController _left;
  final PaneController _right;

  List<StorageVolume> _volumes = const <StorageVolume>[];
  RefreshRateInfo? _refreshRate;
  int _androidSdk = 0;

  /// 当前活跃面板（最后一次交互的列）。
  bool _activeIsLeft = true;

  /// 正在进行的操作进度；空闲时为 null。
  OperationProgress? _progress;

  /// 当前操作的取消令牌。
  CancellationToken? _token;

  /// 是否处于多选模式（由长按进入）。
  bool _multiSelectMode = false;

  // ---------------------------------------------------------------- 只读状态

  /// 左侧面板。
  PaneController get left => _left;

  /// 右侧面板。
  PaneController get right => _right;

  /// 存储卷列表。
  List<StorageVolume> get volumes => List<StorageVolume>.unmodifiable(_volumes);

  /// 刷新率信息。
  RefreshRateInfo? get refreshRate => _refreshRate;

  /// Android SDK 版本。
  int get androidSdk => _androidSdk;

  /// 当前活跃面板。
  PaneController get activePane => _activeIsLeft ? _left : _right;

  /// 非活跃面板（跨列操作的目标）。
  PaneController get inactivePane => _activeIsLeft ? _right : _left;

  /// 活跃面板是否为左列。
  bool get activeIsLeft => _activeIsLeft;

  /// 是否处于多选模式。
  bool get multiSelectMode => _multiSelectMode;

  /// 是否有操作在进行。
  bool get isBusy => _progress != null;

  /// 当前操作进度。
  OperationProgress? get progress => _progress;

  /// 按 [isLeft] 取面板。
  PaneController pane(bool isLeft) => isLeft ? _left : _right;

  // ------------------------------------------------------------------ 交互

  /// 标记某列为活跃列。
  void setActive({required bool isLeft}) {
    if (_activeIsLeft == isLeft) {
      return;
    }
    _activeIsLeft = isLeft;
    notifyListeners();
  }

  /// 进入多选模式。
  void enterMultiSelect() {
    if (_multiSelectMode) {
      return;
    }
    _multiSelectMode = true;
    notifyListeners();
  }

  /// 退出多选模式并清空选择。
  void exitMultiSelect() {
    _multiSelectMode = false;
    _left.clearSelection();
    _right.clearSelection();
    notifyListeners();
  }

  /// 刷新存储卷信息（容量可能随时间变化）。
  Future<void> refreshVolumes() async {
    _volumes = await bridge.listStorageVolumes();
    notifyListeners();
  }

  /// 读取刷新率与 SDK 版本。
  Future<void> refreshDeviceInfo() async {
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      bridge.refreshRateInfo(),
      bridge.androidSdkInt(),
    ]);
    _refreshRate = results[0] as RefreshRateInfo?;
    _androidSdk = (results[1] as int?) ?? 0;
    notifyListeners();
  }

  /// 请求设备最高刷新率。
  Future<double?> requestMaxRefreshRate() async {
    final double? hz = await bridge.requestMaxRefreshRate();
    await refreshDeviceInfo();
    return hz;
  }

  // ------------------------------------------------------------------ 剪贴板

  /// 复制选中项到剪贴板。
  void copySelection(PaneController pane) {
    if (!pane.hasSelection) {
      return;
    }
    clipboard.setFromEntries(pane.selectedEntries, ClipboardAction.copy);
    notifyListeners();
  }

  /// 剪切选中项到剪贴板。
  void cutSelection(PaneController pane) {
    if (!pane.hasSelection) {
      return;
    }
    clipboard.setFromEntries(pane.selectedEntries, ClipboardAction.cut);
    notifyListeners();
  }

  /// 把剪贴板内容粘贴到指定面板的当前目录。
  Future<OperationResult?> pasteInto(PaneController pane) async {
    if (clipboard.isEmpty) {
      return null;
    }
    final List<String> sources = clipboard.paths;
    final bool isCut = clipboard.action == ClipboardAction.cut;
    final OperationResult result = await _runTransfer(
      sources: sources,
      destinationDir: pane.path,
      move: isCut,
    );
    if (isCut && result.succeeded > 0) {
      clipboard.clear();
    }
    await pane.refresh();
    return result;
  }

  /// 直接复制/移动选中项到另一个面板（无需先复制到剪贴板）。
  Future<OperationResult?> transferSelectionToOtherPane(
    PaneController source, {
    required bool move,
  }) async {
    if (!source.hasSelection) {
      return null;
    }
    final PaneController target = identical(source, _left) ? _right : _left;
    final List<String> sources = source.selectedEntries.map((FileEntry e) => e.path).toList();
    final OperationResult result = await _runTransfer(
      sources: sources,
      destinationDir: target.path,
      move: move,
    );
    await source.refresh();
    await target.refresh();
    return result;
  }

  /// 删除选中项。
  Future<OperationResult?> deleteSelection(PaneController pane) async {
    if (!pane.hasSelection) {
      return null;
    }
    final List<String> targets = pane.selectedEntries.map((FileEntry e) => e.path).toList();
    final CancellationToken token = CancellationToken();
    _token = token;
    _progress = OperationProgress(
      title: '正在删除',
      currentItem: 0,
      totalItems: targets.length,
      currentPath: '',
      bytesDone: 0,
      bytesTotal: 0,
    );
    notifyListeners();

    try {
      final OperationResult result = await operations.delete(
        paths: targets,
        token: token,
        onProgress: _updateProgress,
      );
      pane.clearSelection();
      await pane.refresh();
      return result;
    } finally {
      _finishOperation();
    }
  }

  /// 重命名单个条目。
  Future<OperationResult> renameEntry(PaneController pane, FileEntry entry, String newName) async {
    final Map<String, String> failed = <String, String>{};
    int succeeded = 0;
    try {
      await operations.rename(entry.path, newName);
      succeeded = 1;
    } on FileSystemException catch (error) {
      failed[entry.path] = error.message.isEmpty ? '重命名失败' : error.message;
    }
    await pane.refresh();
    return OperationResult(succeeded: succeeded, failed: failed, cancelled: false);
  }

  /// 批量重命名。
  Future<OperationResult> batchRename(PaneController pane, Map<String, String> renames) async {
    final OperationResult result = await operations.batchRename(renames);
    await pane.refresh();
    return result;
  }

  /// 新建文件夹。
  Future<String?> createDirectory(PaneController pane, String name) async {
    try {
      final String path = await operations.createDirectory(pane.path, name);
      await pane.refresh();
      return path;
    } on FileSystemException {
      return null;
    }
  }

  /// 新建文件。
  Future<String?> createFile(PaneController pane, String name, {String content = ''}) async {
    try {
      final String path = await operations.createFile(pane.path, name, content: content);
      await pane.refresh();
      return path;
    } on FileSystemException {
      return null;
    }
  }

  /// 取消当前操作。
  void cancelOperation() {
    _token?.cancel();
  }

  /// 执行一次传输操作（复制或移动）。
  Future<OperationResult> _runTransfer({
    required List<String> sources,
    required String destinationDir,
    required bool move,
  }) async {
    final CancellationToken token = CancellationToken();
    _token = token;
    _progress = OperationProgress(
      title: move ? '正在移动' : '正在复制',
      currentItem: 0,
      totalItems: sources.length,
      currentPath: '',
      bytesDone: 0,
      bytesTotal: 0,
    );
    notifyListeners();

    try {
      final OperationResult result = await operations.transfer(
        sources: sources,
        destinationDir: destinationDir,
        move: move,
        token: token,
        onProgress: _updateProgress,
      );
      return result;
    } finally {
      _finishOperation();
    }
  }

  void _updateProgress(OperationProgress progress) {
    _progress = progress;
    notifyListeners();
  }

  void _finishOperation() {
    _progress = null;
    _token = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ 工具

  /// 默认起始路径：优先内部存储，其次根目录。
  static String _defaultLeftPath(List<StorageVolume> volumes) {
    for (final StorageVolume volume in volumes) {
      if (volume.isPrimary) {
        return volume.path;
      }
    }
    return AppConstants.primaryStoragePath;
  }

  /// 右列默认落在根目录，方便访问全盘。
  ///
  /// 根目录不可读时退回主存储，避免启动即报错。
  static String _defaultRightPath(List<StorageVolume> volumes) {
    if (Directory(AppConstants.rootPath).existsSync()) {
      return AppConstants.rootPath;
    }
    return _defaultLeftPath(volumes);
  }

  /// 校验持久化路径是否仍然可用；不可用则回退默认值。
  static String _resolveStartPath(
    String? saved,
    List<StorageVolume> volumes,
    String fallback,
  ) {
    if (saved == null || saved.isEmpty) {
      return fallback;
    }
    final String normalized = FileUtils.normalize(saved);
    try {
      if (Directory(normalized).existsSync()) {
        return normalized;
      }
    } on FileSystemException {
      return fallback;
    }
    return fallback;
  }

  /// 常见快捷入口路径，用于侧边栏。
  List<ShortcutEntry> shortcuts() {
    final List<ShortcutEntry> items = <ShortcutEntry>[];
    for (final StorageVolume volume in _volumes) {
      items.add(ShortcutEntry(
        label: volume.label.isEmpty ? FileUtils.baseName(volume.path) : volume.label,
        path: volume.path,
        icon: volume.isRemovable ? ShortcutIcon.sdCard : ShortcutIcon.storage,
      ));
    }
    StorageVolume? primary;
    for (final StorageVolume volume in _volumes) {
      if (volume.isPrimary) {
        primary = volume;
        break;
      }
    }
    if (primary != null) {
      const List<(String, String)> common = <(String, String)>[
        ('下载', 'Download'),
        ('图片', 'Pictures'),
        ('相机', 'DCIM'),
        ('音乐', 'Music'),
        ('视频', 'Movies'),
        ('文档', 'Documents'),
      ];
      for (final (String label, String folder) in common) {
        final String path = p.posix.join(primary.path, folder);
        if (Directory(path).existsSync()) {
          items.add(ShortcutEntry(label: label, path: path, icon: ShortcutIcon.folder));
        }
      }
    }
    return items;
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    clipboard.dispose();
    unawaited(thumbnails.dispose());
    super.dispose();
  }
}

/// 快捷入口图标类别。
enum ShortcutIcon {
  storage,
  sdCard,
  folder,
}

/// 侧边栏快捷入口。
class ShortcutEntry {
  const ShortcutEntry({required this.label, required this.path, required this.icon});

  final String label;
  final String path;
  final ShortcutIcon icon;
}
