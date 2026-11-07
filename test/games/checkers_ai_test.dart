import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/checkers/engine/ai.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/engine/rules.dart';

GameState position(GameVariant variant, Map<Square, Piece> pieces) => GameState(
  variant: variant,
  board: Board(variant.boardSize, pieces),
  turn: Side.white,
);

/// Белая простая может пойти на (4, 1) и попасть под бой чёрной с (3, 0), либо
/// на (4, 3) и остаться в безопасности. Любой разумный поиск выберет (4, 3).
GameState hangingMan() => position(GameVariant.russian, {
  const Square(5, 2): const Piece(Side.white),
  const Square(3, 0): const Piece(Side.black),
});

/// Материальный вес стороны: простая — единица, дамка — тройка.
int material(GameState state, Side side) => state.board.pieces.entries
    .where((entry) => entry.value.side == side)
    .fold(0, (sum, entry) => sum + (entry.value.king ? 3 : 1));

/// Материальный баланс стороны после того, как все обязательные взятия
/// доиграны. Взятие обязательно в любом варианте, поэтому баланс сразу после
/// хода ни о чём не говорит: шашка стоит лишь столько, сколько взято. Сторону,
/// которую бьют, выбирает худший для [side] ответ, сам [side] — лучший из своих
/// вынужденных досмотров.
int balanceAfterCaptures(StandardRules rules, GameState state, Side side) {
  final captures = rules.legalMoves(state).where((move) => move.isCapture);
  if (captures.isEmpty) {
    return material(state, side) - material(state, side.opponent);
  }
  final values = [
    for (final move in captures)
      balanceAfterCaptures(rules, rules.applyKnownLegal(state, move), side),
  ];
  return state.turn == side ? values.reduce(max) : values.reduce(min);
}

void main() {
  test('находит победу за один полный ход', () {
    final state = position(GameVariant.russian, {
      const Square(2, 1): const Piece(Side.white),
      const Square(1, 2): const Piece(Side.black),
    });
    expect(
      CheckersAI(random: Random(1)).findBestMove(state, 2)!.to,
      const Square(0, 3),
    );
  });

  test('в обычной игре избегает подставы в два полухода', () {
    expect(
      CheckersAI(random: Random(1)).findBestMove(hangingMan(), 2)!.to,
      const Square(4, 3),
    );
  });

  test('ответное взятие видно даже на глубине в один полуход', () {
    // Продление взятиями в листьях не даёт shallow-поиску отдать шашку под бой.
    expect(
      CheckersAI(random: Random(1)).findBestMove(
        hangingMan(),
        1,
        materialOnly: true,
      )!.to,
      const Square(4, 3),
    );
  });

  test('подсказка глубины 3 не ставит шашку под бой', () {
    expect(
      CheckersAI(random: Random(1)).findBestMove(hangingMan(), 3)!.to,
      const Square(4, 3),
    );
  });

  test('подсказка не теряет материал в начале партии', () {
    // Ситуация с телефона: подсказка предлагала шашку, которую тут же били.
    // Только баланс после обязательных взятий скажет, действительно ли ход
    // отдаёт материал: ровный обмен сразу после хода — нормальная игра,
    // потеря простой — нет.
    for (final variant in [GameVariant.russian, GameVariant.american]) {
      var state = GameState.initial(variant);
      final rules = GameRules.forVariant(variant) as StandardRules;
      final ai = CheckersAI(random: Random(1));
      for (var ply = 0; ply < 4; ply++) {
        final mover = state.turn;
        final before = material(state, mover) - material(state, mover.opponent);
        final move = ai.findBestMove(state, 3);
        expect(move, isNotNull, reason: '${variant.name}/$ply');
        final after = rules.applyKnownLegal(state, move!);
        expect(
          balanceAfterCaptures(rules, after, mover),
          greaterThanOrEqualTo(before),
          reason: '${variant.name}: ход $move на полуходе $ply теряет материал',
        );
        state = after;
      }
    }
  });

  test('в поддавках стремится отдать последнюю шашку', () {
    final state = position(GameVariant.giveaway, {
      const Square(5, 2): const Piece(Side.white),
      const Square(3, 0): const Piece(Side.black),
    });
    expect(
      CheckersAI(random: Random(1)).findBestMove(state, 2)!.to,
      const Square(4, 1),
    );
  });

  test('уровни различаются глубиной и эвристикой', () {
    expect(Difficulty.values.map((d) => d.depth).toList(), [1, 3, 5]);
    expect(Difficulty.easy.materialOnly, isTrue);
    expect(Difficulty.medium.materialOnly, isFalse);
    expect(Difficulty.hard.materialOnly, isFalse);
  });

  test('обычный бюджет позволяет доиграть заявленную глубину', () {
    final ai = CheckersAI(random: Random(1));
    expect(ai.findBestMove(GameState.initial(GameVariant.russian), 3), isNotNull);
    expect(ai.lastDepth, 3);
  });

  test('обрезанный проход не считается ответом поиска', () {
    // Бюджет слишком мал, чтобы закончить даже один проход, — ничего не
    // считается найденным, и отвечает безопасный запасной ход.
    final ai = CheckersAI(nodeBudget: 2);
    final move = ai.findBestMove(hangingMan(), 5);
    expect(move, isNotNull);
    expect(ai.lastDepth, 0);
    expect(move!.to, const Square(4, 3));
  });

  test(
    'каждый уровень возвращает допустимый ход во всех вариантах',
    () {
      for (final variant in GameVariant.values) {
        final state = GameState.initial(variant);
        final legal = GameRules.forVariant(variant).legalMoves(state);
        for (final difficulty in Difficulty.values) {
          final move = CheckersAI(random: Random(5)).findBestMove(
            state,
            difficulty.depth,
            easyNoise: difficulty == Difficulty.easy,
            materialOnly: difficulty.materialOnly,
          );
          expect(move, isNotNull, reason: '${variant.name}/${difficulty.name}');
          expect(
            legal,
            contains(move),
            reason: '${variant.name}/${difficulty.name}',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
