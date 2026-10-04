import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/file_operations.dart';
import '../../state/app_state.dart';
import '../../state/file_clipboard.dart';
import '../../state/pane_controller.dart';

/// 底部操作栏。
///
/// 两种形态：
/// * 有进行中的操作时显示进度与取消按钮；
/// * 否则显示剪贴板状态与「粘贴到当前列」入口。
class FileActionBar extends StatelessWidget {
  const FileActionBar({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final OperationProgress? progress = appState.progress;
    if (progress != null) {
      return _buildProgress(context, progress);
    }
    return _buildClipboard(context);
  }

  /// 进度条形态。
  Widget _buildProgress(BuildContext context, OperationProgress progress) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double? byteRatio = progress.byteRatio;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${progress.title} ${progress.currentItem}/${progress.totalItems}',
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    byteRatio != null
                        ? '${(byteRatio * 100).toStringAsFixed(0)}%'
                        : '${(progress.itemRatio * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelMedium,
                  ),
                  IconButton(
                    onPressed: appState.cancelOperation,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: '取消',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: byteRatio ?? progress.itemRatio,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  progress.bytesTotal > 0
                      ? '${Formatters.fileSize(progress.bytesDone)} / '
                          '${Formatters.fileSize(progress.bytesTotal)}'
                      : progress.currentPath,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 剪贴板形态。
  Widget _buildClipboard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final FileClipboard clipboard = appState.clipboard;
    final PaneController target = appState.activePane;
    final bool isCut = clipboard.action == ClipboardAction.cut;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: <Widget>[
              Icon(
                isCut ? Icons.content_cut_rounded : Icons.copy_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${clipboard.describe()}，粘贴到「${target.title}」',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: clipboard.clear,
                child: const Text('取消'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final OperationResult? result = await appState.pasteInto(target);
                  if (!context.mounted || result == null) {
                    return;
                  }
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(result.describe())));
                },
                child: const Text('粘贴'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
