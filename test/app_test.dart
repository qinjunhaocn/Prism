import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism/core/app_constants.dart';
import 'package:prism/data/file_operations.dart';
import 'package:prism/data/file_repository.dart';
import 'package:prism/data/models/file_entry.dart';
import 'package:prism/data/native_bridge.dart';
import 'package:prism/data/thumbnail_cache.dart';
import 'package:prism/state/app_state.dart';
import 'package:prism/state/file_clipboard.dart';
import 'package:prism/state/pane_controller.dart';
import 'package:prism/state/settings_controller.dart';
import 'package:prism/ui/pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造一个指向临时目录的 AppState，避免测试触碰真实设备存储。
///
/// 必须在真实异步环境（`tester.runAsync`）中调用：内部会执行真实的
/// 文件系统 I/O，在 `testWidgets` 的 FakeAsync 区域内直接 await 会死锁。
Future<AppState> buildTestState(Directory root) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SettingsController settings = await SettingsController.load();
  // 关闭缩略图，避免测试中触发真实图片解码，让结果保持确定性。
  await settings.setThumbnailsEnabled(false);

  const FileRepository repository = FileRepository();
  const FileOperationService operations = FileOperationService();

  final PaneController left = PaneController(
    repository: repository,
    settings: settings,
    isLeft: true,
    initialPath: root.path,
  );
  final PaneController right = PaneController(
    repository: repository,
    settings: settings,
    isLeft: false,
    initialPath: root.path,
  );

  final AppState state = AppState(
    left,
    right,
    settings: settings,
    repository: repository,
    operations: operations,
    bridge: NativeBridge(),
    clipboard: FileClipboard(),
    thumbnails: ThumbnailCache(),
  );

  await left.initialize();
  await right.initialize();
  return state;
}

/// 主界面渲染测试。
void main() {
  late Directory tempDir;

  setUp(() async {
    // 屏蔽原生通道调用，返回空实现。
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(AppConstants.nativeChannel),
      (MethodCall call) async => null,
    );

    tempDir = await Directory.systemTemp.createTemp('prism_test_');
    await File('${tempDir.path}/note.txt').writeAsString('hello prism');
    await Directory('${tempDir.path}/sub').create();
    await File('${tempDir.path}/.hidden').writeAsString('secret');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 在真实异步环境中构建状态，然后挂载主界面。
  Future<AppState> mountHome(WidgetTester tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = await buildTestState(tempDir);
    });
    addTearDown(state.dispose);

    await tester.pumpWidget(MaterialApp(home: HomePage(appState: state)));
    await tester.pump();
    return state;
  }

  testWidgets('主界面可渲染并列出目录内容', (WidgetTester tester) async {
    await mountHome(tester);

    expect(find.text('Prism'), findsOneWidget);
    expect(find.text('note.txt'), findsWidgets);
    expect(find.text('sub'), findsWidgets);
    // 默认不显示隐藏文件。
    expect(find.text('.hidden'), findsNothing);
  });

  testWidgets('长按进入多选并更新标题', (WidgetTester tester) async {
    final AppState state = await mountHome(tester);

    await tester.longPress(find.text('note.txt').first);
    await tester.pump();

    expect(state.multiSelectMode, isTrue);
    expect(state.activePane.selectionCount, 1);
    expect(find.textContaining('已选择'), findsOneWidget);
  });

  testWidgets('显示隐藏文件开关生效', (WidgetTester tester) async {
    final AppState state = await mountHome(tester);

    await tester.runAsync(() async {
      await state.settings.setShowHidden(true);
      await state.left.refresh();
    });
    await tester.pump();

    expect(find.text('.hidden'), findsWidgets);
  });

  testWidgets('窄屏显示左右列切换器', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await mountHome(tester);

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
  });

  testWidgets('宽屏并排显示两列', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await mountHome(tester);

    // 宽屏时没有列切换器，两列同时可见。
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('note.txt'), findsNWidgets(2));
  });

  group('文件操作', () {
    test('复制文件后内容一致', () async {
      final Directory source = await Directory.systemTemp.createTemp('prism_src_');
      final Directory target = await Directory.systemTemp.createTemp('prism_dst_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await target.delete(recursive: true);
      });

      final File file = File('${source.path}/a.txt');
      await file.writeAsString('payload');

      const FileOperationService service = FileOperationService();
      final OperationResult result = await service.transfer(
        sources: <String>[file.path],
        destinationDir: target.path,
        move: false,
      );

      expect(result.succeeded, 1);
      expect(result.failed, isEmpty);
      expect(await File('${target.path}/a.txt').readAsString(), 'payload');
      // 源文件仍在（复制而非移动）。
      expect(file.existsSync(), isTrue);
    });

    test('移动文件后源文件消失', () async {
      final Directory source = await Directory.systemTemp.createTemp('prism_src_');
      final Directory target = await Directory.systemTemp.createTemp('prism_dst_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await target.delete(recursive: true);
      });

      final File file = File('${source.path}/b.txt');
      await file.writeAsString('payload');

      const FileOperationService service = FileOperationService();
      final OperationResult result = await service.transfer(
        sources: <String>[file.path],
        destinationDir: target.path,
        move: true,
      );

      expect(result.succeeded, 1);
      expect(file.existsSync(), isFalse);
      expect(File('${target.path}/b.txt').existsSync(), isTrue);
    });

    test('重名复制自动追加序号', () async {
      final Directory source = await Directory.systemTemp.createTemp('prism_src_');
      final Directory target = await Directory.systemTemp.createTemp('prism_dst_');
      addTearDown(() async {
        await source.delete(recursive: true);
        await target.delete(recursive: true);
      });

      final File file = File('${source.path}/c.txt');
      await file.writeAsString('new');
      await File('${target.path}/c.txt').writeAsString('old');

      const FileOperationService service = FileOperationService();
      await service.transfer(
        sources: <String>[file.path],
        destinationDir: target.path,
        move: false,
      );

      expect(await File('${target.path}/c.txt').readAsString(), 'old');
      expect(await File('${target.path}/c (1).txt').readAsString(), 'new');
    });

    test('拒绝把目录移动到自身子目录', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_self_');
      addTearDown(() => root.delete(recursive: true));

      final Directory parent = Directory('${root.path}/parent');
      final Directory child = Directory('${parent.path}/child');
      await child.create(recursive: true);

      const FileOperationService service = FileOperationService();
      final OperationResult result = await service.transfer(
        sources: <String>[parent.path],
        destinationDir: child.path,
        move: true,
      );

      expect(result.succeeded, 0);
      expect(result.failed, isNotEmpty);
      expect(parent.existsSync(), isTrue);
    });

    test('递归删除目录', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_del_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });

      final Directory nested = Directory('${root.path}/a/b/c');
      await nested.create(recursive: true);
      await File('${nested.path}/deep.txt').writeAsString('x');

      const FileOperationService service = FileOperationService();
      final OperationResult result = await service.delete(paths: <String>[root.path]);

      expect(result.succeeded, 1);
      expect(root.existsSync(), isFalse);
    });

    test('重命名并拒绝非法名称', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_ren_');
      addTearDown(() => root.delete(recursive: true));

      final File file = File('${root.path}/old.txt');
      await file.writeAsString('x');

      const FileOperationService service = FileOperationService();
      final String renamed = await service.rename(file.path, 'new.txt');
      expect(renamed, '${root.path}/new.txt');
      expect(File(renamed).existsSync(), isTrue);

      await expectLater(
        service.rename(renamed, 'bad/name.txt'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('新建文件夹与文件', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_new_');
      addTearDown(() => root.delete(recursive: true));

      const FileOperationService service = FileOperationService();
      final String dir = await service.createDirectory(root.path, '新建文件夹');
      expect(Directory(dir).existsSync(), isTrue);

      final String file = await service.createFile(root.path, 'a.txt', content: 'hi');
      expect(await File(file).readAsString(), 'hi');

      // 同名创建应当失败。
      await expectLater(
        service.createDirectory(root.path, '新建文件夹'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('FileRepository', () {
    test('列举目录并按规则排序', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_list_');
      addTearDown(() => root.delete(recursive: true));

      await Directory('${root.path}/zdir').create();
      await File('${root.path}/a.txt').writeAsString('1');
      await File('${root.path}/b.txt').writeAsString('22');

      const FileRepository repository = FileRepository();
      final DirectoryListing listing = await repository.listDirectory(root.path);

      expect(listing.isOk, isTrue);
      // 目录优先，其后按名称升序。
      expect(
        listing.entries.map((FileEntry entry) => entry.name).toList(),
        <String>['zdir', 'a.txt', 'b.txt'],
      );
    });

    test('不存在的目录返回错误而非抛异常', () async {
      const FileRepository repository = FileRepository();
      final DirectoryListing listing =
          await repository.listDirectory('/definitely/not/here/prism');
      expect(listing.isOk, isFalse);
      expect(listing.entries, isEmpty);
    });

    test('读取文本预览', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_txt_');
      addTearDown(() => root.delete(recursive: true));

      final File file = File('${root.path}/t.txt');
      await file.writeAsString('中文内容 abc');

      const FileRepository repository = FileRepository();
      expect(await repository.readTextPreview(file.path), '中文内容 abc');
    });

    test('递归搜索命中子目录文件', () async {
      final Directory root = await Directory.systemTemp.createTemp('prism_search_');
      addTearDown(() => root.delete(recursive: true));

      final Directory nested = Directory('${root.path}/deep/nested');
      await nested.create(recursive: true);
      await File('${nested.path}/target.txt').writeAsString('x');

      const FileRepository repository = FileRepository();
      final List<SearchHit> hits =
          await repository.search(root.path, query: 'target').toList();

      expect(hits.length, 1);
      expect(hits.first.entry.name, 'target.txt');
      expect(hits.first.matchStart, 0);
    });
  });
}
