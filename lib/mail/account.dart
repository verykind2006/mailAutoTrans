import 'dart:convert';
import 'dart:io';
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:path_provider/path_provider.dart';

/// 一个邮箱账户的连接设置。
class Account {
  Account({
    required this.email,
    required this.userName,
    required this.password,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
    this.displayName = '',
  });

  final String email; // 发信时的「发件人」地址
  final String displayName; // 发件人名字（对方看到的），可以空
  final String userName; // 登录名，绝大多数邮箱就是邮箱地址
  final String password; // 客户端专用密码 / 应用专用密码
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;

  Map<String, dynamic> toJson() => {
    'email': email,
    'userName': userName,
    'password': password,
    'imapHost': imapHost,
    'imapPort': imapPort,
    'smtpHost': smtpHost,
    'smtpPort': smtpPort,
    'displayName': displayName,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    email: j['email'] as String,
    userName: j['userName'] as String,
    password: j['password'] as String,
    imapHost: j['imapHost'] as String,
    imapPort: j['imapPort'] as int,
    smtpHost: j['smtpHost'] as String,
    smtpPort: j['smtpPort'] as int,
    displayName: j['displayName'] as String? ?? '',
  );
}

/// 常用邮箱的服务器设置，选了就自动填好。
class MailPreset {
  const MailPreset(this.label, this.imapHost, this.imapPort, this.smtpHost, this.smtpPort, this.hint);
  final String label;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;
  final String hint; // 密码去哪里拿

  static const all = [
    MailPreset(
      'Gmail',
      'imap.gmail.com',
      993,
      'smtp.gmail.com',
      465,
      '要用「应用专用密码」：先开两步验证，再打开网址 myaccount.google.com/apppasswords 生成（Google 设置菜单里已经不显示这一项）。',
    ),
    MailPreset(
      'iCloud 邮箱',
      'imap.mail.me.com',
      993,
      'smtp.mail.me.com',
      587,
      '要用「App 专用密码」：在 account.apple.com 的「登录与安全」里生成。',
    ),
    MailPreset('QQ 邮箱', 'imap.qq.com', 993, 'smtp.qq.com', 465, '要用「授权码」：QQ 邮箱网页版 → 设置 → 账户 → 开启 IMAP/SMTP 后生成。'),
    MailPreset('163 邮箱', 'imap.163.com', 993, 'smtp.163.com', 465, '要用「授权码」：163 邮箱网页版 → 设置 → POP3/SMTP/IMAP。'),
  ];
}

/// 邮箱账户列表存在本机的应用数据文件夹里：accounts.json（数组，密码是明文）。
/// 不用 Mac 钥匙串：自签名的 App 每次重新编译后读钥匙串都会弹窗要密码（用户 2026-11-10 的要求）。
/// 旧版本只有一个账户，存在 account.json；第一次读时自动搬进列表。
class AccountStore {
  static Future<Directory> _dir() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  static Future<List<Account>> loadAll() async {
    final dir = await _dir();
    final f = File('${dir.path}/accounts.json');
    if (await f.exists()) {
      try {
        return (jsonDecode(await f.readAsString()) as List)
            .map((e) => Account.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
    // 旧版的单个账户
    final old = File('${dir.path}/account.json');
    if (await old.exists()) {
      try {
        final a = Account.fromJson(jsonDecode(await old.readAsString()) as Map<String, dynamic>);
        await saveAll([a]);
        await old.delete();
        return [a];
      } catch (_) {}
    }
    return [];
  }

  static Future<void> saveAll(List<Account> accounts) async {
    final dir = await _dir();
    await File('${dir.path}/accounts.json').writeAsString(jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }
}
