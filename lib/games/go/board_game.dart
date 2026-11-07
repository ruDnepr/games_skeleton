import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/theme.dart';
import 'engine/model.dart';
import 'go_controller.dart';

// Тёплые тона деревянной доски го — те же, что в оригинальной игре «Го для
// Дианы», чтобы у ребёнка знакомая картинка.
const woodLight = Color(0xFFE7B677);
const woodMid = Color(0xFFD39A52);
const woodDark = Color(0xFFB97A39);
const woodLine = Color(0xFF6E4422);
const blackStoneDark = Color(0xFF1B1A22);
const blackStoneLight = Color(0xFF5A5764);
const whiteStoneDark = Color(0xFFE2D6BE);
const whiteStoneLight = Color(0xFFFFFFFF);

/// Доска го с объёмными камнями, подсказками и анимациями.
///
/// Реализована через CustomPaint + AnimationController — это надёжнее, чем
/// Flame-компоненты, для статичной геометрии го, и даёт ту же 3D-картинку.
class GoBoardView extends StatefulWidget {
  const GoBoardView({
    super.key,
    required this.controller,
    this.flipped = false,
  });

  final GoController controller;
  final bool flipped;

  @override
  State<GoBoardView> createState() => _GoBoardViewState();
}

class _GoBoardViewState extends State<GoBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  MoveAnimation? _lastAnimation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant GoBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  void _onChange() {
    final a = widget.controller.animation;
    if (a != null && !identical(a, _lastAnimation)) {
      _lastAnimation = a;
      _anim.forward(from: 0);
    } else if (a == null && _lastAnimation != null) {
      _lastAnimation = null;
      _anim.value = 1;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _anim.dispose();
    super.dispose();
  }

  Point? _pointFromLocal(
    Offset local,
    double boardSizePx,
    int n,
    double margin,
  ) {
    final usable = boardSizePx - margin * 2;
    final cell = usable / (n - 1);
    final dx = local.dx - margin;
    final dy = local.dy - margin;
    // Переворачиваем координаты, если доска отражена.
    final fx = widget.flipped ? (usable - dx) : dx;
    final fy = widget.flipped ? (usable - dy) : dy;
    final x = (fx / cell).round();
    final y = (fy / cell).round();
    if (x < 0 || y < 0 || x >= n || y >= n) return null;
    // Точность попадания — в радиусе половины клетки.
    final dxp = fx - x * cell;
    final dyp = fy - y * cell;
    if (math.sqrt(dxp * dxp + dyp * dyp) > cell * 0.45) {
      return null;
    }
    return Point(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return GestureDetector(
          onTapDown: (details) {
            final p = _pointFromLocal(
              details.localPosition,
              size,
              c.state.board.size,
              size * 0.06,
            );
            if (p != null) c.tap(p);
          },
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: _GoBoardPainter(
                  state: c.state,
                  legal: c.legalPlacements,
                  atari: c.atariPoints,
                  suggested: c.suggestedMove,
                  hintsOn: c.hints,
                  isMyTurn: c.isMyTurn,
                  animation: c.animation,
                  progress: _anim.value,
                  flipped: widget.flipped,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoBoardPainter extends CustomPainter {
  _GoBoardPainter({
    required this.state,
    required this.legal,
    required this.atari,
    required this.suggested,
    required this.hintsOn,
    required this.isMyTurn,
    required this.animation,
    required this.progress,
    required this.flipped,
  });

  final GameState state;
  final List<Point> legal;
  final Set<Point> atari;
  final Point? suggested;
  final bool hintsOn;
  final bool isMyTurn;
  final MoveAnimation? animation;
  final double progress;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final size = canvasSize.shortestSide;
    final margin = size * 0.06;
    final n = state.board.size;
    final usable = size - margin * 2;
    final cell = usable / (n - 1);

    Offset centerOf(Point p) {
      final x = flipped ? (n - 1 - p.x) : p.x;
      final y = flipped ? (n - 1 - p.y) : p.y;
      return Offset(margin + x * cell, margin + y * cell);
    }

    // Деревянная доска.
    final boardRect = Rect.fromLTWH(0, 0, size, size);
    canvas.drawRect(
      boardRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [woodLight, woodMid, woodDark],
        ).createShader(boardRect),
    );
    // Внутренняя рамка.
    canvas.drawRect(
      boardRect,
      Paint()
        ..color = woodLine.withValues(alpha: .25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.012,
    );

    // Линии сетки.
    final linePaint = Paint()
      ..color = woodLine
      ..strokeWidth = math.max(1.2, size * 0.004)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        Offset(margin + i * cell, margin),
        Offset(margin + i * cell, margin + (n - 1) * cell),
        linePaint,
      );
      canvas.drawLine(
        Offset(margin, margin + i * cell),
        Offset(margin + (n - 1) * cell, margin + i * cell),
        linePaint,
      );
    }

    // Звёздные точки (хоси).
    final starPaint = Paint()..color = woodLine;
    for (final p in state.board.starPoints()) {
      canvas.drawCircle(centerOf(p), size * 0.006, starPaint);
    }

    // Подсказки: допустимые ходы (мягкие точки) — только в мой ход.
    if (hintsOn && isMyTurn && animation == null) {
      final hintPaint = Paint()..color = purple.withValues(alpha: .25);
      for (final p in legal) {
        canvas.drawCircle(centerOf(p), cell * 0.12, hintPaint);
      }
    }

    // Сначала рисуем «затухающие» снятые камни (из предыдущего состояния).
    if (animation != null) {
      for (final p in animation!.captured) {
        final color = animation!.color.opponent;
        final opacity = (1 - progress).clamp(0.0, 1.0);
        final scale = 1 - progress * 0.5;
        _drawStone(canvas, centerOf(p), cell * 0.46 * scale, color, opacity);
      }
    }

    // Все стоящие камни.
    for (final entry in state.board.stones.entries) {
      final p = entry.key;
      final color = entry.value;
      // Камень, поставленный последним ходом — анимация появления.
      final isPlaced = animation != null &&
          animation!.point == p &&
          color == animation!.color;
      var scale = 1.0;
      var opacity = 1.0;
      if (isPlaced) {
        scale = 0.5 + 0.5 * Curves.easeOutBack.transform(progress);
        opacity = progress.clamp(0.0, 1.0);
      }
      _drawStone(canvas, centerOf(p), cell * 0.46 * scale, color, opacity);

      // Маркер последнего хода — кольцо на камне.
      if (state.lastMove?.point == p && !isPlaced) {
        final ringPaint = Paint()
          ..color = color == StoneColor.black
              ? Colors.white.withValues(alpha: .85)
              : ink.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size * 0.005);
        canvas.drawCircle(centerOf(p), cell * 0.18, ringPaint);
      }

      // Группы в атари — красное кольцо (подсказка под угрозой).
      if (hintsOn && atari.contains(p)) {
        final danger = Paint()
          ..color = const Color(0xFFE5484D).withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size * 0.006);
        canvas.drawCircle(centerOf(p), cell * 0.40, danger);
      }
    }

    // Запрещённая точка ко — маленький красный крестик.
    if (state.koPoint != null && hintsOn) {
      final c = centerOf(state.koPoint!);
      final crossPaint = Paint()
        ..color = const Color(0xFFE5484D).withValues(alpha: .6)
        ..strokeWidth = math.max(1.5, size * 0.006)
        ..strokeCap = StrokeCap.round;
      final r = cell * 0.18;
      canvas.drawLine(
        Offset(c.dx - r, c.dy - r),
        Offset(c.dx + r, c.dy + r),
        crossPaint,
      );
      canvas.drawLine(
        Offset(c.dx - r, c.dy + r),
        Offset(c.dx + r, c.dy - r),
        crossPaint,
      );
    }

    // Предложенный ход — зелёное кольцо.
    if (hintsOn && suggested != null) {
      final suggest = Paint()
        ..color = const Color(0xFF34C759).withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size * 0.007);
      canvas.drawCircle(centerOf(suggested!), cell * 0.42, suggest);
    }
  }

  void _drawStone(
    Canvas canvas,
    Offset center,
    double radius,
    StoneColor color, [
    double opacity = 1.0,
  ]) {
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Тень под камнем.
    canvas.drawCircle(
      Offset(center.dx, center.dy + radius * 0.12),
      radius * 0.96,
      Paint()
        ..color = ink.withValues(alpha: 0.28 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.18),
    );
    // Тело камня — радиальный градиент для объёма.
    final colors = color == StoneColor.black
        ? const [blackStoneLight, blackStoneDark]
        : const [whiteStoneLight, whiteStoneDark];
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.9,
          colors: colors.map((c) => c.withValues(alpha: opacity)).toList(),
        ).createShader(rect),
    );
    // Блик.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx - radius * 0.32,
          center.dy - radius * 0.38,
        ),
        width: radius * 0.55,
        height: radius * 0.34,
      ),
      Paint()
        ..color = Colors.white.withValues(
          alpha: (color == StoneColor.black ? 0.30 : 0.80) * opacity,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _GoBoardPainter old) =>
      old.state.fingerprint != state.fingerprint ||
      old.suggested != suggested ||
      old.hintsOn != hintsOn ||
      old.isMyTurn != isMyTurn ||
      old.animation != animation ||
      old.progress != progress ||
      old.flipped != flipped;
}

/// Объёмный камень го с бликом и тенью — для логотипа, заставки и иконок.
class StoneIcon extends StatelessWidget {
  const StoneIcon({
    super.key,
    this.dark = false,
    this.size = 48,
  });
  final bool dark;
  final double size;
  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: Offset(0, -size * .04),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.35, -.35),
              radius: .9,
              colors: dark
                  ? const [blackStoneLight, blackStoneDark]
                  : const [whiteStoneLight, whiteStoneDark],
            ),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: .28),
                blurRadius: size * .08,
                offset: Offset(0, size * .09),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(size * .14),
            child: Align(
              alignment: const Alignment(-.4, -.5),
              child: Container(
                width: size * .26,
                height: size * .18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * .13),
                  color: Colors.white.withValues(alpha: dark ? .35 : .85),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Маленькая доска го для логотипа/заставки — деревянная с линиями и точками.
class MiniGoBoard extends StatelessWidget {
  const MiniGoBoard({super.key, this.size = 120, this.rotate = -.12});
  final double size;
  final double rotate;
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: rotate,
        child: Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * .06),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [woodLight, woodMid],
            ),
            boxShadow: [
              BoxShadow(
                color: woodDark.withValues(alpha: .6),
                offset: Offset(0, size * .05),
              ),
              BoxShadow(
                color: ink.withValues(alpha: .18),
                blurRadius: size * .15,
                offset: Offset(0, size * .09),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _MiniGoBoardPainter(),
            child: const SizedBox.expand(),
          ),
        ),
      );
}

class _MiniGoBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final n = 5; // мини-сетка 5×5 для логотипа
    final cell = (size.width) / (n - 1);
    final line = Paint()
      ..color = woodLine
      ..strokeWidth = size.width * .018
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        Offset(i * cell, 0),
        Offset(i * cell, (n - 1) * cell),
        line,
      );
      canvas.drawLine(
        Offset(0, i * cell),
        Offset((n - 1) * cell, i * cell),
        line,
      );
    }
    // центральная звёздная точка
    canvas.drawCircle(
      Offset((n ~/ 2) * cell, (n ~/ 2) * cell),
      size.width * .025,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
