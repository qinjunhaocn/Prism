import 'package:flutter/material.dart';

import '../../data/models/file_entry.dart';
import '../../state/app_state.dart';
import '../../state/pane_controller.dart';
import '../../state/settings_controller.dart';

/// 单个面板的顶部工具栏。
///
/// 包含：导航按钮、路径标题、即时过滤框、排序菜单、视图切换、新建、搜索。
class PaneToolbar extends StatefulWidget {
  const PaneToolbar({
    required this.appState,
    required this.pane,
    required this.isLeft,
    required this.filterQuery,
    required this.onFilterChanged,
    required this.onCreate,
    required this.onSearch,
    super.key,
  });

  final AppState appState;
  final PaneController pane;
  final bool isLeft;
  final String filterQuery;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onCreate;
  final VoidCallback onSearch;

  @override
  State<PaneToolbar> createState() => _PaneToolbarState();
}

class _PaneToolbarState extends State<PaneToolbar> {
  late final TextEditingController _filterController;
  bool _filtering = false;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(text: widget.filterQuery);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 切换过滤输入框的显示状态。
  void _toggleFilter() {
    setState(() {
      _filtering = !_filtering;
      if (!_filtering) {
        _filterController.clear();
        widget.onFilterChanged('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PaneController pane = widget.pane;
    final bool isActive = widget.appState.activeIsLeft == widget.isLeft;

    return Material(
      color: isActive ? scheme.surfaceContainerLow : Colors.transparent,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                _NavButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '后退',
                  onPressed: pane.canGoBack ? pane.goBack : null,
                ),
                _NavButton(
                  icon: Icons.arrow_forward_rounded,
                  tooltip: '前进',
                  onPressed: pane.canGoForward ? pane.goForward : null,
                ),
                _NavButton(
                  icon: Icons.arrow_upward_rounded,
                  tooltip: '上级目录',
                  onPressed: pane.canGoUp ? pane.goUp : null,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.appState.setActive(isLeft: widget.isLeft),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        pane.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isActive ? scheme.primary : scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                _NavButton(
                  icon: _filtering ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
                  tooltip: _filtering ? '关闭过滤' : '过滤当前目录',
                  onPressed: _toggleFilter,
                ),
                _SortMenu(appState: widget.appState, pane: pane),
                _ViewModeToggle(appState: widget.appState),
                _NavButton(
                  icon: Icons.create_new_folder_rounded,
                  tooltip: '新建',
                  onPressed: widget.onCreate,
                ),
                _NavButton(
                  icon: Icons.search_rounded,
                  tooltip: '搜索',
                  onPressed: widget.onSearch,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          if (_filtering)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _filterController,
                autofocus: true,
                onChanged: widget.onFilterChanged,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '过滤当前目录的文件名',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _filterController.clear();
                      widget.onFilterChanged('');
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 紧凑型导航按钮。
class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 20,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}

/// 排序菜单。
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.appState, required this.pane});

  final AppState appState;
  final PaneController pane;

  @override
  Widget build(BuildContext context) {
    final SortSpec current = pane.sort;
    return PopupMenuButton<SortField>(
      tooltip: '排序方式',
      icon: Icon(_iconFor(current), size: 20),
      padding: EdgeInsets.zero,
      onSelected: pane.toggleSort,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<SortField>>[
        for (final SortField field in SortField.values)
          PopupMenuItem<SortField>(
            value: field,
            child: Row(
              children: <Widget>[
                Icon(
                  current.field == field
                      ? (current.isAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                      : Icons.remove_rounded,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(_labelFor(field)),
              ],
            ),
          ),
      ],
    );
  }

  /// 当前排序字段的图标。
  IconData _iconFor(SortSpec spec) {
    final IconData base = switch (spec.field) {
      SortField.name => Icons.sort_by_alpha_rounded,
      SortField.size => Icons.data_usage_rounded,
      SortField.modified => Icons.schedule_rounded,
      SortField.type => Icons.category_rounded,
    };
    return base;
  }

  /// 排序字段中文名。
  String _labelFor(SortField field) => switch (field) {
        SortField.name => '按名称',
        SortField.size => '按大小',
        SortField.modified => '按修改时间',
        SortField.type => '按类型',
      };
}

/// 列表/网格视图切换。
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final ViewMode mode = appState.settings.viewMode;
    return IconButton(
      onPressed: () {
        appState.settings.setViewMode(
          mode == ViewMode.list ? ViewMode.grid : ViewMode.list,
        );
      },
      icon: Icon(
        mode == ViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded,
        size: 20,
      ),
      tooltip: mode == ViewMode.list ? '切换为网格' : '切换为列表',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}
