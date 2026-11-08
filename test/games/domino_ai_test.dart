import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/domino/engine/ai.dart';
import 'package:games_for_diana/games/domino/engine/model.dart';
import 'package:games_for_diana/games/domino/engine/rules.dart';

const rules = DominoRules();

GameState table({
  required List<List<String>> hands,
  List<String> board = const [],
  int turn = 0,
  List<String> bazaar = const [],
}) {
  var chain = const Board.empty();
  for (final label in board) {
    chain = chain.place(DominoTile.parse(label), ChainSide.right);
  }
  return GameState(
    playerCount: hands.length,
    hands: [
      for (final hand in hands)
        [for (final label in hand) DominoTile.parse(label)],
    ],
    bazaar: [for (final label in bazaar) DominoTile.parse(label)],
    board: chain,
    turn: turn,
  );
}

bool isLegal(GameState state, DominoMove? move) {
  if (move == null) return false;
  return rules.getValidMoves(state).any(
    (candidate) => candidate.tile == move.tile && candidate.side == move.side,
  );
}

void main() {
  group('выбор хода', () {
    test('лёгкий уровень выбирает только допустимый ход', () {
      final state = table(
        hands: [
          ['1:2', '3:5', '6:6'],
          ['0:4'],
        ],
        board: ['2:6'],
      );
      final rng = Random(1);
      for (var attempt = 0; attempt < 20; attempt++) {
        expect(
          isLegal(state, DominoAI.findBestMove(state, 0, Difficulty.easy, rng)),
          isTrue,
        );
      }
    });

    test('средний и сложный уровни тоже не нарушают правила', () {
      final rng = Random(2);
      final states = [
        table(
          hands: [
            ['1:2', '2:3', '4:6'],
            ['0:5'],
          ],
          board: ['1:6'],
        ),
        table(
          hands: [
            ['0:0', '0:1', '5:5', '3:4'],
            ['6:6', '2:5'],
            ['1:4'],
          ],
          board: ['4:5'],
          turn: 2,
        ),
        table(
          hands: [
            ['2:2', '2:6', '6:6'],
            ['3:3'],
          ],
          bazaar: ['1:4', '0:6'],
        ),
      ];
      for (final state in states) {
        for (final level in [Difficulty.medium, Difficulty.hard]) {
          expect(
            isLegal(state, DominoAI.findBestMove(state, state.turn, level, rng)),
            isTrue,
          );
        }
      }
    });

    test('когда ходов нет, компьютер не выдумывает ход', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['0:0'],
      );
      final rng = Random(3);
      for (final level in Difficulty.values) {
        expect(
          DominoAI.findBestMove(state, 0, level, rng),
          isNull,
        );
      }
    });

    test('сложный уровень заканчивает партию последней костью', () {
      final state = table(
        hands: [
          ['5:6'],
          ['0:1'],
        ],
        board: ['5:1'],
      );
      final move = DominoAI.findBestMove(state, 0, Difficulty.hard, Random(4));
      expect(move?.tile.label, '5:6');
    });

    test('ход компьютера всегда можно применить к позиции', () {
      final state = table(
        hands: [
          ['1:2', '3:4'],
          ['0:6', '5:5'],
        ],
        board: ['2:2'],
      );
      final move = DominoAI.findBestMove(state, 0, Difficulty.medium, Random(5));
      expect(move, isNotNull);
      final next = rules.applyMove(state, move!);
      expect(next.board.length, 2);
      expect(next.turn, 1);
    });

    test('подсказка просит чужое место — ходов нет', () {
      final state = table(
        hands: [
          ['1:2', '3:4'],
          ['0:6', '5:5'],
        ],
        board: ['2:2'],
        turn: 1,
      );
      final move = DominoAI.findBestMove(state, 0, Difficulty.medium, Random(6));
      expect(move, isNull);
    });
  });
}
