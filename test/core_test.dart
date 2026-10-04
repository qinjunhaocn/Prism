import 'package:flutter_test/flutter_test.dart';
import 'package:prism/core/file_utils.dart';
import 'package:prism/core/formatters.dart';
import 'package:prism/data/models/file_entry.dart';

void main() {
  group('Formatters', () {
    test('文件大小按 1024 进制换算', () {
      expect(Formatters.fileSize(0), '0 B');
      expect(Formatters.fileSize(512), '512 B');
      expect(Formatters.fileSize(1024), '1.0 KB');
      expect(Formatters.fileSize(1536), '1.5 KB');
      expect(Formatters.fileSize(1024 * 1024), '1.0 MB');
      expect(Formatters.fileSize(-1), '--');
    });

    test('相对时间描述', () {
      final DateTime now = DateTime(2026, 1, 10, 12);
      expect(
        Formatters.relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
        '刚刚',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(minutes: 3)), now: now),
        '3 分钟前',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(hours: 5)), now: now),
        '5 小时前',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2 天前',
      );
    });

    test('刷新率格式化', () {
      expect(Formatters.refreshRate(120), '120 Hz');
      expect(Formatters.refreshRate(59.94), '59.94 Hz');
      expect(Formatters.refreshRate(0), '--');
    });
  });

  group('FileUtils', () {
    test('规范化路径', () {
      expect(FileUtils.normalize('/sdcard//Download/'), '/sdcard/Download');
      expect(FileUtils.normalize('/'), '/');
    });

    test('父目录与基名', () {
      expect(FileUtils.parentOf('/sdcard/Download'), '/sdcard');
      expect(FileUtils.parentOf('/'), '/');
      expect(FileUtils.baseName('/sdcard/Download'), 'Download');
      expect(FileUtils.baseName('/'), '/');
    });

    test('路径包含关系', () {
      expect(FileUtils.isInside('/sdcard/Download/a.txt', '/sdcard/Download'), isTrue);
      expect(FileUtils.isInside('/sdcard/Download', '/sdcard/Download'), isTrue);
      expect(FileUtils.isInside('/sdcard/Downloads', '/sdcard/Download'), isFalse);
      expect(FileUtils.isInside('/sdcard/Download/a.txt', '/'), isTrue);
    });

    test('扩展名与类别推断', () {
      expect(FileUtils.extensionOf('photo.JPEG'), 'jpeg');
      expect(FileUtils.extensionOf('noext'), '');
      expect(FileUtils.extensionOf('.hidden'), '');
      expect(FileUtils.kindOf('a.png'), FileKind.image);
      expect(FileUtils.kindOf('a.mp4'), FileKind.video);
      expect(FileUtils.kindOf('a.zip'), FileKind.archive);
      expect(FileUtils.kindOf('a.apk'), FileKind.apk);
      expect(FileUtils.kindOf('a.dart'), FileKind.code);
      expect(FileUtils.kindOf('folder', isDirectory: true), FileKind.directory);
    });

    test('非法文件名检测', () {
      expect(FileUtils.isValidFileName('a.txt'), isTrue);
      expect(FileUtils.isValidFileName(''), isFalse);
      expect(FileUtils.isValidFileName('..'), isFalse);
      expect(FileUtils.isValidFileName('a/b'), isFalse);
    });

    test('重名去重', () {
      final Set<String> existing = <String>{'a.txt', 'a (1).txt'};
      expect(FileUtils.dedupeName('a.txt', exists: existing.contains), 'a (2).txt');
      expect(FileUtils.dedupeName('b.txt', exists: existing.contains), 'b.txt');
    });
  });

  group('SortSpec', () {
    FileEntry makeEntry(String name, {bool isDirectory = false}) {
      return FileEntry(
        path: '/tmp/$name',
        name: name,
        isDirectory: isDirectory,
        isLink: false,
        size: 0,
        modified: DateTime(2026, 1, 1),
        kind: FileUtils.kindOf(name, isDirectory: isDirectory),
      );
    }

    test('目录始终排在文件之前', () {
      final List<FileEntry> entries = <FileEntry>[
        makeEntry('b.txt'),
        makeEntry('zdir', isDirectory: true),
        makeEntry('a.txt'),
      ];
      const SortSpec(field: SortField.name).apply(entries);
      expect(entries.first.name, 'zdir');
    });

    test('自然序：file2 在 file10 之前', () {
      final List<FileEntry> entries = <FileEntry>[
        makeEntry('file10.txt'),
        makeEntry('file2.txt'),
      ];
      const SortSpec(field: SortField.name).apply(entries);
      expect(
        entries.map((FileEntry entry) => entry.name).toList(),
        <String>['file2.txt', 'file10.txt'],
      );
    });

    test('切换同一字段会反转方向', () {
      const SortSpec spec = SortSpec(field: SortField.name);
      final SortSpec toggled = spec.toggle(SortField.name);
      expect(toggled.order, SortOrder.descending);
      expect(toggled.toggle(SortField.name).order, SortOrder.ascending);
    });

    test('序列化往返', () {
      const SortSpec spec = SortSpec(field: SortField.size, order: SortOrder.descending);
      final SortSpec restored = SortSpec.deserialize(spec.serialize());
      expect(restored.field, SortField.size);
      expect(restored.order, SortOrder.descending);
      expect(SortSpec.deserialize(null).field, SortField.name);
    });
  });
}
