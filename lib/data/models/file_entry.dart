import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/file_utils.dart';

/// 一个文件系统条目的不可变快照。
///
/// 构造后不再变化，便于在列表中被 `const` 复用与做相等性比较，
/// 从而让 `AnimatedBuilder`/`ListView` 的 diff 更廉价。
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.isLink,
    required this.size,
    required this.modified,
    required this.kind,
    this.isHidden = false,
    this.isReadable = true,
    this.isWritable = true,
    this.linkTarget,
    this.childCount,
  });

  /// 绝对路径。
  final String path;

  /// 文件名（含扩展名）。
  final String name;

  final bool isDirectory;

  /// 是否为符号链接。
  final bool isLink;

  /// 字节大小；目录为 0。
  final int size;

  final DateTime modified;
  final FileKind kind;

  /// 是否为隐藏项（以 `.` 开头）。
  final bool isHidden;

  final bool isReadable;
  final bool isWritable;

  /// 符号链接指向的目标（可能为空）。
  final String? linkTarget;

  /// 目录内的条目数；未统计时为 null（惰性计算，避免列举目录时付出代价）。
  final int? childCount;

  /// 展示名：目录不带扩展名，文件保留完整名。
  String get displayName => name;

  /// 扩展名（小写，不含点）。
  String get extension => FileUtils.extensionOf(name);

  /// 用于排序的可比较键。
  String get sortKey => name.toLowerCase();

  /// 复制并覆盖部分字段。
  FileEntry copyWith({
    int? size,
    DateTime? modified,
    int? childCount,
    bool? isReadable,
    bool? isWritable,
  }) {
    return FileEntry(
      path: path,
      name: name,
      isDirectory: isDirectory,
      isLink: isLink,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      kind: kind,
      isHidden: isHidden,
      isReadable: isReadable ?? this.isReadable,
      isWritable: isWritable ?? this.isWritable,
      linkTarget: linkTarget,
      childCount: childCount ?? this.childCount,
    );
  }

  /// 由 `FileSystemEntity` 的 stat 结果构造。
  ///
  /// 使用 `FileStat` 而非多次 `exists()`/`length()` 调用，减少系统调用次数。
  factory FileEntry.fromStat(String path, FileStat stat, {String? name, String? linkTarget}) {
    final String resolvedName = name ?? p.posix.basename(path);
    final bool isDir = stat.type == FileSystemEntityType.directory;
    final bool isLink = stat.type == FileSystemEntityType.link;
    return FileEntry(
      path: path,
      name: resolvedName,
      isDirectory: isDir,
      isLink: isLink,
      size: isDir ? 0 : stat.size,
      modified: stat.modified,
      kind: FileUtils.kindOf(resolvedName, isDirectory: isDir),
      isHidden: resolvedName.startsWith('.'),
      isReadable: _canRead(stat.mode),
      isWritable: _canWrite(stat.mode),
      linkTarget: linkTarget,
    );
  }

  /// 由 `FileSystemEntity` 直接构造，内部完成 stat。
  static Future<FileEntry?> fromEntity(FileSystemEntity entity) async {
    try {
      final FileStat stat = await entity.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      return FileEntry.fromStat(entity.path, stat);
    } on FileSystemException {
      return null;
    }
  }

  /// 占位条目：stat 失败时仍展示名称，避免整目录列举因单项权限问题失败。
  factory FileEntry.unreadable(String path, {bool isDirectory = false}) {
    final String name = p.posix.basename(path);
    return FileEntry(
      path: path,
      name: name,
      isDirectory: isDirectory,
      isLink: false,
      size: 0,
      modified: DateTime.fromMillisecondsSinceEpoch(0),
      kind: FileUtils.kindOf(name, isDirectory: isDirectory),
      isHidden: name.startsWith('.'),
      isReadable: false,
      isWritable: false,
    );
  }

  /// POSIX 权限位：其他用户可读。
  static bool _canRead(int mode) => (mode & 0x4) != 0;

  /// POSIX 权限位：其他用户可写。
  static bool _canWrite(int mode) => (mode & 0x2) != 0;

  @override
  bool operator ==(Object other) {
    return other is FileEntry &&
        other.path == path &&
        other.size == size &&
        other.modified == modified &&
        other.childCount == childCount;
  }

  @override
  int get hashCode => Object.hash(path, size, modified, childCount);

  @override
  String toString() => 'FileEntry($path, dir=$isDirectory, size=$size)';
}

/// 排序字段。
enum SortField {
  name,
  size,
  modified,
  type,
}

/// 排序方向。
enum SortOrder {
  ascending,
  descending,
}

/// 一套排序规则。
class SortSpec {
  const SortSpec({this.field = SortField.name, this.order = SortOrder.ascending});

  final SortField field;
  final SortOrder order;

  /// 是否升序。
  bool get isAscending => order == SortOrder.ascending;

  /// 切换字段：若字段相同则反转方向，否则使用该字段的默认方向。
  SortSpec toggle(SortField next) {
    if (next == field) {
      return SortSpec(
        field: field,
        order: order == SortOrder.ascending ? SortOrder.descending : SortOrder.ascending,
      );
    }
    // 名称与类型默认升序，大小与时间默认降序（更符合直觉）。
    final SortOrder defaultOrder =
        next == SortField.size || next == SortField.modified
            ? SortOrder.descending
            : SortOrder.ascending;
    return SortSpec(field: next, order: defaultOrder);
  }

  SortSpec copyWith({SortField? field, SortOrder? order}) {
    return SortSpec(field: field ?? this.field, order: order ?? this.order);
  }

  /// 对条目列表排序：目录始终优先，随后按字段比较。
  ///
  /// 排序是就地进行的，调用方应传入可变副本。
  void apply(List<FileEntry> entries) {
    entries.sort(_compare);
  }

  int _compare(FileEntry a, FileEntry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    int result;
    switch (field) {
      case SortField.name:
        result = _naturalCompare(a.sortKey, b.sortKey);
      case SortField.size:
        result = a.size.compareTo(b.size);
      case SortField.modified:
        result = a.modified.compareTo(b.modified);
      case SortField.type:
        result = a.extension.compareTo(b.extension);
        if (result == 0) {
          result = _naturalCompare(a.sortKey, b.sortKey);
        }
    }
    return isAscending ? result : -result;
  }

  /// 自然序比较：让 `file2` 排在 `file10` 之前。
  static int _naturalCompare(String a, String b) {
    int i = 0;
    int j = 0;
    while (i < a.length && j < b.length) {
      final int ca = a.codeUnitAt(i);
      final int cb = b.codeUnitAt(j);
      final bool digitA = ca >= 0x30 && ca <= 0x39;
      final bool digitB = cb >= 0x30 && cb <= 0x39;
      if (digitA && digitB) {
        int endA = i;
        while (endA < a.length) {
          final int c = a.codeUnitAt(endA);
          if (c < 0x30 || c > 0x39) {
            break;
          }
          endA++;
        }
        int endB = j;
        while (endB < b.length) {
          final int c = b.codeUnitAt(endB);
          if (c < 0x30 || c > 0x39) {
            break;
          }
          endB++;
        }
        final int numA = int.tryParse(a.substring(i, endA)) ?? 0;
        final int numB = int.tryParse(b.substring(j, endB)) ?? 0;
        if (numA != numB) {
          return numA.compareTo(numB);
        }
        i = endA;
        j = endB;
        continue;
      }
      if (ca != cb) {
        return ca.compareTo(cb);
      }
      i++;
      j++;
    }
    return (a.length - i).compareTo(b.length - j);
  }

  /// 序列化为字符串以便持久化。
  String serialize() => '${field.name}:${order.name}';

  /// 反序列化；无法识别时返回默认规则。
  static SortSpec deserialize(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const SortSpec();
    }
    final List<String> parts = raw.split(':');
    if (parts.length != 2) {
      return const SortSpec();
    }
    final SortField field = SortField.values.firstWhere(
      (SortField value) => value.name == parts[0],
      orElse: () => SortField.name,
    );
    final SortOrder order = SortOrder.values.firstWhere(
      (SortOrder value) => value.name == parts[1],
      orElse: () => SortOrder.ascending,
    );
    return SortSpec(field: field, order: order);
  }
}
