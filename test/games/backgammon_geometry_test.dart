import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/ui/board_geometry.dart';

/// Геометрия доски: пункты, бар и вынос попадают в правильные места при тапе.
/// Чистый Dart — без Flame и без виджетов.
void main() {
  final geo = BoardGeometry(const Size(400, 500));

  test('верх/низ распределены по индексам', () {
    expect(geo.isTop(0), isFalse);
    expect(geo.isTop(11), isFalse);
    expect(geo.isTop(12), isTrue);
    expect(geo.isTop(23), isTrue);
  });

  test('пункт 0 — крайний справа внизу, пункт 5 — у бара', () {
    expect(geo.pointCenterX(0), greaterThan(geo.pointCenterX(5)));
    // Пункт 5 (дом белых, у бара) левее пункта 0 (крайний справа).
    expect(geo.isTop(0), isFalse);
  });

  test('тап в центр пункта попадает в этот пункт', () {
    final center = Offset(geo.pointCenterX(3), geo.baseY(3) - 30);
    final hit = geo.hitTest(center);
    expect(hit.isPoint, isTrue);
    expect(hit.point, 3);
  });

  test('тап по бару попадает в бар', () {
    final hit = geo.hitTest(geo.barRect(false).center);
    expect(hit.isBar, isTrue);
  });

  test('тап по зоне выноса попадает в вынос', () {
    final whiteOff = geo.offRect(true).center;
    expect(geo.hitTest(whiteOff).isOff, isTrue);
    final blackOff = geo.offRect(false).center;
    expect(geo.hitTest(blackOff).isOff, isTrue);
  });

  test('все 24 пункта достижимы тапом по их прямоугольнику', () {
    for (var i = 0; i < 24; i++) {
      final rect = geo.pointRect(i);
      final hit = geo.hitTest(rect.center);
      expect(hit.isPoint, isTrue, reason: 'пункт $i');
      expect(hit.point, i, reason: 'пункт $i');
    }
  });
}
