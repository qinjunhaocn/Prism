import 'package:flutter/material.dart';

import '../../core/file_utils.dart';
import '../../data/models/file_entry.dart';

/// 文件类型图标与配色。
///
/// 颜色由 [ColorScheme] 派生，保证在 Monet 动态取色下依然协调。
abstract final class FileVisuals {
  /// 取条目对应的图标。
  static IconData iconFor(FileEntry entry) {
    if (entry.isLink) {
      return Icons.link_rounded;
    }
    return iconForKind(entry.kind);
  }

  /// 取类别对应的图标。
  static IconData iconForKind(FileKind kind) => switch (kind) {
        FileKind.directory => Icons.folder_rounded,
        FileKind.image => Icons.image_rounded,
        FileKind.video => Icons.movie_rounded,
        FileKind.audio => Icons.audiotrack_rounded,
        FileKind.archive => Icons.folder_zip_rounded,
        FileKind.apk => Icons.android_rounded,
        FileKind.document => Icons.description_rounded,
        FileKind.code => Icons.code_rounded,
        FileKind.text => Icons.article_rounded,
        FileKind.font => Icons.text_fields_rounded,
        FileKind.database => Icons.storage_rounded,
        FileKind.unknown => Icons.insert_drive_file_rounded,
      };

  /// 取条目对应的强调色。
  static Color colorFor(FileEntry entry, ColorScheme scheme) {
    if (entry.isDirectory) {
      return scheme.primary;
    }
    return colorForKind(entry.kind, scheme);
  }

  /// 取类别对应的强调色。
  static Color colorForKind(FileKind kind, ColorScheme scheme) => switch (kind) {
        FileKind.directory => scheme.primary,
        FileKind.image => scheme.tertiary,
        FileKind.video => scheme.secondary,
        FileKind.audio => scheme.secondary,
        FileKind.archive => scheme.tertiary,
        FileKind.apk => scheme.primary,
        FileKind.document => scheme.secondary,
        FileKind.code => scheme.tertiary,
        FileKind.text => scheme.onSurfaceVariant,
        FileKind.font => scheme.onSurfaceVariant,
        FileKind.database => scheme.onSurfaceVariant,
        FileKind.unknown => scheme.onSurfaceVariant,
      };

  /// 权限标记：不可读 / 不可写。
  static List<IconData> permissionBadges(FileEntry entry) {
    final List<IconData> badges = <IconData>[];
    if (!entry.isReadable) {
      badges.add(Icons.lock_rounded);
    }
    if (!entry.isWritable && entry.isReadable) {
      badges.add(Icons.lock_outline_rounded);
    }
    return badges;
  }
}

/// 文件类型图标徽标。
class FileIcon extends StatelessWidget {
  const FileIcon({
    required this.entry,
    this.size = 40,
    this.showBadge = true,
    super.key,
  });

  final FileEntry entry;
  final double size;

  /// 是否显示符号链接等角标。
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = FileVisuals.colorFor(entry, scheme);
    final IconData icon = FileVisuals.iconFor(entry);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(size * 0.28),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: size * 0.56, color: color),
          ),
          if (showBadge && entry.isLink)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shortcut_rounded,
                  size: size * 0.26,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
