// 统一的界面零件：浅灰底 + 白卡片 + 细分割线；四级字号；状态徽章。
// 配色和字号照搬 autoTransWhatsapp 的 DesignKit.swift（用户老花眼：浅底深字、大字、不用浅灰字）。
// 新界面一律用这些，不要各写各的。
import 'package:material_ui/material_ui.dart';

class Kit {
  static const canvas = Color(0xFFEEF4F1); // 页面底色：很浅的薄荷绿，衬出白卡片（比纯灰活泼）
  static const hairline = Color(0xFFDCE2E7); // 卡片边框、分割线
  static const ink = Color(0xFF111B21); // 正文：近黑
  static const inkSoft = Color(0xFF3B4A54); // 次要文字：深灰蓝（白底对比约 9:1）
  static const accent = Color(0xFF00705A); // 深绿
  static const accentBg = Color(0xFFE6F2EE);
  static const warn = Color(0xFF9E1A0D); // 深红
  static const okBg = Color(0xFFE2F3EB);
  static const warnBg = Color(0xFFFBE8E5);

  // 四级字号 26 / 19 / 18 / 16
  static const pageTitle = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ink, height: 1.3);
  static const cardTitle = TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink, height: 1.4);
  static const text = TextStyle(fontSize: 18, color: ink, height: 1.6);
  static const textBold = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink, height: 1.5);
  static const caption = TextStyle(fontSize: 16, color: inkSoft, height: 1.5);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      primary: accent,
      error: warn,
      surface: Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      textTheme: const TextTheme(
        bodyLarge: text,
        bodyMedium: text,
        bodySmall: caption,
        titleLarge: pageTitle,
        titleMedium: cardTitle,
        labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: pageTitle,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(fontSize: 17, color: inkSoft),
        floatingLabelStyle: TextStyle(fontSize: 17, color: accent),
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: hairline, width: 1.5),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      tooltipTheme: const TooltipThemeData(textStyle: TextStyle(fontSize: 16, color: Colors.white)),
    );
  }
}

/// 白色圆角卡片，可选标题
class KitCard extends StatelessWidget {
  const KitCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding});
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Kit.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || subtitle != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) Text(title!, style: Kit.cardTitle),
                        if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: Kit.caption)],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Kit.hairline),
          ],
          Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}

/// ✓ / ✗ 徽章：图标 + 文字 + 底色（不只靠颜色）
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final fg = ok ? Kit.accent : Kit.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: ok ? Kit.okBg : Kit.warnBg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            ok ? '✓ $text' : '✗ $text',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// 页面内容最大宽度，大屏上不至于一行太长
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 860});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 语言小标签的配色：每种语言一个色系（浅底 + 同色系深字，对比度 ≥ 4.5:1）+ 国旗，文字标签照样写。
class LangStyle {
  const LangStyle(this.bg, this.fg, this.flag);
  final Color bg;
  final Color fg;
  final String flag;

  static const _styles = {
    'es': LangStyle(Color(0xFFFFE9B3), Color(0xFF7A3E00), '🇪🇸'),
    'en': LangStyle(Color(0xFFDCEBFF), Color(0xFF0B4A99), '🇬🇧'),
    'it': LangStyle(Color(0xFFD9F5E1), Color(0xFF136434), '🇮🇹'),
    'fr': LangStyle(Color(0xFFE4E6FF), Color(0xFF3B34A0), '🇫🇷'),
    'de': LangStyle(Color(0xFFEFE6D8), Color(0xFF5B4313), '🇩🇪'),
    'pt': LangStyle(Color(0xFFD4F2EF), Color(0xFF0D5C57), '🇵🇹'),
    'ca': LangStyle(Color(0xFFFFE2D4), Color(0xFF9A3412), ''),
    'other': LangStyle(Color(0xFFF0E3FF), Color(0xFF6B21A8), '🌐'),
  };

  static LangStyle of(String code) => _styles[code] ?? _styles['other']!;
}

/// 语言小标签：国旗 + 文字（西语 / 英语 …）+ 彩色底
class LangChip extends StatelessWidget {
  const LangChip({super.key, required this.code, required this.label});
  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final st = LangStyle.of(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: st.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: st.fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        st.flag.isEmpty ? label : '${st.flag} $label',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: st.fg),
      ),
    );
  }
}

/// 发件人头像：彩色圆 + 首字母（白字，底色都够深，对比度 ≥ 4.5:1）。同一个人永远同一个颜色。
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 38});
  final String name;
  final double size;

  static const _colors = [
    Color(0xFF1565C0), // 蓝
    Color(0xFF2E7D32), // 绿
    Color(0xFFC62828), // 红
    Color(0xFF6A1B9A), // 紫
    Color(0xFFAD1457), // 玫红
    Color(0xFF00695C), // 青
    Color(0xFFBF360C), // 橙
    Color(0xFF4527A0), // 靛
    Color(0xFF006064), // 深青
    Color(0xFF5D4037), // 棕
  ];

  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final letter = n.isEmpty ? '?' : String.fromCharCode(n.runes.first).toUpperCase();
    var h = 0;
    for (final r in n.toLowerCase().runes) {
      h = (h * 31 + r) & 0x7fffffff;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _colors[h % _colors.length], shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
        textScaler: TextScaler.noScaling, // 头像大小固定，字不跟着全局缩放
      ),
    );
  }
}
