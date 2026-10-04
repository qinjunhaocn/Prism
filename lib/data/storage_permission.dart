import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 存储权限的请求结果。
enum StoragePermissionStatus {
  /// 已获得完整读写权限。
  granted,

  /// 只有部分权限（例如仅能读媒体文件）。
  limited,

  /// 被拒绝，但还可以再次请求。
  denied,

  /// 被永久拒绝，需要引导用户去系统设置。
  permanentlyDenied,

  /// 当前平台无需权限（例如桌面环境）。
  notRequired,
}

/// 存储权限协调器。
///
/// 文件管理器需要完整读写共享存储的能力：
/// * Android 11+ 需要 `MANAGE_EXTERNAL_STORAGE`（"所有文件访问权限"），
///   该权限只能由用户在系统设置中手动开启，因此这里负责跳转引导。
/// * Android 10 及以下使用 `READ/WRITE_EXTERNAL_STORAGE`。
/// * Android 13+ 读媒体文件还需要 `READ_MEDIA_*` 细分权限。
class StoragePermissionService {
  const StoragePermissionService();

  /// 查询当前是否已经拥有完整权限（不弹窗）。
  Future<bool> hasFullAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    // Android 10 及以下：普通存储权限即等价于完整访问。
    final bool legacy =
        await Permission.storage.isGranted || await Permission.photos.isGranted;
    return legacy;
  }

  /// 请求权限。
  ///
  /// Android 11+ 会先尝试弹出系统对话框；若系统要求手动授权，
  /// 则返回 [StoragePermissionStatus.denied]，由 UI 决定是否引导到设置页。
  Future<StoragePermissionStatus> request() async {
    if (!Platform.isAndroid) {
      return StoragePermissionStatus.notRequired;
    }

    // Android 11+：优先申请「所有文件访问权限」。
    final PermissionStatus manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) {
      return StoragePermissionStatus.granted;
    }

    // 退回旧版存储权限（Android 10 及以下）。
    final Map<Permission, PermissionStatus> legacy = await <Permission>[
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.audio,
    ].request();

    final bool storageGranted = legacy[Permission.storage]?.isGranted ?? false;
    if (storageGranted) {
      return StoragePermissionStatus.granted;
    }

    final bool anyMedia = legacy.values.any((PermissionStatus status) => status.isGranted);
    if (anyMedia) {
      return StoragePermissionStatus.limited;
    }

    final bool permanentlyDenied = manageStatus.isPermanentlyDenied ||
        legacy.values.any((PermissionStatus status) => status.isPermanentlyDenied);
    return permanentlyDenied
        ? StoragePermissionStatus.permanentlyDenied
        : StoragePermissionStatus.denied;
  }

  /// 跳转到系统设置页，供用户手动开启权限。
  Future<bool> openSettings() => openAppSettings();
}
