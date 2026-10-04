import 'package:flutter/material.dart';

import '../../state/pane_controller.dart';

/// 可横向滚动的面包屑导航栏。
///
/// 当前目录段始终可见（自动滚动到末尾），前面的段可点击跳转，
/// 过长时折叠为省略号菜单。
class BreadcrumbBar extends StatefulWidget {
  const BreadcrumbBar({
    required this.pane,
    required this.onNavigate,
    this.trailing,
    super.key,
  });

  final PaneController pane;

  /// 点击某一段时回调（传入该段路径）。
  final ValueChanged<String> onNavigate;

  /// 右侧附加控件。
  final Widget? trailing;

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(BreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pane.path != widget.pane.path) {
      _scrollToEnd();
    }
  }

  /// 目录切换后把面包屑滚到最右，保证当前目录可见。
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<BreadcrumbSegment> segments = widget.pane.breadcrumbs;
    // 最多显示 4 段，超出部分折叠进「…」菜单。
    const int maxVisible = 4;
    final bool needsCollapse = segments.length > maxVisible;
    final List<BreadcrumbSegment> head = needsCollapse
        ? segments.sublist(0, 1)
        : segments;
    final List<BreadcrumbSegment> collapsed =
        needsCollapse ? segments.sublist(1, segments.length - maxVisible + 2) : <BreadcrumbSegment>[];
    final List<BreadcrumbSegment> tail =
        needsCollapse ? segments.sublist(segments.length - maxVisible + 2) : <BreadcrumbSegment>[];

    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  for (final BreadcrumbSegment segment in head)
                    _Crumb(
                      segment: segment,
                      isLast: !needsCollapse && segment == segments.last,
                      onTap: () => widget.onNavigate(segment.path),
                    ),
                  if (collapsed.isNotEmpty)
                    _CollapsedCrumbs(
                      segments: collapsed,
                      onNavigate: widget.onNavigate,
                    ),
                  for (final BreadcrumbSegment segment in tail)
                    _Crumb(
                      segment: segment,
                      isLast: segment == segments.last,
                      onTap: () => widget.onNavigate(segment.path),
                    ),
                ],
              ),
            ),
          ),
          if (widget.trailing != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: widget.trailing!,
            ),
        ],
      ),
    );
  }
}

/// 单个路径段。
class _Crumb extends StatelessWidget {
  const _Crumb({required this.segment, required this.isLast, required this.onTap});

  final BreadcrumbSegment segment;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        if (!segment.isRoot)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        InkWell(
          onTap: isLast ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: <Widget>[
                if (segment.isRoot)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.smartphone_rounded,
                      size: 16,
                      color: isLast ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  segment.isRoot ? '设备' : segment.name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isLast ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 折叠的中间路径段菜单。
class _CollapsedCrumbs extends StatelessWidget {
  const _CollapsedCrumbs({required this.segments, required this.onNavigate});

  final List<BreadcrumbSegment> segments;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
        PopupMenuButton<String>(
          tooltip: '展开路径',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_horiz_rounded, size: 20, color: scheme.onSurfaceVariant),
          onSelected: onNavigate,
          itemBuilder: (BuildContext context) => segments
              .map(
                (BreadcrumbSegment segment) => PopupMenuItem<String>(
                  value: segment.path,
                  child: Text(segment.name),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// 目录信息条：显示条目数与隐藏项数量。
class PaneStatusBar extends StatelessWidget {
  const PaneStatusBar({
    required this.pane,
    this.visibleCount,
    super.key,
  });

  final PaneController pane;
  final int? visibleCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int shown = visibleCount ?? pane.visibleEntries.length;
    final int total = pane.entries.length;

    final StringBuffer text = StringBuffer();
    text.write('$shown 项');
    if (total > shown) {
      text.write(' · 已隐藏 ${total - shown} 项');
    }
    if (pane.hasSelection) {
      text.write(' · 已选 ${pane.selectionCount} 项');
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toString(),
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pane.loading)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
