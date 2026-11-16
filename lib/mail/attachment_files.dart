import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 附件的「打开 / 存到下载」。Mac 沙盒已关（2026-11-16），可以直接写「下载」、用系统默认程序打开。
class AttachmentFiles {
  /// 文件名里不能出现的字符换掉（/ : 等），防止写到别的文件夹去
  static String safeName(String name) {
    final n = name.replaceAll(RegExp(r'[/\\:\x00-\x1f]'), '_').trim();
    return n.isEmpty || n == '.' || n == '..' ? '附件' : n;
  }

  /// 在 [dir] 里找一个不重名的路径：报价.pdf → 报价 (1).pdf → 报价 (2).pdf …
  static Future<String> uniquePath(String dir, String name) async {
    final safe = safeName(name);
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    var path = '$dir/$safe';
    for (var i = 1; await File(path).exists() || await Directory(path).exists(); i++) {
      path = '$dir/$base ($i)$ext';
    }
    return path;
  }

  /// 存到「下载」文件夹，返回存好的路径
  static Future<String> saveToDownloads(String name, Uint8List data) async {
    final dir = (await getDownloadsDirectory())?.path ?? '${Platform.environment['HOME']}/Downloads';
    await Directory(dir).create(recursive: true);
    final path = await uniquePath(dir, name);
    await File(path).writeAsBytes(data, flush: true);
    return path;
  }

  /// 用系统默认程序打开（先写到 App 的临时文件夹里）
  static Future<void> open(String name, Uint8List data) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/mailautotrans-attachments/${DateTime.now().microsecondsSinceEpoch}');
    await dir.create(recursive: true);
    final path = '${dir.path}/${safeName(name)}';
    await File(path).writeAsBytes(data, flush: true);
    await _run('open', [path]);
  }

  /// 在访达里显示这个文件
  static Future<void> reveal(String path) => _run('open', ['-R', path]);

  static Future<void> _run(String cmd, List<String> args) async {
    if (!Platform.isMacOS) throw UnsupportedError('目前只支持 Mac');
    final r = await Process.run(cmd, args);
    if (r.exitCode != 0) throw Exception('${r.stderr}'.trim());
  }

  /// 1234567 → 1.2 MB
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
