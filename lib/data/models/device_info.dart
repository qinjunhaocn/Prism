/// 存储卷信息，由原生 StorageManager 提供。
class StorageVolume {
  const StorageVolume({
    required this.path,
    required this.label,
    required this.totalBytes,
    required this.freeBytes,
    required this.isPrimary,
    required this.isRemovable,
  });

  /// 挂载路径，例如 `/storage/emulated/0`。
  final String path;

  /// 用户可见名称，例如「内部存储」。
  final String label;

  final int totalBytes;
  final int freeBytes;

  /// 是否为主共享存储。
  final bool isPrimary;

  /// 是否可移除（SD 卡、U 盘）。
  final bool isRemovable;

  /// 已使用字节数。
  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);

  /// 已使用比例，范围 0..1。
  double get usedRatio => totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0, 1).toDouble();

  /// 从原生 Map 构造；字段缺失时使用安全默认值。
  factory StorageVolume.fromMap(Map<Object?, Object?> map) {
    return StorageVolume(
      path: map['path'] as String? ?? '',
      label: map['label'] as String? ?? '',
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      freeBytes: (map['freeBytes'] as num?)?.toInt() ?? 0,
      isPrimary: map['isPrimary'] as bool? ?? false,
      isRemovable: map['isRemovable'] as bool? ?? false,
    );
  }
}

/// 屏幕刷新率信息。
class RefreshRateInfo {
  const RefreshRateInfo({
    required this.currentHz,
    required this.maxHz,
    required this.supportedHz,
  });

  /// 当前实际刷新率。
  final double currentHz;

  /// 设备支持的最高刷新率。
  final double maxHz;

  /// 所有去重并升序排列的候选刷新率。
  final List<double> supportedHz;

  /// 从原生 Map 构造。
  factory RefreshRateInfo.fromMap(Map<Object?, Object?> map) {
    final List<Object?> rawList =
        (map['supported'] as List<Object?>?) ?? const <Object?>[];
    final List<double> supported = rawList
        .whereType<num>()
        .map((num value) => value.toDouble())
        .toList()
      ..sort();
    return RefreshRateInfo(
      currentHz: (map['current'] as num?)?.toDouble() ?? 0,
      maxHz: (map['max'] as num?)?.toDouble() ?? 0,
      supportedHz: supported,
    );
  }
}
