import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/file_utils.dart';
import '../../data/file_repository.dart';
import '../../data/models/file_entry.dart';
import '../../state/app_state.dart';
import '../../state/pane_controller.dart';
import '../dialogs/properties_sheet.dart';
import '../viewers/file_viewer_page.dart';
import '../widgets/file_icon.dart';
import '../widgets/file_thumbnail.dart';

/// 面板内递归搜索页。
///
/// 搜索以流式方式返回结果，边搜边显示；用户可随时停止或跳转到文件所在目录。
class PaneSearchPage extends StatefulWidget {
  const PaneSearchPage({
    required this.appState,
    required this.pane,
    super.key,
  });

  final AppState appState;
  final PaneController pane;

  @override
  State<PaneSearchPage> createState() => _PaneSearchPageState();
}

class _PaneSearchPageState extends State<PaneSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<SearchHit> _results = <SearchHit>[];

  StreamSubscription<SearchHit>? _subscription;
  bool _searching = false;
  bool _useRegex = false;
  bool _searchDirectories = true;
  bool _cancelled = false;
  bool _truncated = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 开始搜索；会先取消上一次搜索。
  void _startSearch() {
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }
    unawaited(_subscription?.cancel());
    setState(() {
      _query = query;
      _results.clear();
      _searching = true;
      _cancelled = false;
      _truncated = false;
    });

    final Stream<SearchHit> stream = widget.pane.search(
      query,
      useRegex: _useRegex,
      searchDirectories: _searchDirectories,
      isCancelled: () => _cancelled,
    );

    _subscription = stream.listen(
      (SearchHit hit) {
        if (!mounted) {
          return;
        }
        setState(() => _results.add(hit));
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _searching = false;
          // 结果数量达到上限时提示用户。
          if (_results.length >= 2000) {
            _truncated = true;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() => _searching = false);
      },
    );
  }

  /// 停止搜索。
  void _stopSearch() {
    _cancelled = true;
    unawaited(_subscription?.cancel());
    setState(() => _searching = false);
  }

  /// 打开搜索结果所在目录。
  Future<void> _revealInPane(SearchHit hit) async {
    final String parent = FileUtils.parentOf(hit.entry.path);
    Navigator.of(context).pop();
    await widget.pane.open(parent);
    widget.pane.selectOnly(hit.entry.path);
  }

  /// 打开文件。
  Future<void> _openHit(SearchHit hit) async {
    final FileEntry entry = hit.entry;
    if (entry.isDirectory) {
      Navigator.of(context).pop();
      await widget.pane.open(entry.path);
      return;
    }
    if (FileUtils.isDecodableImage(entry.name) || FileUtils.isTextLike(entry.name)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => FileViewerPage(
            entry: entry,
            repository: widget.appState.repository,
          ),
        ),
      );
      return;
    }
    final bool ok = await widget.appState.bridge.openFile(
      entry.path,
      mimeType: FileUtils.mimeTypeOf(entry.name),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('无法打开该文件')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _startSearch(),
          decoration: InputDecoration(
            hintText: '在 ${widget.pane.title} 中搜索',
            border: InputBorder.none,
            filled: false,
            isDense: true,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          style: theme.textTheme.bodyLarge,
        ),
        actions: <Widget>[
          if (_searching)
            IconButton(
              onPressed: _stopSearch,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止搜索',
            )
          else
            IconButton(
              onPressed: _startSearch,
              icon: const Icon(Icons.search_rounded),
              tooltip: '搜索',
            ),
          PopupMenuButton<String>(
            tooltip: '搜索选项',
            icon: const Icon(Icons.tune_rounded),
            onSelected: (String value) {
              setState(() {
                switch (value) {
                  case 'regex':
                    _useRegex = !_useRegex;
                  case 'dirs':
                    _searchDirectories = !_searchDirectories;
                }
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              CheckedPopupMenuItem<String>(
                value: 'regex',
                checked: _useRegex,
                child: const Text('正则表达式'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'dirs',
                checked: _searchDirectories,
                child: const Text('包含文件夹'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_searching)
            const LinearProgressIndicator(minHeight: 2),
          _buildSummary(theme),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  /// 结果统计条。
  Widget _buildSummary(ThemeData theme) {
    if (_query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '输入关键词后回车开始搜索。\n搜索范围为当前目录「${widget.pane.path}」及其子目录。',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final String suffix = _searching ? '搜索中…' : '搜索完成';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$suffix · 找到 ${_results.length} 项${_truncated ? '（已达上限）' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// 结果列表。
  Widget _buildResults() {
    if (_results.isEmpty) {
      if (_searching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_query.isEmpty) {
        return const SizedBox.shrink();
      }
      return const Center(child: Text('没有找到匹配的文件'));
    }

    return ListView.builder(
      itemCount: _results.length,
      itemExtent: 64,
      scrollCacheExtent: const ScrollCacheExtent.pixels(64 * 8),
      itemBuilder: (BuildContext context, int index) {
        final SearchHit hit = _results[index];
        final FileEntry entry = hit.entry;
        final ColorScheme scheme = Theme.of(context).colorScheme;

        return RepaintBoundary(
          child: ListTile(
            leading: FileIcon(entry: entry, size: 40),
            title: HighlightedName(
              text: entry.name,
              matchStart: hit.matchStart,
              matchEnd: hit.matchEnd,
            ),
            subtitle: Text(
              FileUtils.parentOf(entry.path),
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 20, color: scheme.onSurfaceVariant),
              onSelected: (String value) async {
                switch (value) {
                  case 'reveal':
                    await _revealInPane(hit);
                  case 'properties':
                    await showPropertiesSheet(
                      context: context,
                      entry: entry,
                      repository: widget.appState.repository,
                      bridge: widget.appState.bridge,
                    );
                  case 'open':
                    await _openHit(hit);
                }
              },
              itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'open', child: Text('打开')),
                PopupMenuItem<String>(value: 'reveal', child: Text('在面板中定位')),
                PopupMenuItem<String>(value: 'properties', child: Text('属性')),
              ],
            ),
            onTap: () => _openHit(hit),
            onLongPress: () => _revealInPane(hit),
          ),
        );
      },
    );
  }
}
