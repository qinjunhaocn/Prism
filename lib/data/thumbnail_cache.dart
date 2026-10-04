import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/app_constants.dart';
import '../core/file_utils.dart';

/// 缩略图缓存。
///
/// 使用 LRU 策略限制内存占用，并把解码宽度限制在
/// [AppConstants.thumbnailDecodeWidth] 以内，避免大图占满堆。
/// 解码在后台线程完成，不阻塞 UI isolate。
class ThumbnailCache {
  ThumbnailCache({this.maxEntries = 160});

  /// 最大缓存条目数。
  final int maxEntries;

  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap<String, ui.Image>();
  final Set<String> _pending = <String>{};
  final StreamController<String> _updates = StreamController<String>.broadcast();

  /// 缓存更新通知（参数为已就绪的路径）。
  Stream<String> get updates => _updates.stream;

  /// 当前缓存数量。
  int get length => _cache.length;

  /// 同步取图；未命中返回 null。
  ui.Image? get(String path) {
    final ui.Image? image = _cache.remove(path);
    if (image == null) {
      return null;
    }
    // 命中后重新插入到队尾，维持 LRU 顺序。
    _cache[path] = image;
    return image;
  }

  /// 是否正在解码。
  bool isPending(String path) => _pending.contains(path);

  /// 异步加载并解码缩略图；结果通过 [updates] 通知。
  ///
  /// 非图片、缓存已存在或已在解码中的请求会被忽略。
  Future<void> load(String path) async {
    if (_cache.containsKey(path) || _pending.contains(path)) {
      return;
    }
    if (!FileUtils.isDecodableImage(path)) {
      return;
    }
    _pending.add(path);
    try {
      final ui.Image? image = await _decode(path);
      if (image != null) {
        _put(path, image);
        if (!_updates.isClosed) {
          _updates.add(path);
        }
      }
    } finally {
      _pending.remove(path);
    }
  }

  /// 在后台 isolate 中解码并缩放到目标宽度。
  Future<ui.Image?> _decode(String path) async {
    try {
      final File file = File(path);
      if (!await file.exists()) {
        return null;
      }
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      // 先解析出原始尺寸，按需缩小后再生成最终纹理。
      final ui.Codec probe = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo probeFrame = await probe.getNextFrame();
      final int originalWidth = probeFrame.image.width;
      final int originalHeight = probeFrame.image.height;
      probeFrame.image.dispose();
      probe.dispose();

      if (originalWidth <= 0 || originalHeight <= 0) {
        return null;
      }

      final int targetWidth = originalWidth > AppConstants.thumbnailDecodeWidth
          ? AppConstants.thumbnailDecodeWidth
          : originalWidth;
      final int targetHeight =
          (originalHeight * (targetWidth / originalWidth)).round().clamp(1, 1 << 16);

      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      // 损坏图片、OOM 等情况一律降级为「无缩略图」。
      return null;
    }
  }

  /// 写入缓存并淘汰最旧条目。
  void _put(String path, ui.Image image) {
    final ui.Image? evicted = _cache.remove(path);
    evicted?.dispose();
    _cache[path] = image;
    while (_cache.length > maxEntries) {
      final String oldestKey = _cache.keys.first;
      final ui.Image? oldest = _cache.remove(oldestKey);
      oldest?.dispose();
    }
  }

  /// 清空缓存并释放纹理。
  void clear() {
    for (final ui.Image image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  /// 释放资源。
  Future<void> dispose() async {
    clear();
    await _updates.close();
  }
}
