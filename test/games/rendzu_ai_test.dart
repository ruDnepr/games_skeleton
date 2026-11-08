import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/rendzu/engine/ai.dart';
import 'package:games_for_diana/games/rendzu/engine/model.dart';
import 'package:games_for_diana/games/rendzu/engine/rules.dart';

Board _board(int size, List<Point> black, [List<Point> white = const []]) {
  final b = Board(size);
  for (final p in black) {
    b.place(p, StoneColor.black);
  }
  for (final p in white) {
    b.place(p, StoneColor.white);
  }
  return b;
}

void main() {
  group('RenjuAI — общий', () {
    test('пустая доска → ход в центр', () {
      final b = Board(9);
      final m = RenjuAI.findBestMove(
        b,
        StoneColor.black,
        Difficulty.easy,
        ruleset: Ruleset.gomoku,
      );
      expect(m, isNotNull);
      expect(m, const Point(4, 4));
    });

    test('возвращает ход рядом с камнями', () {
      final b = _board(9, [const Point(4, 4)]);
      final m = RenjuAI.findBestMove(
        b,
        StoneColor.white,
        Difficulty.easy,
        ruleset: Ruleset.gomoku,
      );
      expect(m, isNotNull);
      expect((m!.x - 4).abs() + (m.y - 4).abs(), lessThanOrEqualTo(2));
    });
  });

  group('RenjuAI — немедленная победа', () {
    test('ИИ завершает пять, если может', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
      ]);
      for (final level in Difficulty.values) {
        final m = RenjuAI.findBestMove(
          b,
          StoneColor.black,
          level,
          ruleset: Ruleset.gomoku,
        );
        expect(
          m,
          const Point(4, 0),
          reason: 'Уровень $level должен завершать пять',
        );
      }
    });
  });

  group('RenjuAI — блокировка', () {
    test('ИИ блокирует победный ход соперника (4 в ряд)', () {
      final b = _board(9, const [], [
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      final m = RenjuAI.findBestMove(
        b,
        StoneColor.black,
        Difficulty.hard,
        ruleset: Ruleset.gomoku,
      );
      expect(m, isNotNull);
      expect(
        m,
        anyOf(equals(const Point(1, 0)), equals(const Point(6, 0))),
      );
    });

    test('средний уровень блокирует 4 в ряд', () {
      final b = _board(9, const [], [
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      final m = RenjuAI.findBestMove(
        b,
        StoneColor.black,
        Difficulty.medium,
        ruleset: Ruleset.gomoku,
      );
      expect(
        m,
        anyOf(equals(const Point(1, 0)), equals(const Point(6, 0))),
      );
    });
  });

  group('RenjuAI — запрещённые ходы', () {
    test('ИИ (чёрные, рэндзю) не делает запрещённый ход', () {
      final b = _board(
        15,
        [
          const Point(5, 7),
          const Point(6, 7),
          const Point(7, 5),
          const Point(7, 6),
        ],
        const [],
      );
      b.place(const Point(0, 0), StoneColor.white);
      for (final level in Difficulty.values) {
        final m = RenjuAI.findBestMove(
          b,
          StoneColor.black,
          level,
          ruleset: Ruleset.renju,
        );
        expect(m, isNotNull);
        final copy = b.copy();
        copy.place(m!, StoneColor.black);
        final forbidden = RenjuForbiddenChecker.check(copy, m);
        expect(
          forbidden,
          isNull,
          reason: 'Уровень $level: ИИ не должен делать запрещённый ход $m',
        );
      }
    });

    test('ИИ избегает оверлайна', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(5, 0),
      ]);
      b.place(const Point(7, 7), StoneColor.white);
      for (final level in Difficulty.values) {
        final m = RenjuAI.findBestMove(
          b,
          StoneColor.black,
          level,
          ruleset: Ruleset.renju,
        );
        expect(m, isNotNull);
        expect(
          m,
          isNot(const Point(4, 0)),
          reason: 'Уровень $level не должен делать оверлайн',
        );
      }
    });
  });

  group('RenjuAI — уровни различаются', () {
    test('лёгкий и сложный уровни возвращают ход', () {
      final b = _board(9, const [], [
        const Point(4, 3),
        const Point(4, 4),
        const Point(3, 4),
        const Point(5, 4),
      ]);
      final easyMove = RenjuAI.findBestMove(
        b,
        StoneColor.black,
        Difficulty.easy,
        ruleset: Ruleset.gomoku,
      );
      final hardMove = RenjuAI.findBestMove(
        b,
        StoneColor.black,
        Difficulty.hard,
        ruleset: Ruleset.gomoku,
      );
      expect(easyMove, isNotNull);
      expect(hardMove, isNotNull);
    });
  });
}
