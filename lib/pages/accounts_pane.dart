import 'package:material_ui/material_ui.dart';

import '../mail/account.dart';
import '../ui/kit.dart';
import 'account_page.dart';

/// 设置 →「邮箱账户」标签：邮箱列表（编辑 / 删除）+「添加邮箱」。
class AccountsPane extends StatefulWidget {
  const AccountsPane({super.key, required this.accounts, required this.onChanged});
  final List<Account> accounts;
  final Future<void> Function(List<Account>) onChanged; // 保存到本机并通知主界面

  @override
  State<AccountsPane> createState() => _AccountsPaneState();
}

class _AccountsPaneState extends State<AccountsPane> {
  late List<Account> _list = [...widget.accounts];

  Future<void> _edit({int? index}) async {
    final isNew = index == null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => AccountPage(
          title: isNew ? '添加邮箱' : '编辑邮箱',
          initial: isNew ? null : _list[index],
          onSaved: (a) async {
            final dup = _list.indexWhere((x) => x.email.toLowerCase() == a.email.toLowerCase());
            if (dup >= 0 && dup != index) {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(SnackBar(content: Text('${a.email} 已经添加过了。', style: const TextStyle(fontSize: 18))));
              return;
            }
            final next = [..._list];
            if (isNew) {
              next.add(a);
            } else {
              next[index] = a;
            }
            setState(() => _list = next);
            await widget.onChanged(next);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  Future<void> _delete(int index) async {
    final a = _list[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${a.email}？', style: Kit.cardTitle),
        content: const Text('只是从这个软件里移除，不会删除邮箱里的任何信。以后可以再添加回来。', style: Kit.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Kit.warn),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final next = [..._list]..removeAt(index);
    setState(() => _list = next);
    await widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: PageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('可以添加多个邮箱。左侧栏按邮箱分组显示，写信时可以选从哪个邮箱发。', style: Kit.caption),
            const SizedBox(height: 16),
            for (var i = 0; i < _list.length; i++) ...[
              KitCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Avatar(name: _list[i].email, size: 44),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_list[i].email, style: Kit.cardTitle),
                          Text(
                            [
                              if (_list[i].displayName.isNotEmpty) '发件人名字：${_list[i].displayName}',
                              '收信 ${_list[i].imapHost} · 发信 ${_list[i].smtpHost}',
                            ].join('　'),
                            style: Kit.caption,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _edit(index: i),
                      child: const Text('编辑'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => _delete(i),
                      child: const Text('删除', style: TextStyle(fontSize: 18, color: Kit.warn)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_list.isEmpty) ...[const Text('还没有邮箱。', style: Kit.text), const SizedBox(height: 12)],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 24),
                label: const Text('添加邮箱'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
