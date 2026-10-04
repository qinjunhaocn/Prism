/// 与展示相关的格式化工具。
///
/// 只做纯计算，不依赖 Flutter，便于单元测试与在 isolate 中复用。
abstract final class Formatters {
  static const List<String> _sizeUnits = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  /// 将字节数格式化为易读字符串，例如 `1.5 MB`。
  ///
  /// 采用 1024 进制，保留 1 位小数（字节数本身不带小数）。
  static String fileSize(int bytes) {
    if (bytes < 0) {
      return '--';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < _sizeUnits.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final String text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${_sizeUnits[unitIndex]}';
  }

  /// 格式化为 `yyyy-MM-dd HH:mm`。
  static String dateTime(DateTime time) {
    final DateTime local = time.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String mo = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final String h = local.hour.toString().padLeft(2, '0');
    final String mi = local.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  /// 格式化为 `yyyy-MM-dd`。
  static String date(DateTime time) {
    final DateTime local = time.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String mo = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    return '$y-$mo-$d';
  }

  /// 相对时间描述，例如 `3 分钟前`，超过 7 天则退回绝对日期。
  static String relativeTime(DateTime time, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final Duration diff = reference.difference(time);
    if (diff.isNegative) {
      return dateTime(time);
    }
    if (diff.inSeconds < 60) {
      return '刚刚';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    }
    return date(time);
  }

  /// 刷新率展示，例如 `120 Hz`。
  static String refreshRate(double hz) {
    if (hz <= 0) {
      return '--';
    }
    final double rounded = (hz * 100).roundToDouble() / 100;
    final String text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(2);
    return '$text Hz';
  }

  /// 计数展示，超过 999 使用 `k` 缩写。
  static String count(int value) {
    if (value < 1000) {
      return '$value';
    }
    final double k = value / 1000;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
  }
}
