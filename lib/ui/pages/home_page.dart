import 'package:flutter/material.dart';

import '../../core/app_constants.dart';
import '../../core/file_utils.dart';
import '../../core/formatters.dart';
import '../../data/file_operations.dart';
import '../../data/models/device_info.dart';
import '../../data/storage_permission.dart';
import '../../state/app_state.dart';
import '../../state/pane_controller.dart';
import '../panes/file_pane_view.dart';
import '../widgets/file_action_bar.dart';
import 'settings_page.dart';

/// 双列文件管理器主界面。
///
/// 布局策略：
/// * 窄屏（手机竖屏）：一次显示一列，通过顶部 SegmentedButton 切换左右列，
///   切换时保留各自路径与选择状态，因此仍是「双列」语义。
/// * 宽屏（横屏/平板，宽度 ≥ [AppConstants.wideLayoutBreakpoint]）：两列并排。
class HomePage extends StatefulWidget {
  const HomePage({required this.appState, super.key});

  final AppState appState;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 窄屏下当前显示的列。
  bool _showLeftOnNarrow = true;

  /// 抽屉控制器（存储卷与书签）。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 存储权限协调器。
  final StoragePermissionService _permissions = const StoragePermissionService();

  /// 是否已经检查过权限（避免每次重建都弹窗）。
  bool _permissionChecked = false;

  AppState get _appState => widget.appState;

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermissions());
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 首次进入时检查存储权限；不足则引导用户授权。
  Future<void> _ensurePermissions() async {
    if (_permissionChecked || !mounted) {
      return;
    }
    _permissionChecked = true;

    if (await _permissions.hasFullAccess()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final StoragePermissionStatus status = await _permissions.request();
    if (!mounted) {
      return;
    }

    switch (status) {
      case StoragePermissionStatus.granted:
      case StoragePermissionStatus.notRequired:
        await _appState.refreshVolumes();
        await _appState.left.refresh();
        await _appState.right.refresh();
      case StoragePermissionStatus.limited:
        _showPermissionBanner(
          '当前仅有部分媒体访问权限，部分目录可能无法读写。',
          showSettingsAction: true,
        );
      case StoragePermissionStatus.denied:
      case StoragePermissionStatus.permanentlyDenied:
        _showPermissionBanner(
          '缺少存储访问权限，无法浏览和修改文件。请在系统设置中开启「所有文件访问权限」。',
          showSettingsAction: true,
        );
    }
  }

  /// 用 SnackBar 展示权限提示，并提供跳转设置的入口。
  void _showPermissionBanner(String message, {required bool showSettingsAction}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
          action: showSettingsAction
              ? SnackBarAction(
                  label: '去设置',
                  onPressed: _permissions.openSettings,
                )
              : null,
        ),
      );
  }

  /// 打开设置页。
  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SettingsPage(appState: _appState),
      ),
    );
  }

  /// 退出多选模式。
  void _exitMultiSelect() {
    _appState.exitMultiSelect();
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= AppConstants.wideLayoutBreakpoint;
    final bool multiSelect = _appState.multiSelectMode;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: multiSelect
            ? IconButton(
                onPressed: _exitMultiSelect,
                icon: const Icon(Icons.close_rounded),
                tooltip: '退出多选',
              )
            : IconButton(
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu_rounded),
                tooltip: '存储与书签',
              ),
        title: multiSelect
            ? Text('已选择 ${_appState.activePane.selectionCount} 项')
            : const Text(AppConstants.appName),
        actions: <Widget>[
          if (multiSelect) ...<Widget>[
            IconButton(
              onPressed: () => _appState.activePane.selectAll(),
              icon: const Icon(Icons.select_all_rounded),
              tooltip: '全选',
            ),
            IconButton(
              onPressed: () => _appState.activePane.invertSelection(),
              icon: const Icon(Icons.flip_to_back_rounded),
              tooltip: '反选',
            ),
          ] else ...<Widget>[
            IconButton(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
              tooltip: '设置',
            ),
          ],
        ],
      ),
      drawer: _StorageDrawer(
        appState: _appState,
        onOpenPath: (String path) {
          final PaneController pane = _appState.activePane;
          Navigator.of(context).pop();
          pane.open(path);
        },
      ),
      body: wide ? _buildWideLayout() : _buildNarrowLayout(),
      bottomNavigationBar: multiSelect ? null : _buildBottomBar(),
      floatingActionButton: _buildFab(),
    );
  }

  /// 宽屏：左右并排。
  Widget _buildWideLayout() {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilePaneView(
            appState: _appState,
            pane: _appState.left,
            isLeft: true,
          ),
        ),
        Expanded(
          child: FilePaneView(
            appState: _appState,
            pane: _appState.right,
            isLeft: false,
            showDivider: false,
          ),
        ),
      ],
    );
  }

  /// 窄屏：单列 + 顶部列切换。
  Widget _buildNarrowLayout() {
    final PaneController pane = _showLeftOnNarrow ? _appState.left : _appState.right;
    final bool isLeft = _showLeftOnNarrow;

    return Column(
      children: <Widget>[
        _PaneSwitcher(
          showLeft: _showLeftOnNarrow,
          leftTitle: _appState.left.title,
          rightTitle: _appState.right.title,
          onChanged: (bool left) {
            setState(() => _showLeftOnNarrow = left);
            _appState.setActive(isLeft: left);
          },
        ),
        Expanded(
          child: FilePaneView(
            key: ValueKey<bool>(isLeft),
            appState: _appState,
            pane: pane,
            isLeft: isLeft,
            showDivider: false,
          ),
        ),
      ],
    );
  }

  /// 底部操作栏：显示剪贴板状态与粘贴入口。
  Widget? _buildBottomBar() {
    if (_appState.clipboard.isEmpty && _appState.progress == null) {
      return null;
    }
    return FileActionBar(appState: _appState);
  }

  /// 浮动按钮：快速粘贴（有剪贴板内容时）。
  Widget? _buildFab() {
    if (_appState.clipboard.isEmpty || _appState.multiSelectMode || _appState.isBusy) {
      return null;
    }
    return FloatingActionButton.extended(
      onPressed: () async {
        final PaneController pane = _appState.activePane;
        final OperationResult? result = await _appState.pasteInto(pane);
        if (!mounted || result == null) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.describe())));
      },
      icon: const Icon(Icons.content_paste_rounded),
      label: Text('粘贴到「${_appState.activePane.title}」'),
    );
  }
}

/// 窄屏下的左右列切换器。
class _PaneSwitcher extends StatelessWidget {
  const _PaneSwitcher({
    required this.showLeft,
    required this.leftTitle,
    required this.rightTitle,
    required this.onChanged,
  });

  final bool showLeft;
  final String leftTitle;
  final String rightTitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: true,
              icon: const Icon(Icons.view_sidebar_rounded, size: 18),
              label: Text(
                leftTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: const Icon(Icons.view_sidebar_outlined, size: 18),
              label: Text(
                rightTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: <bool>{showLeft},
          onSelectionChanged: (Set<bool> value) => onChanged(value.first),
        ),
      ),
    );
  }
}

/// 存储卷与书签抽屉。
class _StorageDrawer extends StatelessWidget {
  const _StorageDrawer({required this.appState, required this.onOpenPath});

  final AppState appState;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<ShortcutEntry> shortcuts = appState.shortcuts();
    final List<String> bookmarks = appState.settings.bookmarks;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.diamond_rounded, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(AppConstants.appName, style: theme.textTheme.titleMedium),
                      Text('双列文件管理器', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DrawerSectionTitle(title: '存储设备'),
            for (final StorageVolume volume in appState.volumes)
              _StorageTile(
                volume: volume,
                onTap: () => onOpenPath(volume.path),
              ),
            const Divider(height: 24),
            _DrawerSectionTitle(title: '常用位置'),
            for (final ShortcutEntry shortcut in shortcuts)
              ListTile(
                leading: Icon(
                  switch (shortcut.icon) {
                    ShortcutIcon.storage => Icons.smartphone_rounded,
                    ShortcutIcon.sdCard => Icons.sd_card_rounded,
                    ShortcutIcon.folder => Icons.folder_rounded,
                  },
                  color: scheme.primary,
                ),
                title: Text(shortcut.label),
                subtitle: Text(
                  shortcut.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () => onOpenPath(shortcut.path),
              ),
            if (bookmarks.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              _DrawerSectionTitle(title: '书签'),
              for (final String path in bookmarks)
                ListTile(
                  leading: Icon(Icons.bookmark_rounded, color: scheme.tertiary),
                  title: Text(FileUtils.baseName(path)),
                  subtitle: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: '移除书签',
                    onPressed: () => appState.settings.removeBookmark(path),
                  ),
                  onTap: () => onOpenPath(path),
                ),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.home_rounded),
              title: const Text('回到根目录'),
              onTap: () => onOpenPath(AppConstants.rootPath),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('将当前目录加入书签'),
              onTap: () async {
                await appState.settings.addBookmark(appState.activePane.path);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('已加入书签')),
                    );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 抽屉分组标题。
class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// 存储卷条目：显示容量进度。
class _StorageTile extends StatelessWidget {
  const _StorageTile({required this.volume, required this.onTap});

  final StorageVolume volume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool known = volume.totalBytes > 0;

    return ListTile(
      leading: Icon(
        volume.isRemovable ? Icons.sd_card_rounded : Icons.smartphone_rounded,
        color: scheme.primary,
      ),
      title: Text(volume.label.isEmpty ? volume.path : volume.label),
      subtitle: known
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: volume.usedRatio,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Formatters.fileSize(volume.freeBytes)} 可用 / '
                  '${Formatters.fileSize(volume.totalBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            )
          : Text(
              volume.path,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: onTap,
    );
  }
}
