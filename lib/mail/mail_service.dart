import 'package:enough_mail/enough_mail.dart';

import 'account.dart';

/// 左侧栏的文件夹。各家邮箱文件夹名不同，按 IMAP 的特殊用途标记（\Sent 等）找，找不到再按常见名字找。
enum MailFolder {
  inbox('收件箱'),
  sent('已发送'),
  drafts('草稿');

  const MailFolder(this.label);
  final String label;
}

/// 信件列表里的一行（只有信封信息，不含正文）。
class MailSummary {
  MailSummary({
    required this.uid,
    this.seq = 0,
    required this.fromName,
    required this.fromEmail,
    required this.toName,
    required this.subject,
    this.messageId,
    this.date,
    required this.seen,
  });
  final int uid;
  final int seq; // 在文件夹里的序号（1 = 最旧）；往下翻「更早的信」用
  final String fromName;
  final String fromEmail;
  final String toName; // 第一个收件人（「已发送」里显示这个）
  final String subject;
  final String? messageId; // 信头里的 Message-ID，全球唯一，用来存译文
  final DateTime? date;
  final bool seen;

  /// 标成已读后的同一封信
  MailSummary asSeen() => MailSummary(
    uid: uid,
    seq: seq,
    fromName: fromName,
    fromEmail: fromEmail,
    toName: toName,
    subject: subject,
    messageId: messageId,
    date: date,
    seen: true,
  );
}

/// 一个文件夹的收信结果。
class FolderPage {
  FolderPage({required this.mails, required this.total, required this.unseen});
  final List<MailSummary> mails; // 最近的若干封，最新的在前

  /// 已载入的最旧一封的序号；> 1 说明还有更早的信
  int get lowestSeq => mails.isEmpty ? 0 : mails.map((m) => m.seq).reduce((a, b) => a < b ? a : b);
  final int total; // 文件夹里一共几封
  final int unseen; // 未读几封
}

/// 打开后的一封信。
class MailDetail {
  MailDetail({
    required this.summary,
    this.messageId,
    this.html,
    this.plain,
    required this.to,
    required this.attachments,
    this.replyToEmail,
    this.references,
    this.cc = '',
    this.toEmails = const [],
    this.ccEmails = const [],
  });
  final MailSummary summary;
  final String cc; // 抄送（显示用）
  final List<String> toEmails; // 收件人地址（回复全部用）
  final List<String> ccEmails; // 抄送地址（回复全部用）
  final String? replyToEmail; // 信头 Reply-To（回信优先发到这里）
  final String? references; // 信头 References（回信时接在后面，让对方邮箱把信归成一串）
  final String? messageId; // 信头里的 Message-ID，全球唯一，用来存译文
  final String? html;
  final String? plain;
  final String to;
  final List<String> attachments; // 附件文件名
}

/// 要发出的一封信（已经是翻译好的外语）。
class OutgoingMail {
  OutgoingMail({
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    this.inReplyTo,
    this.references,
  });
  final List<String> to; // 收件人邮箱地址
  final List<String> cc; // 抄送
  final List<String> bcc; // 密送（只在发给服务器的收件人名单里，信里不出现）
  final String subject;
  final String body;
  final String? inReplyTo; // 回信：原信的 Message-ID
  final String? references; // 回信：原信的 References
}

/// 发信结果。sentNote 不为空时说明「已发送」里没存成功（信本身已发出）。
class SendResult {
  SendResult({this.sentNote});
  final String? sentNote;
}

/// 连接测试的结果：收信、发信分开报。
class ConnectionReport {
  ConnectionReport({this.imapError, this.smtpError});
  final String? imapError;
  final String? smtpError;
  bool get ok => imapError == null && smtpError == null;
}

/// 收发信。小样阶段每次操作都新开一条连接、做完就断开，简单可靠；以后再优化成长连接。
/// 现在只读：取信用 BODY.PEEK，不会把信标成已读。
class MailService {
  MailService(this.account);
  final Account account;

  static const _timeout = Duration(seconds: 30);

  Future<ImapClient> _openImap() async {
    final a = account;
    final client = ImapClient(defaultResponseTimeout: _timeout);
    await client.connectToServer(a.imapHost, a.imapPort, isSecure: a.imapPort == 993);
    if (a.imapPort != 993) await client.startTls();
    await client.login(a.userName, a.password);
    // 有些国内邮箱（网易等）要求客户端先报身份（IMAP ID 命令）才让读信；不支持的服务器忽略即可
    try {
      await client.id(
        clientId: const Id(name: 'MailAutoTrans', version: '0.1'),
      );
    } catch (_) {}
    return client;
  }

  Future<void> _close(ImapClient c) async {
    try {
      await c.logout();
    } catch (_) {}
    try {
      await c.disconnect();
    } catch (_) {}
  }

  /// 测试收信（IMAP 登录）和发信（SMTP 登录），不发出任何信。
  Future<ConnectionReport> test() async {
    String? imapError;
    String? smtpError;
    try {
      final c = await _openImap();
      await _close(c);
    } catch (e) {
      imapError = describeError(e);
    }
    try {
      final s = await _openSmtp();
      try {
        await s.quit();
      } catch (_) {}
    } catch (e) {
      smtpError = describeError(e);
    }
    return ConnectionReport(imapError: imapError, smtpError: smtpError);
  }

  Future<SmtpClient> _openSmtp() async {
    final a = account;
    final domain = a.email.contains('@') ? a.email.split('@').last : 'localhost';
    final client = SmtpClient(domain);
    await client.connectToServer(a.smtpHost, a.smtpPort, isSecure: a.smtpPort == 465);
    await client.ehlo();
    if (a.smtpPort != 465) {
      await client.startTls();
    }
    final mech = client.serverInfo.supportsAuth(AuthMechanism.plain) ? AuthMechanism.plain : AuthMechanism.login;
    await client.authenticate(a.userName, a.password, mech);
    return client;
  }

  // 没有特殊用途标记的服务器，按这些常见名字找（小写比较）
  static const _sentNames = [
    'sent',
    'sent messages',
    'sent items',
    'sent mail',
    '[gmail]/sent mail',
    '已发送',
    '已发送邮件',
    'enviados',
    'elementos enviados',
  ];
  static const _draftNames = ['drafts', 'draft', '[gmail]/drafts', '草稿', '草稿箱', 'borradores'];

  /// 找到文件夹（只定位，不打开）。
  Future<Mailbox?> _locate(ImapClient c, MailFolder f) async {
    final boxes = await c.listMailboxes(recursive: true);
    Mailbox? hit;
    for (final b in boxes) {
      if ((f == MailFolder.inbox && (b.isInbox || b.path.toUpperCase() == 'INBOX')) ||
          (f == MailFolder.sent && b.isSent) ||
          (f == MailFolder.drafts && b.isDrafts)) {
        hit = b;
        break;
      }
    }
    if (hit == null && f != MailFolder.inbox) {
      final names = f == MailFolder.sent ? _sentNames : _draftNames;
      for (final b in boxes) {
        if (names.contains(b.path.toLowerCase()) || names.contains(b.name.toLowerCase())) {
          hit = b;
          break;
        }
      }
    }
    return hit;
  }

  /// 文件夹里最近 [count] 封，最新的在前。只取信封，不取正文，不标已读。
  Future<FolderPage> fetchFolder(MailFolder folder, {int count = 50}) async {
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) throw StateError('这个邮箱里找不到「${folder.label}」文件夹。');
      // 未读数要在打开文件夹之前问（规范不建议对已打开的文件夹用 STATUS）
      var unseen = 0;
      try {
        unseen = (await c.statusMailbox(found, [StatusFlags.unseen])).messagesUnseen;
      } catch (_) {}
      final box = await c.selectMailbox(found);
      if (box.messagesExists == 0) return FolderPage(mails: [], total: 0, unseen: unseen);
      // 库里的算法把区间两端都算上，传 count 会多取一封（显示 51 封），所以减 1
      final result = await c.fetchRecentMessages(messageCount: count - 1, criteria: '(UID FLAGS ENVELOPE)');
      final list = result.messages.map(_summary).toList();
      list.sort((a, b) => b.uid.compareTo(a.uid));
      return FolderPage(mails: list, total: box.messagesExists, unseen: unseen);
    } finally {
      await _close(c);
    }
  }

  /// 只问文件夹的未读数（左侧栏其他邮箱用，不取信）
  Future<int> unseenCount(MailFolder folder) async {
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) return 0;
      return (await c.statusMailbox(found, [StatusFlags.unseen])).messagesUnseen;
    } finally {
      await _close(c);
    }
  }

  /// 往下翻：取序号 [beforeSeq] 之前（更早）的 [count] 封，最新的在前。
  Future<List<MailSummary>> fetchOlder(MailFolder folder, int beforeSeq, {int count = 50}) async {
    if (beforeSeq <= 1) return [];
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) throw StateError('这个邮箱里找不到「${folder.label}」文件夹。');
      await c.selectMailbox(found);
      final hi = beforeSeq - 1;
      final lo = (hi - count + 1).clamp(1, hi);
      final result = await c.fetchMessages(MessageSequence.fromRange(lo, hi), '(UID FLAGS ENVELOPE)');
      return result.messages.map(_summary).toList()..sort((a, b) => b.uid.compareTo(a.uid));
    } finally {
      await _close(c);
    }
  }

  /// 在服务器上搜整个文件夹（不只是已载入的）：发件人、收件人、标题里含 [query]。
  /// [extraSubjects]：中文搜索词对上了本机缓存的中文标题时，把对应的外文原标题也一起搜。
  /// 返回所有匹配信的 UID，最新的在前。
  Future<List<int>> search(MailFolder folder, String query, {List<String> extraSubjects = const []}) async {
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) throw StateError('这个邮箱里找不到「${folder.label}」文件夹。');
      await c.selectMailbox(found);
      SearchTerm term = SearchTermOr(
        SearchTermFrom(query),
        SearchTermOr(SearchTermTo(query), SearchTermSubject(query)),
      );
      for (final s in extraSubjects) {
        term = SearchTermOr(term, SearchTermSubject(s));
      }
      final q = SearchQueryBuilder.from('', SearchQueryType.subject);
      final nonAscii = [query, ...extraSubjects].any((t) => t.codeUnits.any((u) => u < 32 || u >= 127));
      if (nonAscii) q.add(const SearchTermCharsetUf8());
      q.add(term);
      final result = await c.uidSearchMessagesWithQuery(q);
      final uids = result.matchingSequence?.toList() ?? <int>[];
      uids.sort((a, b) => b.compareTo(a));
      return uids;
    } finally {
      await _close(c);
    }
  }

  /// 按 UID 批量取信封（搜索结果分页用），最新的在前。
  Future<List<MailSummary>> fetchByUids(MailFolder folder, List<int> uids) async {
    if (uids.isEmpty) return [];
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) throw StateError('这个邮箱里找不到「${folder.label}」文件夹。');
      await c.selectMailbox(found);
      final result = await c.uidFetchMessages(MessageSequence.fromIds(uids, isUid: true), '(UID FLAGS ENVELOPE)');
      return result.messages.map(_summary).toList()..sort((a, b) => b.uid.compareTo(a.uid));
    } finally {
      await _close(c);
    }
  }

  /// 按 UID 取一封信的全文（UID 只在所属文件夹里有效）。
  /// [markSeen]：顺便在服务器上标成已读（Gmail / Outlook 里也会变成已读），和一般邮件软件一样。
  Future<MailDetail> fetchMessage(MailFolder folder, int uid, {bool markSeen = true}) async {
    final c = await _openImap();
    try {
      final found = await _locate(c, folder);
      if (found == null) throw StateError('这个邮箱里找不到「${folder.label}」文件夹。');
      await c.selectMailbox(found);
      final result = await c.uidFetchMessage(uid, '(UID FLAGS BODY.PEEK[])');
      if (result.messages.isEmpty) {
        throw StateError('这封信找不到了，可能已被删除或移走。');
      }
      final m = result.messages.first;
      if (markSeen && !m.isSeen) {
        try {
          await c.uidMarkSeen(MessageSequence.fromId(uid, isUid: true));
        } catch (_) {} // 标已读失败不影响读信
      }
      final to = (m.to ?? const <MailAddress>[]).map(_addr).join('、');
      final attachments = m
          .findContentInfo(disposition: ContentDisposition.attachment)
          .map((i) => i.fileName ?? '（无名附件）')
          .toList();
      return MailDetail(
        summary: _summary(m),
        messageId: m.decodeHeaderValue('message-id')?.trim(),
        html: m.decodeTextHtmlPart(),
        plain: m.decodeTextPlainPart(),
        to: to,
        attachments: attachments,
        replyToEmail: (m.replyTo?.isNotEmpty ?? false) ? m.replyTo!.first.email : null,
        cc: (m.cc ?? const <MailAddress>[]).map(_addr).join('、'),
        toEmails: (m.to ?? const <MailAddress>[]).map((e) => e.email).toList(),
        ccEmails: (m.cc ?? const <MailAddress>[]).map((e) => e.email).toList(),
        references: m.decodeHeaderValue('references')?.trim(),
      );
    } finally {
      await _close(c);
    }
  }

  /// 发一封纯文字信（UTF-8）。回信时带上 In-Reply-To / References，对方邮箱会把信归成一串。
  /// 发出后检查「已发送」里有没有这封（Gmail 等会自动存）；没有才自己存一份，避免重复。
  Future<SendResult> send(OutgoingMail mail) async {
    // 发出去的那份不带 Bcc 信头（否则所有收件人都看得到密送名单）；存进「已发送」的那份带上，自己以后查得到
    final built = buildOutgoing(account, mail);
    final message = built.message;
    final messageId = built.messageId;
    final sentCopy = mail.bcc.isEmpty
        ? message
        : buildOutgoing(account, mail, includeBcc: true, messageId: messageId).message;
    final recipients = [...mail.to, ...mail.cc, ...mail.bcc].map((e) => MailAddress(null, e)).toList();

    final smtp = await _openSmtp();
    try {
      await smtp.sendMessage(message, recipients: recipients);
    } finally {
      try {
        await smtp.quit();
      } catch (_) {}
    }

    // 存进「已发送」：失败不影响「已发出」这个事实，只在结果里说明
    String? sentNote;
    try {
      await Future<void>.delayed(const Duration(seconds: 3)); // 给服务器一点时间自动存
      final c = await _openImap();
      try {
        final box = await _locate(c, MailFolder.sent);
        if (box == null) {
          sentNote = '邮箱里找不到「已发送」文件夹，这封信没有存副本。';
        } else {
          await c.selectMailbox(box);
          var already = false;
          if (messageId != null) {
            final found = await c.uidSearchMessages(
              searchCriteria: 'HEADER Message-ID "${messageId.replaceAll('"', '')}"',
            );
            already = !(found.matchingSequence?.isEmpty ?? true);
          }
          if (!already) {
            await c.appendMessage(sentCopy, targetMailbox: box, flags: [r'\Seen']);
          }
        }
      } finally {
        await _close(c);
      }
    } catch (e) {
      sentNote = '信已经发出，但存进「已发送」时出错：${describeError(e)}';
    }
    return SendResult(sentNote: sentNote);
  }

  MailSummary _summary(MimeMessage m) {
    final env = m.envelope;
    final from = (env?.from ?? m.from ?? const <MailAddress>[]);
    final first = from.isEmpty ? null : from.first;
    final name = first?.personalName;
    final tos = (env?.to ?? m.to ?? const <MailAddress>[]);
    final firstTo = tos.isEmpty ? null : tos.first;
    final toN = firstTo?.personalName;
    final subj = (env?.subject ?? m.decodeSubject() ?? '').trim();
    return MailSummary(
      uid: m.uid ?? 0,
      seq: m.sequenceId ?? 0,
      fromName: (name != null && name.trim().isNotEmpty) ? name.trim() : (first?.email ?? '（无发件人）'),
      fromEmail: first?.email ?? '',
      toName: (toN != null && toN.trim().isNotEmpty) ? toN.trim() : (firstTo?.email ?? '（无收件人）'),
      messageId: env?.messageId?.trim() ?? m.decodeHeaderValue('message-id')?.trim(),
      subject: subj.isEmpty ? '（无标题）' : subj,
      date: env?.date ?? m.decodeDate(),
      seen: m.isSeen,
    );
  }

  static String _addr(MailAddress a) {
    final n = a.personalName;
    return (n != null && n.trim().isNotEmpty) ? '${n.trim()} <${a.email}>' : a.email;
  }
}

/// 把各种连接错误翻成人话。
String describeError(Object e) {
  final s = e.toString();
  final lower = s.toLowerCase();
  if (lower.contains('authenticationfailed') ||
      lower.contains('authentication failed') ||
      lower.contains('invalid credentials') ||
      lower.contains('535') ||
      lower.contains('login failed') ||
      lower.contains('auth')) {
    return '用户名或密码不对。注意要用「客户端专用密码 / 应用专用密码 / 授权码」，不是平时网页登录的密码。\n（原始信息：$s）';
  }
  if (lower.contains('failed host lookup') || lower.contains('nodename nor servname')) {
    return '找不到这个服务器地址，请检查拼写，或者网络是否连上。\n（原始信息：$s）';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '连接超时：服务器没有回应。请检查端口号和网络。\n（原始信息：$s）';
  }
  if (lower.contains('connection refused')) {
    return '服务器拒绝连接，端口号可能不对。\n（原始信息：$s）';
  }
  if (lower.contains('operation not permitted')) {
    return '本机不允许这个 App 联网（Mac 沙盒权限没开）。这是程序的问题，请告诉开发者。\n（原始信息：$s）';
  }
  return s;
}

/// 把要发的信组装成 MIME 邮件（单独拿出来方便测试）。
/// [includeBcc] 只给「已发送」里的副本用；[messageId] 让两份用同一个 Message-ID。
({MimeMessage message, String? messageId}) buildOutgoing(
  Account a,
  OutgoingMail mail, {
  bool includeBcc = false,
  String? messageId,
}) {
  final builder = MessageBuilder()
    ..from = [MailAddress(a.displayName.trim().isEmpty ? null : a.displayName.trim(), a.email)]
    ..to = mail.to.map((e) => MailAddress(null, e)).toList()
    ..subject = mail.subject
    ..text = mail.body;
  if (mail.cc.isNotEmpty) builder.cc = mail.cc.map((e) => MailAddress(null, e)).toList();
  if (includeBcc && mail.bcc.isNotEmpty) builder.bcc = mail.bcc.map((e) => MailAddress(null, e)).toList();
  if (messageId != null) builder.messageId = messageId;
  if (mail.inReplyTo != null && mail.inReplyTo!.isNotEmpty) {
    builder.setHeader('In-Reply-To', mail.inReplyTo);
    final refs = [if (mail.references != null && mail.references!.isNotEmpty) mail.references!, mail.inReplyTo!];
    builder.setHeader('References', refs.join(' '));
  }
  final message = builder.buildMimeMessage();
  return (message: message, messageId: builder.messageId);
}
