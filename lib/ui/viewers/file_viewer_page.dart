import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/file_utils.dart';
import '../../core/formatters.dart';
import '../../data/file_repository.dart';
import '../../data/models/file_entry.dart';

/// 内置文件查看器。
///
/// 支持图片缩放查看与文本预览；其它类型提示使用外部应用打开。
class FileViewerPage extends StatefulWidget {
  const FileViewerPage({
    required this.entry,
    required this.repository,
    super.key,
  });

  final FileEntry entry;
  final FileRepository repository;

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  /// 文本内容；仅文本模式加载。
  String? _text;
  bool _loadingText = false;
  String? _textError;

  /// 文本预览是否被截断（文件大于读取上限）。
  bool _truncated = false;

  /// 图片缩放变换控制器。
  final TransformationController _transformController = TransformationController();

  bool get _isImage => FileUtils.isDecodableImage(widget.entry.name);
  bool get _isText => FileUtils.isTextLike(widget.entry.name);

  @override
  void initState() {
    super.initState();
    if (_isText) {
      _loadText();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// 加载文本内容。
  Future<void> _loadText() async {
    setState(() {
      _loadingText = true;
      _textError = null;
    });

    final String? content = await widget.repository.readTextPreview(widget.entry.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingText = false;
      if (content == null) {
        _textError = '无法读取该文件，可能不是文本或没有访问权限';
      } else {
        _text = content;
        _truncated = widget.entry.size > content.length;
      }
    });
  }

  /// 重置图片缩放。
  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.entry.name,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              Formatters.fileSize(widget.entry.size),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          if (_isImage)
            IconButton(
              onPressed: _resetZoom,
              icon: const Icon(Icons.center_focus_strong_rounded),
              tooltip: '重置缩放',
            ),
          if (_isText)
            IconButton(
              onPressed: _loadText,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新加载',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isImage) {
      return _buildImage();
    }
    if (_isText) {
      return _buildText();
    }
    return _buildUnsupported();
  }

  /// 图片视图：支持双指缩放与拖动。
  Widget _buildImage() {
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 8,
      boundaryMargin: const EdgeInsets.all(64),
      child: Center(
        child: Image.file(
          File(widget.entry.path),
          fit: BoxFit.contain,
          // 大图按屏幕尺寸解码，避免内存暴涨。
          cacheWidth: 2048,
          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
            return _buildUnsupported(message: '无法解码该图片');
          },
        ),
      ),
    );
  }

  /// 文本视图：等宽字体 + 可选复制。
  Widget _buildText() {
    if (_loadingText) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _textError;
    if (error != null) {
      return _buildUnsupported(message: error);
    }
    final String content = _text ?? '';
    if (content.isEmpty) {
      return const Center(child: Text('文件为空'));
    }

    return Column(
      children: <Widget>[
        if (_truncated)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '文件较大，仅显示开头部分内容',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onTertiaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 不支持的类型提示。
  Widget _buildUnsupported({String? message}) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? '暂不支持内置预览此类型文件',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '可使用「打开方式」交给系统应用处理',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 读取文件字节的工具（供未来扩展，例如十六进制查看）。
Future<Uint8List?> readBytes(String path, {int? limit}) async {
  try {
    final File file = File(path);
    if (limit == null) {
      return await file.readAsBytes();
    }
    final RandomAccessFile handle = await file.open();
    try {
      return Uint8List.fromList(await handle.read(limit));
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    return null;
  }
}
