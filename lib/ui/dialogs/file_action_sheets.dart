import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/file_utils.dart';
import '../../core/formatters.dart';
import '../../data/file_operations.dart';
import '../../data/models/file_entry.dart';
import '../../state/app_state.dart';
import '../../state/file_clipboard.dart';
import '../../state/pane_controller.dart';
import '../viewers/file_viewer_page.dart';
import 'input_dialogs.dart';
import 'properties_sheet.dart';

/// 显示选中条目的操作面板（底部弹出）。
///
/// 这是文件管理器的核心交互入口，功能对齐 MT 管理器：
/// 打开 / 复制 / 剪切 / 删除 / 重命名 / 分享 / 属性 / 复制路径 /
/// 跨列复制与移动 / 批量重命名。
///
/// 上下文安全：面板关闭后原 `BuildContext` 可能已失效，因此所有后续动作
/// 都通过预先捕获的 [ScaffoldMessengerState]、[NavigatorState] 以及带
/// `mounted` 守卫的页面上下文完成。
Future<void> showFileActionSheet({
  required BuildContext context,
  required AppState appState,
  required PaneController pane,
  FileEntry? anchor,
}) async {
  if (!pane.hasSelection) {
    return;
  }
  final List<FileEntry> selected = pane.selectedEntries;
  if (selected.isEmpty) {
    return;
  }
  final FileEntry primary = anchor ?? selected.first;
  final bool single = selected.length == 1;
  final bool allDirectories = selected.every((FileEntry entry) => entry.isDirectory);

  // 预先捕获，避免依赖可能失效的面板上下文。
  final BuildContext pageContext = context;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(pageContext);
  final NavigatorState navigator = Navigator.of(pageContext);

  await showModalBottomSheet<void>(
    context: pageContext,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _SheetHeader(
                title: single ? primary.name : '已选择 ${selected.length} 项',
                subtitle: _subtitleFor(selected, primary),
                icon: primary.isDirectory
                    ? Icons.folder_rounded
                    : Icons.insert_drive_file_rounded,
              ),
              const Divider(height: 1),
              Wrap(
                children: <Widget>[
                  if (single && !primary.isDirectory)
                    _ActionChip(
                      icon: Icons.open_in_new_rounded,
                      label: '打开',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openEntry(appState, primary, navigator, messenger);
                      },
                    ),
                  _ActionChip(
                    icon: Icons.copy_rounded,
                    label: '复制',
                    onTap: () {
                      appState.clipboard.setFromEntries(selected, ClipboardAction.copy);
                      Navigator.of(sheetContext).pop();
                      _toast(messenger, '已复制 ${selected.length} 项到剪贴板');
                    },
                  ),
                  _ActionChip(
                    icon: Icons.content_cut_rounded,
                    label: '剪切',
                    onTap: () {
                      appState.clipboard.setFromEntries(selected, ClipboardAction.cut);
                      Navigator.of(sheetContext).pop();
                      _toast(messenger, '已剪切 ${selected.length} 项');
                    },
                  ),
                  _ActionChip(
                    icon: Icons.drive_file_move_rounded,
                    label: '移动到另一列',
                    onTap: () => _confirmThenClose(
                      sheetContext: sheetContext,
                      pageContext: pageContext,
                      title: '移动到另一列',
                      message: '把选中的 ${selected.length} 项移动到另一列当前目录？',
                      action: () async {
                        final OperationResult? result =
                            await appState.transferSelectionToOtherPane(pane, move: true);
                        _reportResult(messenger, result);
                      },
                    ),
                  ),
                  _ActionChip(
                    icon: Icons.copy_all_rounded,
                    label: '复制到另一列',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaitedAction(() async {
                        final OperationResult? result =
                            await appState.transferSelectionToOtherPane(pane, move: false);
                        _reportResult(messenger, result);
                      });
                    },
                  ),
                  if (single)
                    _ActionChip(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: '重命名',
                      onTap: () => _promptThenClose(
                        sheetContext: sheetContext,
                        pageContext: pageContext,
                        title: '重命名',
                        hint: '新名称',
                        initial: primary.name,
                        action: (String name) async {
                          if (name == primary.name) {
                            return;
                          }
                          final OperationResult result =
                              await appState.renameEntry(pane, primary, name);
                          _reportResult(messenger, result);
                        },
                      ),
                    ),
                  if (!single)
                    _ActionChip(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: '批量重命名',
                      onTap: () => _batchRenameThenClose(
                        sheetContext: sheetContext,
                        pageContext: pageContext,
                        selected: selected,
                        appState: appState,
                        pane: pane,
                        messenger: messenger,
                      ),
                    ),
                  _ActionChip(
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    destructive: true,
                    onTap: () {
                      final String message = allDirectories
                          ? '将递归删除 ${selected.length} 个文件夹及其全部内容，此操作不可撤销。'
                          : '将删除 ${selected.length} 项，此操作不可撤销。';
                      if (!appState.settings.confirmDelete) {
                        Navigator.of(sheetContext).pop();
                        unawaitedAction(() async {
                          final OperationResult? result =
                              await appState.deleteSelection(pane);
                          _reportResult(messenger, result);
                        });
                        return;
                      }
                      _confirmThenClose(
                        sheetContext: sheetContext,
                        pageContext: pageContext,
                        title: '删除确认',
                        message: message,
                        confirmLabel: '删除',
                        destructive: true,
                        action: () async {
                          final OperationResult? result =
                              await appState.deleteSelection(pane);
                          _reportResult(messenger, result);
                        },
                      );
                    },
                  ),
                  if (single)
                    _ActionChip(
                      icon: Icons.share_rounded,
                      label: '分享',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaitedAction(() async {
                          final bool ok = await appState.bridge.shareFile(
                            primary.path,
                            mimeType: FileUtils.mimeTypeOf(primary.name),
                          );
                          if (!ok) {
                            _toast(messenger, '分享失败');
                          }
                        });
                      },
                    ),
                  if (single)
                    _ActionChip(
                      icon: Icons.info_outline_rounded,
                      label: '属性',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        unawaitedAction(() async {
                          if (!pageContext.mounted) {
                            return;
                          }
                          await showPropertiesSheet(
                            context: pageContext,
                            entry: primary,
                            repository: appState.repository,
                            bridge: appState.bridge,
                          );
                        });
                      },
                    ),
                  _ActionChip(
                    icon: Icons.link_rounded,
                    label: '复制路径',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaitedAction(() async {
                        final String text =
                            selected.map((FileEntry e) => e.path).join('\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        _toast(messenger, '已复制路径');
                      });
                    },
                  ),
                  _ActionChip(
                    icon: Icons.checklist_rounded,
                    label: '全选',
                    onTap: () {
                      pane.selectAll();
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  _ActionChip(
                    icon: Icons.deselect_rounded,
                    label: '取消选择',
                    onTap: () {
                      pane.clearSelection();
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// 在面板仍然打开时弹出确认框，确认后关闭面板并执行动作。
///
/// 顺序很关键：先弹对话框（面板上下文此时有效），再关闭面板。
void _confirmThenClose({
  required BuildContext sheetContext,
  required BuildContext pageContext,
  required String title,
  required String message,
  required Future<void> Function() action,
  String confirmLabel = '确定',
  bool destructive = false,
}) {
  unawaitedAction(() async {
    final bool ok = await confirmAction(
      context: sheetContext,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (!sheetContext.mounted) {
      return;
    }
    Navigator.of(sheetContext).pop();
    if (ok) {
      await action();
    }
  });
}

/// 在面板仍然打开时弹出输入框，确认后关闭面板并执行动作。
void _promptThenClose({
  required BuildContext sheetContext,
  required BuildContext pageContext,
  required String title,
  required String hint,
  required String initial,
  required Future<void> Function(String value) action,
}) {
  unawaitedAction(() async {
    final String? value = await promptForName(
      context: sheetContext,
      title: title,
      hint: hint,
      initial: initial,
    );
    if (!sheetContext.mounted) {
      return;
    }
    Navigator.of(sheetContext).pop();
    if (value != null && value.isNotEmpty) {
      await action(value);
    }
  });
}

/// 批量重命名流程。
void _batchRenameThenClose({
  required BuildContext sheetContext,
  required BuildContext pageContext,
  required List<FileEntry> selected,
  required AppState appState,
  required PaneController pane,
  required ScaffoldMessengerState? messenger,
}) {
  unawaitedAction(() async {
    final Map<String, String>? mapping = await showBatchRenameDialog(
      context: sheetContext,
      names: selected.map((FileEntry entry) => entry.name).toList(),
      paths: selected.map((FileEntry entry) => entry.path).toList(),
    );
    if (!sheetContext.mounted) {
      return;
    }
    Navigator.of(sheetContext).pop();
    if (mapping == null || mapping.isEmpty) {
      return;
    }
    final OperationResult result = await appState.batchRename(pane, mapping);
    _reportResult(messenger, result);
  });
}

/// 显式忽略返回的 Future，表达「有意不等待」。
///
/// 接收一个返回 Future 的闭包并立即执行，异常统一兜底，
/// 避免未捕获的异步错误导致红屏或日志噪音。
void unawaitedAction(Future<void> Function() action) {
  action().catchError((Object error) {
    // 动作内部已处理可预期错误，这里只兜底避免未捕获异常。
  });
}

/// 打开单个条目。
///
/// 可内置预览的交给 [FileViewerPage]，其余走系统「打开方式」。
Future<void> _openEntry(
  AppState appState,
  FileEntry entry,
  NavigatorState navigator,
  ScaffoldMessengerState? messenger,
) async {
  if (entry.isDirectory) {
    return;
  }
  if (FileUtils.isDecodableImage(entry.name) || FileUtils.isTextLike(entry.name)) {
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => FileViewerPage(
          entry: entry,
          repository: appState.repository,
        ),
      ),
    );
    return;
  }
  final bool ok = await appState.bridge.openFile(
    entry.path,
    mimeType: FileUtils.mimeTypeOf(entry.name),
  );
  if (!ok) {
    _toast(messenger, '无法打开该文件，可能没有关联的应用');
  }
}

/// 展示操作结果。
void _reportResult(ScaffoldMessengerState? messenger, OperationResult? result) {
  if (result == null) {
    return;
  }
  if (result.failed.isEmpty) {
    _toast(messenger, result.describe());
    return;
  }
  final String firstReason = result.failed.values.first;
  _toast(messenger, '${result.describe()}（$firstReason）');
}

/// 轻提示。
void _toast(ScaffoldMessengerState? messenger, String message) {
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 面板头部：图标 + 名称 + 摘要。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 生成选中项的摘要文字。
String _subtitleFor(List<FileEntry> selected, FileEntry primary) {
  if (selected.length == 1) {
    if (primary.isDirectory) {
      return '文件夹 · ${Formatters.relativeTime(primary.modified)}';
    }
    return '${Formatters.fileSize(primary.size)} · ${Formatters.relativeTime(primary.modified)}';
  }
  int directories = 0;
  int bytes = 0;
  for (final FileEntry entry in selected) {
    if (entry.isDirectory) {
      directories++;
    } else {
      bytes += entry.size;
    }
  }
  final String sizeText = bytes > 0 ? ' · ${Formatters.fileSize(bytes)}' : '';
  return '$directories 个文件夹，${selected.length - directories} 个文件$sizeText';
}

/// 操作面板中的方形按钮。
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color foreground = destructive ? scheme.error : scheme.onSurfaceVariant;

    return SizedBox(
      width: 96,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: destructive
                      ? scheme.errorContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 22,
                  color: destructive ? scheme.onErrorContainer : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
