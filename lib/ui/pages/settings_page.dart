import 'package:flutter/material.dart';

import '../../core/app_constants.dart';
import '../../core/formatters.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../theme/app_theme.dart';

/// 设置页。
///
/// 分为外观、行为、设备三组；所有开关即时生效并持久化。
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = appState.settings;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: AnimatedBuilder(
        animation: settings,
        builder: (BuildContext context, Widget? child) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              _SectionHeader(title: '外观', theme: theme),
              _SettingTile(
                icon: Icons.brightness_6_rounded,
                title: '主题模式',
                subtitle: AppTheme.themeModeLabel(settings.themeMode),
                trailing: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<AppThemeMode>>[
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded, size: 18),
                      tooltip: '跟随系统',
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded, size: 18),
                      tooltip: '浅色',
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded, size: 18),
                      tooltip: '深色',
                    ),
                  ],
                  selected: <AppThemeMode>{settings.themeMode},
                  onSelectionChanged: (Set<AppThemeMode> value) {
                    settings.setThemeMode(value.first);
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.palette_rounded),
                title: const Text('动态取色（Monet）'),
                subtitle: Text(
                  appState.androidSdk >= 31
                      ? '从壁纸提取配色（Android 12+）'
                      : '当前系统版本不支持，将使用下方种子色',
                ),
                value: settings.dynamicColorEnabled,
                onChanged: settings.setDynamicColorEnabled,
              ),
              if (!settings.dynamicColorEnabled || appState.androidSdk < 31)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('主题色', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: AppTheme.seedOptions.map((SeedColorOption option) {
                          final bool selected =
                              settings.seedColor.toARGB32() == option.color.toARGB32();
                          return Tooltip(
                            message: option.label,
                            child: InkWell(
                              onTap: () => settings.setSeedColor(option.color),
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: option.color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              _SettingTile(
                icon: Icons.view_agenda_rounded,
                title: '默认视图',
                subtitle: settings.viewMode == ViewMode.list ? '列表' : '网格',
                trailing: SegmentedButton<ViewMode>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<ViewMode>>[
                    ButtonSegment<ViewMode>(
                      value: ViewMode.list,
                      icon: Icon(Icons.view_list_rounded, size: 18),
                    ),
                    ButtonSegment<ViewMode>(
                      value: ViewMode.grid,
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                    ),
                  ],
                  selected: <ViewMode>{settings.viewMode},
                  onSelectionChanged: (Set<ViewMode> value) {
                    settings.setViewMode(value.first);
                  },
                ),
              ),
              _SettingTile(
                icon: Icons.density_medium_rounded,
                title: '列表密度',
                subtitle: switch (settings.listDensity) {
                  0 => '紧凑',
                  2 => '宽松',
                  _ => '标准',
                },
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 0, label: Text('紧凑')),
                    ButtonSegment<int>(value: 1, label: Text('标准')),
                    ButtonSegment<int>(value: 2, label: Text('宽松')),
                  ],
                  selected: <int>{settings.listDensity},
                  onSelectionChanged: (Set<int> value) {
                    settings.setListDensity(value.first);
                  },
                ),
              ),
              const Divider(height: 32),
              _SectionHeader(title: '行为', theme: theme),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_rounded),
                title: const Text('显示隐藏文件'),
                subtitle: const Text('显示以 . 开头的文件和文件夹'),
                value: settings.showHidden,
                onChanged: settings.setShowHidden,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.image_rounded),
                title: const Text('生成缩略图'),
                subtitle: const Text('为图片生成预览，关闭可提升滚动流畅度'),
                value: settings.thumbnailsEnabled,
                onChanged: settings.setThumbnailsEnabled,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.delete_outline_rounded),
                title: const Text('删除前确认'),
                subtitle: const Text('执行删除操作前弹出确认对话框'),
                value: settings.confirmDelete,
                onChanged: settings.setConfirmDelete,
              ),
              const Divider(height: 32),
              _SectionHeader(title: '性能', theme: theme),
              SwitchListTile(
                secondary: const Icon(Icons.speed_rounded),
                title: const Text('高刷新率'),
                subtitle: const Text('请求系统以设备支持的最高刷新率渲染'),
                value: settings.highRefreshEnabled,
                onChanged: (bool value) async {
                  await settings.setHighRefreshEnabled(value);
                  if (value) {
                    final double? hz = await appState.requestMaxRefreshRate();
                    if (hz != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text('已切换到 ${Formatters.refreshRate(hz)}')),
                        );
                    }
                  }
                },
              ),
              _SettingTile(
                icon: Icons.monitor_rounded,
                title: '屏幕刷新率',
                subtitle: appState.refreshRate == null
                    ? '未知'
                    : '当前 ${Formatters.refreshRate(appState.refreshRate!.currentHz)}'
                        ' · 最高 ${Formatters.refreshRate(appState.refreshRate!.maxHz)}',
                trailing: IconButton(
                  onPressed: () async {
                    await appState.requestMaxRefreshRate();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '重新读取',
                ),
              ),
              const Divider(height: 32),
              _SectionHeader(title: '关于', theme: theme),
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('${AppConstants.appName} 文件管理器'),
                subtitle: Text('版本 1.0.0 · 双列 Material Design 3'),
              ),
              ListTile(
                leading: const Icon(Icons.android_rounded),
                title: const Text('包名'),
                subtitle: const Text(AppConstants.packageName),
              ),
              if (appState.androidSdk > 0)
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: const Text('Android SDK'),
                  subtitle: Text('API ${appState.androidSdk}'),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 分组标题。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 通用设置项：图标 + 标题 + 副标题 + 尾部控件。
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
