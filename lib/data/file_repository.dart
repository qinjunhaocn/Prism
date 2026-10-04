import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_constants.dart';
import '../core/file_utils.dart';
import 'models/file_entry.dart';

/// 目录列举结果。
class DirectoryListing {
  const DirectoryListing({
    required this.path,
    required this.entries,
    required this.hiddenCount,
    required this.error,
  });

  final String path;

  /// 已按调用方排序规则排序的条目（含隐藏项，由调用方过滤）。
  final List<FileEntry> entries;

  /// 被过滤掉的隐藏项数量，用于提示。
  final int hiddenCount;

  /// 列举失败时的错误描述；成功为 null。
  final String? error;

  /// 是否成功。
  bool get isOk => error == null;

  /// 空目录。
  factory DirectoryListing.failure(String path, String error) {
    return DirectoryListing(
      path: path,
      entries: const <FileEntry>[],
      hiddenCount: 0,
      error: error,
    );
  }
}

/// 搜索结果。
class SearchHit {
  const SearchHit({required this.entry, required this.matchStart, required this.matchEnd});

  final FileEntry entry;

  /// 名称中匹配到的区间，用于高亮。
  final int matchStart;
  final int matchEnd;
}

/// 文件系统只读访问层。
///
/// 设计要点：
/// * 列举目录只做一次 `list`，随后用受限并发批量 stat，避免逐项 await 造成
///   串行等待；并发上限见 [AppConstants.statConcurrency]。
/// * 任何单项失败都不会让整个目录列举失败。
/// * 不缓存文件内容，只返回不可变快照，交由上层决定生命周期。
class FileRepository {
  const FileRepository();

  /// 列举目录内容。
  ///
  /// [showHidden] 为 false 时过滤以 `.` 开头的条目。
  Future<DirectoryListing> listDirectory(
    String path, {
    bool showHidden = false,
    SortSpec sort = const SortSpec(),
  }) async {
    final String normalized = FileUtils.normalize(path);
    final Directory directory = Directory(normalized);

    List<FileSystemEntity> raw;
    try {
      raw = await directory.list(followLinks: false).toList();
    } on FileSystemException catch (error) {
      return DirectoryListing.failure(normalized, _describeError(error));
    }

    // 隐藏项在 stat 之前过滤，省掉不必要的系统调用。
    final List<FileSystemEntity> visible = <FileSystemEntity>[];
    int hiddenCount = 0;
    for (final FileSystemEntity entity in raw) {
      final String name = p.posix.basename(entity.path);
      if (!showHidden && name.startsWith('.')) {
        hiddenCount++;
        continue;
      }
      visible.add(entity);
    }

    final List<FileEntry> entries = await _statAll(visible);
    sort.apply(entries);
    return DirectoryListing(
      path: normalized,
      entries: entries,
      hiddenCount: hiddenCount,
      error: null,
    );
  }

  /// 并发 stat 一批实体，保持输入顺序。
  Future<List<FileEntry>> _statAll(List<FileSystemEntity> entities) async {
    if (entities.isEmpty) {
      return <FileEntry>[];
    }
    final List<FileEntry?> results = List<FileEntry?>.filled(entities.length, null);
    final int workers = entities.length < AppConstants.statConcurrency
        ? entities.length
        : AppConstants.statConcurrency;
    int cursor = 0;

    Future<void> worker() async {
      while (true) {
        final int index = cursor++;
        if (index >= entities.length) {
          return;
        }
        results[index] = await _statEntity(entities[index]);
      }
    }

    await Future.wait<void>(List<Future<void>>.generate(workers, (_) => worker()));
    final List<FileEntry> entries = <FileEntry>[];
    for (final FileEntry? entry in results) {
      if (entry != null) {
        entries.add(entry);
      }
    }
    return entries;
  }

  /// 单个实体的 stat；符号链接额外解析目标。
  Future<FileEntry?> _statEntity(FileSystemEntity entity) async {
    final String name = p.posix.basename(entity.path);
    try {
      final FileStat stat = await entity.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return FileEntry.unreadable(entity.path);
      }
      String? linkTarget;
      bool isLink = false;
      if (entity is Link) {
        isLink = true;
        try {
          linkTarget = await entity.target();
        } on FileSystemException {
          linkTarget = null;
        }
      }
      final FileEntry entry = FileEntry.fromStat(
        entity.path,
        stat,
        name: name,
        linkTarget: linkTarget,
      );
      return isLink ? _markLink(entry) : entry;
    } on FileSystemException {
      return FileEntry.unreadable(entity.path);
    }
  }

  /// 把条目标记为符号链接（保留其余字段）。
  FileEntry _markLink(FileEntry entry) {
    return FileEntry(
      path: entry.path,
      name: entry.name,
      isDirectory: entry.isDirectory,
      isLink: true,
      size: entry.size,
      modified: entry.modified,
      kind: entry.kind,
      isHidden: entry.isHidden,
      isReadable: entry.isReadable,
      isWritable: entry.isWritable,
      linkTarget: entry.linkTarget,
      childCount: entry.childCount,
    );
  }

  /// 读取单个路径的条目信息。
  Future<FileEntry?> statPath(String path) async {
    final String normalized = FileUtils.normalize(path);
    final FileSystemEntityType type =
        await FileSystemEntity.type(normalized, followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    final FileSystemEntity entity = type == FileSystemEntityType.directory
        ? Directory(normalized)
        : File(normalized);
    return _statEntity(entity);
  }

  /// 统计目录内直接子项数量（不递归），用于「包含 N 项」展示。
  Future<int> countChildren(String path, {bool showHidden = true}) async {
    try {
      int count = 0;
      await for (final FileSystemEntity entity in Directory(path).list(followLinks: false)) {
        if (!showHidden && p.posix.basename(entity.path).startsWith('.')) {
          continue;
        }
        count++;
      }
      return count;
    } on FileSystemException {
      return 0;
    }
  }

  /// 递归计算目录占用空间。
  ///
  /// [onProgress] 可用于展示进度；返回值为总字节数。
  Future<int> directorySize(
    String path, {
    void Function(int bytes, int items)? onProgress,
    bool Function()? isCancelled,
  }) async {
    int total = 0;
    int items = 0;
    final List<String> stack = <String>[path];
    while (stack.isNotEmpty) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final String current = stack.removeLast();
      try {
        await for (final FileSystemEntity entity in Directory(current).list(followLinks: false)) {
          if (isCancelled?.call() ?? false) {
            break;
          }
          try {
            final FileStat stat = await entity.stat();
            if (stat.type == FileSystemEntityType.directory) {
              stack.add(entity.path);
            } else {
              total += stat.size;
              items++;
            }
          } on FileSystemException {
            continue;
          }
          if (items % 64 == 0) {
            onProgress?.call(total, items);
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    onProgress?.call(total, items);
    return total;
  }

  /// 递归搜索。
  ///
  /// [query] 为名称子串（大小写不敏感）；[useRegex] 为 true 时按正则解释。
  /// [maxResults] 达到后停止遍历。返回结果按路径深度优先顺序排列。
  Stream<SearchHit> search(
    String root, {
    required String query,
    bool useRegex = false,
    bool showHidden = false,
    bool searchDirectories = true,
    int maxResults = 2000,
    bool Function()? isCancelled,
  }) async* {
    if (query.isEmpty) {
      return;
    }
    RegExp? regex;
    final String needle = query.toLowerCase();
    if (useRegex) {
      try {
        regex = RegExp(query, caseSensitive: false);
      } on FormatException {
        return;
      }
    }

    int emitted = 0;
    final List<String> stack = <String>[FileUtils.normalize(root)];
    final Set<String> visited = <String>{};

    while (stack.isNotEmpty) {
      if (isCancelled?.call() ?? false) {
        return;
      }
      final String current = stack.removeLast();
      // 防止符号链接成环导致无限遍历。
      if (!visited.add(current)) {
        continue;
      }
      List<FileSystemEntity> children;
      try {
        children = await Directory(current).list(followLinks: false).toList();
      } on FileSystemException {
        continue;
      }

      for (final FileSystemEntity entity in children) {
        if (isCancelled?.call() ?? false) {
          return;
        }
        final String name = p.posix.basename(entity.path);
        if (!showHidden && name.startsWith('.')) {
          continue;
        }

        final int matchIndex = regex != null
            ? (regex.firstMatch(name)?.start ?? -1)
            : name.toLowerCase().indexOf(needle);

        if (matchIndex >= 0) {
          final FileEntry? entry = await _statEntity(entity);
          if (entry != null) {
            if (searchDirectories || !entry.isDirectory) {
              final int matchLength = regex != null
                  ? (regex.firstMatch(name)?.end ?? name.length) - matchIndex
                  : needle.length;
              yield SearchHit(
                entry: entry,
                matchStart: matchIndex,
                matchEnd: matchIndex + matchLength,
              );
              emitted++;
              if (emitted >= maxResults) {
                return;
              }
            }
          }
        }

        // 目录继续下探；符号链接目录不跟随，避免重复与环路。
        if (entity is! Link) {
          try {
            final FileStat stat = await entity.stat();
            if (stat.type == FileSystemEntityType.directory) {
              stack.add(entity.path);
            }
          } on FileSystemException {
            continue;
          }
        }
      }
    }
  }

  /// 读取文本文件前 [AppConstants.textPreviewLimit] 字节。
  ///
  /// 返回 null 表示读取失败或内容不是有效 UTF-8。
  Future<String?> readTextPreview(String path, {int? limit}) async {
    final int maxBytes = limit ?? AppConstants.textPreviewLimit;
    try {
      final File file = File(path);
      final int length = await file.length();
      final RandomAccessFile handle = await file.open();
      try {
        final int toRead = length < maxBytes ? length : maxBytes;
        final List<int> bytes = await handle.read(toRead);
        return _decodeUtf8(bytes);
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// 宽容的 UTF-8 解码：忽略非法字节序列，而不是抛异常。
  String _decodeUtf8(List<int> bytes) {
    final StringBuffer buffer = StringBuffer();
    int i = 0;
    while (i < bytes.length) {
      final int b = bytes[i];
      int codePoint;
      int extra;
      if (b < 0x80) {
        codePoint = b;
        extra = 0;
      } else if (b >= 0xC0 && b < 0xE0) {
        codePoint = b & 0x1F;
        extra = 1;
      } else if (b >= 0xE0 && b < 0xF0) {
        codePoint = b & 0x0F;
        extra = 2;
      } else if (b >= 0xF0 && b < 0xF8) {
        codePoint = b & 0x07;
        extra = 3;
      } else {
        // 非法起始字节（含孤立续字节），跳过。
        i++;
        continue;
      }

      bool valid = true;
      for (int k = 1; k <= extra; k++) {
        if (i + k >= bytes.length) {
          valid = false;
          break;
        }
        final int next = bytes[i + k];
        if (next < 0x80 || next >= 0xC0) {
          valid = false;
          break;
        }
        codePoint = (codePoint << 6) | (next & 0x3F);
      }

      if (!valid) {
        i++;
        continue;
      }
      buffer.writeCharCode(codePoint);
      i += extra + 1;
    }
    return buffer.toString();
  }

  /// 判断路径是否可写（通过尝试创建临时文件验证）。
  Future<bool> canWrite(String path) async {
    final Directory directory = Directory(path);
    if (!directory.existsSync()) {
      return false;
    }
    final File probe = File(FileUtils.join(path, '.prism_write_probe'));
    try {
      await probe.writeAsString('', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// 把 [FileSystemException] 转成中文提示。
  String _describeError(FileSystemException error) {
    final int code = error.osError?.errorCode ?? 0;
    return switch (code) {
      1 => '权限不足，无法访问该目录',
      2 => '目录不存在',
      13 => '权限不足，无法访问该目录',
      20 => '不是目录',
      21 => '目标是一个目录',
      _ => error.osError?.message ?? '无法访问该目录',
    };
  }
}
