/// 把 HTML 邮件粗略转成纯文字，给翻译用（显示原文仍然用 WebView）。
String htmlToText(String html) {
  var s = html;
  // 去掉不显示的部分
  s = s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  s = s.replaceAll(RegExp(r'<(head|style|script|title)\b[^>]*>.*?</\1\s*>', caseSensitive: false, dotAll: true), '');
  // 换行类标签
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|blockquote|table)\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ');
  s = s.replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), '  ');
  // 其余标签全部去掉
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  s = _decodeEntities(s);
  // 整理空白：行内多余空格压成一个，连续空行最多留一行
  s = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim()).join('\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

String _decodeEntities(String s) {
  const named = {
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'iexcl': '¡',
    'iquest': '¿',
    'euro': '€',
    'copy': '©',
    'reg': '®',
    'hellip': '…',
    'ndash': '–',
    'mdash': '—',
    'laquo': '«',
    'raquo': '»',
    'ordm': 'º',
    'ordf': 'ª',
  };
  return s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
    final code = m[1]!;
    if (code.startsWith('#')) {
      final n = code.startsWith('#x') || code.startsWith('#X')
          ? int.tryParse(code.substring(2), radix: 16)
          : int.tryParse(code.substring(1));
      return n == null ? m[0]! : String.fromCharCode(n);
    }
    // 带重音的字母（á é ñ ü …）
    final accent = RegExp(r'^([a-zA-Z])(acute|grave|tilde|uml|circ|cedil)$').firstMatch(code);
    if (accent != null) {
      const table = {
        'aacute': 'á',
        'eacute': 'é',
        'iacute': 'í',
        'oacute': 'ó',
        'uacute': 'ú',
        'Aacute': 'Á',
        'Eacute': 'É',
        'Iacute': 'Í',
        'Oacute': 'Ó',
        'Uacute': 'Ú',
        'ntilde': 'ñ',
        'Ntilde': 'Ñ',
        'uuml': 'ü',
        'Uuml': 'Ü',
        'ccedil': 'ç',
        'Ccedil': 'Ç',
        'agrave': 'à',
        'egrave': 'è',
        'ograve': 'ò',
        'acirc': 'â',
        'ecirc': 'ê',
        'ocirc': 'ô',
      };
      return table[code] ?? m[0]!;
    }
    return named[code] ?? m[0]!;
  });
}

/// 粗判是不是中文信：汉字占「字母 + 汉字」的三成以上就算中文，不用花钱翻译。
bool looksChinese(String text) {
  var han = 0;
  var letters = 0;
  for (final r in text.runes) {
    if (r >= 0x4E00 && r <= 0x9FFF) {
      han++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) {
      letters++;
    }
  }
  // 一个汉字大约顶五个字母
  return han * 5 > (han * 5 + letters) * 0.3;
}
