import 'package:flutter/foundation.dart';

import '../data/models/file_entry.dart';

/// 剪贴板操作类型。
enum ClipboardAction {
  copy,
  cut,
}

/// 文件剪贴板。
///
/// 只保存路径与操作类型，不持有文件句柄，因此可以长期存在；
/// 粘贴时才真正访问文件系统。
class FileClipboard extends ChangeNotifier {
  List<String> _paths = const <String>[];
  ClipboardAction _action = ClipboardAction.copy;

  /// 当前剪贴板中的路径。
  List<String> get paths => List<String>.unmodifiable(_paths);

  /// 当前操作类型。
  ClipboardAction get action => _action;

  /// 是否为空。
  bool get isEmpty => _paths.isEmpty;

  /// 条目数量。
  int get length => _paths.length;

  /// 写入剪贴板。
  void set(List<String> paths, ClipboardAction action) {
    _paths = List<String>.from(paths);
    _action = action;
    notifyListeners();
  }

  /// 从条目写入。
  void setFromEntries(List<FileEntry> entries, ClipboardAction action) {
    set(entries.map((FileEntry entry) => entry.path).toList(), action);
  }

  /// 清空剪贴板。
  void clear() {
    if (_paths.isEmpty) {
      return;
    }
    _paths = const <String>[];
    notifyListeners();
  }

  /// 判断某个路径是否在剪贴板中。
  bool contains(String path) => _paths.contains(path);

  /// 中文描述，用于底部提示条。
  String describe() {
    if (_paths.isEmpty) {
      return '';
    }
    final String verb = _action == ClipboardAction.copy ? '复制' : '剪切';
    return '$verb ${_paths.length} 项';
  }
}
