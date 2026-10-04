import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 通用文本输入对话框。
///
/// 返回用户确认的文本；取消返回 null。
Future<String?> promptForName({
  required BuildContext context,
  required String title,
  required String hint,
  String initial = '',
  String? helper,
  bool allowEmpty = false,
}) async {
  final TextEditingController controller = TextEditingController(text: initial);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: initial.length,
  );

  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: hint, helperText: helper),
          onSubmitted: (String value) {
            Navigator.of(context).pop(value.trim());
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      );
    },
  );

  controller.dispose();
  if (result == null) {
    return null;
  }
  if (result.isEmpty && !allowEmpty) {
    return null;
  }
  return result;
}

/// 新建条目菜单：返回文件夹或文件的标记，取消返回 null。
Future<String?> showCreateEntrySheet({required BuildContext context}) async {
  return showModalBottomSheet<String>(
    context: context,
    builder: (BuildContext context) {
      final ColorScheme scheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: <Widget>[
                  Text('新建', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.create_new_folder_rounded, color: scheme.primary),
              title: const Text('新建文件夹'),
              onTap: () => Navigator.of(context).pop('__prism_new_folder__'),
            ),
            ListTile(
              leading: Icon(Icons.note_add_rounded, color: scheme.tertiary),
              title: const Text('新建空文件'),
              onTap: () => Navigator.of(context).pop('__prism_new_file__'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// 确认对话框；用户确认返回 true。
Future<bool> confirmAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 批量重命名对话框。
///
/// 支持两种模式：查找替换、添加前后缀。返回 `旧路径 -> 新名称` 的映射。
Future<Map<String, String>?> showBatchRenameDialog({
  required BuildContext context,
  required List<String> names,
  required List<String> paths,
}) async {
  if (names.length != paths.length || names.isEmpty) {
    return null;
  }

  final TextEditingController findController = TextEditingController();
  final TextEditingController replaceController = TextEditingController();
  final TextEditingController prefixController = TextEditingController();
  final TextEditingController suffixController = TextEditingController();
  bool useRegex = false;
  int mode = 0; // 0 = 查找替换，1 = 添加前后缀

  final Map<String, String>? result = await showDialog<Map<String, String>>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocalState) {
          /// 计算某个原名对应的新名。
          String transform(String name) {
            if (mode == 0) {
              final String find = findController.text;
              if (find.isEmpty) {
                return name;
              }
              if (useRegex) {
                try {
                  return name.replaceAll(RegExp(find), replaceController.text);
                } on FormatException {
                  return name;
                }
              }
              return name.replaceAll(find, replaceController.text);
            }
            return '${prefixController.text}$name${suffixController.text}';
          }

          return AlertDialog(
            title: const Text('批量重命名'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 0, label: Text('查找替换')),
                        ButtonSegment<int>(value: 1, label: Text('前后缀')),
                      ],
                      selected: <int>{mode},
                      onSelectionChanged: (Set<int> value) {
                        setLocalState(() => mode = value.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (mode == 0) ...<Widget>[
                      TextField(
                        controller: findController,
                        decoration: const InputDecoration(
                          labelText: '查找',
                          isDense: true,
                        ),
                        onChanged: (_) => setLocalState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: replaceController,
                        decoration: const InputDecoration(
                          labelText: '替换为',
                          isDense: true,
                        ),
                        onChanged: (_) => setLocalState(() {}),
                      ),
                      SwitchListTile(
                        value: useRegex,
                        onChanged: (bool value) {
                          setLocalState(() => useRegex = value);
                        },
                        title: const Text('使用正则表达式'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ] else ...<Widget>[
                      TextField(
                        controller: prefixController,
                        decoration: const InputDecoration(
                          labelText: '前缀',
                          isDense: true,
                        ),
                        onChanged: (_) => setLocalState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: suffixController,
                        decoration: const InputDecoration(
                          labelText: '后缀（加在扩展名之前）',
                          isDense: true,
                        ),
                        onChanged: (_) => setLocalState(() {}),
                      ),
                    ],
                    const Divider(height: 24),
                    Text(
                      '预览',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < names.length && i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${names[i]}  →  ${transform(names[i])}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (names.length > 5)
                      Text(
                        '… 共 ${names.length} 项',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final Map<String, String> mapping = <String, String>{};
                  for (int i = 0; i < names.length; i++) {
                    final String next = transform(names[i]);
                    if (next.isNotEmpty && next != names[i]) {
                      mapping[paths[i]] = next;
                    }
                  }
                  Navigator.of(context).pop(mapping);
                },
                child: const Text('应用'),
              ),
            ],
          );
        },
      );
    },
  );

  findController.dispose();
  replaceController.dispose();
  prefixController.dispose();
  suffixController.dispose();
  return result;
}

/// 在剪贴板中复制文本并提示。
Future<void> copyToSystemClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
}
