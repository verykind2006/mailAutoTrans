import 'package:auto_trans_mail/mail/account.dart';
import 'package:auto_trans_mail/pages/compose_page.dart';
import 'package:auto_trans_mail/ui/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('写信页：光标在正文里时 ⌘↩、Esc 都能触发', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: Kit.theme(),
        home: Scaffold(
          body: ComposeView(
            account: Account(
              email: 'me@example.com',
              userName: 'me@example.com',
              password: 'pw',
              imapHost: 'i',
              imapPort: 993,
              smtpHost: 's',
              smtpPort: 465,
            ),
            onClose: () => closed = true,
            onSent: (_) {},
            onOpenTranslateSettings: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 在正文里打字，然后按 ⌘↩：收件人没填，应该出提示（说明快捷键没被输入框吞掉）
    final body = find.widgetWithText(TextField, '正文（像平时说话一样写就行）');
    await tester.tap(body);
    await tester.enterText(body, '你好');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining('请填写收件人'), findsOneWidget);

    // 按 Esc：还没翻译 = 关闭；写了内容会先问
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('不发了？'), findsOneWidget);
    await tester.tap(find.text('丢掉'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
