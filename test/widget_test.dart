import 'package:auto_trans_mail/mail/account.dart';
import 'package:auto_trans_mail/mail/mail_service.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:auto_trans_mail/translate/text_tools.dart';
import 'package:auto_trans_mail/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('账户设置存取前后一致', () {
    final a = Account(
      email: 'someone@example.com',
      userName: 'someone@example.com',
      password: 'pw',
      imapHost: 'imap.example.com',
      imapPort: 993,
      smtpHost: 'smtp.example.com',
      smtpPort: 465,
    );
    final b = Account.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('列表日期格式', () {
    final now = DateTime(2026, 11, 16, 15, 0);
    expect(formatMailDate(DateTime(2026, 11, 16, 9, 5), now: now), '今天 09:05');
    expect(formatMailDate(DateTime(2026, 3, 2, 18, 30), now: now), '3月2日 18:30');
    expect(formatMailDate(DateTime(2025, 12, 31, 8, 0), now: now), '2025年12月31日 08:00');
    expect(formatMailDate(null, now: now), '');
  });

  test('HTML 转纯文字', () {
    const html =
        '<html><head><style>p{color:red}</style></head><body>'
        '<p>Hola&nbsp;Ana,</p><p>Le env&iacute;o el presupuesto: 1.200&euro;</p>'
        '<ul><li>Pintura</li><li>Suelo</li></ul><br>Saludos</body></html>';
    expect(htmlToText(html), 'Hola Ana,\nLe envío el presupuesto: 1.200€\n• Pintura\n• Suelo\n\nSaludos');
  });

  test('判断中文信', () {
    expect(looksChinese('你好，明天下午三点见面可以吗？'), isTrue);
    expect(looksChinese('Hola, ¿podemos quedar mañana a las tres?'), isFalse);
    expect(
      looksChinese('Re: 报价 / Presupuesto para la reforma del piso en la calle Mayor, por favor confirme'),
      isFalse,
    );
  });

  test('组装回信：中文名字、西语正文、回信信头', () {
    final a = Account(
      email: 'me@example.com',
      userName: 'me@example.com',
      password: 'pw',
      imapHost: 'imap.example.com',
      imapPort: 993,
      smtpHost: 'smtp.example.com',
      smtpPort: 465,
      displayName: '小明',
    );
    final built = buildOutgoing(
      a,
      OutgoingMail(
        to: ['ana@example.es'],
        subject: 'Re: Presupuesto reforma',
        body: 'Hola Ana,\n¿Podéis venir el miércoles? Un saludo.',
        inReplyTo: '<abc@example.es>',
        references: '<old@example.es>',
      ),
    );
    final text = built.message.renderMessage();
    final parsed = MimeMessage.parseFromText(text);
    expect(parsed.decodeSubject(), 'Re: Presupuesto reforma');
    expect(parsed.from!.first.personalName, '小明');
    // 邮件里换行是 \r\n，统一成 \n 再比
    expect(
      parsed.decodeTextPlainPart()!.replaceAll('\r\n', '\n').trim(),
      'Hola Ana,\n¿Podéis venir el miércoles? Un saludo.',
    );
    expect(parsed.getHeaderValue('in-reply-to'), '<abc@example.es>');
    expect(parsed.getHeaderValue('references'), '<old@example.es> <abc@example.es>');
    expect(built.messageId, isNotNull);
  });

  test('密送不出现在发出去的信里，只出现在「已发送」副本里', () {
    final a = Account(
      email: 'me@example.com',
      userName: 'me@example.com',
      password: 'pw',
      imapHost: 'i',
      imapPort: 993,
      smtpHost: 's',
      smtpPort: 465,
    );
    final mail = OutgoingMail(
      to: ['ana@example.es'],
      cc: ['luis@example.es'],
      bcc: ['secret@example.com'],
      subject: 'Hola',
      body: 'Hola',
    );
    final sent = buildOutgoing(a, mail);
    final copy = buildOutgoing(a, mail, includeBcc: true, messageId: sent.messageId);
    final sentText = sent.message.renderMessage();
    expect(sentText.toLowerCase().contains('bcc:'), isFalse);
    expect(sentText.contains('secret@example.com'), isFalse);
    expect(sentText.contains('luis@example.es'), isTrue);
    final copyParsed = MimeMessage.parseFromText(copy.message.renderMessage());
    expect(copyParsed.bcc!.first.email, 'secret@example.com');
    expect(copy.messageId, sent.messageId);
  });
}
