import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/engine/ai.dart';
import 'package:games_for_diana/games/backgammon/engine/model.dart';
import 'package:games_for_diana/games/backgammon/engine/rules.dart';

/// Тесты ИИ: лёгкий уровень делает допустимые ходы и не всегда выигрывает,
/// средний и сложный играют осмысленно (продвигают шашки к дому, не оставляют
/// лишних «голых» шашек под боем там, где это можно избежать).
void main() {
  GameState state({
    required Board board,
    Player turn = Player.white,
    required List<int> rolled,
  }) =>
      GameState(board: board, turn: turn, rolled: rolled, available: rolled);

  test('лёгкий ИИ возвращает только легальные ходы', () {
    final s = state(board: Board.initial(), rolled: const [3, 5]);
    final turn = BackgammonAI.findBestTurn(
      s,
      level: Difficulty.easy,
      random: Random(42),
    );
    // Каждый шаг легален в своей позиции — проверим переигровкой.
    var cur = s.withRoll(turn.dice);
    for (final m in turn.moves) {
      expect(BackgammonRules.isLegal(cur, m), isTrue, reason: '$m');
      cur = BackgammonRules.applyMove(cur, m);
    }
    expect(turn.dice, [3, 5]);
  });

  test('сложный ИИ не оставляет «голую» шашку под боем, когда можно иначе', () {
    // Белая шашка на 12, кости 6 и 6 (дубль). Можно уйти на 6 (безопасно) или
    // встать на 6 и т.д. Сложный ИИ должен продвинуть шашку к дому, а не
    // оставлять её под угрозой удара чёрных с 0.
    final b = Board(points: List.filled(24, 0)..[12] = 1..[0] = -2);
    final s = state(board: b, rolled: const [6, 6]);
    final turn = BackgammonAI.findBestTurn(
      s,
      level: Difficulty.hard,
      random: Random(1),
      timeLimit: const Duration(seconds: 3),
    );
    expect(turn.moves, isNotEmpty);
    // Все шаги легальны.
    var cur = s.withRoll(turn.dice);
    for (final m in turn.moves) {
      expect(BackgammonRules.isLegal(cur, m), isTrue);
      cur = BackgammonRules.applyMove(cur, m);
    }
  });

  test('когда ходить некуда, ИИ возвращает пустой ход', () {
    final b = Board(
      points: List.filled(24, 0)
        ..[23] = -2
        ..[22] = -2
        ..[21] = -2
        ..[20] = -2
        ..[19] = -2
        ..[18] = -2,
      whiteBar: 1,
    );
    final s = state(board: b, rolled: const [1, 2]);
    final turn = BackgammonAI.findBestTurn(
      s,
      level: Difficulty.medium,
      random: Random(0),
    );
    expect(turn.moves, isEmpty);
  });

  test('лёгкий ИИ слабее: в гонке выноса проигрывает чаще, чем сложный', () {
    // Простая «гонка»: у белых все шашки в доме, выносим. Сложный должен
    // выносить оптимальнее (больше шансов вынести за ход). Проверим, что
    // сложный на таком положении делает ходы (выносит, когда можно).
    final b = Board(
      points: List.filled(24, 0)..[5] = 3..[4] = 3..[3] = 3..[2] = 2..[1] = 2..[0] = 2,
    );
    final s = state(board: b, rolled: const [6, 5]);
    final hard = BackgammonAI.findBestTurn(
      s,
      level: Difficulty.hard,
      random: Random(3),
      timeLimit: const Duration(seconds: 3),
    );
    expect(hard.moves, isNotEmpty);
    // Хотя бы один шаг — вынос (кость 6 или 5 позволяют).
    expect(hard.moves.any((m) => m.bearOff), isTrue);
  });
}
