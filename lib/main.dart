import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'mail/account.dart';
import 'mail/data_migration.dart';
import 'pages/account_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'translate/translator.dart';
import 'ui/kit.dart';
import 'ui/ui_prefs.dart';
import 'ui/zoom.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataMigration.fromSandbox(); // 关沙盒后第一次启动：把旧数据搬过来
  await Zoom.load();
  await UiPrefs.load();
  runApp(const AutoTransMailApp());
}

class AutoTransMailApp extends StatefulWidget {
  const AutoTransMailApp({super.key});

  @override
  State<AutoTransMailApp> createState() => _AutoTransMailAppState();
}

class _AutoTransMailAppState extends State<AutoTransMailApp> {
  // 菜单栏在 Navigator 外面，要靠这两个 key 打开页面、通知主界面收信
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _homeKey = GlobalKey<HomePageState>();

  List<Account> _accounts = [];
  bool _loaded = false;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    AccountStore.loadAll().then((list) {
      if (mounted) {
        setState(() {
          _accounts = list;
          _loaded = true;
        });
      }
    });
  }

  /// 邮箱列表改了：存到本机，主界面跟着刷新
  Future<void> _setAccounts(List<Account> list) async {
    await AccountStore.saveAll(list);
    if (mounted) setState(() => _accounts = list);
  }

  /// 打开设置（菜单「AutoTransMail → 设置…」⌘,）。tab 0 = 邮箱账户，1 = 翻译引擎
  Future<void> _openSettings([int tab = 0]) async {
    final nav = _navigatorKey.currentState;
    if (nav == null || _settingsOpen) return;
    _settingsOpen = true;
    final translate = await TranslateSettings.load();
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsPage(accounts: _accounts, translate: translate, initialTab: tab, onAccountsChanged: _setAccounts),
      ),
    );
    _settingsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final hasAccount = _accounts.isNotEmpty;
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'MailAutoTrans',
          menus: [
            const PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about)]),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: '设置…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
                  onSelected: _loaded ? () => _openSettings(0) : null,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
                PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: '邮件',
          menus: [
            PlatformMenuItem(
              label: '收信',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
              onSelected: hasAccount ? () => _homeKey.currentState?.refresh() : null,
            ),
          ],
        ),
        PlatformMenu(
          label: '显示',
          menus: [
            PlatformMenuItemGroup(
              members: [
                // 用「字符」快捷键：西班牙语键盘有单独的 + 键，美式键盘是 Shift+=，都能触发
                PlatformMenuItem(
                  label: '放大字号',
                  shortcut: const CharacterActivator('+', meta: true),
                  onSelected: Zoom.zoomIn,
                ),
                PlatformMenuItem(
                  label: '缩小字号',
                  shortcut: const CharacterActivator('-', meta: true),
                  onSelected: Zoom.zoomOut,
                ),
                PlatformMenuItem(
                  label: '实际大小',
                  shortcut: const CharacterActivator('0', meta: true),
                  onSelected: Zoom.reset,
                ),
              ],
            ),
          ],
        ),
        const PlatformMenu(
          label: '窗口',
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
      ],
      child: MaterialApp(
        title: 'MailAutoTrans',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: Kit.theme(),
        themeMode: ThemeMode.light, // 只用浅色（用户老花眼，不要深色模式）
        home: _home(),
        // 全局字号缩放：所有文字按 Zoom.scale 放大缩小；⌘= 也当放大（美式键盘不按 Shift 的习惯）
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: Zoom.scale,
          builder: (context, scale, _) => CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.equal, meta: true): Zoom.zoomIn},
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      ),
    );
  }

  Widget _home() {
    if (!_loaded) return const Scaffold(body: SizedBox.shrink());
    if (_accounts.isEmpty) {
      // 第一次用（或邮箱全删了）：直接显示添加邮箱页
      return AccountPage(title: '添加邮箱', onSaved: (a) => _setAccounts([a]));
    }
    return HomePage(key: _homeKey, accounts: _accounts, onOpenSettings: _openSettings);
  }
}
