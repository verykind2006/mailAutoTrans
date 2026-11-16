import 'package:material_ui/material_ui.dart';

import '../translate/local_model.dart';
import '../translate/translator.dart';
import '../ui/kit.dart';

/// 设置 →「翻译引擎」：选引擎（Claude / DeepSeek / OpenAI / 其他 OpenAI 兼容 / 本机模型），
/// 填 key、点「测试」拉出这家的模型列表再选；本机模型选模型文件夹并检查。每家的 key、模型各自记住。
class TranslateSettingsPage extends StatefulWidget {
  const TranslateSettingsPage({super.key, required this.initial, required this.onSaved, this.embedded = false});
  final TranslateSettings initial;
  final void Function(TranslateSettings) onSaved;

  /// true = 放在「设置」窗口的标签页里（不带自己的标题栏）
  final bool embedded;

  @override
  State<TranslateSettingsPage> createState() => _TranslateSettingsPageState();
}

class _TranslateSettingsPageState extends State<TranslateSettingsPage> {
  late Engine _engine = widget.initial.engine;
  late final Map<String, String> _keys = {...widget.initial.keys};
  late final Map<String, String> _models = {...widget.initial.models};
  late final _key = TextEditingController(text: widget.initial.keyOf(_engine));
  late final _model = TextEditingController(text: widget.initial.modelOf(_engine));
  late final _baseUrl = TextEditingController(text: widget.initial.customBaseUrl);
  late final _localPath = TextEditingController(text: widget.initial.localModelPath);
  late TranslateSettings _saved = widget.initial;
  bool _showKey = false;
  bool _testing = false;
  List<String>? _modelList; // 「测试」拉回来的模型列表
  String? _error;
  bool? _ok;
  List<({bool ok, String text})>? _localChecks;

  @override
  void dispose() {
    for (final c in [_key, _model, _baseUrl, _localPath]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 把当前框里的内容收进一份设置（换引擎前、测试前、保存前都调用）
  TranslateSettings _current() {
    _keys[_engine.name] = _key.text.trim();
    if (_model.text.trim().isNotEmpty) _models[_engine.name] = _model.text.trim();
    return TranslateSettings(
      engine: _engine,
      keys: {..._keys},
      models: {..._models},
      customBaseUrl: _baseUrl.text.trim(),
      localModelPath: _localPath.text.trim(),
    );
  }

  void _switchEngine(Engine e) {
    final s = _current();
    setState(() {
      _engine = e;
      _key.text = s.keyOf(e);
      _model.text = s.modelOf(e);
      _modelList = null;
      _ok = null;
      _error = null;
      _localChecks = null;
    });
  }

  /// 联网引擎：用 key 拉模型列表（不收费），成功 = key 和网址都对
  Future<void> _test() async {
    final s = _current();
    if (s.apiKey.isEmpty) {
      setState(() {
        _ok = false;
        _error = '请先填写 API key。';
      });
      return;
    }
    setState(() {
      _testing = true;
      _ok = null;
      _error = null;
    });
    try {
      final list = await Translator(s).listModels();
      if (!mounted) return;
      setState(() {
        _ok = true;
        _modelList = list;
        if (_model.text.trim().isEmpty && list.length == 1) _model.text = list.first;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _checkLocal() async {
    setState(() => _localChecks = null);
    try {
      final r = await LocalModel.check(_localPath.text.trim());
      if (mounted) setState(() => _localChecks = r);
    } catch (e) {
      if (mounted) setState(() => _localChecks = [(ok: false, text: '$e')]);
    }
  }

  Future<void> _pickFolder() async {
    final p = await LocalModel.pickFolder(_localPath.text.trim());
    if (p != null && mounted) {
      setState(() => _localPath.text = p);
      await _checkLocal();
    }
  }

  Future<void> _save() async {
    final s = _current();
    if (!s.configured) {
      setState(() {
        _ok = false;
        _error = _engine == Engine.local
            ? '请先选择本机模型文件夹。'
            : (s.apiKey.isEmpty ? '请先填写 API key。' : '请先选好模型（点「测试」后从列表里选）。');
      });
      return;
    }
    await s.save();
    setState(() {
      _saved = s;
      _error = null;
    });
    widget.onSaved(s);
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: PageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitCard(
              title: '用哪个翻译引擎',
              subtitle: '每家的 key 和模型各自记住，切换不会丢。现在在用：${_saved.summary}',
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RadioGroup<Engine>(
                groupValue: _engine,
                onChanged: (e) {
                  if (e != null) _switchEngine(e);
                },
                child: Column(
                  children: [
                    for (final e in Engine.values)
                      if (e != Engine.local || LocalModel.supported)
                        RadioListTile<Engine>(
                          value: e,
                          title: Text(e.title, style: Kit.text),
                          subtitle: Text(_engineNote(e), style: Kit.caption),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_engine),
                child: _engine == Engine.local ? _localCard() : _onlineCard(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('保存并使用')),
                const SizedBox(width: 16),
                if (_ok != null) StatusBadge(ok: _ok!, text: _ok! ? '测试通过' : '有问题'),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 18, color: Kit.warn, height: 1.5)),
            ],
          ],
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('翻译设置')),
      // 用 SelectionArea + Text，不用 SelectableText（Flutter 3.50 Mac 无障碍桥会崩，见 CLAUDE.md）
      body: SelectionArea(child: body),
    );
  }

  static String _engineNote(Engine e) => switch (e) {
    Engine.anthropic => '效果最好，按用量付费。默认模型 ${TranslateSettings.defaultClaudeModel}',
    Engine.deepseek => '便宜，中文好',
    Engine.openai => 'GPT 系列',
    Engine.custom => '通义千问、Kimi、智谱等，凡是支持 OpenAI 格式的都行',
    Engine.local => '不联网、不花钱，但慢一些、质量差一些；要先下载 MLX 格式的模型',
  };

  Widget _onlineCard() {
    final list = _modelList;
    return KitCard(
      title: _engine.title,
      subtitle: _engine.keyHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_engine == Engine.custom) ...[
            TextField(
              controller: _baseUrl,
              style: Kit.text,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: '例如 https://dashscope.aliyuncs.com/compatible-mode/v1',
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _key,
            obscureText: !_showKey,
            style: Kit.text,
            onChanged: (_) => setState(() => _ok = null),
            decoration: InputDecoration(
              labelText: 'API key',
              suffixIcon: IconButton(
                tooltip: _showKey ? '隐藏' : '显示',
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(onPressed: _testing ? null : _test, child: Text(_testing ? '正在测试…' : '测试并获取模型列表')),
              const SizedBox(width: 12),
              const Flexible(child: Text('测试不收费', style: Kit.caption)),
            ],
          ),
          const SizedBox(height: 16),
          if (list != null && list.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: list.contains(_model.text.trim()) ? _model.text.trim() : null,
              isExpanded: true,
              style: Kit.text,
              menuMaxHeight: 480,
              decoration: InputDecoration(labelText: '模型（这家共有 ${list.length} 个）'),
              items: [for (final m in list) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _model.text = v ?? ''),
            )
          else
            TextField(
              controller: _model,
              style: Kit.text,
              decoration: const InputDecoration(
                labelText: '模型名',
                helperText: '点上面「测试」后可以从列表里选；也可以直接填',
                helperStyle: Kit.caption,
              ),
            ),
        ],
      ),
    );
  }

  Widget _localCard() {
    final checks = _localChecks;
    return KitCard(
      title: '本机模型（MLX）',
      subtitle: '选一个 MLX 格式的模型文件夹（例如 Qwen 的 4 位量化版）。可以和 autoTransWhatsapp 共用同一个文件夹。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _localPath,
                  style: Kit.text,
                  decoration: const InputDecoration(labelText: '模型文件夹'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _pickFolder, child: const Text('选择…')),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _checkLocal, child: const Text('检查模型文件夹')),
          ),
          if (checks != null) ...[
            const SizedBox(height: 12),
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${c.ok ? '✓' : '✗'} ${c.text}',
                  style: TextStyle(fontSize: 18, color: c.ok ? Kit.accent : Kit.warn, height: 1.5),
                ),
              ),
          ],
          const SizedBox(height: 8),
          const Text('第一次翻译要把模型载入内存，大约十几秒；之后快一些。', style: Kit.caption),
        ],
      ),
    );
  }
}
