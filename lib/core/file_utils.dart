import 'package:path/path.dart' as p;

/// 文件类别，用于选择图标、决定能否预览以及 MIME 推断。
enum FileKind {
  directory,
  image,
  video,
  audio,
  archive,
  apk,
  document,
  code,
  text,
  font,
  database,
  unknown,
}

/// 与文件路径、扩展名相关的纯函数集合。
abstract final class FileUtils {
  static const Set<String> imageExtensions = <String>{
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif', 'avif', 'svg', 'ico', 'tif', 'tiff',
  };

  static const Set<String> videoExtensions = <String>{
    'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', '3gp', 'm4v', 'ts', 'rmvb', 'mpg', 'mpeg',
  };

  static const Set<String> audioExtensions = <String>{
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus', 'amr', 'mid', 'midi',
  };

  static const Set<String> archiveExtensions = <String>{
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'jar', 'apks', 'iso', 'lz4', 'zst',
  };

  static const Set<String> documentExtensions = <String>{
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf', 'epub', 'csv',
  };

  static const Set<String> codeExtensions = <String>{
    'dart', 'kt', 'java', 'js', 'ts', 'jsx', 'tsx', 'py', 'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs',
    'rb', 'php', 'swift', 'sh', 'bash', 'lua', 'sql', 'gradle', 'groovy', 'vue', 'html', 'css', 'scss',
  };

  static const Set<String> textExtensions = <String>{
    'txt', 'md', 'markdown', 'log', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'cfg', 'properties',
    'toml', 'env', 'srt', 'vtt', 'pro', 'gitignore',
  };

  static const Set<String> fontExtensions = <String>{'ttf', 'otf', 'woff', 'woff2'};

  static const Set<String> databaseExtensions = <String>{'db', 'sqlite', 'sqlite3', 'realm'};

  /// 提取小写扩展名（不含点）；无扩展名返回空串。
  static String extensionOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// 提取不含扩展名的显示名。
  static String stemOf(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }

  /// 规范化路径：折叠多余的 `/`，去掉结尾 `/`（根目录除外）。
  static String normalize(String path) {
    if (path.isEmpty) {
      return '/';
    }
    String result = p.posix.normalize(path.replaceAll('\\', '/'));
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 父目录；已在根目录时返回根目录。
  static String parentOf(String path) {
    final String normalized = normalize(path);
    if (normalized == '/') {
      return '/';
    }
    final String parent = p.posix.dirname(normalized);
    return parent.isEmpty ? '/' : parent;
  }

  /// 目录名，用于面包屑展示。
  static String baseName(String path) {
    final String normalized = normalize(path);
    if (normalized == '/') {
      return '/';
    }
    final String base = p.posix.basename(normalized);
    return base.isEmpty ? normalized : base;
  }

  /// 拼接子路径。
  static String join(String directory, String name) {
    if (directory == '/') {
      return '/$name';
    }
    return '${normalize(directory)}/$name';
  }

  /// 判断 `path` 是否位于 `ancestor` 之内（含自身）。
  static bool isInside(String path, String ancestor) {
    final String a = normalize(ancestor);
    final String c = normalize(path);
    if (a == c) {
      return true;
    }
    return c.startsWith(a == '/' ? '/' : '$a/');
  }

  /// 根据名称推断文件类别。
  static FileKind kindOf(String name, {bool isDirectory = false}) {
    if (isDirectory) {
      return FileKind.directory;
    }
    final String ext = extensionOf(name);
    if (ext.isEmpty) {
      return FileKind.unknown;
    }
    if (imageExtensions.contains(ext)) {
      return FileKind.image;
    }
    if (videoExtensions.contains(ext)) {
      return FileKind.video;
    }
    if (audioExtensions.contains(ext)) {
      return FileKind.audio;
    }
    if (ext == 'apk') {
      return FileKind.apk;
    }
    if (archiveExtensions.contains(ext)) {
      return FileKind.archive;
    }
    if (documentExtensions.contains(ext)) {
      return FileKind.document;
    }
    if (codeExtensions.contains(ext)) {
      return FileKind.code;
    }
    if (textExtensions.contains(ext)) {
      return FileKind.text;
    }
    if (fontExtensions.contains(ext)) {
      return FileKind.font;
    }
    if (databaseExtensions.contains(ext)) {
      return FileKind.database;
    }
    return FileKind.unknown;
  }

  /// 是否为可解码的位图（svg 需要额外渲染器，故排除）。
  static bool isDecodableImage(String name) {
    final String ext = extensionOf(name);
    return imageExtensions.contains(ext) && ext != 'svg';
  }

  /// 是否为可当作文本读取的文件。
  static bool isTextLike(String name) {
    final FileKind kind = kindOf(name);
    return kind == FileKind.text || kind == FileKind.code;
  }

  /// 推测 MIME 类型，供系统「打开方式」使用。
  static String mimeTypeOf(String name) {
    switch (kindOf(name)) {
      case FileKind.directory:
        return 'resource/folder';
      case FileKind.image:
        return switch (extensionOf(name)) {
          'png' => 'image/png',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          'bmp' => 'image/bmp',
          'heic' || 'heif' => 'image/heic',
          'svg' => 'image/svg+xml',
          _ => 'image/*',
        };
      case FileKind.video:
        return 'video/*';
      case FileKind.audio:
        return 'audio/*';
      case FileKind.apk:
        return 'application/vnd.android.package-archive';
      case FileKind.archive:
        return switch (extensionOf(name)) {
          'zip' => 'application/zip',
          'rar' => 'application/x-rar-compressed',
          '7z' => 'application/x-7z-compressed',
          'tar' => 'application/x-tar',
          'gz' || 'tgz' => 'application/gzip',
          _ => 'application/octet-stream',
        };
      case FileKind.document:
        return switch (extensionOf(name)) {
          'pdf' => 'application/pdf',
          'epub' => 'application/epub+zip',
          'csv' => 'text/csv',
          _ => 'application/octet-stream',
        };
      case FileKind.text:
      case FileKind.code:
        return 'text/plain';
      case FileKind.font:
        return 'font/ttf';
      case FileKind.database:
        return 'application/x-sqlite3';
      case FileKind.unknown:
        return '*/*';
    }
  }

  /// 过滤非法文件名字符，并在必要时补充唯一后缀。
  static bool isValidFileName(String name) {
    if (name.isEmpty || name == '.' || name == '..') {
      return false;
    }
    if (name.contains('/') || name.contains('\u0000')) {
      return false;
    }
    return true;
  }

  /// 生成 `name (1).ext` 形式的候选名，用于解决重名冲突。
  static String dedupeName(String name, {required bool Function(String candidate) exists}) {
    if (!exists(name)) {
      return name;
    }
    final String stem = stemOf(name);
    final String ext = extensionOf(name);
    final String suffix = ext.isEmpty ? '' : '.$ext';
    for (int i = 1; i < 10000; i++) {
      final String candidate = '$stem ($i)$suffix';
      if (!exists(candidate)) {
        return candidate;
      }
    }
    return '$stem (${DateTime.now().millisecondsSinceEpoch})$suffix';
  }
}
