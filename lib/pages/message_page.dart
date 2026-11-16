import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../mail/account.dart';
import '../mail/attachment_files.dart';
import '../mail/mail_service.dart';
import '../translate/html_translate.dart';
import '../translate/text_tools.dart';
import 'compose_page.dart';
import '../translate/translator.dart';
import '../ui/format.dart';
import '../ui/kit.dart';
import '../ui/zoom.dart';

enum _View { chinese, original }

enum _TrState { idle, translating, done, chineseMail, needKey, tooLong, failed }

/// 读一封信（嵌在主界面右侧内容区，像 Gmail 那样替换列表）：打开就自动翻成中文；「中文 / 原文」两个标签切换。
/// 原文里的 HTML 信用 WebView（网页显示控件）显示，纯文字信直接用大字显示。
class MessageView extends StatefulWidget {
  const MessageView({
    super.key,
    required this.account,
    required this.folder,
    required this.summary,
    this.listSubjectZh,
    required this.onBack,
    required this.onOpenTranslateSettings,
    this.onReply,
    this.onMarkedRead,
  });
  final Account account;
  final MailFolder folder;
  final MailSummary summary;
  final String? listSubjectZh; // 列表里已经翻好的中文标题，正文翻好前先用它
  final VoidCallback onBack;
  final Future<void> Function() onOpenTranslateSettings;
  final void Function(ReplyContext)? onReply; // 只有收件箱里的信能回复
  final void Function(int uid)? onMarkedRead; // 打开后标成了已读，让列表跟着变

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  /// 超过这么多字的信不自动翻，先问一声（长信多花钱）
  static const _autoLimit = 20000;

  MailDetail? _detail;
  String? _loadError;
  _View _view = _View.chinese;
  _TrState _tr = _TrState.idle;
  MailTranslation? _translation;
  String? _trError;
  String _text = ''; // 送去翻译的纯文字正文
  String? _zhHtml; // HTML 信：保留排版翻好的中文 HTML
  String _progress = ''; // 长信分批翻译的进度
  int _htmlFailed = 0; // 格式没对上、只放了文字的段落数

  bool get _isHtml => (_detail?.html ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await MailService(widget.account).fetchMessage(widget.folder, widget.summary.uid);
      if (!mounted) return;
      final plain = d.plain?.trim() ?? '';
      _text = plain.isNotEmpty ? plain : htmlToText(d.html ?? '');
      setState(() => _detail = d);
      if (!widget.summary.seen) widget.onMarkedRead?.call(widget.summary.uid);
      await _autoTranslate();
    } catch (e) {
      if (mounted) setState(() => _loadError = describeError(e));
    }
  }

  String get _cacheKey {
    final d = _detail!;
    return '${widget.account.email}|${d.messageId ?? 'uid:${d.summary.uid}'}';
  }

  Future<void> _autoTranslate() async {
    final d = _detail!;
    if (looksChinese('${d.summary.subject}\n$_text')) {
      setState(() {
        _tr = _TrState.chineseMail;
        _view = _View.original;
      });
      return;
    }
    if (_isHtml) {
      final meta = await TranslationCache.get('html|$_cacheKey');
      final html = await HtmlTranslationCache.get(_cacheKey);
      if (!mounted) return;
      if (meta != null && html != null) {
        setState(() {
          _translation = meta;
          _zhHtml = html;
          _tr = _TrState.done;
        });
        return;
      }
    }
    final cached = _isHtml ? null : await TranslationCache.get(_cacheKey);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _translation = cached;
        _tr = _TrState.done;
      });
      return;
    }
    if (_text.length > _autoLimit) {
      setState(() => _tr = _TrState.tooLong);
      return;
    }
    await _translate();
  }

  Future<void> _translate() async {
    final settings = await TranslateSettings.load();
    if (!mounted) return;
    if (!settings.configured) {
      setState(() => _tr = _TrState.needKey);
      return;
    }
    setState(() {
      _tr = _TrState.translating;
      _trError = null;
    });
    final d = _detail!;
    if (_isHtml) return _translateHtml(settings);
    try {
      final t = await Translator(settings).translateIncoming(
        subject: d.summary.subject,
        from: d.summary.fromEmail.isEmpty ? d.summary.fromName : '${d.summary.fromName} <${d.summary.fromEmail}>',
        body: _text.isEmpty ? '（没有正文）' : _text,
      );
      await TranslationCache.put(_cacheKey, t);
      // 正文翻译带的中文标题更准，顺便更新列表用的标题缓存
      if (!t.isChinese && t.subjectZh.isNotEmpty) {
        await SubjectCache.putAll({
          d.summary.subject: SubjectInfo(zh: t.subjectZh, lang: langCodeFromName(t.sourceLanguage)),
        });
      }
      if (!mounted) return;
      setState(() {
        _translation = t;
        _tr = t.isChinese ? _TrState.chineseMail : _TrState.done;
        if (t.isChinese) _view = _View.original;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tr = _TrState.failed;
        _trError = e.toString();
      });
    }
  }

  /// HTML 信：拆段翻译，原位换回，保留原来的排版、图片、按钮
  Future<void> _translateHtml(TranslateSettings settings) async {
    final d = _detail!;
    try {
      final seg = HtmlSegmenter.parse(d.html!);
      final entries = [MapEntry(0, d.summary.subject), ...seg.segments.map((s) => MapEntry(s.id, s.source))];
      final r = await Translator(settings).translateHtmlSegments(
        entries,
        onProgress: (done, total) {
          if (mounted && total > 1) setState(() => _progress = '（长信分 $total 批翻，已完成 $done 批）');
        },
      );
      if (!mounted) return;
      if (r.isChinese) {
        setState(() {
          _tr = _TrState.chineseMail;
          _view = _View.original;
        });
        return;
      }
      final applied = seg.apply(r.zh);
      final t = MailTranslation(
        isChinese: false,
        sourceLanguage: r.sourceLanguage,
        subjectZh: (r.zh[0] ?? '').trim(),
        bodyZh: '',
        quotedSummary: '',
      );
      await TranslationCache.put('html|$_cacheKey', t);
      await HtmlTranslationCache.put(_cacheKey, applied.html);
      if (t.subjectZh.isNotEmpty) {
        await SubjectCache.putAll({
          d.summary.subject: SubjectInfo(zh: t.subjectZh, lang: langCodeFromName(t.sourceLanguage)),
        });
      }
      if (!mounted) return;
      setState(() {
        _translation = t;
        _zhHtml = applied.html;
        _htmlFailed = applied.failed;
        _progress = '';
        _tr = _TrState.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tr = _TrState.failed;
        _trError = e.toString();
        _progress = '';
      });
    }
  }

  /// 回复全部时的抄送名单：原信的收件人 + 抄送，去掉自己和发件人
  List<String> _others() {
    final d = _detail;
    if (d == null) return [];
    final me = widget.account.email.toLowerCase();
    final sender = (d.replyToEmail ?? d.summary.fromEmail).toLowerCase();
    final seen = <String>{};
    return [
      ...d.toEmails,
      ...d.ccEmails,
    ].where((e) => e.toLowerCase() != me && e.toLowerCase() != sender && seen.add(e.toLowerCase())).toList();
  }

  void _reply({bool all = false}) {
    final d = _detail!;
    final s = d.summary;
    final t = _translation;
    final zhSubject = (t != null && !t.isChinese && t.subjectZh.isNotEmpty) ? t.subjectZh : widget.listSubjectZh;
    widget.onReply!(
      ReplyContext(
        toEmail: d.replyToEmail ?? s.fromEmail,
        toName: s.fromName,
        cc: all ? _others() : const [],
        replyAll: all,
        subject: s.subject,
        subjectZh: zhSubject,
        originalText: _text,
        date: s.date,
        messageId: d.messageId,
        references: d.references,
        langCode: t == null || t.isChinese ? null : langCodeFromName(t.sourceLanguage),
      ),
    );
  }

  void _openSettings() async {
    await widget.onOpenTranslateSettings();
    if (mounted && _tr == _TrState.needKey) await _translate();
  }

  @override
  Widget build(BuildContext context) {
    final s = _detail?.summary ?? widget.summary;
    final t = _translation;
    final zhSubject = (t != null && !t.isChinese && t.subjectZh.isNotEmpty) ? t.subjectZh : widget.listSubjectZh;
    final showZhSubject = zhSubject != null && zhSubject.isNotEmpty && zhSubject != s.subject;
    final peer = widget.folder == MailFolder.inbox
        ? '发件人：${s.fromName}${s.fromEmail.isNotEmpty && s.fromEmail != s.fromName ? ' <${s.fromEmail}>' : ''}'
        : '发件人：${s.fromName}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 24, 20),
      child: PageBody(
        maxWidth: 1100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 24),
                  label: Text('返回${widget.folder.label}', style: const TextStyle(fontSize: 18)),
                ),
                const Spacer(),
                if (widget.onReply != null) ...[
                  FilledButton.icon(
                    onPressed: _detail == null ? null : () => _reply(),
                    icon: const Icon(Icons.reply_rounded, size: 22),
                    label: const Text('回复'),
                  ),
                  // 原信还有别的收件人 / 抄送人时才显示「回复全部」
                  if (_others().isNotEmpty) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _reply(all: true),
                      icon: const Icon(Icons.reply_all_rounded, size: 22),
                      label: Text('回复全部（另有 ${_others().length} 人）'),
                    ),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 8),
            KitCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(showZhSubject ? zhSubject : s.subject, style: Kit.pageTitle),
                  if (showZhSubject) ...[const SizedBox(height: 4), Text('原标题：${s.subject}', style: Kit.caption)],
                  const SizedBox(height: 10),
                  Text(peer, style: Kit.text),
                  if (_detail != null && _detail!.to.isNotEmpty) Text('收件人：${_detail!.to}', style: Kit.text),
                  if (_detail != null && _detail!.cc.isNotEmpty) Text('抄送：${_detail!.cc}', style: Kit.text),
                  Text('时间：${formatMailDate(s.date)}', style: Kit.caption),
                  if (_detail != null && _detail!.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [for (final a in _detail!.attachments) _AttachmentChip(att: a)],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_detail != null) _toolbar(),
            if (_detail != null) const SizedBox(height: 12),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final status = switch (_tr) {
      _TrState.translating => '正在翻译…$_progress',
      _TrState.done => '${_translation?.sourceLanguage.isNotEmpty == true ? _translation!.sourceLanguage : '外语'} → 中文',
      _TrState.chineseMail => '中文信，不用翻译',
      _TrState.failed => '✗ 翻译失败',
      _TrState.needKey => '还没填翻译用的 API key',
      _TrState.tooLong => '长信，等你确认再翻',
      _TrState.idle => '',
    };
    return Row(
      children: [
        SegmentedButton<_View>(
          segments: const [
            ButtonSegment(
              value: _View.chinese,
              label: Text('中文', style: TextStyle(fontSize: 18)),
            ),
            ButtonSegment(
              value: _View.original,
              label: Text('原文', style: TextStyle(fontSize: 18)),
            ),
          ],
          selected: {_view},
          showSelectedIcon: true,
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        const SizedBox(width: 16),
        if (_tr == _TrState.translating) ...[
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 10),
        ],
        if (_tr == _TrState.done && _translation != null) ...[
          LangChip(
            code: langCodeFromName(_translation!.sourceLanguage),
            label: _translation!.sourceLanguage.isEmpty ? '外语' : _translation!.sourceLanguage,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(_tr == _TrState.done ? '→ 中文' : status, style: Kit.caption)),
        if (_tr == _TrState.done)
          TextButton(
            onPressed: _translate,
            child: const Text('重新翻译', style: TextStyle(fontSize: 17)),
          ),
      ],
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return KitCard(
        title: '打开失败',
        trailing: const StatusBadge(ok: false, text: '没打开'),
        child: Text(_loadError!, style: Kit.text),
      );
    }
    final d = _detail;
    if (d == null) return const Center(child: Text('正在打开…', style: Kit.text));
    // 两个视图都留着，切换时原文的 WebView 不用重新加载
    return IndexedStack(
      index: _view == _View.chinese ? 0 : 1,
      sizing: StackFit.expand,
      children: [_chinesePane(), _originalPane(d)],
    );
  }

  Widget _box(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Kit.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    ),
  );

  Widget _chinesePane() {
    Widget center(List<Widget> children) => _box(
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
    switch (_tr) {
      case _TrState.idle:
      case _TrState.translating:
        return center([
          Text(_isHtml ? '正在翻译，保留原来的排版和图片…\n$_progress' : '正在翻译，一般十几秒…', style: Kit.text, textAlign: TextAlign.center),
        ]);
      case _TrState.chineseMail:
        return center([const Text('这封信是中文的，不用翻译，请看「原文」。', style: Kit.text)]);
      case _TrState.needKey:
        return center([
          const Text('翻译要用 Claude 的 API key，还没有填。', style: Kit.text),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openSettings, child: const Text('去填 API key')),
        ]);
      case _TrState.tooLong:
        return center([
          Text('这封信很长（约 ${_text.length} 个字符），翻译会多花一些钱。', style: Kit.text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _translate, child: const Text('翻译这封信')),
        ]);
      case _TrState.failed:
        return center([
          const StatusBadge(ok: false, text: '翻译失败'),
          const SizedBox(height: 12),
          Text(_trError ?? '', style: Kit.text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _translate, child: const Text('再试一次')),
        ]);
      case _TrState.done:
        final t = _translation!;
        final zhHtml = _zhHtml;
        if (zhHtml != null) {
          // HTML 信：翻好的中文放回原来的排版里，和「原文」一样显示
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_htmlFailed > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('⚠ 有 $_htmlFailed 段的加粗 / 链接没对上，那几段只显示了文字。', style: Kit.caption),
                ),
              Expanded(
                child: _box(
                  ValueListenableBuilder<double>(
                    valueListenable: Zoom.scale,
                    builder: (_, scale, _) => _HtmlView(key: ValueKey('zh$scale'), html: zhHtml, scale: scale),
                  ),
                ),
              ),
            ],
          );
        }
        return _box(
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.bodyZh, style: Kit.text),
                if (t.quotedSummary.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Kit.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(left: BorderSide(color: Kit.hairline, width: 4)),
                    ),
                    child: Text('↩ 信里引用的旧邮件（没有翻译）：${t.quotedSummary}', style: Kit.caption),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  Widget _originalPane(MailDetail d) {
    final html = d.html;
    if (html != null && html.trim().isNotEmpty) {
      // 字号缩放变了就重新载入网页（WebView 不吃 Flutter 的字号设置）
      return _box(
        ValueListenableBuilder<double>(
          valueListenable: Zoom.scale,
          builder: (_, scale, _) => _HtmlView(key: ValueKey(scale), html: html, scale: scale),
        ),
      );
    }
    return _box(
      SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text((d.plain ?? '').trim().isEmpty ? '（这封信没有正文）' : d.plain!, style: Kit.text),
      ),
    );
  }
}

class _HtmlView extends StatefulWidget {
  const _HtmlView({super.key, required this.html, required this.scale});
  final String html;
  final double scale;

  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  // 给邮件套一层基础样式：浅底深字、正文 18px、图片不超宽。信里自带的样式仍然优先。
  // 整体再按字号缩放（CSS zoom），信里自带的小字也一起放大。
  String get _zoomStyle => '<style>html { zoom: ${widget.scale}; }</style>';

  static const _baseStyle = '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { background:#FFFFFF; color:#111B21; }
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         font-size:18px; line-height:1.6; margin:0; padding:20px; word-wrap:break-word; }
  img { max-width:100%; height:auto; }
  table { max-width:100%; }
  pre { white-space:pre-wrap; font-size:16px; }
  blockquote { border-left:3px solid #DCE2E7; margin-left:0; padding-left:12px; color:#3B4A54; }
</style>
''';

  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // 邮件里的脚本一律不跑（安全）
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          // 第一次载入信件内容放行；之后点链接的跳转都拦下（以后改成用浏览器打开）
          onNavigationRequest: (req) => _loaded ? NavigationDecision.prevent : NavigationDecision.navigate,
          onPageFinished: (_) => _loaded = true,
        ),
      )
      ..loadHtmlString(_baseStyle + _zoomStyle + widget.html);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

/// 一个附件：图标 + 文件名 + 大小，「打开」「存到下载」两个按钮
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.att});
  final MailAttachment att;

  IconData get _icon {
    final t = att.mediaType;
    if (t.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (t.startsWith('image/')) return Icons.image_rounded;
    if (t.contains('word') || t.contains('document')) return Icons.description_rounded;
    if (t.contains('sheet') || t.contains('excel')) return Icons.table_chart_rounded;
    if (t.contains('zip') || t.contains('compressed')) return Icons.folder_zip_rounded;
    return Icons.attach_file_rounded;
  }

  void _snack(BuildContext context, String text, {SnackBarAction? action}) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 18)),
          action: action,
        ),
      );

  Future<void> _open(BuildContext context) async {
    try {
      await AttachmentFiles.open(att.name, att.data);
    } catch (e) {
      if (context.mounted) _snack(context, '打不开：$e');
    }
  }

  Future<void> _save(BuildContext context) async {
    try {
      final path = await AttachmentFiles.saveToDownloads(att.name, att.data);
      if (context.mounted) {
        _snack(
          context,
          '✓ 已存到「下载」：${path.split('/').last}',
          action: SnackBarAction(label: '在访达中显示', onPressed: () => AttachmentFiles.reveal(path)),
        );
      }
    } catch (e) {
      if (context.mounted) _snack(context, '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Kit.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Kit.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 26, color: const Color(0xFF1565C0)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(att.name, style: Kit.textBold, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(AttachmentFiles.formatSize(att.size), style: Kit.caption),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _open(context),
            child: const Text('打开', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => _save(context),
            child: const Text('存到下载', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
  }
}
