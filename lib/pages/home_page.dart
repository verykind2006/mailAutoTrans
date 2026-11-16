import 'package:material_ui/material_ui.dart';

import '../mail/account.dart';
import '../mail/mail_service.dart';
import '../translate/text_tools.dart';
import '../translate/translator.dart';
import '../ui/format.dart';
import '../ui/kit.dart';
import '../ui/ui_prefs.dart';
import 'compose_page.dart';
import 'message_page.dart';

/// 主界面：照 Gmail 网页版的布局——左侧栏（写邮件 + 文件夹）、顶部搜索框、一行一封的信件列表；
/// 点开一封信，右侧内容区换成读信界面。
/// 字号、颜色按老花眼规矩来（列表 18px、摘要用深灰），不照搬 Gmail 的小字浅灰。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.accounts, required this.onOpenSettings});
  final List<Account> accounts; // 至少一个

  /// 打开设置；tab 0 = 邮箱账户，1 = 翻译引擎
  final Future<void> Function(int tab) onOpenSettings;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  String _email = ''; // 当前选中的邮箱
  MailFolder _folder = MailFolder.inbox;
  final Map<String, FolderPage> _pages = {}; // 键 = 邮箱|文件夹
  final Map<String, int> _unseen = {}; // 邮箱 → 收件箱未读数（左侧栏显示）
  final Map<String, SubjectInfo> _zh = {}; // 原标题 → 中文标题 + 原文语言
  bool _loading = false;
  String? _error;
  bool _translatingSubjects = false;
  String? _subjectError;
  MailSummary? _open; // 正在读的信
  bool _composing = false; // 正在写信
  ReplyContext? _replyTo; // 正在回复的信（新写信为 null）
  final _search = TextEditingController();
  String _query = ''; // 搜索框里的字（打字时只在已载入的信里筛）
  bool _loadingMore = false; // 正在往下加载更早的信
  // 按回车后：在服务器上搜整个文件夹
  String? _serverQuery;
  List<int> _searchUids = []; // 全部匹配的 UID（最新的在前）
  List<MailSummary> _searchResults = []; // 已取回信封的那部分
  bool _searching = false;

  /// 当前邮箱（被删了就退回第一个）
  Account get _account => widget.accounts.firstWhere((a) => a.email == _email, orElse: () => widget.accounts.first);

  /// 当前「邮箱 + 文件夹」的键
  String get _key => '${_account.email}|${_folder.name}';

  @override
  void initState() {
    super.initState();
    _email = widget.accounts.first.email;
    refresh();
    _loadOtherUnseen();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 在设置里增删改了邮箱：清空旧列表，重新收信
    if (!identical(oldWidget.accounts, widget.accounts)) {
      _pages.clear();
      _unseen.removeWhere((e, _) => !widget.accounts.any((a) => a.email == e));
      if (!widget.accounts.any((a) => a.email == _email)) _email = widget.accounts.first.email;
      _open = null;
      _composing = false;
      refresh();
      _loadOtherUnseen();
    }
  }

  /// 其他邮箱的收件箱未读数（只问数字，不取信）
  Future<void> _loadOtherUnseen() async {
    for (final a in widget.accounts) {
      if (a.email == _email) continue;
      try {
        final n = await MailService(a).unseenCount(MailFolder.inbox);
        if (mounted) setState(() => _unseen[a.email] = n);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 收信（菜单「邮件 → 收信」⌘R 也调这个）
  Future<void> refresh() async {
    if (_loading) return;
    if (_serverQuery != null) {
      await _serverSearch(); // 正在看搜索结果：重新搜一次
      return;
    }
    final key = _key;
    final account = _account;
    final folder = _folder;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await MailService(account).fetchFolder(folder);
      if (!mounted) return;
      setState(() {
        _pages[key] = page;
        if (folder == MailFolder.inbox) _unseen[account.email] = page.unseen;
      });
      await _loadSubjects(page.mails);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 列表的中文标题：先读本机缓存，没翻过的外语标题一次批量翻。
  Future<void> _loadSubjects(List<MailSummary> mails) async {
    final todo = <String>{};
    for (final m in mails) {
      if (_zh.containsKey(m.subject) || looksChinese(m.subject)) continue;
      final cached = await SubjectCache.get(m.subject);
      if (cached != null) {
        _zh[m.subject] = cached;
      } else {
        todo.add(m.subject);
      }
    }
    if (mounted) setState(() {});
    if (todo.isEmpty) return;
    final settings = await TranslateSettings.load();
    if (!settings.configured || !mounted) return; // 没填 key 就先显示原标题
    setState(() {
      _translatingSubjects = true;
      _subjectError = null;
    });
    try {
      final list = todo.toList();
      final result = await Translator(settings).translateSubjects({for (var i = 0; i < list.length; i++) i: list[i]});
      final pairs = {for (final e in result.entries) list[e.key]: e.value};
      await SubjectCache.putAll(pairs);
      _zh.addAll(pairs);
    } catch (e) {
      _subjectError = '标题翻译失败：$e';
    } finally {
      if (mounted) setState(() => _translatingSubjects = false);
    }
  }

  void _selectFolder(String email, MailFolder f) {
    setState(() {
      _email = email;
      _folder = f;
      _open = null;
      _composing = false;
      _replyTo = null;
      // 换文件夹：搜索清空
      _search.clear();
      _query = '';
      _serverQuery = null;
      _searchUids = [];
      _searchResults = [];
    });
    refresh(); // 每次切换都收一次（切回来也保持最新）；已有的列表先显示着
  }

  void _compose([ReplyContext? reply]) {
    setState(() {
      _composing = true;
      _replyTo = reply;
    });
  }

  void _closeCompose() => setState(() {
    _composing = false;
    _replyTo = null;
  });

  void _sent(String? note) {
    final wasReply = _replyTo != null;
    _closeCompose();
    if (!wasReply) setState(() => _open = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: note == null ? 4 : 10),
        content: Text(note == null ? '✓ 已发出，并存进了「已发送」' : '✓ 已发出。$note', style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  /// 打开一封未读信后：列表里这封变成已读（不再是绿底加粗），收件箱未读数减一
  void _markedRead(int uid) {
    setState(() {
      final page = _pages[_key];
      if (page != null) {
        final i = page.mails.indexWhere((m) => m.uid == uid);
        if (i >= 0 && !page.mails[i].seen) {
          final mails = [...page.mails]..[i] = page.mails[i].asSeen();
          _pages[_key] = FolderPage(mails: mails, total: page.total, unseen: page.unseen > 0 ? page.unseen - 1 : 0);
          if (_folder == MailFolder.inbox) _unseen[_account.email] = _pages[_key]!.unseen;
        }
      }
      final j = _searchResults.indexWhere((m) => m.uid == uid);
      if (j >= 0) _searchResults = [..._searchResults]..[j] = _searchResults[j].asSeen();
      if (_open?.uid == uid) _open = _open!.asSeen();
    });
  }

  // ── 往下翻：懒加载，每次 50 封 ──

  bool get _hasMore {
    if (_serverQuery != null) return _searchResults.length < _searchUids.length;
    if (_query.trim().isNotEmpty) return false; // 本地筛选时不自动往下载（否则会把整个邮箱都载进来）
    return (_pages[_key]?.lowestSeq ?? 0) > 1;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _searching || !_hasMore) return;
    final folder = _folder;
    final key = _key;
    setState(() => _loadingMore = true);
    try {
      final svc = MailService(_account);
      if (_serverQuery != null) {
        final next = _searchUids.skip(_searchResults.length).take(50).toList();
        final more = await svc.fetchByUids(folder, next);
        if (!mounted || _key != key) return;
        setState(() => _searchResults = [..._searchResults, ...more]);
        await _loadSubjects(more);
      } else {
        final page = _pages[key]!;
        final more = await svc.fetchOlder(folder, page.lowestSeq);
        if (!mounted || _key != key) return;
        final known = page.mails.map((m) => m.uid).toSet();
        final fresh = more.where((m) => !known.contains(m.uid)).toList();
        setState(
          () => _pages[key] = FolderPage(mails: [...page.mails, ...fresh], total: page.total, unseen: page.unseen),
        );
        await _loadSubjects(fresh);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更早的信失败：${describeError(e)}', style: const TextStyle(fontSize: 18))));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── 搜索：回车 = 在服务器上搜整个文件夹 ──

  Future<void> _serverSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    final folder = _folder;
    final key = _key;
    setState(() {
      _searching = true;
      _serverQuery = q;
      _searchUids = [];
      _searchResults = [];
      _open = null;
      _error = null;
    });
    try {
      // 中文搜索词：服务器上只有外文原标题，所以把本机中文标题对得上的原标题也一起搜
      final extra = looksChinese(q) ? await SubjectCache.originalsMatching(q) : <String>[];
      final svc = MailService(_account);
      final uids = await svc.search(folder, q, extraSubjects: extra);
      final first = await svc.fetchByUids(folder, uids.take(50).toList());
      if (!mounted || _key != key || _serverQuery != q) return;
      setState(() {
        _searchUids = uids;
        _searchResults = first;
      });
      await _loadSubjects(first);
    } catch (e) {
      if (mounted) setState(() => _error = '搜索失败：${describeError(e)}');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearSearch() => setState(() {
    _search.clear();
    _query = '';
    _serverQuery = null;
    _searchUids = [];
    _searchResults = [];
  });

  List<MailSummary> get _visible {
    if (_serverQuery != null) return _searchResults;
    final mails = _pages[_key]?.mails ?? const <MailSummary>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return mails;
    return mails.where((m) {
      final hay = '${m.fromName} ${m.fromEmail} ${m.toName} ${m.subject} ${_zh[m.subject]?.zh ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Kit.canvas,
      // 用 SelectionArea + Text，不用 SelectableText（Flutter 3.50 Mac 无障碍桥会崩，见 CLAUDE.md）
      body: SelectionArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              accounts: widget.accounts,
              email: _account.email,
              folder: _folder,
              unseen: _unseen,
              onSelect: _selectFolder,
              onCompose: _compose,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _searchBar(),
                  // 列表 / 读信 / 写信 之间淡入淡出切换
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(
                          _composing
                              ? 'compose:${_replyTo?.messageId}:${_replyTo?.replyAll}'
                              : (_open == null ? 'list:${_folder.name}' : 'read:${_open!.uid}'),
                        ),
                        child: _composing
                            ? ComposeView(
                                account: _account,
                                accounts: widget.accounts,
                                reply: _replyTo,
                                onClose: _closeCompose,
                                onSent: _sent,
                                onOpenTranslateSettings: () => widget.onOpenSettings(1),
                              )
                            : (_open == null ? _listPane() : _readPane(_open!)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 24, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: TextField(
            controller: _search,
            style: Kit.text,
            onChanged: (v) => setState(() {
              _query = v;
              _open = null;
              _serverQuery = null; // 改了搜索词，旧的全部搜索结果作废，回到本地筛选
            }),
            onSubmitted: (_) => _serverSearch(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索邮件：打字先筛已载入的，按回车搜全部',
              hintStyle: const TextStyle(fontSize: 18, color: Kit.inkSoft),
              prefixIcon: const Icon(Icons.search, size: 26, color: Kit.inkSoft),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(tooltip: '清除', icon: const Icon(Icons.close, size: 24), onPressed: _clearSearch),
              filled: true,
              fillColor: const Color(0xFFE6EAEE),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: Kit.accent, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readPane(MailSummary m) {
    return MessageView(
      key: ValueKey('${_folder.name}:${m.uid}'),
      account: _account,
      folder: _folder,
      summary: m,
      listSubjectZh: _zh[m.subject]?.zh,
      onBack: () => setState(() => _open = null),
      onOpenTranslateSettings: () => widget.onOpenSettings(1),
      onReply: _folder == MailFolder.inbox ? _compose : null,
      onMarkedRead: _markedRead,
    );
  }

  Widget _listPane() {
    final page = _pages[_key];
    final mails = _visible;
    final String status;
    if (_loading) {
      status = '正在收信…';
    } else if (_searching) {
      status = '正在搜「$_serverQuery」…';
    } else if (_serverQuery != null) {
      status = '全部「${_folder.label}」里搜「$_serverQuery」：找到 ${_searchUids.length} 封';
    } else if (_translatingSubjects) {
      status = '正在把标题翻成中文…';
    } else if (page != null) {
      final shown = page.mails.length;
      status = _query.isEmpty
          ? '共 ${page.total} 封，已载入 $shown 封（往下拉自动加载）'
          : '在已载入的 $shown 封里筛出 ${mails.length} 封 · 按回车搜全部';
    } else {
      status = '';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 24, 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Kit.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 工具条：收信 + 状态
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : refresh,
                    icon: const Icon(Icons.refresh, size: 24),
                    label: const Text('收信', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  // 列表标题：中文 / 原文 切换（记住选择）
                  ValueListenableBuilder<bool>(
                    valueListenable: UiPrefs.showOriginalSubjects,
                    builder: (_, original, _) => SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('中文标题', style: TextStyle(fontSize: 17))),
                        ButtonSegment(value: true, label: Text('原标题', style: TextStyle(fontSize: 17))),
                      ],
                      selected: {original},
                      showSelectedIcon: true,
                      onSelectionChanged: (v) => UiPrefs.setShowOriginalSubjects(v.first),
                    ),
                  ),
                  if (_loading || _translatingSubjects) ...[
                    const SizedBox(width: 8),
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
                  ],
                  const Spacer(),
                  Text(status, style: Kit.caption),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Kit.hairline),
            if (_subjectError != null)
              Container(
                color: Kit.warnBg,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text('✗ $_subjectError', style: const TextStyle(fontSize: 16, color: Kit.warn)),
              ),
            Expanded(child: _listBody(page, mails)),
          ],
        ),
      ),
    );
  }

  Widget _listBody(FolderPage? page, List<MailSummary> mails) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusBadge(ok: false, text: '收信失败'),
            const SizedBox(height: 12),
            Text(_error!, style: Kit.text),
          ],
        ),
      );
    }
    if (page == null) return const Center(child: Text('正在收信…', style: Kit.text));
    if (mails.isEmpty) {
      if (_searching) return const Center(child: Text('正在搜索…', style: Kit.text));
      if (_serverQuery != null) {
        return Center(child: Text('全部「${_folder.label}」里没有找到「$_serverQuery」。', style: Kit.text));
      }
      return Center(
        child: Text(_query.isEmpty ? '「${_folder.label}」里没有信。' : '已载入的信里没有匹配的。按回车，在全部邮件里搜。', style: Kit.text),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: UiPrefs.showOriginalSubjects,
      builder: (_, original, _) => ListView.separated(
        itemCount: mails.length + 1, // 最后一行是「加载更多 / 到底了」
        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1, color: Kit.hairline),
        itemBuilder: (context, i) {
          if (i == mails.length) return _footer();
          final m = mails[i];
          return _MailRow(
            mail: m,
            info: _zh[m.subject],
            showOriginal: original,
            showRecipient: _folder != MailFolder.inbox,
            onTap: () => setState(() => _open = m),
          );
        },
      ),
    );
  }

  /// 列表最后一行：滚到这里就自动加载下一批（ListView 只在快显示时才构建它）
  Widget _footer() {
    final more = _hasMore;
    if (more && !_loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
    final String text;
    if (_loadingMore || more) {
      text = '正在加载更早的 50 封…';
    } else if (_serverQuery != null) {
      text = '搜索结果就这些（共 ${_searchUids.length} 封）';
    } else if (_query.trim().isNotEmpty) {
      text = '只筛了已载入的信。按回车，在全部邮件里搜。';
    } else {
      text = '已经到底了（共 ${_pages[_key]?.total ?? 0} 封）';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_loadingMore || more) ...[
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 12),
          ],
          Text(text, style: Kit.caption),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.accounts,
    required this.email,
    required this.folder,
    required this.unseen,
    required this.onSelect,
    required this.onCompose,
  });
  final List<Account> accounts;
  final String email; // 当前选中的邮箱
  final MailFolder folder;
  final Map<String, int> unseen; // 邮箱 → 收件箱未读数
  final void Function(String email, MailFolder folder) onSelect;
  final VoidCallback onCompose;

  // 每个文件夹一个图标颜色（文字照样写，不只靠颜色）
  static const _icons = {
    MailFolder.inbox: (Icons.inbox_rounded, Color(0xFF1565C0)),
    MailFolder.sent: (Icons.send_rounded, Color(0xFF2E7D32)),
    MailFolder.drafts: (Icons.edit_note_rounded, Color(0xFFBF360C)),
  };

  @override
  Widget build(BuildContext context) {
    // 宽度跟着字号缩放变（⌘+ 放大后不挤）
    final z = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      width: 270 * z.clamp(1.0, 1.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 彩色小标志 + 名字
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 22),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF00897B), Color(0xFF1565C0)],
                      ),
                    ),
                    child: const Icon(Icons.translate_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'MailAutoTrans',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Kit.ink),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onCompose,
                style: FilledButton.styleFrom(
                  backgroundColor: Kit.accent,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: Kit.accent.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                icon: const Icon(Icons.edit_rounded, size: 24),
                label: const Text('写邮件', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 18),
            // 按邮箱分组：每个邮箱一个小标题（头像 + 地址），下面是它的文件夹
            Expanded(
              child: ListView(
                children: [
                  for (final a in accounts) ...[
                    if (accounts.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 4, 6),
                        child: Row(
                          children: [
                            Avatar(name: a.email, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Kit.inkSoft),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final f in MailFolder.values)
                      _FolderItem(
                        icon: _icons[f]!.$1,
                        iconColor: _icons[f]!.$2,
                        label: f.label,
                        count: f == MailFolder.inbox && (unseen[a.email] ?? 0) > 0 ? unseen[a.email] : null,
                        selected: a.email == email && f == folder,
                        onTap: () => onSelect(a.email, f),
                      ),
                    if (accounts.length > 1) const Divider(height: 18, color: Kit.hairline, indent: 8, endIndent: 8),
                  ],
                ],
              ),
            ),
            if (accounts.length == 1)
              Row(
                children: [
                  Avatar(name: accounts.first.email, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(accounts.first.email, style: Kit.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderItem extends StatelessWidget {
  const _FolderItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weight = selected ? FontWeight.w700 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? const Color(0xFFD3EDE4) : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 26, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 18, fontWeight: weight, color: Kit.ink),
                  ),
                ),
                // 未读数：绿色胶囊白字
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: Kit.accent, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '$count',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表一行：▌未读竖条 ｜ 头像 ｜ 发件人（已发送里是收件人）｜ 语言标签 ｜ 中文标题 - 原标题 ｜ 日期
class _MailRow extends StatefulWidget {
  const _MailRow({
    required this.mail,
    required this.info,
    required this.showOriginal,
    required this.showRecipient,
    required this.onTap,
  });
  final MailSummary mail;
  final SubjectInfo? info; // 中文标题 + 原文语言；中文信或还没翻时为 null
  final bool showOriginal; // true = 只显示原标题
  final bool showRecipient;
  final VoidCallback onTap;

  @override
  State<_MailRow> createState() => _MailRowState();
}

class _MailRowState extends State<_MailRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.mail;
    final unread = !m.seen && !widget.showRecipient;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    final info = widget.info;
    final zh = info?.zh;
    final hasZh = zh != null && zh.isNotEmpty && zh != m.subject;
    final showZh = hasZh && !widget.showOriginal;
    final langTag = info?.label; // 「西语」「英语」…；中文信没有
    final who = widget.showRecipient ? m.toName : m.fromName;
    final z = MediaQuery.textScalerOf(context).scale(1); // 字号缩放倍数，列宽跟着变
    final bg = _hover ? const Color(0xFFE6F2EE) : (unread ? const Color(0xFFF3FBF8) : Colors.white);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            // 未读：左边一条绿色竖条 + 加粗（不只靠颜色）
            border: Border(left: BorderSide(color: unread ? Kit.accent : Colors.transparent, width: 5)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              Avatar(name: who),
              const SizedBox(width: 14),
              SizedBox(
                width: 200 * z,
                child: Text(
                  widget.showRecipient ? '致：$who' : who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: weight, color: Kit.ink),
                ),
              ),
              const SizedBox(width: 16),
              if (langTag != null) ...[LangChip(code: info!.lang, label: langTag), const SizedBox(width: 10)],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: showZh ? zh : m.subject,
                        style: TextStyle(fontSize: 18, fontWeight: weight, color: Kit.ink),
                      ),
                      if (showZh)
                        TextSpan(
                          text: '  -  ${m.subject}',
                          style: const TextStyle(fontSize: 17, color: Kit.inkSoft),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 130 * z,
                child: Text(
                  formatMailDate(m.date),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    color: unread ? Kit.accent : Kit.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
