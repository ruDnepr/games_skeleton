import 'package:flutter/material.dart';

const ink = Color(0xFF3D3154);
const muted = Color(0xFF8B8298);
const purple = Color(0xFF8266D5);
const deepPurple = Color(0xFF6047AF);
const cream = Color(0xFFFFF8ED);
const yellow = Color(0xFFFFD66D);
const peach = Color(0xFFFFD9C7);

ThemeData dianaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.light,
    ),
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: cream,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 19,
        fontWeight: FontWeight.w900,
        color: ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFFFCF6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFBF4), Color(0xFFFFF3E5), Color(0xFFF5EDFF)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -75,
          right: -90,
          child: _Glow(size: 230, color: yellow.withValues(alpha: .20)),
        ),
        Positioned(
          top: 310,
          left: -110,
          child: _Glow(size: 200, color: peach.withValues(alpha: .25)),
        ),
        Positioned(
          bottom: -90,
          right: -50,
          child: _Glow(size: 240, color: purple.withValues(alpha: .08)),
        ),
        child,
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: trailing == null ? null : [trailing!, const SizedBox(width: 12)],
    ),
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(
    this.label, {
    super.key,
    this.color = purple,
    this.background = const Color(0xFFEDE6FF),
    this.fontSize = 11,
  });
  final String label;
  final Color color;
  final Color background;

  /// Smaller on compact screens where the panel is a single line.
  final double fontSize;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: fontSize < 10 ? 9 : 12,
      vertical: fontSize < 10 ? 4 : 7,
    ),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: .8,
      ),
    ),
  );
}

class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.title,
    required this.icon,
    required this.onPressed,
    this.subtitle,
    this.color = purple,
    this.foreground = Colors.white,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .25),
            offset: const Offset(0, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: foreground, size: 25),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: foreground, size: 22),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tag,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tag;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF2EAE3)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: ink.withValues(alpha: .8), size: 29),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 7),
                Text(
                  tag!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: purple,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFC7BDCA)),
            ],
          ),
        ),
      ),
    ),
  );
}

class Intro extends StatelessWidget {
  const Intro({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
  });
  final String title;
  final String subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 15)],
      Text(
        title,
        style: const TextStyle(
          fontSize: 29,
          height: 1.12,
          fontWeight: FontWeight.w900,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 9),
      Text(
        subtitle,
        style: const TextStyle(
          color: muted,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

/// Body text of every dialog: quiet, readable and the same everywhere.
const dialogTextStyle = TextStyle(
  color: muted,
  fontSize: 14,
  fontWeight: FontWeight.w700,
  height: 1.4,
);

/// One button of [showDianaDialog]: [value] is what the dialog returns.
class DianaDialogButton<T> {
  const DianaDialogButton({
    required this.label,
    required this.value,
    this.primary = false,
    this.key,
  });
  final String label;
  final T value;

  /// The safe choice is filled and comes first; the other one is outlined.
  final bool primary;
  final Key? key;
}

/// A dialog with big buttons, one under another.
///
/// Material lays dialog actions out in a row. Three Russian labels there —
/// «Отменить ход», «В меню», «Играть снова» — shrink to a height a child
/// cannot hit, which is exactly what happened on the phone. Here every button
/// is full width and 56 px high, and the text never shrinks.
Future<T?> showDianaDialog<T>({
  required BuildContext context,
  required String title,
  required List<DianaDialogButton<T>> actions,
  Widget? content,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (dialogContext) => AlertDialog(
    scrollable: true,
    contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
    titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
    title: Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: ink,
        height: 1.15,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (content != null) ...[
          content,
          const SizedBox(height: 16),
        ],
        for (final (index, action) in actions.indexed) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: action.primary
                ? FilledButton(
                    key: action.key,
                    onPressed: () => Navigator.pop(dialogContext, action.value),
                    child: Text(action.label),
                  )
                : OutlinedButton(
                    key: action.key,
                    onPressed: () => Navigator.pop(dialogContext, action.value),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE3D8F5)),
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(action.label),
                  ),
          ),
          if (index != actions.length - 1) const SizedBox(height: 10),
        ],
      ],
    ),
  ),
);
