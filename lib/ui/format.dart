String _two(int n) => n.toString().padLeft(2, '0');

/// 列表里的日期：今天只显示时间，今年显示「11月3日 09:15」，往年带年份。
String formatMailDate(DateTime? d, {DateTime? now}) {
  if (d == null) return '';
  final t = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final hm = '${_two(t.hour)}:${_two(t.minute)}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return '今天 $hm';
  if (t.year == n.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日 $hm';
}

/// 回信引用头里的日期：16/11/2026 15:30（日/月/年，欧洲通用写法）
String formatQuoteDate(DateTime d) {
  final t = d.toLocal();
  return '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';
}
