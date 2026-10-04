import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/app_constants.dart';
import '../../core/file_utils.dart';
import '../../data/models/file_entry.dart';
import '../../state/app_state.dart';
import '../../state/pane_controller.dart';
import '../../state/settings_controller.dart';
import '../dialogs/file_action_sheets.dart';
import '../dialogs/input_dialogs.dart';
import '../search/pane_search_page.dart';
import '../viewers/file_viewer_page.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/pane_toolbar.dart';

/// 单个文件面板（列）。
///
/// 一个面板包含：工具栏、面包屑、内容区（列表/网格）、状态栏。
/// 左右两列复用同一个 widget，只是绑定的 [PaneController] 不同。
class FilePaneView extends StatefulWidget {
  const FilePaneView({
    required this.appState,
    required this.pane,
    required this.isLeft,
    this.showDivider = true,
    super.key,
  });

  final AppState appState;
  final PaneController pane;

  /// 是否为左列（用于激活态高亮与方向键语义）。
  final bool isLeft;

  /// 是否在右侧绘制分隔线（双列并排时使用）。
  final bool showDivider;

  @override
  State<FilePaneView> createState() => _FilePaneViewState();
}

class _FilePaneViewState extends State<FilePaneView> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'prism-pane');

  /// 当前搜索关键词（面板内即时过滤）。
  String _filterQuery = '';

  /// 最近一次点击的条目，用于「范围选择」。
  FileEntry? _lastTapped;

  PaneController get _pane => widget.pane;

  @override
  void initState() {
    super.initState();
    _pane.addListener(_onPaneChanged);
  }

  @override
  void dispose() {
    _pane.removeListener(_onPaneChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPaneChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 应用面板内即时过滤后的条目。
  List<FileEntry> _visibleEntries() {
    final List<FileEntry> entries = _pane.visibleEntries;
    if (_filterQuery.isEmpty) {
      return entries;
    }
    final String needle = _filterQuery.toLowerCase();
    return entries
        .where((FileEntry entry) => entry.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  // -------------------------------------------------------------- 点击处理

  /// 处理条目点击。
  Future<void> _onEntryTap(FileEntry entry) async {
    widget.appState.setActive(isLeft: widget.isLeft);

    // 多选模式：点击即切换选中。
    if (widget.appState.multiSelectMode) {
      _pane.toggleSelection(entry.path);
      _lastTapped = entry;
      return;
    }

    // 已有选择时点击其它项，视为调整选择范围。
    if (_pane.hasSelection) {
      if (_pane.selectionCount == 1 && _pane.isSelected(entry.path)) {
        _pane.clearSelection();
        _lastTapped = entry;
        return;
      }
      // 连续点击相邻项时做范围选择，贴近桌面文件管理器的操作手感。
      final FileEntry? previous = _lastTapped;
      if (previous != null &&
          previous.path != entry.path &&
          _pane.isSelected(previous.path)) {
        _pane.selectRange(entry.path, additive: true);
      } else {
        _pane.toggleSelection(entry.path);
      }
      _lastTapped = entry;
      return;
    }

    if (entry.isDirectory) {
      await _pane.openChild(entry);
      _resetScroll();
      return;
    }
    await _openFile(entry);
  }

  /// 处理长按：进入多选模式并选中。
  void _onEntryLongPress(FileEntry entry) {
    widget.appState.setActive(isLeft: widget.isLeft);
    widget.appState.enterMultiSelect();
    _pane.toggleSelection(entry.path);
    _lastTapped = entry;
    HapticFeedback.mediumImpact();
  }

  /// 打开文件：可预览的内置查看，其余交给系统。
  Future<void> _openFile(FileEntry entry) async {
    final bool canPreviewInApp =
        FileUtils.isDecodableImage(entry.name) || FileUtils.isTextLike(entry.name);
    if (canPreviewInApp) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => FileViewerPage(
            entry: entry,
            repository: widget.appState.repository,
          ),
        ),
      );
      return;
    }
    final bool ok = await widget.appState.bridge.openFile(
      entry.path,
      mimeType: FileUtils.mimeTypeOf(entry.name),
    );
    if (!ok && mounted) {
      _showSnack('无法打开该文件，可能没有关联的应用');
    }
  }

  /// 重置滚动位置到顶部。
  void _resetScroll() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------- 操作入口

  /// 显示条目的上下文操作菜单。
  Future<void> _showEntryActions(FileEntry entry) async {
    widget.appState.setActive(isLeft: widget.isLeft);
    if (!_pane.isSelected(entry.path)) {
      _pane.selectOnly(entry.path);
    }
    await showFileActionSheet(
      context: context,
      appState: widget.appState,
      pane: _pane,
      anchor: entry,
    );
  }

  /// 新建菜单。
  Future<void> _showCreateMenu() async {
    final String? result = await showCreateEntrySheet(context: context);
    if (result == null || !mounted) {
      return;
    }
    if (result == _createFolderToken) {
      final String? name = await promptForName(
        context: context,
        title: '新建文件夹',
        hint: '文件夹名称',
        initial: '新建文件夹',
      );
      if (name == null) {
        return;
      }
      final String? created = await widget.appState.createDirectory(_pane, name);
      if (!mounted) {
        return;
      }
      _showSnack(created == null ? '创建失败，可能已存在同名文件夹' : '已创建 ${FileUtils.baseName(created)}');
      return;
    }
    if (result == _createFileToken) {
      final String? name = await promptForName(
        context: context,
        title: '新建文件',
        hint: '文件名，例如 note.txt',
        initial: '新建文件.txt',
      );
      if (name == null) {
        return;
      }
      final String? created = await widget.appState.createFile(_pane, name);
      if (!mounted) {
        return;
      }
      _showSnack(created == null ? '创建失败，可能已存在同名文件' : '已创建 ${FileUtils.baseName(created)}');
    }
  }

  /// 打开搜索页。
  Future<void> _openSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PaneSearchPage(
          appState: widget.appState,
          pane: _pane,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = widget.appState.activeIsLeft == widget.isLeft;
    final List<FileEntry> entries = _visibleEntries();

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (bool focused) {
        if (focused) {
          widget.appState.setActive(isLeft: widget.isLeft);
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isActive ? scheme.surface : scheme.surfaceContainerLowest,
          border: widget.showDivider
              ? Border(right: BorderSide(color: scheme.outlineVariant))
              : null,
        ),
        child: Column(
          children: <Widget>[
            PaneToolbar(
              appState: widget.appState,
              pane: _pane,
              isLeft: widget.isLeft,
              filterQuery: _filterQuery,
              onFilterChanged: (String value) => setState(() => _filterQuery = value),
              onCreate: _showCreateMenu,
              onSearch: _openSearch,
            ),
            BreadcrumbBar(
              pane: _pane,
              onNavigate: (String path) {
                widget.appState.setActive(isLeft: widget.isLeft);
                _pane.open(path);
                _resetScroll();
              },
            ),
            Expanded(child: _buildContent(entries, isActive)),
            PaneStatusBar(pane: _pane, visibleCount: entries.length),
          ],
        ),
      ),
    );
  }

  /// 内容区：根据加载/错误/空/视图模式选择呈现方式。
  Widget _buildContent(List<FileEntry> entries, bool isActive) {
    if (_pane.error != null) {
      return PanePlaceholder(
        icon: Icons.lock_rounded,
        title: '无法访问该目录',
        subtitle: _pane.error,
        action: FilledButton.tonalIcon(
          onPressed: () => _pane.goUp(),
          icon: const Icon(Icons.arrow_upward_rounded),
          label: const Text('返回上级'),
        ),
      );
    }

    if (_pane.loading && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (entries.isEmpty) {
      final bool filtered = _filterQuery.isNotEmpty && _pane.entries.isNotEmpty;
      return PanePlaceholder(
        icon: filtered ? Icons.filter_alt_off_rounded : Icons.folder_open_rounded,
        title: filtered ? '没有匹配的条目' : '此文件夹为空',
        subtitle: filtered ? '试试其它关键词' : '长按条目可进入多选，右上角可新建',
      );
    }

    if (_pane.viewMode == ViewMode.grid) {
      return _buildGrid(entries, isActive);
    }
    return _buildList(entries, isActive);
  }

  /// 列表视图：固定行高让 ListView 走更快的布局路径。
  Widget _buildList(List<FileEntry> entries, bool isActive) {
    final double itemHeight = listItemHeightFor(widget.appState.settings.listDensity);
    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: entries.length,
        itemExtent: itemHeight,
        scrollCacheExtent: ScrollCacheExtent.pixels(itemHeight * 8),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (BuildContext context, int index) {
          final FileEntry entry = entries[index];
          return FileListTile(
            key: ValueKey<String>(entry.path),
            entry: entry,
            cache: widget.appState.thumbnails,
            settings: widget.appState.settings,
            selected: _pane.isSelected(entry.path),
            multiSelectMode: widget.appState.multiSelectMode,
            childCount: _pane.childCountOf(entry.path),
            onTap: () => _onEntryTap(entry),
            onLongPress: () => _onEntryLongPress(entry),
            onMore: () => _showEntryActions(entry),
          );
        },
      ),
    );
  }

  /// 网格视图：按可用宽度动态决定列数。
  Widget _buildGrid(List<FileEntry> entries, bool isActive) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth - 16;
        final int columns =
            (available / AppConstants.gridTileMinWidth).floor().clamp(2, 8);
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: AppConstants.gridTileMinWidth / AppConstants.gridTileExtent,
          ),
          itemCount: entries.length,
          itemBuilder: (BuildContext context, int index) {
            final FileEntry entry = entries[index];
            return FileGridTile(
              key: ValueKey<String>(entry.path),
              entry: entry,
              cache: widget.appState.thumbnails,
              settings: widget.appState.settings,
              selected: _pane.isSelected(entry.path),
              multiSelectMode: widget.appState.multiSelectMode,
              onTap: () => _onEntryTap(entry),
              onLongPress: () => _onEntryLongPress(entry),
              onMore: () => _showEntryActions(entry),
            );
          },
        );
      },
    );
  }
}

/// 新建菜单中的文件夹标记。
const String _createFolderToken = '__prism_new_folder__';

/// 新建菜单中的文件标记。
const String _createFileToken = '__prism_new_file__';
