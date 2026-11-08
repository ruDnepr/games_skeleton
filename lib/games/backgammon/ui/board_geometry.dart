import 'dart:ui';

/// Геометрия нардовой доски: координаты пунктов, шашек, бара и выноса.
///
/// Чистые расчёты по размеру холста — без состояния, без Flame. Так Flame и
/// тесты используют одни и те же числа, а раскладку можно проверить без
/// устройства.
///
/// Нумерация пунктов совпадает с моделью: 0..5 — дом белых (низ-справа),
/// 6..11 —.outer белых (низ-слева), 12..17 — outer чёрных (верх-слева),
/// 18..23 — дом чёрных (верх-справа). Белые идут к 0, чёрные к 23.
class BoardGeometry {
  BoardGeometry(this.size);

  final Size size;

  late final double frame = size.width * 0.022;
  late final double barWidth = size.width * 0.07;
  late final double trayWidth = size.width * 0.05;
  late final double halfWidth = (size.width - 2 * frame - barWidth - trayWidth) / 2;
  late final double pointWidth = halfWidth / 6;
  late final double middleGap = size.height * 0.05;

  late final double leftStart = frame;
  late final double rightStart = frame + halfWidth + barWidth;
  late final double barCenterX = frame + halfWidth + barWidth / 2;

  bool isTop(int index) => index >= 12;

  double pointCenterX(int index) {
    final col = _column(index);
    final startX = (index < 6 || index >= 18) ? rightStart : leftStart;
    return startX + col * pointWidth + pointWidth / 2;
  }

  /// Колонка 0..5 внутри своей половины (слева направо).
  int _column(int index) {
    if (index <= 5) return 5 - index; // 0 — крайний справа, 5 — у бара
    if (index <= 11) return 11 - index; // 6 — у бара, 11 — крайний слева
    if (index <= 17) return index - 12; // 12 — крайний слева, 17 — у бара
    return index - 18; // 18 — у бара, 23 — крайний справа
  }

  double baseY(int index) => isTop(index) ? frame : size.height - frame;
  double apexY(int index) =>
      isTop(index) ? size.height / 2 - middleGap : size.height / 2 + middleGap;

  late final double checkerRadius = pointWidth * 0.42;

  /// Центр k-й шашки в стеке пункта (0 — у края доски).
  Offset checkerAt(int index, int stackIndex) {
    final x = pointCenterX(index);
    final base = baseY(index);
    final dir = isTop(index) ? 1.0 : -1.0;
    final spacing = checkerRadius * 1.86;
    return Offset(x, base + dir * (checkerRadius + stackIndex * spacing));
  }

  /// Прямоугольник для тапа по пункту.
  Rect pointRect(int index) {
    final x = pointCenterX(index);
    final base = baseY(index);
    final apex = apexY(index);
    final top = base < apex ? base : apex;
    final bottom = base < apex ? apex : base;
    return Rect.fromLTWH(
      x - pointWidth / 2,
      top,
      pointWidth,
      bottom - top,
    );
  }

  /// Прямоугольник бара для цвета (куда ставятся выбитые шашки).
  Rect barRect(bool isWhite) {
    final top = isWhite ? size.height / 2 + middleGap * 0.4 : frame;
    final h = size.height / 2 - middleGap * 1.4;
    return Rect.fromLTWH(barCenterX - barWidth / 2, top, barWidth, h);
  }

  Offset barCheckerAt(bool isWhite, int stackIndex) {
    final rect = barRect(isWhite);
    final dir = isWhite ? -1.0 : 1.0;
    final start = isWhite ? rect.bottom : rect.top;
    return Offset(
      rect.center.dx,
      start + dir * (checkerRadius + stackIndex * checkerRadius * 1.86),
    );
  }

  /// Прямоугольник зоны выноса для цвета (тэй справа у своего дома).
  Rect offRect(bool isWhite) {
    final x = size.width - trayWidth;
    final top = isWhite ? size.height / 2 + middleGap * 0.4 : frame;
    final h = size.height / 2 - middleGap * 1.4;
    return Rect.fromLTWH(x, top, trayWidth, h);
  }

  /// Куда попасть тапом: индекс пункта 0..23, 'bar', 'off' или null.
  HitTarget hitTest(Offset pos) {
    for (var i = 0; i < 24; i++) {
      if (pointRect(i).contains(pos)) return HitTarget.point(i);
    }
    if (barRect(true).contains(pos)) return const HitTarget.bar();
    if (barRect(false).contains(pos)) return const HitTarget.bar();
    if (offRect(true).contains(pos)) return const HitTarget.off();
    if (offRect(false).contains(pos)) return const HitTarget.off();
    return const HitTarget.none();
  }
}

/// Куда попал тап на доске.
class HitTarget {
  const HitTarget.point(this.point)
      : kind = 'point',
        isWhiteBar = false;
  const HitTarget.bar()
      : kind = 'bar',
        point = null,
        isWhiteBar = false;
  const HitTarget.off()
      : kind = 'off',
        point = null,
        isWhiteBar = false;
  const HitTarget.none()
      : kind = 'none',
        point = null,
        isWhiteBar = false;

  final String kind; // 'point', 'bar', 'off', 'none'
  final int? point;
  final bool isWhiteBar;

  bool get isPoint => kind == 'point';
  bool get isBar => kind == 'bar';
  bool get isOff => kind == 'off';
  bool get isNone => kind == 'none';
}
