import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 发信时可选的目标语言。
enum TargetLang {
  es('西班牙语', '西班牙语（西班牙本地用法，不用拉美说法）'),
  en('英语', '英语'),
  it('意大利语', '意大利语'),
  fr('法语', '法语'),
  de('德语', '德语'),
  pt('葡萄牙语', '葡萄牙语（葡萄牙本地用法）'),
  zh('不翻译（直接发中文）', '中文');

  const TargetLang(this.title, this.promptName);
  final String title;
  final String promptName;

  static TargetLang? fromCode(String? code) {
    for (final l in values) {
      if (l.name == code) return l;
    }
    return null;
  }
}

/// 每个联系人记住上次用的目标语言（键 = 对方邮箱地址，小写）。存 App 数据文件夹的 contacts.json。
class ContactLangStore {
  static Map<String, dynamic>? _items;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/contacts.json');
  }

  static Future<Map<String, dynamic>> _all() async {
    if (_items != null) return _items!;
    final f = await _file();
    try {
      _items = await f.exists() ? jsonDecode(await f.readAsString()) as Map<String, dynamic> : {};
    } catch (_) {
      _items = {};
    }
    return _items!;
  }

  static Future<TargetLang?> get(String email) async =>
      TargetLang.fromCode((await _all())[email.trim().toLowerCase()] as String?);

  static Future<void> put(String email, TargetLang lang) async {
    final all = await _all();
    all[email.trim().toLowerCase()] = lang.name;
    await (await _file()).writeAsString(jsonEncode(all));
  }
}
