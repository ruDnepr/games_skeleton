/// Алгоритм выбора выстрела для компьютера.
///
/// Работает только с тем, что видно стреляющему: свои выстрелы и их результаты.
/// Корабли соперника не видит — это честный ИИ, а не читер. На любом уровне
/// после попадания ИИ добивает раненый корабль (стреляет по соседним клеткам).
/// Уровни отличаются только фазой поиска нового корабля.
library;

import 'dart:math';

import 'model.dart';

/// Уровень сложности компьютера.
enum Difficulty {
  /// Стреляет случайно по необстрелянным клеткам.
  easy,

  /// После попадания добивает корабль по соседним клеткам; в фазе поиска
  /// стреляет «шахматным» паттерном.
  medium,

  /// Вероятностная стратегия: учитывает возможное расположение кораблей и
  /// целенаправленно добивает.
  hard,
}

extension DifficultyX on Difficulty {
  String get russianName => switch (this) {
        Difficulty.easy => 'Лёгкий',
        Difficulty.medium => 'Средний',
        Difficulty.hard => 'Сложный',
      };

  String get russianSubtitle => switch (this) {
        Difficulty.easy => 'Компьютер стреляет наугад',
        Difficulty.medium => 'После попадания добивает корабль',
        Difficulty.hard => 'Думает о вероятностях',
      };

  /// Иконка для выбора уровня — улыбка по нарастающей сложности.
  String get iconHint => switch (this) {
        Difficulty.easy => 'easy',
        Difficulty.medium => 'medium',
        Difficulty.hard => 'hard',
      };
}

/// Ось для линейных проверок: линия попаданий по горизонтали или вертикали.
enum LineAxis { horizontal, vertical }

class BattleshipAI {
  const BattleshipAI(this.level);

  final Difficulty level;

  /// Куда стрелять в данный момент. [enemy] — поле соперника с точки зрения ИИ:
  /// его собственные выстрелы и результаты.
  Square chooseShot(EnemyBoard enemy, [Random? rng]) {
    final random = rng ?? Random();
    final unfired = enemy.unfired;
    if (unfired.isEmpty) {
      // Невероятно при правильной игре, но защитить стоит.
      return allSquares().first;
    }
    // Сначала — добивание раненого корабля (для всех уровней).
    final targets = _targetCandidates(enemy);
    if (targets.isNotEmpty) {
      return targets[random.nextInt(targets.length)];
    }
    // Фаза поиска нового корабля — отличие по уровню.
    switch (level) {
      case Difficulty.easy:
        return _randomUnfired(unfired, random);
      case Difficulty.medium:
        return _checkerboardOrRandom(unfired, random);
      case Difficulty.hard:
        final prob = _probabilisticChoice(enemy, unfired, random);
        return prob ?? _randomUnfired(unfired, random);
    }
  }

  Square _randomUnfired(Set<Square> unfired, Random random) {
    final list = unfired.toList();
    return list[random.nextInt(list.length)];
  }

  /// «Шахматный» поиск: стреляем по клеткам одного цвета в паттерне 2×2,
  /// чтобы не пропустить ни один двухпалубный. Остаток — случайно.
  Square _checkerboardOrRandom(Set<Square> unfired, Random random) {
    final checkerboard =
        unfired.where((s) => (s.row + s.col) % 2 == 0).toList();
    final pool = checkerboard.isEmpty ? unfired.toList() : checkerboard;
    return pool[random.nextInt(pool.length)];
  }

  /// Клетки-кандидаты для добивания раненого, но ещё не потопленного корабля.
  ///
  /// Логика:
  /// 1. найти «неразрешённые» попадания — клетки с результатом hit, не входящие
  ///    в уже потопленный корабль;
  /// 2. если есть два попадания на одной линии — стрелять по продолжениям этой
  ///    линии (так корабль добивается быстрее);
  /// 3. иначе — по непоражённым соседям попаданий.
  List<Square> _targetCandidates(EnemyBoard enemy) {
    final unresolved = _unresolvedHits(enemy);
    if (unresolved.isEmpty) return const [];

    // Сначала пробуем продолжить уже выстроившуюся линию попаданий.
    final lineExt = _lineExtensions(enemy, unresolved);
    if (lineExt.isNotEmpty) return lineExt;

    // Иначе — любые непоражённые соседи неразрешённых попаданий.
    final candidates = <Square>{};
    for (final h in unresolved) {
      for (final n in neighboursOf(h)) {
        if (!enemy.firedAt(n)) candidates.add(n);
      }
    }
    return candidates.toList()..sort(_byReadingOrder);
  }

  /// Попадания, не относящиеся к потопленным кораблям.
  ///
  /// Когда корабль потоплен, все его клетки обстреляны; значит, попадания,
  /// входящие в потопленный корабль, можно вычесть. Точных границ корабля
  /// стреляющий не знает, поэтому берём максимальный отрезок попаданий вдоль
  /// линии через клетку с результатом sunk — это и есть потопленный корабль.
  Set<Square> _unresolvedHits(EnemyBoard enemy) {
    final resolved = <Square>{};
    for (final shot in enemy.shots.values) {
      if (shot.result == ShotResult.sunk) {
        resolved.addAll(_sunkShipCells(enemy, shot.square));
      }
    }
    return enemy.hits.where((h) => !resolved.contains(h)).toSet();
  }

  /// Все клетки потопленного корабля, проходящего через клетку [anchor] (где
  /// был получен результат sunk). Это максимальный отрезок попаданий по
  /// горизонтали или вертикали, содержащий [anchor].
  Set<Square> _sunkShipCells(EnemyBoard enemy, Square anchor) {
    Set<Square> best = {anchor};
    for (final axis in [LineAxis.horizontal, LineAxis.vertical]) {
      final line = <Square>[anchor];
      // Вправо/вниз.
      var step = 1;
      while (true) {
        final next = axis == LineAxis.horizontal
            ? Square(anchor.row, anchor.col + step)
            : Square(anchor.row + step, anchor.col);
        if (!next.inside) break;
        final s = enemy.at(next);
        if (s == null || s.result == ShotResult.miss) break;
        line.add(next);
        step++;
      }
      // Влево/вверх.
      step = 1;
      while (true) {
        final next = axis == LineAxis.horizontal
            ? Square(anchor.row, anchor.col - step)
            : Square(anchor.row - step, anchor.col);
        if (!next.inside) break;
        final s = enemy.at(next);
        if (s == null || s.result == ShotResult.miss) break;
        line.add(next);
        step++;
      }
      if (line.length > best.length) best = line.toSet();
    }
    return best;
  }

  /// Продолжения линии из двух и более попаданий: клетки за концами отрезка.
  List<Square> _lineExtensions(
    EnemyBoard enemy,
    Set<Square> unresolved,
  ) {
    // Группируем попадания по строкам и столбцам.
    final byRow = <int, Set<Square>>{};
    final byCol = <int, Set<Square>>{};
    for (final h in unresolved) {
      byRow.putIfAbsent(h.row, () => {}).add(h);
      byCol.putIfAbsent(h.col, () => {}).add(h);
    }
    for (final cells in byRow.values) {
      if (cells.length >= 2) {
        final ext = _endsOfLine(cells, LineAxis.horizontal);
        final valid =
            ext.where((s) => s.inside && !enemy.firedAt(s)).toList();
        if (valid.isNotEmpty) return valid;
      }
    }
    for (final cells in byCol.values) {
      if (cells.length >= 2) {
        final ext = _endsOfLine(cells, LineAxis.vertical);
        final valid =
            ext.where((s) => s.inside && !enemy.firedAt(s)).toList();
        if (valid.isNotEmpty) return valid;
      }
    }
    return const [];
  }

  /// Две клетки за концами отрезка попаданий вдоль оси [axis].
  List<Square> _endsOfLine(Set<Square> cells, LineAxis axis) {
    final sorted = cells.toList()
      ..sort((a, b) => axis == LineAxis.horizontal
          ? a.col.compareTo(b.col)
          : a.row.compareTo(b.row));
    final first = sorted.first;
    final last = sorted.last;
    return [
      axis == LineAxis.horizontal
          ? Square(first.row, first.col - 1)
          : Square(first.row - 1, first.col),
      axis == LineAxis.horizontal
          ? Square(last.row, last.col + 1)
          : Square(last.row + 1, last.col),
    ];
  }

  /// Вероятностный выбор клетки в фазе поиска нового корабля (hard).
  ///
  /// Для каждой необстрелянной клетки считаем, сколькими способами на неё может
  /// попасть каждый из ещё не потопленных кораблей (с учётом промахов и уже
  /// потопленных кораблей), и выбираем клетку с максимальным счётом. Клетки
  /// рядом с попаданиями получают бонус: их добивать выгоднее.
  Square? _probabilisticChoice(
    EnemyBoard enemy,
    Set<Square> unfired,
    Random random,
  ) {
    final remaining = _remainingShipSizes(enemy);
    if (remaining.isEmpty) return null;

    // Клетки, где корабль точно стоять не может: промахи и «обводка» потопленных.
    final blocked = <Square>{};
    for (final s in enemy.shots.values) {
      if (s.result == ShotResult.miss) blocked.add(s.square);
      if (s.result == ShotResult.sunk) {
        blocked.addAll(_sunkShipCells(enemy, s.square));
        // Вокруг потопленного корабля другие стоять не могут.
        for (final c in _sunkShipCells(enemy, s.square)) {
          for (final n in neighboursOf(c)) {
            blocked.add(n);
          }
        }
      }
    }

    final scores = <Square, int>{};
    for (final size in remaining) {
      for (final origin in allSquares()) {
        for (final o in Orientation.values) {
          // Тип не важен — важен размер; submarine имеет size 1, берём как
          // «каркас» и проверяем длину.
          final ship = Ship(
            type: ShipType.submarine,
            origin: origin,
            orientation: o,
          );
          final cells = ship.cells;
          if (cells.length != size) continue;
          if (cells.any((c) => !c.inside)) continue;
          if (cells.any((c) => blocked.contains(c))) continue;
          // Все клетки размещения должны быть либо необстрелянными, либо
          // попаданиями (размещение не противоречит тому, что мы знаем).
          final ok = cells.every((c) {
            final s = enemy.at(c);
            return s == null || s.result != ShotResult.miss;
          });
          if (!ok) continue;
          for (final c in cells) {
            scores[c] = (scores[c] ?? 0) + 1;
          }
        }
      }
    }

    if (scores.isEmpty) return null;

    // Бонус клеткам рядом с неразрешёнными попаданиями — ускоряет добивание.
    final unresolved = _unresolvedHits(enemy);
    if (unresolved.isNotEmpty) {
      for (final h in unresolved) {
        for (final n in neighboursOf(h)) {
          if (scores.containsKey(n)) scores[n] = scores[n]! + 1000;
        }
      }
    }

    final max = scores.values.reduce(_maxFn);
    final tops = scores.keys.where((k) => scores[k] == max).toList();
    return tops[random.nextInt(tops.length)];
  }

  /// Размеры ещё не потопленных кораблей. Каждый результат sunk убирает один
  /// корабль соответствующего типа из «оставшихся».
  List<int> _remainingShipSizes(EnemyBoard enemy) {
    final remaining = <int>[];
    for (final type in ShipType.values) {
      var left = type.count;
      for (final s in enemy.shots.values) {
        if (s.result == ShotResult.sunk && s.sunkType == type) left--;
      }
      for (var i = 0; i < left; i++) {
        remaining.add(type.size);
      }
    }
    return remaining;
  }

  static int _maxFn(int a, int b) => a > b ? a : b;
}

int _byReadingOrder(Square a, Square b) {
  final r = a.row.compareTo(b.row);
  return r != 0 ? r : a.col.compareTo(b.col);
}
