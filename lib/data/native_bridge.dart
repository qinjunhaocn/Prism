import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_constants.dart';
import 'models/device_info.dart';

/// 原生能力的 Dart 侧封装。
///
/// 所有调用都做了失败降级：原生通道不可用（例如在桌面测试环境运行）时
/// 返回安全的空值，而不是抛异常中断 UI。
class NativeBridge {
  NativeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppConstants.nativeChannel);

  final MethodChannel _channel;

  /// 枚举存储卷；失败时退化为「根目录 + 主共享存储」。
  Future<List<StorageVolume>> listStorageVolumes() async {
    try {
      final List<Object?>? raw = await _channel.invokeMethod<List<Object?>>('listStorageVolumes');
      if (raw == null) {
        return _fallbackVolumes();
      }
      final List<StorageVolume> volumes = raw
          .whereType<Map<Object?, Object?>>()
          .map(StorageVolume.fromMap)
          .where((StorageVolume volume) => volume.path.isNotEmpty)
          .toList();
      return volumes.isEmpty ? _fallbackVolumes() : volumes;
    } on PlatformException {
      return _fallbackVolumes();
    } on MissingPluginException {
      return _fallbackVolumes();
    }
  }

  /// 读取当前/最高刷新率。
  Future<RefreshRateInfo?> refreshRateInfo() async {
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMethod<Map<Object?, Object?>>('getRefreshRate');
      if (raw == null) {
        return null;
      }
      return RefreshRateInfo.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 请求把窗口切换到设备允许的最高刷新率。
  ///
  /// 返回实际生效的刷新率；不支持时返回 null。
  Future<double?> requestMaxRefreshRate() async {
    try {
      final num? hz = await _channel.invokeMethod<num>('setMaxRefreshRate');
      return hz?.toDouble();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 用系统默认应用打开文件。
  Future<bool> openFile(String path, {String? mimeType}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('openFile', <String, Object?>{
        'path': path,
        'mimeType': mimeType ?? '*/*',
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 用系统「分享」面板分享文件。
  Future<bool> shareFile(String path, {String? mimeType}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('shareFile', <String, Object?>{
        'path': path,
        'mimeType': mimeType ?? '*/*',
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 读取文件的 MIME 类型（由原生 MimeTypeMap 推断）。
  Future<String?> mimeTypeOf(String path) async {
    try {
      return await _channel.invokeMethod<String>('getMimeType', <String, Object?>{'path': path});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 触发媒体扫描，让刚写入的文件出现在系统相册/媒体库中。
  Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod<void>('scanFile', <String, Object?>{'path': path});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// 当前 Android SDK 版本；非 Android 环境返回 0。
  Future<int> androidSdkInt() async {
    try {
      final int? sdk = await _channel.invokeMethod<int>('getAndroidSdkInt');
      return sdk ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// 在主线程执行一次轻微 GC 提示，用于批量操作后回收临时对象。
  ///
  /// 该调用是尽力而为的，不保证一定触发 GC。
  Future<void> trimMemory() async {
    try {
      await _channel.invokeMethod<void>('trimMemory');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// 原生通道不可用时的兜底卷列表。
  List<StorageVolume> _fallbackVolumes() {
    final List<StorageVolume> volumes = <StorageVolume>[];
    final Directory primary = Directory(AppConstants.primaryStoragePath);
    if (primary.existsSync()) {
      volumes.add(StorageVolume(
        path: AppConstants.primaryStoragePath,
        label: '内部存储',
        totalBytes: 0,
        freeBytes: 0,
        isPrimary: true,
        isRemovable: false,
      ));
    }
    volumes.add(const StorageVolume(
      path: AppConstants.rootPath,
      label: '根目录',
      totalBytes: 0,
      freeBytes: 0,
      isPrimary: false,
      isRemovable: false,
    ));
    return volumes;
  }
}
