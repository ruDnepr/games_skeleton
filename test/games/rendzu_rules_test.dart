import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/rendzu/engine/model.dart';
import 'package:games_for_diana/games/rendzu/engine/rules.dart';

/// Вспомогательная функция: ставим чёрные камни в перечисленные точки.
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
  group('PatternDetector.runLengthThrough', () {
    test('одиночный камень — длина 1', () {
      final b = _board(9, [const Point(4, 4)]);
      expect(
        PatternDetector.runLengthThrough(b, const Point(4, 4), Direction(1, 0)),
        1,
      );
    });

    test('горизонтальная серия из 5', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      expect(
        PatternDetector.runLengthThrough(b, const Point(2, 0), Direction(1, 0)),
        5,
      );
    });

    test('вертикальная серия из 3', () {
      final b = _board(9, [
        const Point(0, 1),
        const Point(0, 2),
        const Point(0, 3),
      ]);
      expect(
        PatternDetector.runLengthThrough(b, const Point(0, 2), Direction(0, 1)),
        3,
      );
    });

    test('диагональная серия из 4', () {
      final b = _board(9, [
        const Point(1, 1),
        const Point(2, 2),
        const Point(3, 3),
        const Point(4, 4),
      ]);
      expect(
        PatternDetector.runLengthThrough(b, const Point(2, 2), Direction(1, 1)),
        4,
      );
    });

    test('прерывается чужим камнем', () {
      final b = _board(
        9,
        [
          const Point(0, 0),
          const Point(1, 0),
          const Point(2, 0),
        ],
        [const Point(3, 0)],
      );
      expect(
        PatternDetector.runLengthThrough(b, const Point(1, 0), Direction(1, 0)),
        3,
      );
    });
  });

  group('PatternDetector.makesFive / makesOverline', () {
    test('makesFive истинно для 5', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      expect(PatternDetector.makesFive(b, const Point(2, 0)), isTrue);
      expect(PatternDetector.makesOverline(b, const Point(2, 0)), isFalse);
    });

    test('makesOverline истинно для 6', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      expect(PatternDetector.makesFive(b, const Point(2, 0)), isFalse);
      expect(PatternDetector.makesOverline(b, const Point(2, 0)), isTrue);
    });
  });

  group('PatternDetector.fourPatternsThrough', () {
    test('простая четвёрка — 1 четыре', () {
      final b = _board(
        9,
        [
          const Point(1, 0),
          const Point(2, 0),
          const Point(3, 0),
          const Point(4, 0),
        ],
        [const Point(5, 0)],
      );
      final fours = PatternDetector.fourPatternsThrough(b, const Point(2, 0));
      expect(fours.length, 1);
    });

    test('открытая четвёрка _XXXX_ — 1 четыре (не 2)', () {
      final b = _board(9, [
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      final fours = PatternDetector.fourPatternsThrough(b, const Point(2, 0));
      expect(fours.length, 1);
    });

    test('разбитое двойное-четыре на одной линии — 2 четвёрки', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(6, 0),
      ]);
      final fours = PatternDetector.fourPatternsThrough(b, const Point(3, 0));
      expect(fours.length, 2);
    });
  });

  group('PatternDetector.openThreePatternsThrough', () {
    test('открытая тройка _XXX_ — есть', () {
      final b = _board(9, [
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      final threes =
          PatternDetector.openThreePatternsThrough(b, const Point(4, 0));
      expect(threes.length, 1);
    });

    test('закрытая тройка OXXX_ — нет открытой тройки', () {
      final b = _board(
        9,
        [
          const Point(3, 0),
          const Point(4, 0),
          const Point(5, 0),
        ],
        [const Point(2, 0)],
      );
      final threes =
          PatternDetector.openThreePatternsThrough(b, const Point(4, 0));
      expect(threes, isEmpty);
    });
  });

  group('PatternDetector.isOpenFourRun', () {
    test('_XXXX_ — открытая четвёрка', () {
      final b = _board(9, [
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      expect(
        PatternDetector.isOpenFourRun(b, const Point(2, 0), Direction(1, 0)),
        isTrue,
      );
    });

    test('OXXXX_ — закрытая четвёрка (не открытая)', () {
      final b = _board(
        9,
        [
          const Point(1, 0),
          const Point(2, 0),
          const Point(3, 0),
          const Point(4, 0),
        ],
        [const Point(0, 0)],
      );
      expect(
        PatternDetector.isOpenFourRun(b, const Point(2, 0), Direction(1, 0)),
        isFalse,
      );
    });
  });

  group('RenjuForbiddenChecker — оверлайн', () {
    test('ход, создающий 6 в ряд — оверлайн', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(5, 0),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(4, 0));
      expect(f, ForbiddenKind.overline);
    });

    test('ход, создающий 7 в ряд — оверлайн', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(5, 0),
        const Point(6, 0),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(4, 0));
      expect(f, ForbiddenKind.overline);
    });
  });

  group('RenjuForbiddenChecker — двойное три (3-3)', () {
    test('ход создаёт два открытых три — 3-3', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(7, 5),
        const Point(7, 6),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, ForbiddenKind.doubleThree);
    });

    test('одно открытое три — не запрещено', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, isNull);
    });
  });

  group('RenjuForbiddenChecker — двойное четыре (4-4)', () {
    test('ход создаёт две четвёрки — 4-4', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(8, 7),
        const Point(7, 5),
        const Point(7, 6),
        const Point(7, 8),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, ForbiddenKind.doubleFour);
    });

    test('одна четвёрка — не запрещено', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(8, 7),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, isNull);
    });
  });

  group('RenjuForbiddenChecker — исключение (пять перекрывает запрет)', () {
    test('ход создаёт ровно пять И оверлайн — победа, не запрещено', () {
      final b = _board(15, [
        const Point(7, 3),
        const Point(7, 4),
        const Point(7, 5),
        const Point(7, 6),
        const Point(3, 3),
        const Point(4, 4),
        const Point(5, 5),
        const Point(6, 6),
        const Point(8, 8),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, isNull, reason: 'Пять перекрывает оверлайн — это победа');
    });

    test('ход создаёт пять И двойное-три — победа, не запрещено', () {
      final b = _board(15, [
        const Point(7, 3),
        const Point(7, 4),
        const Point(7, 5),
        const Point(7, 6),
        const Point(5, 7),
        const Point(6, 7),
        const Point(5, 9),
        const Point(6, 8),
      ]);
      final f = RenjuForbiddenChecker.checkCandidate(b, const Point(7, 7));
      expect(f, isNull, reason: 'Пять перекрывает двойное-три — победа');
    });
  });

  group('RenjuForbiddenChecker.forbiddenMoves', () {
    test('возвращает пустое множество на пустой доске', () {
      final b = Board(9);
      expect(RenjuForbiddenChecker.forbiddenMoves(b), isEmpty);
    });

    test('находит запрещённый ход рядом с камнями', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(7, 5),
        const Point(7, 6),
      ]);
      final moves = RenjuForbiddenChecker.forbiddenMoves(b);
      expect(moves, contains(const Point(7, 7)));
    });
  });

  group('GomokuRules', () {
    final rules = const GomokuRules();

    test('победа ровно 5', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      final win = rules.checkWin(b, const Point(4, 0));
      expect(win, isNotNull);
      expect(win!.winner, StoneColor.black);
      expect(win.line.stones.length, 5);
    });

    test('победа 6+ (оверлайн = победа в гомоку)', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      final win = rules.checkWin(b, const Point(5, 0));
      expect(win, isNotNull);
      expect(win!.winner, StoneColor.black);
    });

    test('нет победы при 4', () {
      final b = _board(9, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
      ]);
      expect(rules.checkWin(b, const Point(3, 0)), isNull);
    });

    test('нет запрещённых ходов', () {
      final b = _board(9, [const Point(4, 4)]);
      expect(
        rules.forbiddenIfPlaced(b, const Point(5, 5), StoneColor.black),
        isNull,
      );
      expect(
        rules.forbiddenIfPlaced(b, const Point(5, 5), StoneColor.white),
        isNull,
      );
      expect(rules.forbiddenMoves(b, StoneColor.black), isEmpty);
    });

    test('ничья при заполненной доске', () {
      final b = Board(3);
      b.place(const Point(0, 0), StoneColor.black);
      b.place(const Point(1, 0), StoneColor.white);
      b.place(const Point(2, 0), StoneColor.black);
      b.place(const Point(0, 1), StoneColor.white);
      b.place(const Point(1, 1), StoneColor.black);
      b.place(const Point(2, 1), StoneColor.white);
      b.place(const Point(0, 2), StoneColor.black);
      b.place(const Point(1, 2), StoneColor.white);
      b.place(const Point(2, 2), StoneColor.black);
      expect(rules.isDraw(b), isTrue);
    });
  });

  group('RenjuRules — чёрные', () {
    final rules = const RenjuRules();

    test('победа чёрных только ровно 5', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]);
      final win = rules.checkWin(b, const Point(4, 0));
      expect(win, isNotNull);
      expect(win!.winner, StoneColor.black);
    });

    test('оверлайн НЕ победа для чёрных', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]);
      final win = rules.checkWin(b, const Point(5, 0));
      expect(win, isNull, reason: 'Оверлайн не победа для чёрных в рэндзю');
    });

    test('запрещённый ход 3-3', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(7, 5),
        const Point(7, 6),
      ]);
      expect(
        rules.forbiddenIfPlaced(b, const Point(7, 7), StoneColor.black),
        ForbiddenKind.doubleThree,
      );
    });

    test('запрещённый ход 4-4', () {
      final b = _board(15, [
        const Point(5, 7),
        const Point(6, 7),
        const Point(8, 7),
        const Point(7, 5),
        const Point(7, 6),
        const Point(7, 8),
      ]);
      expect(
        rules.forbiddenIfPlaced(b, const Point(7, 7), StoneColor.black),
        ForbiddenKind.doubleFour,
      );
    });

    test('запрещённый ход — оверлайн', () {
      final b = _board(15, [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(5, 0),
      ]);
      expect(
        rules.forbiddenIfPlaced(b, const Point(4, 0), StoneColor.black),
        ForbiddenKind.overline,
      );
    });
  });

  group('RenjuRules — белые', () {
    final rules = const RenjuRules();

    test('победа белых 5', () {
      final bw = Board(15);
      for (final p in [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
      ]) {
        bw.place(p, StoneColor.white);
      }
      final win = rules.checkWin(bw, const Point(4, 0));
      expect(win, isNotNull);
      expect(win!.winner, StoneColor.white);
    });

    test('победа белых 6+ (оверлайн = победа для белых)', () {
      final bw = Board(15);
      for (final p in [
        const Point(0, 0),
        const Point(1, 0),
        const Point(2, 0),
        const Point(3, 0),
        const Point(4, 0),
        const Point(5, 0),
      ]) {
        bw.place(p, StoneColor.white);
      }
      final win = rules.checkWin(bw, const Point(5, 0));
      expect(win, isNotNull);
      expect(win!.winner, StoneColor.white);
    });

    test('белые не имеют запрещённых ходов', () {
      final bw = Board(15);
      bw.place(const Point(0, 0), StoneColor.white);
      bw.place(const Point(1, 0), StoneColor.white);
      bw.place(const Point(2, 0), StoneColor.white);
      bw.place(const Point(3, 0), StoneColor.white);
      bw.place(const Point(5, 0), StoneColor.white);
      expect(
        rules.forbiddenIfPlaced(bw, const Point(4, 0), StoneColor.white),
        isNull,
      );
      expect(rules.forbiddenMoves(bw, StoneColor.white), isEmpty);
    });
  });

  group('rulesFor', () {
    test('gomoku → GomokuRules', () {
      expect(rulesFor(Ruleset.gomoku).runtimeType.toString(), 'GomokuRules');
    });
    test('renju → RenjuRules', () {
      expect(rulesFor(Ruleset.renju).runtimeType.toString(), 'RenjuRules');
    });
  });
}
