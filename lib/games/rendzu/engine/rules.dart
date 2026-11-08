/// Правила рэндзю/гомоку: анализ серий, запрещённые ходы, проверка победы.
///
/// Чистый Dart, без Flutter. Классы без состояния — каждый метод принимает
/// доску и возвращает результат, не меняя исходную позицию. Так один и тот же
/// код проверяет ход человека, ход ИИ и ход, пришедший по сети: расхождения
/// быть не может.
library;

import 'package:flutter/foundation.dart';

import 'model.dart';

/// Линия победы — пять (или более) камней одного цвета подряд.
@immutable
class WinLine {
  const WinLine(this.stones, this.color);

  final List<Point> stones;
  final StoneColor color;

  @override
  String toString() => 'Win($color, ${stones.length}: $stones)';
}

/// Результат проверки хода на победу.
@immutable
class WinResult {
  const WinResult({required this.winner, required this.line});

  final StoneColor winner;
  final WinLine line;

  @override
  String toString() => 'WinResult($winner, ${line.stones.length})';
}

/// Какой именно запрет сработал — нужно для детского пояснения.
enum ForbiddenKind { overline, doubleFour, doubleThree }

extension ForbiddenKindX on ForbiddenKind {
  String get russianName => switch (this) {
        ForbiddenKind.overline => 'Оверлайн (шесть и больше в ряд)',
        ForbiddenKind.doubleFour => 'Двойное четыре (4-4)',
        ForbiddenKind.doubleThree => 'Двойное три (3-3)',
      };

  /// Детское пояснение, почему ход нельзя сделать.
  String get kidExplanation => switch (this) {
        ForbiddenKind.overline =>
          'Этот ход нельзя сделать: получится шесть в ряд. '
              'Чёрные побеждают только ровно пятью камнями!',
        ForbiddenKind.doubleFour =>
          'Этот ход нельзя сделать: получится сразу два «четыре». '
              'Это запрещено для чёрных.',
        ForbiddenKind.doubleThree =>
          'Этот ход нельзя сделать: получится сразу два «три». '
              'Это запрещено для чёрных.',
      };
}

/// Анализатор паттернов: серии камней, четвёрки, открытые тройки, открытые
/// четвёрки. Все функции предполагают, что камень уже поставлен в точке [p].
///
/// Определения:
///  — «пять»: ровно 5 подряд одного цвета.
///  — «оверлайн»: 6 и более подряд.
///  — «четыре»: 4 камня, к которым можно добавить один и получить ровно пять
///    (хотя бы одним способом). Различные четвёрки — различные множества из 4
///    позиций (открытая четвёрка `_XXXX_` считается за одну).
///  — «открытая четвёрка» (`_XXXX_`): 4 подряд, с обеих сторон пусто.
///  — «открытое три»: 3 камня, к которым можно добавить один и получить
///    открытую четвёрку.
class PatternDetector {
  PatternDetector._();

  /// Длина максимальной непрерывной серии цвета `b.at(p)` через точку [p]
  /// вдоль оси [axis] (в обе стороны).
  static int runLengthThrough(Board b, Point p, Direction axis) {
    final color = b.at(p);
    if (color == null) return 0;
    var len = 1;
    var cur = p.step(axis);
    while (b.at(cur) == color) {
      len++;
      cur = cur.step(axis);
    }
    cur = p.step(axis.opposite);
    while (b.at(cur) == color) {
      len++;
      cur = cur.step(axis.opposite);
    }
    return len;
  }

  /// Границы непрерывной серии (start, end) цвета в [p] вдоль оси [axis].
  static (Point, Point) runBounds(Board b, Point p, Direction axis) {
    final color = b.at(p)!;
    var start = p;
    var end = p;
    var cur = p.step(axis);
    while (b.at(cur) == color) {
      end = cur;
      cur = cur.step(axis);
    }
    cur = p.step(axis.opposite);
    while (b.at(cur) == color) {
      start = cur;
      cur = cur.step(axis.opposite);
    }
    return (start, end);
  }

  /// Позиции непрерывной серии цвета в [p] вдоль оси [axis] (включая [p]).
  static List<Point> runPositions(Board b, Point p, Direction axis) {
    final color = b.at(p);
    if (color == null) return const [];
    final (start, end) = runBounds(b, p, axis);
    final out = <Point>[];
    var cur = start;
    out.add(cur);
    while (cur != end) {
      cur = cur.step(axis);
      out.add(cur);
    }
    return out;
  }

  /// Максимальная длина серии через [p] по всем осям.
  static int maxRunThrough(Board b, Point p) {
    var m = 0;
    for (final axis in Direction.axes) {
      final r = runLengthThrough(b, p, axis);
      if (r > m) m = r;
    }
    return m;
  }

  /// Есть ли ровно пять через [p] хотя бы по одной оси?
  static bool makesFive(Board b, Point p) {
    for (final axis in Direction.axes) {
      if (runLengthThrough(b, p, axis) == 5) return true;
    }
    return false;
  }

  /// Есть ли оверлайн (6+) через [p] хотя бы по одной оси?
  static bool makesOverline(Board b, Point p) {
    for (final axis in Direction.axes) {
      if (runLengthThrough(b, p, axis) >= 6) return true;
    }
    return false;
  }

  /// Является ли серия через [p] вдоль [axis] открытой четвёркой: ровно 4
  /// подряд, и обе соседние клетки пустые.
  static bool isOpenFourRun(Board b, Point p, Direction axis) {
    final color = b.at(p);
    if (color == null) return false;
    final len = runLengthThrough(b, p, axis);
    if (len != 4) return false;
    final (start, end) = runBounds(b, p, axis);
    final before = start.step(axis.opposite);
    final after = end.step(axis);
    final beforeEmpty = before.inBounds(b.size) && b.at(before) == null;
    final afterEmpty = after.inBounds(b.size) && b.at(after) == null;
    return beforeEmpty && afterEmpty;
  }

  /// Различные «четвёрки» через [p]: множества по 4 позиции того же цвета,
  /// которые можно дополнить одним камнем до ровно пяти. Дедуплицируются по
  /// ключу позиций, поэтому открытая четвёрка `_XXXX_` считается за одну.
  static List<List<Point>> fourPatternsThrough(Board b, Point p) {
    final color = b.at(p);
    if (color == null) return const [];
    final seen = <String>{};
    final fours = <List<Point>>[];
    for (final axis in Direction.axes) {
      for (var i = -4; i <= 4; i++) {
        if (i == 0) continue;
        final e = Point(p.x + axis.dx * i, p.y + axis.dy * i);
        if (!e.inBounds(b.size) || b.at(e) != null) continue;
        b.place(e, color);
        final run = runLengthThrough(b, p, axis);
        if (run == 5) {
          final positions = runPositions(b, p, axis);
          final four = positions.where((q) => q != e).toList()
            ..sort((a, b2) => a.compareTo(b2));
          final key = four.map((q) => '${q.x},${q.y}').join('|');
          if (seen.add(key)) fours.add(four);
        }
        b.remove(e);
      }
    }
    return fours;
  }

  /// Различные «открытые тройки» через [p]: множества по 3 позиции того же
  /// цвета, которые можно дополнить одним камнем до открытой четвёрки.
  static List<List<Point>> openThreePatternsThrough(Board b, Point p) {
    final color = b.at(p);
    if (color == null) return const [];
    final seen = <String>{};
    final threes = <List<Point>>[];
    for (final axis in Direction.axes) {
      for (var i = -4; i <= 4; i++) {
        if (i == 0) continue;
        final e = Point(p.x + axis.dx * i, p.y + axis.dy * i);
        if (!e.inBounds(b.size) || b.at(e) != null) continue;
        b.place(e, color);
        if (isOpenFourRun(b, p, axis)) {
          final four = runPositions(b, p, axis);
          final three = four.where((q) => q != e).toList()
            ..sort((a, b2) => a.compareTo(b2));
          final key = three.map((q) => '${q.x},${q.y}').join('|');
          if (seen.add(key)) threes.add(three);
        }
        b.remove(e);
      }
    }
    return threes;
  }
}

/// Проверщик запрещённых ходов для чёрных в рэндзю.
///
/// Правила (только для чёрных):
///   1. Ход, создающий ровно пять, — это победа (исключение, не запрещено),
///      даже если одновременно создаётся оверлайн или другие запреты.
///   2. Оверлайн: ход создаёт 6+ подряд — запрещён.
///   3. Двойное четыре (4-4): ход создаёт две и более четвёрки — запрещён.
///   4. Двойное три (3-3): ход создаёт два и более открытых тройки — запрещён.
///
/// Все проверки выполняются на доске, где камень уже поставлен в точку [p].
/// Цвет камня — чёрный (проверка имеет смысл только для чёрных).
class RenjuForbiddenChecker {
  RenjuForbiddenChecker._();

  /// Проверяет, является ли ход чёрных в точку [p] (камень уже стоит на [b])
  /// запрещённым. Возвращает [ForbiddenKind] или `null`, если ход разрешён.
  ///
  /// Порядок проверки соответствует приоритету правил:
  /// пять → оверлайн → двойное-четыре → двойное-три.
  static ForbiddenKind? check(Board b, Point p) {
    // 1. Пять — победа, не запрещено (исключение).
    if (PatternDetector.makesFive(b, p)) {
      return null;
    }
    // 2. Оверлайн (6+).
    if (PatternDetector.makesOverline(b, p)) {
      return ForbiddenKind.overline;
    }
    // 3. Двойное четыре.
    final fours = PatternDetector.fourPatternsThrough(b, p);
    if (fours.length >= 2) {
      return ForbiddenKind.doubleFour;
    }
    // 4. Двойное три.
    final threes = PatternDetector.openThreePatternsThrough(b, p);
    if (threes.length >= 2) {
      return ForbiddenKind.doubleThree;
    }
    return null;
  }

  /// Проверяет запрещённость хода «в точку [p]» относительно доски БЕЗ камня в
  /// [p]. Ставит чёрный камень во временную копию и вызывает [check].
  static ForbiddenKind? checkCandidate(Board board, Point p) {
    if (!p.inBounds(board.size) || board.at(p) != null) return null;
    final copy = board.copy();
    copy.place(p, StoneColor.black);
    return check(copy, p);
  }

  /// Множество точек, где ход чёрных был бы запрещён. Используется для подсказок
  /// и предупреждений. Рассматриваем только пустые поля рядом с уже стоящими
  /// камнями (радиус 2), чтобы не сканировать всю доску.
  static Set<Point> forbiddenMoves(Board board) {
    final result = <Point>{};
    final candidates = <Point>{};
    for (final stone in board.occupiedPoints()) {
      for (var dx = -2; dx <= 2; dx++) {
        for (var dy = -2; dy <= 2; dy++) {
          final pt = Point(stone.x + dx, stone.y + dy);
          if (pt.inBounds(board.size) && board.at(pt) == null) {
            candidates.add(pt);
          }
        }
      }
    }
    for (final c in candidates) {
      final f = checkCandidate(board, c);
      if (f != null) result.add(c);
    }
    return result;
  }
}

/// Интерфейс набора правил: что является победой, ничьей и (для рэндзю)
/// запрещённым ходом. Реализации — [GomokuRules] и [RenjuRules].
abstract class GameRules {
  const GameRules();

  Ruleset get ruleset;

  /// Проверить победу после хода в [p] (камень уже стоит). Возвращает линию
  /// победы или `null`.
  WinResult? checkWin(Board board, Point p);

  /// Проверить, является ли ход в [p] (камень цвета [color] ещё не поставлен)
  /// запрещённым. Для гомоку всегда `null`. Для рэндзю — только для чёрных.
  ForbiddenKind? forbiddenIfPlaced(Board board, Point p, StoneColor color);

  /// Список запрещённых точек для цвета [color] на текущей доске (для подсказок).
  Set<Point> forbiddenMoves(Board board, StoneColor color);

  /// Ничья — доска заполнена и никто не победил.
  bool isDraw(Board board) => board.isFull;

  /// Короткое имя правил.
  String get displayName;
}

/// Гомоку: свободное пять в ряд. Победа — 5 и более подряд. Запретов нет.
class GomokuRules extends GameRules {
  const GomokuRules();

  @override
  Ruleset get ruleset => Ruleset.gomoku;

  @override
  String get displayName => 'Гомоку';

  @override
  WinResult? checkWin(Board board, Point p) {
    final color = board.at(p);
    if (color == null) return null;
    for (final axis in Direction.axes) {
      final run = PatternDetector.runLengthThrough(board, p, axis);
      if (run >= 5) {
        final stones = PatternDetector.runPositions(board, p, axis);
        return WinResult(winner: color, line: WinLine(stones, color));
      }
    }
    return null;
  }

  @override
  ForbiddenKind? forbiddenIfPlaced(Board board, Point p, StoneColor color) {
    return null;
  }

  @override
  Set<Point> forbiddenMoves(Board board, StoneColor color) => {};
}

/// Рэндзю: чёрные имеют запрещённые ходы. Победа чёрных — только ровно пять;
/// победа белых — пять и более.
class RenjuRules extends GameRules {
  const RenjuRules();

  @override
  Ruleset get ruleset => Ruleset.renju;

  @override
  String get displayName => 'Рэндзю';

  @override
  WinResult? checkWin(Board board, Point p) {
    final color = board.at(p);
    if (color == null) return null;
    for (final axis in Direction.axes) {
      final run = PatternDetector.runLengthThrough(board, p, axis);
      if (color == StoneColor.black) {
        // Чёрные побеждают только ровно пятью.
        if (run == 5) {
          final stones = PatternDetector.runPositions(board, p, axis);
          return WinResult(
            winner: StoneColor.black,
            line: WinLine(stones, StoneColor.black),
          );
        }
        // run >= 6 — оверлайн, НЕ победа для чёрных (запрещено, см. forbidden).
      } else {
        // Белые побеждают пятью и более.
        if (run >= 5) {
          final stones = PatternDetector.runPositions(board, p, axis);
          return WinResult(
            winner: StoneColor.white,
            line: WinLine(stones, StoneColor.white),
          );
        }
      }
    }
    return null;
  }

  @override
  ForbiddenKind? forbiddenIfPlaced(Board board, Point p, StoneColor color) {
    if (color != StoneColor.black) return null;
    return RenjuForbiddenChecker.checkCandidate(board, p);
  }

  @override
  Set<Point> forbiddenMoves(Board board, StoneColor color) {
    if (color != StoneColor.black) return {};
    return RenjuForbiddenChecker.forbiddenMoves(board);
  }
}

/// Фабрика правил по набору.
GameRules rulesFor(Ruleset ruleset) {
  switch (ruleset) {
    case Ruleset.gomoku:
      return const GomokuRules();
    case Ruleset.renju:
      return const RenjuRules();
  }
}
