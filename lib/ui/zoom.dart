import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// 全局字号缩放（菜单「显示 → 放大 ⌘+ / 缩小 ⌘- / 实际大小 ⌘0」）。
/// 整个界面的文字一起变，读信的 HTML 正文也跟着变；设置存在本机，下次打开保持。
class Zoom {
  static const min = 0.8;
  static const max = 2.0;
  static const step = 0.1;

  static final scale = ValueNotifier<double>(1.0);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/zoom.json');
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final v = (jsonDecode(await f.readAsString()) as Map<String, dynamic>)['scale'];
        if (v is num) scale.value = v.toDouble().clamp(min, max);
      }
    } catch (_) {}
  }

  static void _set(double v) {
    // 四舍五入到 0.1，避免累加出 1.2000000001
    scale.value = (v.clamp(min, max) * 10).roundToDouble() / 10;
    _file().then((f) => f.writeAsString(jsonEncode({'scale': scale.value}))).catchError((_) => File(''));
  }

  static void zoomIn() => _set(scale.value + step);
  static void zoomOut() => _set(scale.value - step);
  static void reset() => _set(1.0);
}
