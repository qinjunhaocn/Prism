import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/file_utils.dart';
import '../../data/models/file_entry.dart';
import '../../data/thumbnail_cache.dart';
import '../../state/settings_controller.dart';
import 'file_icon.dart';

/// 文件缩略图。
///
/// 图片文件异步解码为缩略图；解码完成前与失败时回退到类型图标。
/// 该组件订阅 [ThumbnailCache.updates]，但只在收到自身路径时重建，
/// 避免全列表因单张图片就绪而整体刷新。
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    required this.entry,
    required this.cache,
    required this.settings,
    this.size = 40,
    super.key,
  });

  final FileEntry entry;
  final ThumbnailCache cache;
  final SettingsController settings;
  final double size;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  ui.Image? _image;
  StreamSubscription<String>? _subscription;

  /// 是否应该尝试生成缩略图。
  bool get _eligible =>
      widget.settings.thumbnailsEnabled &&
      !widget.entry.isDirectory &&
      widget.entry.size > 0 &&
      FileUtils.isDecodableImage(widget.entry.name);

  @override
  void initState() {
    super.initState();
    _image = widget.cache.get(widget.entry.path);
    _subscribeIfNeeded();
  }

  /// 仅在需要解码时订阅缓存更新，并在切换条目时先取消旧订阅。
  void _subscribeIfNeeded() {
    _subscription?.cancel();
    _subscription = null;
    if (_image != null || !_eligible) {
      return;
    }
    _subscription = widget.cache.updates.listen(_onCacheUpdate);
    _requestLoad();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _image = widget.cache.get(widget.entry.path);
      _subscribeIfNeeded();
      if (_image != null && mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _requestLoad() {
    // 小图片才值得解码，超过 64 MB 的直接跳过以免 OOM。
    if (widget.entry.size > 64 * 1024 * 1024) {
      return;
    }
    widget.cache.load(widget.entry.path);
  }

  void _onCacheUpdate(String path) {
    if (!mounted || path != widget.entry.path) {
      return;
    }
    final ui.Image? image = widget.cache.get(path);
    if (image == null) {
      return;
    }
    setState(() {
      _image = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.size * 0.22),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RawImage(
            image: image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }
    return FileIcon(entry: widget.entry, size: widget.size);
  }
}

/// 条目名称文本：匹配搜索关键词时高亮。
class HighlightedName extends StatelessWidget {
  const HighlightedName({
    required this.text,
    this.matchStart,
    this.matchEnd,
    this.style,
    this.maxLines = 1,
    super.key,
  });

  final String text;
  final int? matchStart;
  final int? matchEnd;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int? start = matchStart;
    final int? end = matchEnd;
    final TextStyle baseStyle = style ?? Theme.of(context).textTheme.bodyMedium!;

    if (start == null || end == null || start < 0 || end > text.length || start >= end) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
            ),
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      style: baseStyle,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 供外部判断文件是否具备可预览内容。
bool canPreview(FileEntry entry) {
  if (entry.isDirectory) {
    return true;
  }
  if (FileUtils.isDecodableImage(entry.name)) {
    return true;
  }
  if (FileUtils.isTextLike(entry.name)) {
    return true;
  }
  return false;
}

/// 读取文件前若干字节判断是否为文本（用于无扩展名文件）。
Future<bool> looksLikeText(String path) async {
  try {
    final RandomAccessFile handle = await File(path).open();
    try {
      final List<int> bytes = await handle.read(512);
      if (bytes.isEmpty) {
        return true;
      }
      int suspicious = 0;
      for (final int byte in bytes) {
        if (byte == 0) {
          return false;
        }
        final bool printable =
            byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte < 127) || byte >= 128;
        if (!printable) {
          suspicious++;
        }
      }
      return suspicious / bytes.length < 0.1;
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    return false;
  }
}
