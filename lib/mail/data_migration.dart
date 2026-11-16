import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 2026-11-16 关掉了 Mac 沙盒（要读用户选的本机模型文件夹、以后存附件到「下载」）。
/// 关掉后 App 数据文件夹从
///   ~/Library/Containers/com.vk.autoTransMail/Data/Library/Application Support/com.vk.autoTransMail
/// 变成
///   ~/Library/Application Support/com.vk.autoTransMail
/// 第一次启动时把旧文件夹里的东西（账户、翻译设置、译文缓存……）复制过来；新文件夹里已有的文件不覆盖。旧文件夹不删。
class DataMigration {
  static Future<void> fromSandbox() async {
    if (!Platform.isMacOS) return;
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final dest = await getApplicationSupportDirectory();
    if (dest.path.contains('/Library/Containers/')) return; // 还在沙盒里，不用搬
    final marker = File('${dest.path}/.migrated_from_sandbox');
    if (await marker.exists()) return;
    final src = Directory(
      '$home/Library/Containers/com.vk.autoTransMail/Data/Library/Application Support/com.vk.autoTransMail',
    );
    if (await src.exists()) {
      await dest.create(recursive: true);
      await for (final e in src.list(recursive: true)) {
        final rel = e.path.substring(src.path.length);
        if (e is Directory) {
          await Directory('${dest.path}$rel').create(recursive: true);
        } else if (e is File) {
          final to = File('${dest.path}$rel');
          if (!await to.exists()) {
            await to.parent.create(recursive: true);
            await e.copy(to.path);
          }
        }
      }
    }
    await dest.create(recursive: true);
    await marker.writeAsString(DateTime.now().toIso8601String());
  }
}
