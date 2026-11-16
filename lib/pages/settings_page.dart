import 'package:material_ui/material_ui.dart';

import '../mail/account.dart';
import '../translate/translator.dart';
import '../ui/kit.dart';
import 'accounts_pane.dart';
import 'translate_settings_page.dart';

/// 设置（从菜单「AutoTransMail → 设置…」打开）：邮箱账户、翻译引擎两个标签页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.accounts,
    required this.translate,
    required this.onAccountsChanged,
    this.initialTab = 0,
  });
  final List<Account> accounts;
  final TranslateSettings translate;
  final Future<void> Function(List<Account>) onAccountsChanged;
  final int initialTab;

  void _saved(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('✓ $what已保存', style: const TextStyle(fontSize: 18))));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 18),
            labelColor: Kit.accent,
            unselectedLabelColor: Kit.inkSoft,
            tabs: [
              Tab(text: '邮箱账户'),
              Tab(text: '翻译引擎'),
            ],
          ),
        ),
        // 用 SelectionArea + Text，不用 SelectableText（Flutter 3.50 Mac 无障碍桥会崩，见 CLAUDE.md）
        body: SelectionArea(
          child: Builder(
            builder: (ctx) => TabBarView(
              children: [
                AccountsPane(
                  accounts: accounts,
                  onChanged: (list) async {
                    await onAccountsChanged(list);
                    if (ctx.mounted) _saved(ctx, '邮箱账户');
                  },
                ),
                TranslateSettingsPage(embedded: true, initial: translate, onSaved: (_) => _saved(ctx, '翻译设置')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
