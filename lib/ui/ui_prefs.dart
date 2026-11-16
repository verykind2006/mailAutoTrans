import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// 界面上的小偏好（存本机 ui_prefs.json，下次打开保持）。
class UiPrefs {
  /// 信件列表显示原标题（true）还是中文标题（false，默认）
  static final showOriginalSubjects = ValueNotifier<bool>(false);

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/ui_prefs.json');
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        showOriginalSubjects.value = j['showOriginalSubjects'] == true;
      }
    } catch (_) {}
  }

  static Future<void> setShowOriginalSubjects(bool v) async {
    showOriginalSubjects.value = v;
    try {
      await (await _file()).writeAsString(jsonEncode({'showOriginalSubjects': v}));
    } catch (_) {}
  }
}
