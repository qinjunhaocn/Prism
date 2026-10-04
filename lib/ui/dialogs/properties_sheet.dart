import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/file_utils.dart';
import '../../core/formatters.dart';
import '../../data/file_repository.dart';
import '../../data/models/file_entry.dart';
import '../../data/native_bridge.dart';
import 'input_dialogs.dart';

/// 显示文件/文件夹属性面板。
///
/// 目录会异步递归统计大小，展示实时进度，可中途取消。
Future<void> showPropertiesSheet({
  required BuildContext context,
  required FileEntry entry,
  required FileRepository repository,
  required NativeBridge bridge,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return _PropertiesSheet(
        entry: entry,
        repository: repository,
        bridge: bridge,
      );
    },
  );
}

class _PropertiesSheet extends StatefulWidget {
  const _PropertiesSheet({
    required this.entry,
    required this.repository,
    required this.bridge,
  });

  final FileEntry entry;
  final FileRepository repository;
  final NativeBridge bridge;

  @override
  State<_PropertiesSheet> createState() => _PropertiesSheetState();
}

class _PropertiesSheetState extends State<_PropertiesSheet> {
  /// 目录统计结果；null 表示尚未统计。
  int? _totalBytes;
  int? _fileCount;
  int? _directoryCount;
  bool _scanning = false;
  bool _cancelled = false;
  String? _mimeType;

  @override
  void initState() {
    super.initState();
    if (!widget.entry.isDirectory) {
      _loadMimeType();
    }
  }

  Future<void> _loadMimeType() async {
    final String? mime = await widget.bridge.mimeTypeOf(widget.entry.path);
    if (!mounted || mime == null) {
      return;
    }
    setState(() => _mimeType = mime);
  }

  /// 递归统计目录大小。
  Future<void> _scan() async {
    if (_scanning) {
      return;
    }
    setState(() {
      _scanning = true;
      _cancelled = false;
    });

    int bytes = 0;
    int files = 0;
    int directories = 0;

    final int total = await widget.repository.directorySize(
      widget.entry.path,
      onProgress: (int currentBytes, int items) {
        if (!mounted) {
          return;
        }
        setState(() {
          _totalBytes = currentBytes;
          _fileCount = items;
        });
      },
      isCancelled: () => _cancelled,
    );

    if (!mounted) {
      return;
    }

    // 单独统计目录数量（directorySize 只累加文件）。
    if (!_cancelled) {
      directories = await _countDirectories(widget.entry.path);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      bytes = total;
      files = _fileCount ?? 0;
      _totalBytes = bytes;
      _fileCount = files;
      _directoryCount = directories;
      _scanning = false;
    });
  }

  /// 递归统计子目录数量。
  Future<int> _countDirectories(String path) async {
    int count = 0;
    final List<String> stack = <String>[path];
    while (stack.isNotEmpty) {
      if (_cancelled) {
        break;
      }
      final String current = stack.removeLast();
      try {
        await for (final FileSystemEntity entity in Directory(current).list(followLinks: false)) {
          try {
            final FileStat stat = await entity.stat();
            if (stat.type == FileSystemEntityType.directory) {
              count++;
              stack.add(entity.path);
            }
          } on FileSystemException {
            continue;
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final FileEntry entry = widget.entry;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    entry.isDirectory ? Icons.folder_rounded : Icons.description_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        entry.isDirectory ? '文件夹' : '文件',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _PropertyRow(label: '名称', value: entry.name, copyable: true),
            _PropertyRow(label: '路径', value: entry.path, copyable: true),
            if (!entry.isDirectory)
              _PropertyRow(label: '大小', value: Formatters.fileSize(entry.size))
            else
              _PropertyRow(
                label: '占用空间',
                value: _totalBytes == null
                    ? (_scanning ? '正在统计…' : '未统计')
                    : Formatters.fileSize(_totalBytes!),
              ),
            if (entry.isDirectory && _fileCount != null)
              _PropertyRow(label: '文件数', value: '${_fileCount!}'),
            if (entry.isDirectory && _directoryCount != null)
              _PropertyRow(label: '子文件夹', value: '${_directoryCount!}'),
            _PropertyRow(label: '修改时间', value: Formatters.dateTime(entry.modified)),
            _PropertyRow(
              label: '类型',
              value: entry.isDirectory
                  ? '目录'
                  : (entry.extension.isEmpty ? '未知' : entry.extension.toUpperCase()),
            ),
            if (_mimeType != null)
              _PropertyRow(label: 'MIME', value: _mimeType!, copyable: true),
            _PropertyRow(
              label: '权限',
              value: '${entry.isReadable ? '可读' : '不可读'} · '
                  '${entry.isWritable ? '可写' : '只读'}'
                  '${entry.isLink ? ' · 符号链接' : ''}',
            ),
            if (entry.linkTarget != null)
              _PropertyRow(label: '链接目标', value: entry.linkTarget!, copyable: true),
            if (entry.isDirectory) ...<Widget>[
              const SizedBox(height: 16),
              if (_scanning)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _cancelled = true),
                        child: const Text('停止统计'),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _scan,
                    icon: const Icon(Icons.calculate_rounded),
                    label: Text(_totalBytes == null ? '统计占用空间' : '重新统计'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 属性行。
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (copyable)
            IconButton(
              onPressed: () => copyToSystemClipboard(context, value),
              icon: const Icon(Icons.content_copy_rounded, size: 16),
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// 供外部使用的路径合法性检查（避免重复实现）。
bool isValidEntryName(String name) => FileUtils.isValidFileName(name);
