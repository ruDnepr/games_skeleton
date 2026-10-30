import 'dart:async';

import 'package:flutter/material.dart';

import '../app/catalog.dart';
import '../app/settings.dart';
import 'games_page.dart';
import 'rules_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.settings});
  final SettingsController settings;
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(settings: widget.settings),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: Center(
        child: FadeTransition(
          opacity: _animation,
          child: ScaleTransition(
            scale: Tween(begin: .75, end: 1.0).animate(
              CurvedAnimation(parent: _animation, curve: Curves.elasticOut),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Logo(size: 125),
                const SizedBox(height: 28),
                Text(
                  'Игры для Дианы',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Время играть и улыбаться!',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.settings});
  final SettingsController settings;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  children: [
                    // Настройки открываются пунктом меню ниже: отдельная
                    // шестерёнка в шапке дублировала его и убрана.
                    const Row(children: [Eyebrow('ИГРАЕМ ВМЕСТЕ ✦')]),
                    const SizedBox(height: 24),
                    const _Logo(size: 132),
                    const SizedBox(height: 22),
                    const Text(
                      'Игры\nдля Дианы',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 37,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 11),
                    const Text(
                      'Думай, играй и улыбайся!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 29),
                    BigButton(
                      title: 'Играть',
                      subtitle: 'Выбери свою игру',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GamesPage(settings: settings),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    BigButton(
                      title: 'Сетевая игра',
                      subtitle: 'С другом по Wi-Fi',
                      icon: Icons.wifi_rounded,
                      color: const Color(0xFFF4CB67),
                      foreground: ink,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GamesPage(
                            settings: settings,
                            purpose: GamesPurpose.network,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallMenu(
                            icon: Icons.menu_book_rounded,
                            label: 'Правила',
                            color: const Color(0xFFE9E1FB),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RulesPage(game: GameCatalog.first),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SmallMenu(
                            icon: Icons.tune_rounded,
                            label: 'Настройки',
                            color: const Color(0xFFFCE4D7),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsPage(settings: settings),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      settings.gamesPlayed == 0
                          ? 'Каждая партия — маленькое приключение ✨'
                          : 'Сыграно партий: ${settings.gamesPlayed}  ·  Побед: ${settings.gamesWon}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SmallMenu extends StatelessWidget {
  const _SmallMenu({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .82),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: ink, size: 21),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, color: ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Logo of the app: a tilted board with a grid on it, two chips and a sparkle.
///
/// The composition is the one the frame was drawn with — the same tilt, the
/// same shadows, the same two pieces over the board — but the board itself is
/// neutral: a plain grid of the palette instead of a game position.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 45,
    height: size + 25,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 15,
          top: 10,
          child: Transform.rotate(
            angle: -.12,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF8C5831),
                borderRadius: BorderRadius.circular(23),
                boxShadow: const [
                  BoxShadow(color: Color(0xFFA66C3D), offset: Offset(0, 7)),
                  BoxShadow(
                    color: Color(0x33714850),
                    blurRadius: 20,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),
          ),
        ),
        Positioned(
          left: -2,
          top: size * .28,
          child: Transform.rotate(
            angle: -.2,
            child: _Chip(size: size * .40, color: purple),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 5,
          child: Transform.rotate(
            angle: .2,
            child: _Chip(size: size * .42, color: yellow),
          ),
        ),
        Positioned(
          right: 2,
          top: 0,
          child: Transform.rotate(
            angle: .2,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: const Color(0xFFF0BE48),
              size: size * .24,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One round chip of the logo: no crown, no colour of a side, just a token.
class _Chip extends StatelessWidget {
  const _Chip({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, color],
      ),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .22),
          blurRadius: 0,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: size * .42,
        height: size * .42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: .72),
        ),
      ),
    ),
  );
}

/// A neutral four-by-four grid: no pieces, no position, no rules.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final rect = Rect.fromLTWH(
          c * size.width / 4,
          r * size.height / 4,
          size.width / 4,
          size.height / 4,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = (r + c).isEven
                ? const Color(0xFFFFF3DA)
                : const Color(0xFFE7DDF7),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
