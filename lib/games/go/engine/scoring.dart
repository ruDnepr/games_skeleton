/// Подсчёт очков классического го — упрощённый японский (территориальный).
///
/// 1. Находим все группы на доске.
/// 2. Мёртвые камни — эвристика: группа с одним дыханием (в атари) или без
///    дыханий в конце партии считается мёртвой.
/// 3. Мёртвые камни снимаются, после чего пустые области заливаются:
///    область, граничащая только с одним цветом, — его территория;
///    граничащая с обоими — ничья (дамэ), не считается.
/// 4. Очки: чёрные = территория + пленники + мёртвые белые;
///    белые = территория + пленники + коми + мёртвые чёрные.
///
/// Файл зависит только от `model.dart` — никакой циклической зависимости с
/// правилами: правила зовут подсчёт, подсчёт правил не знает. Поэтому
/// небольшие помощники (`_groupAt`, `_allPoints`) дублированы здесь.
library;

import 'model.dart';

/// Сводка счёта классической партии.
class ScoreSummary {
  const ScoreSummary({
    required this.blackTerritory,
    required this.whiteTerritory,
    required this.blackCaptured,
    required this.whiteCaptured,
    required this.komi,
    required this.deadBlack,
    required this.deadWhite,
  });

  final int blackTerritory;
  final int whiteTerritory;
  final int blackCaptured; // пленные чёрных
  final int whiteCaptured; // пленные белых
  final double komi; // белым
  final int deadBlack; // мёртвые камни, добавленные к пленным белых
  final int deadWhite;

  double get blackScore =>
      blackTerritory + blackCaptured + deadWhite.toDouble();
  double get whiteScore =>
      whiteTerritory + whiteCaptured + komi + deadBlack.toDouble();

  double get difference => blackScore - whiteScore;

  StoneColor? get leader => difference.abs() < 0.01
      ? null
      : (difference > 0 ? StoneColor.black : StoneColor.white);
}

class TerritoryScorer {
  const TerritoryScorer._();

  static ScoreSummary score(
    Board board, {
    required int blackCaptured,
    required int whiteCaptured,
    required double komi,
  }) {
    // 1. Все группы и мёртвые.
    final deadBlack = <Point>{};
    final deadWhite = <Point>{};
    final visited = <Point>{};
    for (final p in _allPoints(board.size)) {
      if (visited.contains(p) || board.at(p) == null) continue;
      final group = _groupAt(board, p)!;
      visited.addAll(group.stones);
      // Эвристика мёртвых: в атари или без дыханий в конце партии.
      if (group.libertyCount <= 1) {
        final color = board.at(p)!;
        if (color == StoneColor.black) {
          deadBlack.addAll(group.stones);
        } else {
          deadWhite.addAll(group.stones);
        }
      }
    }

    // 2. Доска без мёртвых камней — для заливки территории.
    final live = deadBlack.isEmpty && deadWhite.isEmpty
        ? board
        : board.without({...deadBlack, ...deadWhite});

    // 3. Заливка пустых областей.
    final territoryBlack = <Point>{};
    final territoryWhite = <Point>{};
    final seen = <Point>{};
    for (final p in _allPoints(board.size)) {
      if (seen.contains(p) || live.at(p) != null) continue;
      final region = <Point>[];
      final borders = <StoneColor>{};
      final queue = <Point>[p];
      seen.add(p);
      while (queue.isNotEmpty) {
        final q = queue.removeLast();
        region.add(q);
        for (final n in q.neighbors()) {
          if (!n.inside(board.size)) continue;
          final c = live.at(n);
          if (c == null) {
            if (!seen.contains(n)) {
              seen.add(n);
              queue.add(n);
            }
          } else {
            borders.add(c);
          }
        }
      }
      if (borders.length == 1) {
        if (borders.first == StoneColor.black) {
          territoryBlack.addAll(region);
        } else {
          territoryWhite.addAll(region);
        }
      }
    }

    return ScoreSummary(
      blackTerritory: territoryBlack.length,
      whiteTerritory: territoryWhite.length,
      blackCaptured: blackCaptured,
      whiteCaptured: whiteCaptured,
      komi: komi,
      deadBlack: deadBlack.length,
      deadWhite: deadWhite.length,
    );
  }
}

// ---- приватные помощники (дубликат из rules.dart, чтобы не зацикливать импорт) ----

Group? _groupAt(Board board, Point start) {
  final color = board.at(start);
  if (color == null) return null;
  final stones = <Point>{};
  final liberties = <Point>{};
  final queue = <Point>[start];
  stones.add(start);
  while (queue.isNotEmpty) {
    final p = queue.removeLast();
    for (final n in p.neighbors()) {
      if (!n.inside(board.size)) continue;
      final neighborColor = board.at(n);
      if (neighborColor == null) {
        liberties.add(n);
      } else if (neighborColor == color && !stones.contains(n)) {
        stones.add(n);
        queue.add(n);
      }
    }
  }
  return Group(stones: stones, liberties: liberties);
}

List<Point> _allPoints(int size) {
  final result = <Point>[];
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      result.add(Point(x, y));
    }
  }
  return result;
}
