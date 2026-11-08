import 'dart:math' as dart_math;

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/battleship/engine/ai.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/engine/rules.dart';

/// ИИ морского боя: лёгкий, средний, сложный. Порт оригинального `ai_test.dart`.
void main() {
  final rules = const BattleshipRules();

  EnemyBoard boardWith(List<Shot> shots) =>
      EnemyBoard({for (final s in shots) s.square: s});

  test('лёгкий ИИ стреляет только по необстрелянным клеткам', () {
    final ai = const BattleshipAI(Difficulty.easy);
    final rng = _Random(42);
    final prior = [
      for (final s in [
        const Square(0, 0),
        const Square(0, 1),
        const Square(0, 2),
      ])
        Shot(square: s, result: ShotResult.miss),
    ];
    final board = boardWith(prior);
    for (var i = 0; i < 50; i++) {
      final shot = ai.chooseShot(board, rng);
      expect(board.firedAt(shot), isFalse,
          reason: 'ИИ выстрелил в обстрелянную клетку');
    }
  });

  test('средний ИИ после попадания добивает соседей', () {
    final ai = const BattleshipAI(Difficulty.medium);
    final rng = _Random(7);
    // Одно попадание в (4,4) — корабль должен быть рядом.
    final board = boardWith([
      const Shot(square: Square(4, 4), result: ShotResult.hit),
    ]);
    final targets = List.generate(8, (_) => ai.chooseShot(board, rng));
    // Все выстрелы должны быть соседями попадания.
    for (final t in targets) {
      final dr = (t.row - 4).abs();
      final dc = (t.col - 4).abs();
      expect(dr + dc, lessThanOrEqualTo(2),
          reason: 'Средний ИИ отвлёкся от раненого корабля: $t');
    }
  });

  test('средний ИИ добивает корабль до потопления', () {
    final ai = const BattleshipAI(Difficulty.medium);
    final rng = _Random(123);
    // Корабль противника: эсминец в (3,3)-(3,4).
    final enemy = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(3, 3),
        orientation: Orientation.horizontal,
      ),
    ]);
    final shots = <Square, Shot>{};
    var sunk = false;
    // Шахматный паттерн среднего ИИ содержит 50 клеток; чтобы гарантированно
    // попасть в (3,3), нужно до 50 итераций фазы поиска + до 8 итераций
    // фазы добивания. Берём с запасом.
    for (var i = 0; i < 100 && !sunk; i++) {
      final board = EnemyBoard(Map.unmodifiable(shots));
      final target = ai.chooseShot(board, rng);
      expect(shots.containsKey(target), isFalse,
          reason: 'ИИ выстрелил в обстрелянную клетку');
      final shot = rules.shootResult(enemy, shots, target);
      shots[target] = shot;
      if (shot.result == ShotResult.sunk) {
        sunk = true;
      }
    }
    expect(sunk, isTrue, reason: 'Средний ИИ не добил корабль');
  });

  test('сложный ИИ добивает корабль и не стреляет дважды в одну клетку', () {
    final ai = const BattleshipAI(Difficulty.hard);
    final rng = _Random(999);
    final enemy = rules.autoFleet(rng);
    final shots = <Square, Shot>{};
    var sunkCount = 0;
    for (var i = 0; i < 100 && sunkCount < 10; i++) {
      final board = EnemyBoard(Map.unmodifiable(shots));
      final target = ai.chooseShot(board, rng);
      expect(shots.containsKey(target), isFalse,
          reason: 'Сложный ИИ выстрелил в обстрелянную клетку');
      final shot = rules.shootResult(enemy, shots, target);
      shots[target] = shot;
      if (shot.result == ShotResult.sunk) sunkCount++;
    }
    expect(sunkCount, 10,
        reason: 'Сложный ИИ не потопил весь флот за 100 выстрелов');
  });

  test('сложный ИИ не стреляет по «обводке» потопленного корабля', () {
    final ai = const BattleshipAI(Difficulty.hard);
    final rng = _Random(5);
    // Эсминец (3,3)-(3,4) потоплен; соседние клетки не должны быть выбраны.
    final board = boardWith([
      const Shot(square: Square(3, 3), result: ShotResult.hit),
      const Shot(
          square: Square(3, 4),
          result: ShotResult.sunk,
          sunkType: ShipType.destroyer),
    ]);
    final forbidden = <Square>{
      const Square(2, 2),
      const Square(2, 3),
      const Square(2, 4),
      const Square(2, 5),
      const Square(3, 2),
      const Square(3, 5),
      const Square(4, 2),
      const Square(4, 3),
      const Square(4, 4),
      const Square(4, 5),
    };
    for (var i = 0; i < 20; i++) {
      final t = ai.chooseShot(board, rng);
      expect(forbidden.contains(t), isFalse,
          reason: 'Сложный ИИ целился в обводку потопленного: $t');
    }
  });
}

/// Локальный источник детерминированной случайности для тестов. Реализует
/// тот же интерфейс, что и `dart:math.Random`, поэтому ИИ принимает его как
/// `Random?`.
class _Random implements dart_math.Random {
  _Random(this._seed);
  int _seed;

  @override
  int nextInt(int max) {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed % max;
  }

  @override
  double nextDouble() => nextInt(1 << 30) / (1 << 30);

  @override
  bool nextBool() => nextInt(2) == 0;
}
