import 'package:material_ui/material_ui.dart';

import '../mail/account.dart';
import '../mail/mail_service.dart';
import '../ui/kit.dart';

/// 邮箱账户设置：选常用邮箱或手填服务器 → 测试连接 → 保存。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.initial, required this.onSaved, this.embedded = false, this.title = '邮箱设置'});
  final Account? initial;
  final void Function(Account) onSaved;

  /// true = 放在「设置」窗口的标签页里（不带自己的标题栏）
  final bool embedded;
  final String title; // 单独成页时标题栏的字

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '465');
  MailPreset? _preset;
  bool _showPassword = false;
  bool _testing = false;
  ConnectionReport? _report;
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _email.text = a.email;
      _name.text = a.displayName;
      _user.text = a.userName;
      _password.text = a.password;
      _imapHost.text = a.imapHost;
      _imapPort.text = '${a.imapPort}';
      _smtpHost.text = a.smtpHost;
      _smtpPort.text = '${a.smtpPort}';
      _userEdited = a.userName != a.email;
    }
    // 登录名默认跟邮箱地址一样，除非用户自己改过
    _email.addListener(() {
      if (!_userEdited) _user.text = _email.text.trim();
    });
    for (final c in [_email, _name, _user, _password, _imapHost, _imapPort, _smtpHost, _smtpPort]) {
      c.addListener(() {
        if (_report != null) setState(() => _report = null); // 改了设置，旧的测试结果作废
      });
    }
  }

  void _applyPreset(MailPreset? p) {
    setState(() {
      _preset = p;
      if (p != null) {
        _imapHost.text = p.imapHost;
        _imapPort.text = '${p.imapPort}';
        _smtpHost.text = p.smtpHost;
        _smtpPort.text = '${p.smtpPort}';
      }
    });
  }

  Account? _build() {
    final imapPort = int.tryParse(_imapPort.text.trim());
    final smtpPort = int.tryParse(_smtpPort.text.trim());
    if (_email.text.trim().isEmpty ||
        _user.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _imapHost.text.trim().isEmpty ||
        _smtpHost.text.trim().isEmpty ||
        imapPort == null ||
        smtpPort == null) {
      return null;
    }
    return Account(
      email: _email.text.trim(),
      userName: _user.text.trim(),
      password: _password.text,
      imapHost: _imapHost.text.trim(),
      imapPort: imapPort,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: smtpPort,
      displayName: _name.text.trim(),
    );
  }

  Future<void> _test() async {
    final a = _build();
    if (a == null) {
      _snack('请把每一项都填上（端口要填数字）。');
      return;
    }
    setState(() {
      _testing = true;
      _report = null;
    });
    final r = await MailService(a).test();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _report = r;
    });
  }

  Future<void> _save() async {
    final a = _build();
    if (a == null) return;
    widget.onSaved(a);
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s, style: const TextStyle(fontSize: 18))));

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: PageBody(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('填好后先点「测试连接」，收信和发信都通过了再保存。', style: Kit.caption),
            const SizedBox(height: 16),
            KitCard(
              title: '账户',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<MailPreset?>(
                    initialValue: _preset,
                    decoration: const InputDecoration(labelText: '常用邮箱（选了自动填服务器）'),
                    style: Kit.text,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('其他 / 手动填写')),
                      for (final p in MailPreset.all) DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: _applyPreset,
                  ),
                  if (_preset != null) ...[const SizedBox(height: 8), Text(_preset!.hint, style: Kit.caption)],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    style: Kit.text,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱地址'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    style: Kit.text,
                    decoration: const InputDecoration(labelText: '发件人名字（对方收信时看到的，可不填）'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _user,
                    style: Kit.text,
                    onChanged: (_) => _userEdited = true,
                    decoration: const InputDecoration(labelText: '登录名（一般就是邮箱地址）'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    style: Kit.text,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: '客户端专用密码 / 授权码',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? '隐藏密码' : '显示密码',
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            KitCard(
              title: '服务器',
              subtitle: '端口 993 / 465 = 直接加密；143 / 587 = 先连上再加密（STARTTLS）',
              child: Column(
                children: [
                  _serverRow('收信服务器（IMAP）', _imapHost, _imapPort),
                  const SizedBox(height: 16),
                  _serverRow('发信服务器（SMTP）', _smtpHost, _smtpPort),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton(onPressed: _testing ? null : _test, child: Text(_testing ? '正在测试…' : '测试连接')),
                const SizedBox(width: 16),
                FilledButton(onPressed: (r != null && r.ok) ? _save : null, child: const Text('保存')),
                if (_testing) ...[
                  const SizedBox(width: 16),
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                ],
              ],
            ),
            if (r != null) ...[
              const SizedBox(height: 20),
              KitCard(
                title: '测试结果',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_resultRow('收信', r.imapError), const SizedBox(height: 14), _resultRow('发信', r.smtpError)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // 用 SelectionArea + Text 让文字可选中复制；不用 SelectableText——
      // Flutter 3.50 的 Mac 无障碍桥在 SelectableText 内容变化时会崩溃（startEditing unrecognized selector，2026-11-16）
      body: SelectionArea(child: body),
    );
  }

  Widget _serverRow(String label, TextEditingController host, TextEditingController port) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: host,
            style: Kit.text,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextField(
            controller: port,
            style: Kit.text,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '端口'),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(String what, String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBadge(ok: error == null, text: error == null ? '$what：通过' : '$what：失败'),
        if (error != null) ...[const SizedBox(height: 8), Text(error, style: Kit.text)],
      ],
    );
  }
}
