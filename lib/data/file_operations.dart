import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../core/file_utils.dart';
import 'models/file_entry.dart';

/// 单个操作的进度快照。
class OperationProgress {
  const OperationProgress({
    required this.title,
    required this.currentItem,
    required this.totalItems,
    required this.currentPath,
    required this.bytesDone,
    required this.bytesTotal,
  });

  final String title;
  final int currentItem;
  final int totalItems;
  final String currentPath;
  final int bytesDone;
  final int bytesTotal;

  /// 条目维度进度，范围 0..1。
  double get itemRatio => totalItems <= 0 ? 0 : (currentItem / totalItems).clamp(0, 1).toDouble();

  /// 字节维度进度；总大小未知时为 null。
  double? get byteRatio {
    if (bytesTotal <= 0) {
      return null;
    }
    return (bytesDone / bytesTotal).clamp(0, 1).toDouble();
  }
}

/// 操作结果。
class OperationResult {
  const OperationResult({
    required this.succeeded,
    required this.failed,
    required this.cancelled,
    this.message,
  });

  /// 成功处理的路径数。
  final int succeeded;

  /// 失败明细：路径 -> 原因。
  final Map<String, String> failed;

  /// 是否被用户取消。
  final bool cancelled;

  /// 附加说明（成功提示语等）。
  final String? message;

  bool get isClean => failed.isEmpty && !cancelled;

  /// 生成用户可读的总结。
  String describe() {
    if (cancelled) {
      return '已取消，完成 $succeeded 项';
    }
    if (failed.isEmpty) {
      return message ?? '已完成 $succeeded 项';
    }
    return '完成 $succeeded 项，失败 ${failed.length} 项';
  }
}

/// 取消令牌：供 UI 中止长任务。
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 文件写操作服务。
///
/// 所有复制/移动都在流式缓冲区上工作，避免一次性把大文件读进内存；
/// 每次操作前都会做冲突检测与同名去重，且绝不允许把目录复制进自身。
class FileOperationService {
  const FileOperationService();

  /// 复制缓冲区大小：512 KiB 在吞吐与内存之间取得平衡。
  static const int _bufferSize = 512 * 1024;

  /// 复制或移动多个条目到目标目录。
  ///
  /// [move] 为 true 时执行移动（同分区用 rename，跨分区退化为复制后删除）。
  Future<OperationResult> transfer({
    required List<String> sources,
    required String destinationDir,
    required bool move,
    CancellationToken? token,
    void Function(OperationProgress)? onProgress,
  }) async {
    final String target = FileUtils.normalize(destinationDir);
    final Map<String, String> failed = <String, String>{};
    int succeeded = 0;
    final String title = move ? '正在移动' : '正在复制';

    // 预先计算总字节数，让进度条有确定的终点。
    int bytesTotal = 0;
    for (final String source in sources) {
      bytesTotal += await _sizeOf(source, token: token);
      if (token?.isCancelled ?? false) {
        break;
      }
    }

    int bytesDone = 0;
    int index = 0;

    for (final String source in sources) {
      if (token?.isCancelled ?? false) {
        break;
      }
      index++;
      final String name = FileUtils.baseName(source);

      // 安全校验：不能把目录移动/复制到它自己的子目录中。
      if (move && FileUtils.isInside(target, source)) {
        failed[source] = '不能移动到自身或其子目录';
        continue;
      }

      final String resolvedName = _resolveConflict(target, name);
      final String destination = FileUtils.join(target, resolvedName);

      try {
        onProgress?.call(OperationProgress(
          title: title,
          currentItem: index,
          totalItems: sources.length,
          currentPath: name,
          bytesDone: bytesDone,
          bytesTotal: bytesTotal,
        ));

        if (move) {
          final int moved = await _move(source, destination, (int delta) {
            bytesDone += delta;
            onProgress?.call(OperationProgress(
              title: title,
              currentItem: index,
              totalItems: sources.length,
              currentPath: name,
              bytesDone: bytesDone,
              bytesTotal: bytesTotal,
            ));
          }, token);
          bytesDone += moved;
        } else {
          await _copy(source, destination, (int delta) {
            bytesDone += delta;
            onProgress?.call(OperationProgress(
              title: title,
              currentItem: index,
              totalItems: sources.length,
              currentPath: name,
              bytesDone: bytesDone,
              bytesTotal: bytesTotal,
            ));
          }, token);
        }
        succeeded++;
      } on _OperationCancelled {
        break;
      } on FileSystemException catch (error) {
        failed[source] = _describe(error);
      }
    }

    return OperationResult(
      succeeded: succeeded,
      failed: failed,
      cancelled: token?.isCancelled ?? false,
      message: move ? '已移动 $succeeded 项' : '已复制 $succeeded 项',
    );
  }

  /// 删除多个条目（目录递归删除）。
  Future<OperationResult> delete({
    required List<String> paths,
    CancellationToken? token,
    void Function(OperationProgress)? onProgress,
  }) async {
    final Map<String, String> failed = <String, String>{};
    int succeeded = 0;
    int index = 0;

    for (final String path in paths) {
      if (token?.isCancelled ?? false) {
        break;
      }
      index++;
      try {
        onProgress?.call(OperationProgress(
          title: '正在删除',
          currentItem: index,
          totalItems: paths.length,
          currentPath: FileUtils.baseName(path),
          bytesDone: 0,
          bytesTotal: 0,
        ));
        await _deletePath(path);
        succeeded++;
      } on FileSystemException catch (error) {
        failed[path] = _describe(error);
      }
    }

    return OperationResult(
      succeeded: succeeded,
      failed: failed,
      cancelled: token?.isCancelled ?? false,
      message: '已删除 $succeeded 项',
    );
  }

  /// 重命名单个条目。
  ///
  /// 返回新路径；失败时抛出 [FileSystemException]。
  Future<String> rename(String path, String newName) async {
    if (!FileUtils.isValidFileName(newName)) {
      throw const FileSystemException('文件名包含非法字符');
    }
    final String parent = FileUtils.parentOf(path);
    final String destination = FileUtils.join(parent, newName);
    if (FileUtils.normalize(path) == destination) {
      return destination;
    }
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('同名文件已存在');
    }
    final FileSystemEntity entity = _entityFor(path);
    await entity.rename(destination);
    return destination;
  }

  /// 新建文件夹，返回创建后的路径。
  Future<String> createDirectory(String parentDir, String name) async {
    if (!FileUtils.isValidFileName(name)) {
      throw const FileSystemException('文件夹名包含非法字符');
    }
    final String path = FileUtils.join(FileUtils.normalize(parentDir), name);
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw const FileSystemException('同名文件夹已存在');
    }
    await Directory(path).create(recursive: false);
    return path;
  }

  /// 新建空文件，返回创建后的路径。
  Future<String> createFile(String parentDir, String name, {String content = ''}) async {
    if (!FileUtils.isValidFileName(name)) {
      throw const FileSystemException('文件名包含非法字符');
    }
    final String path = FileUtils.join(FileUtils.normalize(parentDir), name);
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw const FileSystemException('同名文件已存在');
    }
    final File file = File(path);
    await file.writeAsString(content, flush: true);
    return path;
  }

  /// 写入文本文件（覆盖）。
  Future<void> writeText(String path, String content) async {
    await File(path).writeAsString(content, flush: true);
  }

  /// 批量重命名：按 [renames] 中 `旧路径 -> 新名` 执行。
  ///
  /// 采用两阶段重命名，避免 `a->b, b->a` 这类交换场景互相覆盖。
  Future<OperationResult> batchRename(Map<String, String> renames) async {
    final Map<String, String> failed = <String, String>{};
    final Map<String, String> staged = <String, String>{};
    int succeeded = 0;
    final String tempDir = FileUtils.join(
      FileUtils.parentOf(renames.keys.first),
      '.prism_rename_${DateTime.now().microsecondsSinceEpoch}',
    );

    try {
      await Directory(tempDir).create(recursive: true);
    } on FileSystemException catch (error) {
      return OperationResult(
        succeeded: 0,
        failed: Map<String, String>.fromEntries(
          renames.keys.map((String key) => MapEntry<String, String>(key, _describe(error))),
        ),
        cancelled: false,
      );
    }

    // 阶段一：把源移动到临时目录，腾出名字。
    int stageIndex = 0;
    for (final MapEntry<String, String> item in renames.entries) {
      try {
        final String tempPath = FileUtils.join(tempDir, 'staging_${stageIndex++}');
        await _entityFor(item.key).rename(tempPath);
        staged[item.key] = tempPath;
      } on FileSystemException catch (error) {
        failed[item.key] = _describe(error);
      }
    }

    // 阶段二：从临时目录移动到最终名称。
    for (final MapEntry<String, String> item in renames.entries) {
      final String? tempPath = staged[item.key];
      if (tempPath == null) {
        continue;
      }
      try {
        final String destination = FileUtils.join(FileUtils.parentOf(item.key), item.value);
        if (await FileSystemEntity.type(destination, followLinks: false) !=
            FileSystemEntityType.notFound) {
          failed[item.key] = '同名文件已存在';
          // 回滚到原名，避免数据滞留临时目录。
          await _entityFor(tempPath).rename(item.key);
          continue;
        }
        await _entityFor(tempPath).rename(destination);
        succeeded++;
      } on FileSystemException catch (error) {
        failed[item.key] = _describe(error);
        try {
          await _entityFor(tempPath).rename(item.key);
        } on FileSystemException {
          failed[item.key] = '${failed[item.key]}（临时文件位于 $tempPath）';
        }
      }
    }

    try {
      await Directory(tempDir).delete(recursive: true);
    } on FileSystemException {
      // 清理失败不影响结果。
    }

    return OperationResult(succeeded: succeeded, failed: failed, cancelled: false);
  }

  /// 计算路径占用空间（文件返回自身大小，目录递归累加）。
  Future<int> _sizeOf(String path, {CancellationToken? token}) async {
    final FileSystemEntityType type = await FileSystemEntity.type(path, followLinks: true);
    if (type == FileSystemEntityType.file) {
      try {
        return await File(path).length();
      } on FileSystemException {
        return 0;
      }
    }
    if (type != FileSystemEntityType.directory) {
      return 0;
    }
    int total = 0;
    final List<String> stack = <String>[path];
    while (stack.isNotEmpty) {
      if (token?.isCancelled ?? false) {
        break;
      }
      final String current = stack.removeLast();
      try {
        await for (final FileSystemEntity entity in Directory(current).list(followLinks: false)) {
          try {
            final FileStat stat = await entity.stat();
            if (stat.type == FileSystemEntityType.directory) {
              stack.add(entity.path);
            } else {
              total += stat.size;
            }
          } on FileSystemException {
            continue;
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  /// 复制：目录递归、文件流式，均支持取消。
  Future<void> _copy(
    String source,
    String destination,
    void Function(int delta) onBytes,
    CancellationToken? token,
  ) async {
    final FileSystemEntityType type = await FileSystemEntity.type(source, followLinks: true);

    if (type == FileSystemEntityType.directory) {
      await Directory(destination).create(recursive: true);
      List<FileSystemEntity> children;
      try {
        children = await Directory(source).list(followLinks: false).toList();
      } on FileSystemException catch (error) {
        throw FileSystemException('无法读取目录：${_describe(error)}', source);
      }
      for (final FileSystemEntity child in children) {
        if (token?.isCancelled ?? false) {
          throw const _OperationCancelled();
        }
        final String name = p.posix.basename(child.path);
        await _copy(child.path, FileUtils.join(destination, name), onBytes, token);
      }
      return;
    }

    if (type != FileSystemEntityType.file) {
      throw FileSystemException('不支持的文件类型', source);
    }

    // 目标已存在时直接覆盖（去重已在调用方完成）。
    final File output = File(destination);
    await output.create(recursive: true);
    final RandomAccessFile input = await File(source).open();
    final RandomAccessFile sink = await output.open(mode: FileMode.write);
    final List<int> buffer = List<int>.filled(_bufferSize, 0);
    try {
      while (true) {
        if (token?.isCancelled ?? false) {
          throw const _OperationCancelled();
        }
        final int read = await input.readInto(buffer);
        if (read == 0) {
          break;
        }
        await sink.writeFrom(buffer, 0, read);
        onBytes(read);
      }
      await sink.flush();
    } finally {
      await input.close();
      await sink.close();
    }

    // 尽量保留原始修改时间；失败不影响复制结果。
    try {
      final FileStat stat = await File(source).stat();
      await output.setLastModified(stat.modified);
    } on FileSystemException {
      // 忽略。
    }
  }

  /// 移动：优先 rename，跨设备时退化为复制后删除。
  Future<int> _move(
    String source,
    String destination,
    void Function(int delta) onBytes,
    CancellationToken? token,
  ) async {
    try {
      await _entityFor(source).rename(destination);
      return 0;
    } on FileSystemException {
      // 跨分区或权限问题，退化为复制+删除。
    }
    final int bytes = await _sizeOf(source, token: token);
    await _copy(source, destination, onBytes, token);
    if (token?.isCancelled ?? false) {
      throw const _OperationCancelled();
    }
    await _deletePath(source);
    return bytes;
  }

  /// 递归删除路径。
  Future<void> _deletePath(String path) async {
    final FileSystemEntityType type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('路径不存在', path);
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
      return;
    }
    // 符号链接用 Link.delete，避免误删链接指向的内容。
    if (type == FileSystemEntityType.link) {
      await Link(path).delete();
      return;
    }
    await File(path).delete();
  }

  /// 为目标目录生成不冲突的名称。
  String _resolveConflict(String directory, String name) {
    final String candidate = FileUtils.join(directory, name);
    if (FileSystemEntity.typeSync(candidate, followLinks: false) == FileSystemEntityType.notFound) {
      return name;
    }
    return FileUtils.dedupeName(
      name,
      exists: (String probe) =>
          FileSystemEntity.typeSync(FileUtils.join(directory, probe), followLinks: false) !=
          FileSystemEntityType.notFound,
    );
  }

  /// 根据类型选择实体包装类。
  FileSystemEntity _entityFor(String path) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(path, followLinks: false);
    return switch (type) {
      FileSystemEntityType.directory => Directory(path),
      FileSystemEntityType.link => Link(path),
      _ => File(path),
    };
  }

  /// 把系统错误翻译为中文提示。
  String _describe(FileSystemException error) {
    final String? message = error.osError?.message;
    if (message == null) {
      return error.message.isEmpty ? '操作失败' : error.message;
    }
    if (message.contains('Permission denied')) {
      return '权限不足';
    }
    if (message.contains('No such file')) {
      return '文件不存在';
    }
    if (message.contains('Read-only')) {
      return '只读文件系统';
    }
    if (message.contains('No space left')) {
      return '存储空间不足';
    }
    if (message.contains('Directory not empty')) {
      return '目录非空';
    }
    if (message.contains('Is a directory')) {
      return '目标是一个目录';
    }
    if (message.contains('Not a directory')) {
      return '目标不是目录';
    }
    if (message.contains('File exists')) {
      return '同名文件已存在';
    }
    return message;
  }
}

/// 内部取消信号，用于中断递归复制。
class _OperationCancelled implements Exception {
  const _OperationCancelled();
}

/// 目录扫描结果，供「存储分析」使用。
class ScanResult {
  const ScanResult({
    required this.totalBytes,
    required this.fileCount,
    required this.directoryCount,
    required this.largest,
  });

  final int totalBytes;
  final int fileCount;
  final int directoryCount;

  /// 最大的若干文件。
  final List<FileEntry> largest;
}

/// 在后台 isolate 中执行目录扫描，避免阻塞 UI 线程。
///
/// 扫描结果只回传聚合数据与 Top-N 大文件，不传输完整目录树。
Future<ScanResult> scanDirectoryInIsolate(
  String root, {
  int topCount = 20,
  void Function(int bytes, int files)? onProgress,
}) async {
  final ReceivePort receivePort = ReceivePort();
  final Completer<ScanResult> completer = Completer<ScanResult>();

  receivePort.listen((Object? message) {
    if (message is Map<Object?, Object?> && message['progress'] == true) {
      onProgress?.call(
        (message['bytes'] as num?)?.toInt() ?? 0,
        (message['files'] as num?)?.toInt() ?? 0,
      );
      return;
    }
    if (message is Map<Object?, Object?> && message['done'] == true) {
      final List<Object?> rawLargest =
          (message['largest'] as List<Object?>?) ?? const <Object?>[];
      final List<FileEntry> largest = <FileEntry>[];
      for (final Object? item in rawLargest) {
        if (item is! Map<Object?, Object?>) {
          continue;
        }
        final String path = item['path'] as String? ?? '';
        final String name = item['name'] as String? ?? FileUtils.baseName(path);
        largest.add(FileEntry(
          path: path,
          name: name,
          isDirectory: false,
          isLink: false,
          size: (item['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch(0),
          kind: FileUtils.kindOf(name),
        ));
      }
      completer.complete(ScanResult(
        totalBytes: (message['total'] as num?)?.toInt() ?? 0,
        fileCount: (message['files'] as num?)?.toInt() ?? 0,
        directoryCount: (message['dirs'] as num?)?.toInt() ?? 0,
        largest: largest,
      ));
      receivePort.close();
    }
  });

  await Isolate.spawn<_ScanRequest>(
    _scanWorker,
    _ScanRequest(root: root, topCount: topCount, sendPort: receivePort.sendPort),
  );

  return completer.future;
}

/// isolate 启动参数。
class _ScanRequest {
  const _ScanRequest({required this.root, required this.topCount, required this.sendPort});

  final String root;
  final int topCount;
  final SendPort sendPort;
}

/// 后台扫描实现：深度优先遍历，维护 Top-N 大文件堆。
Future<void> _scanWorker(_ScanRequest request) async {
  int total = 0;
  int files = 0;
  int dirs = 0;
  int lastReport = 0;
  final List<MapEntry<String, int>> largest = <MapEntry<String, int>>[];

  final List<String> stack = <String>[request.root];
  final Set<String> visited = <String>{};

  while (stack.isNotEmpty) {
    final String current = stack.removeLast();
    if (!visited.add(current)) {
      continue;
    }
    try {
      await for (final FileSystemEntity entity in Directory(current).list(followLinks: false)) {
        try {
          final FileStat stat = await entity.stat();
          if (stat.type == FileSystemEntityType.directory) {
            dirs++;
            stack.add(entity.path);
          } else {
            files++;
            total += stat.size;
            largest.add(MapEntry<String, int>(entity.path, stat.size));
          }
        } on FileSystemException {
          continue;
        }
        // 每 256 个文件汇报一次进度，避免消息通道过载。
        if (files - lastReport >= 256) {
          lastReport = files;
          request.sendPort.send(<String, Object?>{
            'progress': true,
            'bytes': total,
            'files': files,
          });
        }
      }
    } on FileSystemException {
      continue;
    }
  }

  largest.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
  final int keep = math.min(request.topCount, largest.length);
  final List<Map<String, Object?>> top = <Map<String, Object?>>[];
  for (int i = 0; i < keep; i++) {
    top.add(<String, Object?>{
      'path': largest[i].key,
      'name': p.posix.basename(largest[i].key),
      'size': largest[i].value,
    });
  }

  request.sendPort.send(<String, Object?>{
    'done': true,
    'total': total,
    'files': files,
    'dirs': dirs,
    'largest': top,
  });
}
