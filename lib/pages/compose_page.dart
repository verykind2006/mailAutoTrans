import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../mail/account.dart';
import '../mail/attachment_files.dart';
import '../mail/contacts.dart';
import '../mail/mail_service.dart';
import '../translate/translator.dart';
import '../ui/format.dart';
import '../ui/kit.dart';

/// 回信时带过来的原信信息。
class ReplyContext {
  ReplyContext({
    required this.toEmail,
    required this.toName,
    this.cc = const [],
    required this.subject,
    required this.subjectZh,
    required this.originalText,
    this.date,
    this.messageId,
    this.references,
    this.langCode,
    this.replyAll = false,
  });
  final String toEmail;
  final String toName;
  final List<String> cc; // 回复全部时，原信的其他收件人 + 抄送人
  final String subject; // 原标题（外语）
  final String? subjectZh; // 原标题的中文
  final String originalText; // 原信纯文字正文（作翻译上下文，并引用在回信下面）
  final DateTime? date;
  final String? messageId;
  final String? references;
  final String? langCode; // 原信语言（es / en …），回信默认用它
  final bool replyAll;
}

/// 上一次翻译用的中文和语言；中文改了就要重新翻
typedef _Source = ({String subject, String body, TargetLang lang});

/// 写信（嵌在主界面右侧内容区）。
/// 左边「中文」豆腐块一直在（可以随时改）；点「翻译」后右边滑出「要发出去的外文」+「译文的中文意思（核对用）」。
/// 快捷键：⌘↩ 第一次翻译、有译文后发送；Esc 回去改中文（没有译文时 = 关闭）。
/// 和 autoTransWhatsapp 一样：确认后一键直接发出，并存进「已发送」。
class ComposeView extends StatefulWidget {
  const ComposeView({
    super.key,
    required this.account,
    this.accounts = const [],
    this.reply,
    required this.onClose,
    required this.onSent,
    required this.onOpenTranslateSettings,
  });
  final Account account; // 默认从这个邮箱发（回信 = 原信所在的邮箱）
  final List<Account> accounts; // 所有邮箱；多于一个时显示「发件人」下拉
  final ReplyContext? reply;
  final VoidCallback onClose;
  final void Function(String? note) onSent;
  final Future<void> Function() onOpenTranslateSettings;

  @override
  State<ComposeView> createState() => _ComposeViewState();
}

class _ComposeViewState extends State<ComposeView> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subjectZh = TextEditingController();
  final _bodyZh = TextEditingController();
  final _subjectOut = TextEditingController();
  final _bodyOut = TextEditingController();
  final _bodyZhFocus = FocusNode();
  final List<({String name, String path, int size})> _files = []; // 要带的附件
  final _pageFocus = FocusNode();

  late Account _from = widget.account; // 从哪个邮箱发
  TargetLang _lang = TargetLang.es;
  bool _langTouched = false; // 用户手动选过语言，就不再自动改
  bool _showCc = false;
  bool _showBcc = false;

  bool _showRight = false; // 右边译文栏是否展开
  bool _translating = false;
  bool _sending = false;
  _Source? _translatedFrom; // 当前译文是从哪段中文翻的
  DateTime? _translatedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.reply;
    if (r != null) {
      _to.text = r.toEmail;
      if (r.cc.isNotEmpty) {
        _cc.text = r.cc.join(', ');
        _showCc = true;
      }
      final zh = r.subjectZh?.isNotEmpty == true ? r.subjectZh! : r.subject;
      _subjectZh.text = zh.startsWith('回复：') ? zh : '回复：$zh';
      _lang = TargetLang.fromCode(r.langCode) ?? TargetLang.es;
    }
    _pickLangForRecipient();
    _to.addListener(_pickLangForRecipient);
    for (final c in [_subjectZh, _bodyZh]) {
      c.addListener(() => setState(() {})); // 中文一改，「译文过时」提示要跟着变
    }
    // 回信时光标直接放进正文
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (r != null ? _bodyZhFocus : _pageFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subjectZh, _bodyZh, _subjectOut, _bodyOut]) {
      c.dispose();
    }
    _bodyZhFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  // ── 小工具 ──

  Future<void> _pickLangForRecipient() async {
    if (_langTouched) return;
    final first = _split(_to.text).firstOrNull;
    if (first == null) return;
    final remembered = await ContactLangStore.get(first);
    if (remembered != null && mounted && !_langTouched) setState(() => _lang = remembered);
  }

  static List<String> _split(String s) =>
      s.split(RegExp(r'[,，;；\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  _Source get _current => (subject: _subjectZh.text.trim(), body: _bodyZh.text.trim(), lang: _lang);

  /// 中文或语言改过了，现有译文作废
  bool get _stale => _translatedFrom == null || _translatedFrom != _current;

  bool get _dirty => _bodyZh.text.trim().isNotEmpty || _bodyOut.text.trim().isNotEmpty || _files.isNotEmpty;

  String? _validate() {
    final all = {'收件人': _split(_to.text), '抄送': _split(_cc.text), '密送': _split(_bcc.text)};
    if (all['收件人']!.isEmpty) return '请填写收件人邮箱地址。';
    for (final e in all.entries) {
      final bad = e.value.where((x) => !_emailRe.hasMatch(x)).toList();
      if (bad.isNotEmpty) return '${e.key}里这些地址看着不对：${bad.join('、')}';
    }
    if (_subjectZh.text.trim().isEmpty) return '请填写标题。';
    if (_bodyZh.text.trim().isEmpty) return '请写正文。';
    return null;
  }

  // ── 动作 ──

  /// ⌘↩：没有可用译文 → 翻译；有 → 发送
  void _primary() {
    if (_translating || _sending) return;
    if (!_showRight || _stale) {
      _translate();
    } else {
      // 译文刚出来不到 1 秒时忽略，防止连按两下直接发出
      if (_translatedAt != null && DateTime.now().difference(_translatedAt!) < const Duration(seconds: 1)) return;
      _send();
    }
  }

  /// Esc：有译文栏 → 收起，回去改中文；没有 → 关闭写信
  void _escape() {
    if (_sending) return;
    if (_showRight) {
      setState(() {
        _showRight = false;
        _error = null;
      });
      _bodyZhFocus.requestFocus();
    } else {
      _close();
    }
  }

  Future<void> _close() async {
    if (_dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('不发了？', style: Kit.cardTitle),
          content: const Text('写好的内容会丢掉（还没有草稿功能）。', style: Kit.text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续写')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('丢掉')),
          ],
        ),
      );
      if (ok != true) return;
    }
    widget.onClose();
  }

  Future<void> _translate() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    // 中文没改过：直接把上次的译文再拿出来，不重复花钱
    if (!_stale) {
      setState(() {
        _showRight = true;
        _error = null;
        _translatedAt = DateTime.now();
      });
      return;
    }
    final src = _current;
    if (_lang == TargetLang.zh) {
      setState(() {
        _subjectOut.text = src.subject;
        _bodyOut.text = src.body;
        _translatedFrom = src;
        _translatedAt = DateTime.now();
        _showRight = true;
        _error = null;
      });
      return;
    }
    final settings = await TranslateSettings.load();
    if (!mounted) return;
    if (!settings.configured) {
      setState(() => _error = '翻译要用 API key，还没有填。');
      return;
    }
    setState(() {
      _translating = true;
      _showRight = true; // 先把右栏滑出来，显示「正在翻译」
      _error = null;
    });
    try {
      final r = widget.reply;
      final t = await Translator(settings).translateOutgoing(
        subjectZh: src.subject,
        bodyZh: src.body,
        langPromptName: src.lang.promptName,
        spanish: src.lang == TargetLang.es,
        recipient: _split(_to.text).join(', '),
        replyContext: r == null ? null : '标题：${r.subject}\n发件人：${r.toName}\n\n${r.originalText}',
      );
      if (!mounted) return;
      setState(() {
        _subjectOut.text = t.subject;
        _bodyOut.text = t.body;
        _translatedFrom = src;
        _translatedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '翻译失败：$e';
          if (_translatedFrom == null) _showRight = false;
        });
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// 回信时在正文下面引用原信（按目标语言写引用头，和一般邮件软件一样）
  String _quoted() {
    final r = widget.reply;
    if (r == null || r.originalText.trim().isEmpty) return '';
    final date = r.date == null ? '' : formatQuoteDate(r.date!);
    final who = r.toName.isEmpty ? r.toEmail : '${r.toName} <${r.toEmail}>';
    final head = switch (_lang) {
      TargetLang.es => 'El $date, $who escribió:',
      TargetLang.en => 'On $date, $who wrote:',
      TargetLang.it => 'Il $date, $who ha scritto:',
      TargetLang.fr => 'Le $date, $who a écrit :',
      TargetLang.de => 'Am $date schrieb $who:',
      TargetLang.pt => 'Em $date, $who escreveu:',
      TargetLang.zh => '$date，$who 写道：',
    };
    final body = r.originalText.trim().split('\n').map((l) => '> $l').join('\n');
    return '\n\n$head\n$body';
  }

  Future<void> _send() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_subjectOut.text.trim().isEmpty || _bodyOut.text.trim().isEmpty) {
      setState(() => _error = '译文的标题和正文不能是空的。');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final r = widget.reply;
    try {
      final result = await MailService(_from).send(
        OutgoingMail(
          to: _split(_to.text),
          cc: _split(_cc.text),
          bcc: _split(_bcc.text),
          attachments: [
            for (final f in _files) OutgoingAttachment(name: f.name, data: await File(f.path).readAsBytes()),
          ],
          subject: _subjectOut.text.trim(),
          body: _bodyOut.text.trim() + _quoted(),
          inReplyTo: r?.messageId,
          references: r?.references,
        ),
      );
      for (final e in _split(_to.text)) {
        await ContactLangStore.put(e, _lang);
      }
      widget.onSent(result.sentNote);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '发送失败，信没有发出去：${describeError(e)}';
        });
      }
    }
  }

  // ── 界面 ──

  @override
  Widget build(BuildContext context) {
    final r = widget.reply;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _primary,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): _primary,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Focus(
        focusNode: _pageFocus,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(r),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _recipientsCard(r),
                      const SizedBox(height: 12),
                      _twoColumns(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null ? const SizedBox(width: double.infinity) : _errorBox(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部一行：关闭 · 标题 · 步骤 ……（右边）按钮。窗口窄时不显示步骤，给按钮让地方
  Widget _header(ReplyContext? r) {
    final step2 = _showRight;
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          TextButton.icon(
            onPressed: _sending ? null : _close,
            icon: const Icon(Icons.close, size: 24),
            label: const Text('关闭', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Text(r == null ? '写邮件' : (r.replyAll ? '回复全部' : '回复'), style: Kit.pageTitle),
          if (box.maxWidth > 1150 * MediaQuery.textScalerOf(context).scale(1)) ...[
            const SizedBox(width: 20),
            _StepDot(n: 1, label: '写中文', active: !step2),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, color: Kit.inkSoft),
            ),
            _StepDot(n: 2, label: '核对译文并发送', active: step2),
          ],
          // 按钮靠右；地方不够时整体略缩小，不会挤出界
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: _buttons()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipientsCard(ReplyContext? r) {
    Widget addrField(TextEditingController c, String label, {Widget? suffix}) => Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: Kit.textBold)),
        Expanded(
          child: TextField(
            controller: c,
            style: Kit.text,
            decoration: const InputDecoration(hintText: '邮箱地址，多个用逗号隔开'),
          ),
        ),
        if (suffix != null) ...[const SizedBox(width: 8), suffix],
      ],
    );
    return KitCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r != null) ...[
            Text(
              '↩ ${r.replyAll ? '回复全部' : '回复'} ${r.toName}：${r.subjectZh?.isNotEmpty == true ? r.subjectZh : r.subject}',
              style: Kit.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
          ],
          if (widget.accounts.length > 1) ...[
            Row(
              children: [
                const SizedBox(width: 70, child: Text('发件人', style: Kit.textBold)),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _from.email,
                    isExpanded: true,
                    style: Kit.text,
                    items: [
                      for (final a in widget.accounts)
                        DropdownMenuItem(
                          value: a.email,
                          child: Text(a.displayName.isEmpty ? a.email : '${a.displayName} <${a.email}>'),
                        ),
                    ],
                    onChanged: _sending
                        ? null
                        : (v) => setState(() => _from = widget.accounts.firstWhere((a) => a.email == v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          addrField(
            _to,
            '收件人',
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_showCc) TextButton(onPressed: () => setState(() => _showCc = true), child: const Text('+ 抄送')),
                if (!_showBcc) TextButton(onPressed: () => setState(() => _showBcc = true), child: const Text('+ 密送')),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                if (_showCc) ...[const SizedBox(height: 10), addrField(_cc, '抄送')],
                if (_showBcc) ...[
                  const SizedBox(height: 10),
                  addrField(_bcc, '密送'),
                  const Padding(
                    padding: EdgeInsets.only(left: 70, top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('密送的人收得到信，但其他收件人看不到他们。', style: Kit.caption),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 70, child: Text('翻成', style: Kit.textBold)),
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<TargetLang>(
                  initialValue: _lang,
                  isExpanded: true,
                  style: Kit.text,
                  items: [for (final l in TargetLang.values) DropdownMenuItem(value: l, child: Text(l.title))],
                  onChanged: _sending
                      ? null
                      : (v) => setState(() {
                          if (v != null) _lang = v;
                          _langTouched = true;
                        }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _attachmentsRow(),
        ],
      ),
    );
  }

  /// 「附件」一行：添加按钮 + 已选的文件（可以删）+ 太大时提醒
  Widget _attachmentsRow() {
    final total = _files.fold<int>(0, (n, f) => n + f.size);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: SizedBox(width: 70, child: Text('附件', style: Kit.textBold)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in _files)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: Kit.canvas,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Kit.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 20, color: Color(0xFF1565C0)),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(f.name, style: Kit.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(AttachmentFiles.formatSize(f.size), style: Kit.caption),
                          IconButton(
                            tooltip: '去掉这个附件',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: _sending ? null : () => setState(() => _files.remove(f)),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _sending ? null : _pickFiles,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: const Text('添加附件'),
                  ),
                ],
              ),
              if (total > 20 * 1024 * 1024)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠ 附件一共 ${AttachmentFiles.formatSize(total)}，很多邮箱收不了超过 20 MB 的信，可能发不出去。',
                    style: const TextStyle(fontSize: 17, color: Color(0xFF7A3E00), fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickFiles() async {
    final picked = await openFiles(confirmButtonText: '添加');
    if (picked.isEmpty || !mounted) return;
    final added = <({String name, String path, int size})>[];
    for (final x in picked) {
      if (_files.any((f) => f.path == x.path)) continue; // 同一个文件不重复加
      added.add((name: x.name, path: x.path, size: await x.length()));
    }
    if (mounted) setState(() => _files.addAll(added));
  }

  /// 左：中文豆腐块（一直在）；右：译文栏（滑出 / 收起，有动画）
  Widget _twoColumns() {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 16.0;
        final w = box.maxWidth;
        final half = (w - gap) / 2;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: _showRight ? 1 : 0),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final rightW = (half + gap) * t;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(key: const ValueKey('zh'), width: w - rightW, child: _chineseCard()),
                // 右栏：内容始终按「半宽」排版，外面用 Align 的 widthFactor 只露出 t 那么宽（滑出效果）。
                // 不能用 OverflowBox：它在可滚动区域里会被撑成无限高，整页排版出错
                // （2026-11-16 用户截图：红色报错 + 中文卡片消失，test/compose_flow_test.dart 复现）。
                if (t > 0.001)
                  ClipRect(
                    key: const ValueKey('out'),
                    child: Align(
                      alignment: Alignment.topLeft,
                      widthFactor: t,
                      child: SizedBox(
                        width: half + gap,
                        child: Padding(
                          padding: const EdgeInsets.only(left: gap),
                          child: Opacity(opacity: t, child: _rightColumn()),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _chineseCard() {
    final stale = _showRight && !_translating && _translatedFrom != null && _stale;
    return KitCard(
      title: '中文（你写的）',
      subtitle: stale ? '⚠ 中文或语言改过了，右边的译文是旧的——按 ⌘↩ 重新翻译' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _subjectZh,
            style: Kit.textBold,
            enabled: !_sending,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyZh,
            focusNode: _bodyZhFocus,
            style: Kit.text,
            enabled: !_sending,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: '正文（像平时说话一样写就行）', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }

  Widget _rightColumn() {
    // 「正在翻译」和「译文」之间淡入淡出
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _translating && _translatedFrom == null
          ? KitCard(
              key: const ValueKey('loading'),
              title: '正在翻成${_lang.title}…',
              child: const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 4))),
            )
          : Column(
              key: const ValueKey('result'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_outCard()],
            ),
    );
  }

  Widget _outCard() {
    final lang = _translatedFrom?.lang ?? _lang;
    final translated = lang != TargetLang.zh;
    return KitCard(
      title: translated ? '要发出去的${lang.title}（可以直接改）' : '要发出去的内容（中文，不翻译）',
      trailing: _translating
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
          : (translated ? LangChip(code: lang.name, label: lang.title) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _subjectOut,
            style: Kit.textBold,
            enabled: !_sending,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyOut,
            style: Kit.text,
            enabled: !_sending,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: '正文', alignLabelWithHint: true),
          ),
          if (widget.reply != null) ...[
            const SizedBox(height: 8),
            const Text('↩ 发出时会在正文下面自动附上对方原信的引用。', style: Kit.caption),
          ],
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Kit.warnBg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Expanded(
              child: Text('✗ $_error', style: const TextStyle(fontSize: 18, color: Kit.warn)),
            ),
            if (_error!.contains('API key'))
              TextButton(
                onPressed: () async {
                  await widget.onOpenTranslateSettings();
                  if (mounted) setState(() => _error = null);
                },
                child: const Text('去填 API key', style: TextStyle(fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buttons() {
    final canSend = _showRight && !_stale && !_translating;
    final busy = _translating || _sending;
    final Widget primary = canSend
        ? FilledButton.icon(
            key: const ValueKey('send'),
            onPressed: busy ? null : _send,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 22),
            label: Text(_sending ? '正在发送…' : '发送', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          )
        : FilledButton.icon(
            key: const ValueKey('translate'),
            onPressed: busy ? null : _translate,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
            icon: _translating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(Icons.translate_rounded, size: 22),
            label: Text(
              _translating ? '正在翻译…' : (_translatedFrom != null ? '重新翻译' : (_lang == TargetLang.zh ? '下一步' : '翻译')),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: primary),
        const SizedBox(width: 12),
        const _KeyHint(keys: '⌘ ↩'),
        if (_showRight) ...[
          const SizedBox(width: 16),
          OutlinedButton(onPressed: _sending ? null : _escape, child: const Text('← 回去改中文')),
          const SizedBox(width: 8),
          const _KeyHint(keys: 'Esc'),
          if (canSend && _lang != TargetLang.zh) ...[
            const SizedBox(width: 16),
            OutlinedButton(onPressed: busy ? null : _retranslate, child: const Text('重新翻译')),
          ],
        ],
      ],
    );
  }

  /// 中文没改也要重新翻（比如不满意译文）
  void _retranslate() {
    _translatedFrom = null;
    _translate();
  }
}

/// 快捷键提示：键帽样式
class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keys});
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Kit.hairline, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x14000000), offset: Offset(0, 1))],
      ),
      child: Text(
        keys,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Kit.inkSoft),
      ),
    );
  }
}

/// 步骤指示：圆圈数字 + 文字
class _StepDot extends StatelessWidget {
  const _StepDot({required this.n, required this.label, required this.active});
  final int n;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: active ? 1 : 0.75,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Kit.accent : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: active ? Kit.accent : Kit.hairline, width: 2),
            ),
            child: Text(
              '$n',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: active ? Colors.white : Kit.inkSoft),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: 17, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: Kit.ink),
          ),
        ],
      ),
    );
  }
}
