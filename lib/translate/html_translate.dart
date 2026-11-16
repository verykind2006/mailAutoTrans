import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// HTML 邮件「保留排版的翻译」：把 HTML 拆成一段段文字，翻好后原位换回去。
///
/// 做法：
/// - 找「叶子块」（p、td、li、h1… 里面不再有块级元素的那一层），整段送去翻译；
///   段内的加粗、链接等行内标记换成占位标记 `<x1>…</x1>`，图片等换成 `<i2/>`，换行是 `<br/>`。
///   模型只看到占位标记，碰不到链接地址等属性；翻完按编号换回原来的标签。
/// - 不在叶子块里的零散文字（块里夹着子块的情况）单独成段。
/// - 不翻：script/style/head 等；回信里引用的旧信（blockquote、gmail_quote 等）——和纯文字翻译「只翻新写的部分」一致。
class HtmlSegmenter {
  HtmlSegmenter._(this._doc, this.segments);

  final dom.Document _doc;

  /// 要翻译的段落，按在信里出现的顺序；编号从 1 开始（0 留给标题）
  final List<HtmlSegment> segments;

  static const _block = {
    'address', 'article', 'aside', 'blockquote', 'body', 'center', 'dd', 'div', 'dl', 'dt', 'fieldset', //
    'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'html',
    'li', 'main', 'nav', 'ol', 'p', 'section', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul',
    'caption', 'details', 'summary',
  };
  static const _skip = {'script', 'style', 'head', 'title', 'noscript', 'template', 'svg', 'math', 'pre', 'code'};
  static const _void = {'img', 'input', 'hr', 'wbr', 'area', 'col', 'embed', 'source', 'track', 'meta', 'link'};

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _urlOrEmail = RegExp(r'^(https?://\S+|www\.\S+|[^@\s]+@[^@\s]+\.\S+)$', caseSensitive: false);

  static HtmlSegmenter parse(String html) {
    final doc = html_parser.parse(html);
    final segs = <HtmlSegment>[];
    final root = doc.body ?? doc.documentElement;
    if (root != null) _walk(root, segs);
    return HtmlSegmenter._(doc, segs);
  }

  static bool _isQuote(dom.Element e) {
    if (e.localName == 'blockquote') return true;
    final cls = e.className;
    return cls.contains('gmail_quote') || cls.contains('yahoo_quoted') || e.id == 'divRplyFwdMsg';
  }

  static bool _hasBlockDescendant(dom.Element e) {
    for (final c in e.children) {
      if (_block.contains(c.localName) || _hasBlockDescendant(c)) return true;
    }
    return false;
  }

  static bool _meaningful(String text) {
    final t = text.trim();
    if (t.isEmpty || _urlOrEmail.hasMatch(t)) return false;
    return _letter.allMatches(t).length >= 2;
  }

  static void _walk(dom.Element e, List<HtmlSegment> segs) {
    if (_skip.contains(e.localName) || _isQuote(e)) return;
    if (_block.contains(e.localName) && !_hasBlockDescendant(e)) {
      if (_meaningful(e.text)) {
        final seg = HtmlSegment._(segs.length + 1, e, null);
        seg.source = seg._encodeChildren(e).trim();
        segs.add(seg);
      }
      return;
    }
    for (final n in e.nodes.toList()) {
      if (n is dom.Text) {
        if (_meaningful(n.data)) segs.add(HtmlSegment._(segs.length + 1, null, n)..source = n.data.trim());
      } else if (n is dom.Element) {
        _walk(n, segs);
      }
    }
  }

  /// 把译文换回去，返回整封信的 HTML。[zh]：段落编号 → 译文。没给译文的段落保留原文。
  /// 返回值里 [failed] 是占位标记对不上、只能去掉格式放纯文字的段落数。
  ({String html, int failed}) apply(Map<int, String> zh) {
    var failed = 0;
    for (final s in segments) {
      final t = zh[s.id];
      if (t == null || t.trim().isEmpty) continue;
      if (!s._put(t)) failed++;
    }
    return (html: _doc.outerHtml, failed: failed);
  }
}

/// 一段要翻译的文字。
class HtmlSegment {
  HtmlSegment._(this.id, this._element, this._text);

  final int id;
  final dom.Element? _element; // 叶子块：整段（带占位标记）
  final dom.Text? _text; // 零散文字节点
  String source = ''; // 送去翻译的文字（带占位标记）

  final Map<int, (String open, String close)> _pairs = {}; // xN → 原来的开始 / 结束标签
  final Map<int, String> _singles = {}; // iN → 原来的整个元素（图片等）
  int _next = 1;

  static String _attrEscape(String v) => v.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
  static String _textEscape(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static String _startTag(dom.Element e) {
    final b = StringBuffer('<${e.localName}');
    e.attributes.forEach((k, v) => b.write(' $k="${_attrEscape(v)}"'));
    b.write('>');
    return b.toString();
  }

  String _encodeChildren(dom.Element e) {
    final b = StringBuffer();
    for (final n in e.nodes) {
      if (n is dom.Text) {
        b.write(n.data.replaceAll(RegExp(r'\s+'), ' '));
      } else if (n is dom.Element) {
        final tag = n.localName ?? '';
        if (tag == 'br') {
          b.write('<br/>');
        } else if (HtmlSegmenter._void.contains(tag) || HtmlSegmenter._skip.contains(tag) || n.text.trim().isEmpty) {
          final k = _next++;
          _singles[k] = n.outerHtml;
          b.write('<i$k/>');
        } else {
          final k = _next++;
          _pairs[k] = (_startTag(n), '</$tag>');
          b.write('<x$k>${_encodeChildren(n)}</x$k>');
        }
      }
    }
    return b.toString();
  }

  static final _token = RegExp(r'<(/?)x(\d+)>|<i(\d+)\s*/>|<br\s*/?>');

  /// 放回译文。占位标记对得上返回 true；对不上就去掉标记只放文字，返回 false。
  bool _put(String zh) {
    final t = _text;
    if (t != null) {
      t.data = zh.replaceAll(_token, '');
      return true;
    }
    final e = _element!;
    // 检查：每个 xN 开、闭各一次且先开后闭，每个 iN 恰好一次，没有多出来的编号
    final opened = <int>{};
    final closed = <int>{};
    final singles = <int>{};
    var ok = true;
    for (final m in _token.allMatches(zh)) {
      if (m.group(2) != null) {
        final k = int.parse(m.group(2)!);
        if (!_pairs.containsKey(k)) ok = false;
        if (m.group(1) == '/') {
          if (!opened.contains(k) || !closed.add(k)) ok = false;
        } else if (!opened.add(k)) {
          ok = false;
        }
      } else if (m.group(3) != null) {
        final k = int.parse(m.group(3)!);
        if (!_singles.containsKey(k) || !singles.add(k)) ok = false;
      }
    }
    if (opened.length != _pairs.length || closed.length != _pairs.length || singles.length != _singles.length) {
      ok = false;
    }
    if (!ok) {
      e.text = zh.replaceAll(_token, ' ').replaceAll(RegExp(r' {2,}'), ' ').trim();
      return false;
    }
    final out = StringBuffer();
    var last = 0;
    for (final m in _token.allMatches(zh)) {
      out.write(_textEscape(zh.substring(last, m.start)));
      if (m.group(2) != null) {
        final p = _pairs[int.parse(m.group(2)!)]!;
        out.write(m.group(1) == '/' ? p.$2 : p.$1);
      } else if (m.group(3) != null) {
        out.write(_singles[int.parse(m.group(3)!)]);
      } else {
        out.write('<br>');
      }
      last = m.end;
    }
    out.write(_textEscape(zh.substring(last)));
    e.innerHtml = out.toString();
    return true;
  }
}
