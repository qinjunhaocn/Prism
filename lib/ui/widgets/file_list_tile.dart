import 'package:flutter/material.dart';

import '../../core/file_utils.dart';
import '../../core/formatters.dart';
import '../../data/models/file_entry.dart';
import '../../data/thumbnail_cache.dart';
import '../../state/settings_controller.dart';
import 'file_icon.dart';
import 'file_thumbnail.dart';

/// 列表行高度随密度设置变化。
///
/// 取值需容纳「主标题 + 副标题」两行文本（含 1.4 倍字体缩放下的余量），
/// 否则在固定 `itemExtent` 下会发生 RenderFlex 溢出。
double listItemHeightFor(int density) => switch (density) {
      0 => 56,
      2 => 76,
      _ => 64,
    };

/// 列表模式下的单行条目。
///
/// 使用 [RepaintBoundary] 隔离每一行，滚动时避免整列表重绘。
class FileListTile extends StatelessWidget {
  const FileListTile({
    required this.entry,
    required this.cache,
    required this.settings,
    required this.selected,
    required this.multiSelectMode,
    required this.onTap,
    required this.onLongPress,
    this.onMore,
    this.searchMatchStart,
    this.searchMatchEnd,
    this.childCount,
    super.key,
  });

  final FileEntry entry;
  final ThumbnailCache cache;
  final SettingsController settings;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMore;
  final int? searchMatchStart;
  final int? searchMatchEnd;
  final int? childCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int density = settings.listDensity;
    final double iconSize = switch (density) {
      0 => 32,
      2 => 44,
      _ => 40,
    };

    final Color? background = selected ? scheme.secondaryContainer : null;

    return RepaintBoundary(
      child: Material(
        color: background ?? Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onMore,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: density == 0 ? 6 : 10,
            ),
            child: Row(
              children: <Widget>[
                if (multiSelectMode) ...<Widget>[
                  _SelectionIndicator(selected: selected),
                  const SizedBox(width: 8),
                ],
                FileThumbnail(
                  entry: entry,
                  cache: cache,
                  settings: settings,
                  size: iconSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: HighlightedName(
                              text: entry.name,
                              matchStart: searchMatchStart,
                              matchEnd: searchMatchEnd,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          for (final IconData badge in FileVisuals.permissionBadges(entry))
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                badge,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // 副标题允许被压缩，保证极端字体缩放下也不溢出。
                      Flexible(
                        child: Text(
                          _subtitle(),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onMore != null)
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(Icons.more_vert_rounded),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    tooltip: '更多',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 副标题：目录显示项数，文件显示大小与修改时间。
  String _subtitle() {
    if (entry.isDirectory) {
      final int? count = childCount;
      final String countText = count == null ? '目录' : '$count 项';
      if (!entry.isReadable) {
        return '$countText · 无访问权限';
      }
      return '$countText · ${Formatters.relativeTime(entry.modified)}';
    }
    final String size = Formatters.fileSize(entry.size);
    final String time = Formatters.relativeTime(entry.modified);
    final String ext = entry.extension.toUpperCase();
    if (ext.isEmpty) {
      return '$size · $time';
    }
    return '$size · $ext · $time';
  }
}

/// 网格模式下的单元。
class FileGridTile extends StatelessWidget {
  const FileGridTile({
    required this.entry,
    required this.cache,
    required this.settings,
    required this.selected,
    required this.multiSelectMode,
    required this.onTap,
    required this.onLongPress,
    this.onMore,
    this.searchMatchStart,
    this.searchMatchEnd,
    super.key,
  });

  final FileEntry entry;
  final ThumbnailCache cache;
  final SettingsController settings;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMore;
  final int? searchMatchStart;
  final int? searchMatchEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return RepaintBoundary(
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onMore,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: FileThumbnail(
                          entry: entry,
                          cache: cache,
                          settings: settings,
                          size: 56,
                        ),
                      ),
                      if (multiSelectMode)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: _SelectionIndicator(selected: selected),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                HighlightedName(
                  text: entry.name,
                  matchStart: searchMatchStart,
                  matchEnd: searchMatchEnd,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 多选状态指示圆点。
class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
          : null,
    );
  }
}

/// 空目录 / 错误 / 加载中的占位视图。
class PanePlaceholder extends StatelessWidget {
  const PanePlaceholder({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 供列表展示的条目元信息文本。
String describeEntry(FileEntry entry, {int? childCount}) {
  if (entry.isDirectory) {
    return childCount == null ? '目录' : '$childCount 项';
  }
  final String ext = entry.extension;
  final String kind = ext.isEmpty ? '文件' : '${ext.toUpperCase()} 文件';
  return '$kind · ${Formatters.fileSize(entry.size)}';
}

/// 生成条目的一行式路径描述。
String describePath(String path) => FileUtils.normalize(path);
