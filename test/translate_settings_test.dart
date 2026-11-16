import 'package:auto_trans_mail/translate/translator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧版设置（只有 Claude 的 apiKey/model）能自动搬到新格式', () {
    final s = TranslateSettings.fromJson({'apiKey': 'sk-ant-xxx', 'model': 'claude-opus-5-5'});
    expect(s.engine, Engine.anthropic);
    expect(s.apiKey, 'sk-ant-xxx');
    expect(s.model, 'claude-opus-5-5');
    expect(s.configured, isTrue);
  });

  test('每家各存 key 和模型；切引擎不丢', () {
    final s = TranslateSettings(
      engine: Engine.deepseek,
      keys: {'anthropic': 'a', 'deepseek': 'd'},
      models: {'deepseek': 'deepseek-chat'},
    );
    final back = TranslateSettings.fromJson(s.toJson());
    expect(back.engine, Engine.deepseek);
    expect(back.keyOf(Engine.anthropic), 'a');
    expect(back.modelOf(Engine.anthropic), TranslateSettings.defaultClaudeModel); // Claude 没选模型 → 默认
    expect(back.baseUrl, 'https://api.deepseek.com');
    expect(back.configured, isTrue);
  });

  test('什么时候算「设置好了」', () {
    expect(TranslateSettings(engine: Engine.openai, keys: {'openai': 'k'}).configured, isFalse); // 没选模型
    expect(
      TranslateSettings(engine: Engine.custom, keys: {'custom': 'k'}, models: {'custom': 'm'}).configured,
      isFalse,
    ); // 没填网址
    expect(
      TranslateSettings(
        engine: Engine.custom,
        keys: {'custom': 'k'},
        models: {'custom': 'm'},
        customBaseUrl: 'https://x/v1',
      ).configured,
      isTrue,
    );
    expect(TranslateSettings(engine: Engine.local).configured, isFalse);
    expect(TranslateSettings(engine: Engine.local, localModelPath: '/m').configured, isTrue);
  });

  test('模型回的 JSON 字符串里直接换行（Qwen2.5-7B 实测）也能解析', () {
    const reply =
        '好的：\n{"is_chinese":false,"subject_zh":"厨房装修报价单","body_zh":"安娜，\n\n我附上报价单：4850欧元。\n\n此致，\n路易斯","quoted_summary":""}';
    final j = Translator.parseModelJson(reply);
    expect(j['body_zh'], '安娜，\n\n我附上报价单：4850欧元。\n\n此致，\n路易斯');
    expect(j['subject_zh'], '厨房装修报价单');
    // 本来就合法、带转义的 JSON 不受影响
    expect(Translator.parseModelJson(r'{"a":"x\ny \"q\""}')['a'], 'x\ny "q"');
  });
}
