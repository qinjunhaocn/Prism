/// 应用级常量与全局约定。
///
/// 所有需要跨层共享的字面量集中在此，避免散落在各处导致不一致。
abstract final class AppConstants {
  /// 展示用应用名。
  static const String appName = 'Prism';

  /// Android applicationId，同时用于原生侧包名。
  static const String packageName = 'com.voxyn.prism';

  /// Flutter 与原生通信的通道名。
  static const String nativeChannel = 'com.voxyn.prism/native';

  /// 文件系统根目录。
  static const String rootPath = '/';

  /// Android 主共享存储挂载点。
  static const String primaryStoragePath = '/storage/emulated/0';

  /// 分栏数量：Prism 为双列文件管理器。
  static const int paneCount = 2;

  /// 目录列举时的并发 stat 上限，兼顾速度与 fd 占用。
  static const int statConcurrency = 24;

  /// 判定「宽屏」的阈值，超过则两列并排展示。
  static const double wideLayoutBreakpoint = 720;

  /// 列表行高，固定后可用 itemExtent 加速布局。
  static const double listItemExtent = 60;

  /// 网格单元最小宽度，用于计算列数。
  static const double gridTileMinWidth = 104;

  /// 网格单元高度。
  static const double gridTileExtent = 116;

  /// 文本预览最多读取的字节数。
  static const int textPreviewLimit = 256 * 1024;

  /// 缩略图解码上限，控制内存占用。
  static const int thumbnailDecodeWidth = 256;
}
