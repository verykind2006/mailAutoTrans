import 'package:auto_trans_mail/mail/account.dart';
import 'package:auto_trans_mail/pages/compose_page.dart';
import 'package:auto_trans_mail/ui/kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 复现用户 2026-11-16 截图：翻译后按 Esc 回去改中文，中文豆腐块不见了 / 红色报错
void main() {
  Future<void> cmdEnter(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }

  // 1600 = 宽窗口；730 = 窗口最小宽 1000 减去左侧栏
  for (final width in [1600.0, 730.0]) {
    testWidgets('翻译 → Esc → 再翻译：中文卡片一直在，没有报错（宽 $width）', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final acc = Account(
        email: 'me@example.com',
        userName: 'me@example.com',
        password: 'pw',
        imapHost: 'i',
        imapPort: 993,
        smtpHost: 's',
        smtpPort: 465,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: Kit.theme(),
          home: Scaffold(
            body: ComposeView(account: acc, onClose: () {}, onSent: (_) {}, onOpenTranslateSettings: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '邮箱地址，多个用逗号隔开').first, 'ana@example.es');
      await tester.enterText(find.widgetWithText(TextField, '标题'), '你好');
      await tester.enterText(find.widgetWithText(TextField, '正文（像平时说话一样写就行）'), '明天见');
      // 选「不翻译」，这样不用联网就能走到第二步
      await tester.tap(find.text('西班牙语'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不翻译（直接发中文）').last);
      await tester.pumpAndSettle();

      final chinese = find.text('中文（你写的）');
      for (var round = 0; round < 3; round++) {
        await cmdEnter(tester); // 翻译（不翻译模式 = 直接进第二步）
        await tester.pumpAndSettle();
        expect(find.textContaining('要发出去的内容'), findsOneWidget, reason: '第 $round 轮：右栏应该出来');
        expect(chinese, findsOneWidget, reason: '第 $round 轮：翻译后中文卡片应该还在');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape); // 回去改中文
        await tester.pump(const Duration(milliseconds: 100)); // 动画进行中
        expect(chinese, findsOneWidget, reason: '第 $round 轮：收起动画中中文卡片应该还在');
        await tester.pumpAndSettle();
        expect(chinese, findsOneWidget, reason: '第 $round 轮：收起后中文卡片应该还在');
        expect(tester.takeException(), isNull);
      }
    });
  }
}
