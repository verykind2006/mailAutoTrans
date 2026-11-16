import 'package:auto_trans_mail/translate/html_translate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const html = '''
<html><head><style>.x{color:red}</style><title>Informe</title></head><body>
<table><tr><td align="center"><img src="https://bbva.es/logo.png" alt="BBVA"></td></tr>
<tr><td><h1>Accede a tu <b>extracto mensual</b></h1></td></tr>
<tr><td><p>Para consultarlo deberás introducir <b>tu documento de identidad</b>. Más info en
<a href="https://www.bbva.es/ayuda?a=1&amp;b=2">nuestra web</a>.</p></td></tr>
<tr><td>900 102 801</td></tr>
</table>
<div class="gmail_quote">El lunes, Ana escribió:<p>Texto antiguo que no se traduce</p></div>
</body></html>''';

  test('拆段：只拆有字的段，跳过 style / 纯数字 / 引用的旧信；行内标记换成占位', () {
    final s = HtmlSegmenter.parse(html);
    final src = s.segments.map((e) => e.source).toList();
    expect(src, [
      'Accede a tu <x1>extracto mensual</x1>',
      'Para consultarlo deberás introducir <x1>tu documento de identidad</x1>. Más info en <x2>nuestra web</x2>.',
    ]);
  });

  test('换回：链接地址、图片、引用原样保留，文字换成中文', () {
    final s = HtmlSegmenter.parse(html);
    final r = s.apply({1: '查看您的<x1>月度对账单</x1>', 2: '查看时需要输入<x1>您的身份证件号码</x1>。更多信息见<x2>我们的网站</x2>。'});
    expect(r.failed, 0);
    expect(r.html, contains('查看您的<b>月度对账单</b>'));
    expect(r.html, contains('<a href="https://www.bbva.es/ayuda?a=1&amp;b=2">我们的网站</a>'));
    expect(r.html, contains('src="https://bbva.es/logo.png"'));
    expect(r.html, contains('Texto antiguo que no se traduce')); // 引用的旧信不动
    expect(r.html, contains('900 102 801'));
    expect(r.html, isNot(contains('Accede a tu')));
  });

  test('占位标记对不上：只放文字，不让格式乱掉', () {
    final s = HtmlSegmenter.parse(html);
    final r = s.apply({1: '查看您的月度对账单（标记丢了）'});
    expect(r.failed, 1);
    expect(r.html, contains('查看您的月度对账单（标记丢了）'));
  });

  test('译文里的 < & 当文字处理，不会变成标签', () {
    final s = HtmlSegmenter.parse('<p>Hola <b>Ana</b> amiga</p>');
    final r = s.apply({1: '你好 <x1>Ana</x1> 朋友 <script>&'});
    expect(r.html, contains('&lt;script&gt;&amp;'));
  });
}
