// ignore_for_file: avoid_print -- 命令行测试工具，就是要打印
// 本机 MLX 模型冒烟测试：不开界面，按 App 里的四种用法各翻一次，打印结果和耗时，然后退出。
// 用法（Mac）：
//   flutter run -d macos -t tools/local_smoke.dart --dart-define=MODEL=/path/to/mlx-model
// 不联网、不花钱。
import 'dart:io';

import 'package:auto_trans_mail/translate/html_translate.dart';
import 'package:auto_trans_mail/translate/translator.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const model = String.fromEnvironment('MODEL');
  final t = Translator(TranslateSettings(engine: Engine.local, localModelPath: model));
  final sw = Stopwatch();

  Future<void> step(String name, Future<Object?> Function() f) async {
    sw
      ..reset()
      ..start();
    try {
      final r = await f();
      print('SMOKE ✓ $name（${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒）\n$r\n');
    } catch (e) {
      print('SMOKE ✗ $name（${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒）：$e\n');
    }
  }

  print('SMOKE 模型：$model');
  await step(
    '列表标题（含加载模型）',
    () => t
        .translateSubjects({
          0: 'Informe mensual BBVA Octubre 2026',
          1: '1 nuovo annuncio per la tua ricerca istantanea',
          2: 'Your Uber receipt for Sunday evening',
        })
        .then((m) => m.entries.map((e) => '${e.key}: ${e.value.zh} [${e.value.lang}]').join('\n')),
  );

  await step(
    '读信（纯文字）',
    () => t
        .translateIncoming(
          subject: 'Presupuesto reforma cocina',
          from: 'Reformas García <info@example.es>',
          body:
              'Hola Ana,\n\nOs envío el presupuesto de la reforma de la cocina: 4.850 € IVA incluido. '
              'Podemos empezar el lunes 1 de diciembre si nos confirmáis antes del viernes.\n\nUn saludo,\nLuis',
        )
        .then((r) => '[${r.sourceLanguage}] ${r.subjectZh}\n${r.bodyZh}'),
  );

  final seg = HtmlSegmenter.parse(
    '<p>Accede a tu <b>extracto mensual</b></p>'
    '<p>Para consultarlo deberás introducir <b>tu documento de identidad</b>. Más info en '
    '<a href="https://www.bbva.es/ayuda">nuestra web</a>.</p>',
  );
  await step('HTML 信（占位标记要保住）', () async {
    final r = await t.translateHtmlSegments([for (final s in seg.segments) MapEntry(s.id, s.source)]);
    final applied = seg.apply(r.zh);
    return '${r.zh}\n占位对不上的段落：${applied.failed}';
  });

  await step(
    '写信（中文 → 西班牙语）',
    () => t
        .translateOutgoing(
          subjectZh: '回复：厨房装修报价',
          bodyZh: '你好 Luis，\n\n报价收到了，谢谢。我们同意 12 月 1 日周一开工。请问需要先付定金吗？\n\n谢谢',
          langPromptName: '西班牙语（西班牙本地用法，不用拉美说法）',
          spanish: true,
        )
        .then((o) => '${o.subject}\n${o.body}'),
  );

  print('SMOKE 结束');
  exit(0);
}
