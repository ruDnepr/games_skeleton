import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/domino/engine/model.dart';
import 'package:games_for_diana/games/domino/engine/rules.dart';

const rules = DominoRules();

/// Собирает позицию из читаемых записей: руки, базар и цепочка.
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

List<String> labelsOf(Iterable<DominoTile> tiles) => [
  for (final tile in tiles) tile.label,
];

List<String> movesOf(List<DominoMove> moves) => [
  for (final move in moves) '${move.tile.label}>${move.side.name}',
];

void main() {
  group('колода и раздача', () {
    test('в наборе 28 разных костей от 0:0 до 6:6', () {
      final deck = fullDeck();
      expect(deck, hasLength(deckSize));
      expect(deck.toSet(), hasLength(deckSize));
      expect(deck.first.label, '0:0');
      expect(deck.last.label, '6:6');
    });

    test('двум игрокам достаётся по семь костей', () {
      final state = rules.initial(players: 2, random: Random(7));
      expect(state.handSizes, [tilesPerPlayer, tilesPerPlayer]);
      expect(state.bazaarCount, deckSize - 2 * tilesPerPlayer);
      expect(state.bazaar, hasLength(state.bazaarCount));
      final seen = {...state.bazaar, for (final hand in state.hands) ...hand};
      expect(seen, hasLength(deckSize));
    });

    test('четверо игроков разбирают весь базар', () {
      final state = rules.initial(players: 4, random: Random(3));
      expect(state.handSizes, [7, 7, 7, 7]);
      expect(state.bazaarCount, 0);
      expect(state.playerCount, 4);
    });

    test('порядок колоды можно задать, чтобы партия была предсказуемой', () {
      final deck = fullDeck();
      final state = rules.initial(players: 2, order: deck);
      expect(labelsOf(state.handOf(0)), labelsOf(deck.take(7)));
      expect(labelsOf(state.bazaar), labelsOf(deck.skip(14)));
    });

    test('колода из повторов не принимается', () {
      final bad = [
        for (var index = 0; index < deckSize; index++) DominoTile(0, 0),
      ];
      expect(
        () => rules.initial(players: 2, order: bad),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('первая кость партии', () {
    test('открывает дубль 1:1, даже если 2:2 лежит у другого игрока', () {
      final starting = rules.startingTileFor([
        [DominoTile(2, 2), DominoTile(1, 1)],
        [DominoTile(6, 5)],
      ]);
      expect(starting.tile.label, '1:1');
      expect(starting.seat, 0);
      expect(starting.fromDouble, isTrue);
    });

    test('если 1:1 нет, играет 2:2, потом 3:3 и так далее', () {
      final starting = rules.startingTileFor([
        [DominoTile(0, 6)],
        [DominoTile(3, 3), DominoTile(4, 4)],
      ]);
      expect(starting.tile.label, '3:3');
      expect(starting.seat, 1);
    });

    test('без дублей партию открывает самая большая кость', () {
      final starting = rules.startingTileFor([
        [DominoTile(1, 2)],
        [DominoTile(5, 6), DominoTile(2, 3)],
      ]);
      expect(starting.tile.label, '5:6');
      expect(starting.seat, 1);
      expect(starting.fromDouble, isFalse);
    });

    test('0:0 не открывает партию, если есть кость с очками', () {
      final starting = rules.startingTileFor([
        [DominoTile(0, 0)],
        [DominoTile(0, 1)],
      ]);
      expect(starting.tile.label, '0:1');
      expect(starting.seat, 1);
    });

    test('после раздачи ход принадлежит владельцу старшей кости', () {
      final deck = fullDeck();
      final state = rules.initial(players: 2, order: deck);
      final starting = rules.startingTileFor(state.hands);
      expect(state.turn, starting.seat);
      expect(state.handOf(starting.seat), contains(starting.tile));
    });
  });

  group('подходящие ходы', () {
    test('на пустом столе подходит любая кость', () {
      final state = table(hands: [
        ['1:2', '3:3'],
        ['0:6'],
      ]);
      expect(movesOf(rules.getValidMoves(state)), ['1:2>right', '3:3>right']);
      expect(rules.canPlay(state), isTrue);
    });

    test('кость приставляется к концу с тем же числом', () {
      final state = table(
        hands: [
          ['3:4', '5:6', '1:2'],
          ['0:0'],
        ],
        board: ['3:5'],
      );
      final moves = rules.getValidMoves(state);
      expect(movesOf(moves), containsAll(['3:4>left', '5:6>right']));
      expect(movesOf(moves), isNot(contains('1:2>right')));
      expect(rules.canPlay(state, DominoTile(3, 4)), isTrue);
      expect(rules.canPlay(state, DominoTile(1, 2)), isFalse);
    });

    test('дубль подходит к концу, где стоит его число', () {
      final state = table(
        hands: [
          ['4:4'],
          ['0:0'],
        ],
        board: ['4:6'],
      );
      final moves = rules.getValidMoves(state);
      expect(movesOf(moves), contains('4:4>left'));
      expect(movesOf(moves), allOf(isNot(contains('4:4>right'))));
    });

    test('без подходящих костей список ходов пуст', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['0:0'],
      );
      expect(rules.getValidMoves(state), isEmpty);
      expect(rules.canPlay(state), isFalse);
      expect(rules.anyoneCanPlay(state), isFalse);
    });

    test('вышедший игрок не мешает ходу остальных', () {
      final state = table(
        hands: [
          ['1:1'],
          ['2:2'],
          ['3:3'],
        ],
        board: ['1:2'],
        turn: 1,
      );
      final next = state.copyWith(inactive: {1});
      expect(rules.getValidMoves(next), isEmpty);
      expect(rules.nextSeat(next, from: 0), 2);
    });
  });

  group('выкладывание кости', () {
    test('кость уходит из руки, а ход переходит дальше', () {
      final state = table(hands: [
        ['1:2', '3:4'],
        ['5:6'],
      ]);
      final next = rules.applyMove(
        state,
        const DominoMove(tile: DominoTile(1, 2), side: ChainSide.right),
      );
      expect(labelsOf(next.handOf(0)), ['3:4']);
      expect(next.handSizes[0], 1);
      expect(next.turn, 1);
      expect(next.ply, 1);
      expect(next.board.chain.single.encode(), '1:2');
      expect(next.board.leftEnd, 1);
      expect(next.board.rightEnd, 2);
    });

    test('дубль первым ходом ложится поперёк цепочки', () {
      final state = table(hands: [
        ['3:3', '1:2'],
        ['4:5'],
      ]);
      final next = rules.applyMove(
        state,
        const DominoMove(tile: DominoTile(3, 3), side: ChainSide.right),
      );
      expect(next.board.chain.single.isAcross, isTrue);
      expect(next.board.leftEnd, 3);
      expect(next.board.rightEnd, 3);
    });

    test('кость встаёт к левому концу и поворачивается нужной стороной', () {
      final state = table(
        hands: [
          ['1:2', '0:0'],
          ['0:0'],
        ],
        board: ['2:4'],
      );
      final next = rules.applyMove(
        state,
        const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
      );
      expect(next.board.fingerprint, '1:2,2:4');
      expect(next.board.leftEnd, 1);
    });

    test('нельзя поставить кость, которой нет на руке', () {
      final state = table(hands: [
        ['1:2'],
        ['1:3'],
      ]);
      expect(
        () => rules.applyMove(
          state,
          const DominoMove(tile: DominoTile(1, 3), side: ChainSide.right),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('нельзя поставить кость не к тому концу', () {
      final state = table(
        hands: [
          ['1:2'],
          ['1:3'],
        ],
        board: ['1:4'],
      );
      expect(
        () => rules.applyMove(
          state,
          const DominoMove(tile: DominoTile(1, 2), side: ChainSide.right),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('базар и пропуск хода', () {
    test('кость из базара добавляется в руку, а очередь не меняется', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['5:5'],
        bazaar: ['6:6', '0:3'],
      );
      final next = rules.drawFromBazaar(state);
      expect(labelsOf(next.handOf(0)), ['1:2', '6:6']);
      expect(next.bazaarCount, 1);
      expect(next.bazaar.single.label, '0:3');
      expect(next.turn, 0);
      expect(next.ply, 1);
    });

    test('из пустого базара кость не взять', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['5:5'],
      );
      expect(() => rules.drawFromBazaar(state), throwsStateError);
    });

    test('пропуск передаёт ход следующему игроку', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
          ['5:6'],
        ],
        board: ['0:0'],
        turn: 1,
      );
      final next = rules.pass(state);
      expect(next.turn, 2);
      expect(next.ply, 1);
      expect(next.handSizes, [1, 1, 1]);
    });

    test('пропуск не перескакивает вышедшего игрока', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
          ['5:6'],
        ],
        board: ['0:0'],
        turn: 0,
      ).copyWith(inactive: {1});
      final next = rules.pass(state);
      expect(next.turn, 2);
    });
  });

  group('конец партии', () {
    test('выложивший все кости выигрывает', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['1:5'],
      );
      final next = rules.applyMove(
        state,
        const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
      );
      expect(next.isOver, isTrue);
      expect(next.result?.winner, 0);
      expect(next.result?.kind, ResultKind.win);
      expect(rules.checkWin(next)?.winner, 0);
    });

    test('рыба: побеждает игрок с меньшей суммой очков на руках', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['0:0'],
      );
      final settled = rules.settle(state);
      expect(settled.isOver, isTrue);
      expect(settled.result?.kind, ResultKind.fish);
      expect(settled.result?.winner, 0);
      expect(settled.result?.sums, [3, 7]);
      expect(settled.result?.isFish, isTrue);
      expect(settled.result?.isDraw, isFalse);
    });

    test('рыба с равными суммами заканчивается ничьей', () {
      // Ни одна кость на руках не подходит к нулю, базар пуст — это рыба.
      // Суммы равны: 1 + 5 = 2 + 4 = 6.
      final state = table(
        hands: [
          ['1:5'],
          ['2:4'],
        ],
        board: ['0:0'],
      );
      final settled = rules.settle(state);
      expect(settled.result?.kind, ResultKind.draw);
      expect(settled.result?.winner, isNull);
      expect(settled.result?.isDraw, isTrue);
    });

    test('пока в базаре есть кости, партия не заканчивается', () {
      final state = table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['0:0'],
        bazaar: ['6:6'],
      );
      expect(rules.settle(state).isOver, isFalse);
    });

    test('выход игрока отправляет его кости в базар', () {
      final state = table(
        hands: [
          ['1:2', '3:4'],
          ['5:6'],
          ['0:1'],
        ],
        board: ['6:6'],
        turn: 0,
      );
      final next = rules.abandonSeat(state, 0);
      expect(next.isActive(0), isFalse);
      expect(next.handSizes[0], 0);
      expect(next.bazaarCount, 2);
      expect(
        next.bazaar.map((tile) => tile.label),
        containsAll(['1:2', '3:4']),
      );
      expect(next.turn, 1);
      expect(next.isOver, isFalse);
    });

    test('если остался один игрок, партия заканчивается его победой', () {
      final state = table(
        hands: [
          ['1:2'],
          ['5:6'],
        ],
        board: ['6:6'],
      );
      final next = rules.abandonSeat(state, 0);
      expect(next.isOver, isTrue);
      expect(next.result?.winner, 1);
    });
  });

  group('сеть', () {
    test('ход соперника не раскрывает чужие кости', () {
      final state = GameState(
        playerCount: 2,
        hands: [
          [const DominoTile(1, 2), const DominoTile(3, 5)],
          const [],
        ],
        sizes: [2, 7],
        bazaar: const [],
        bazaarTotal: 0,
        board: const Board.empty(),
        turn: 1,
      );
      final next = rules.applyNetworkMove(
        state,
        1,
        const DominoMove(tile: DominoTile(2, 2), side: ChainSide.right),
        ply: 1,
        turn: 0,
        sizes: [2, 6],
        bazaarCount: 0,
      );
      expect(next.board.chain.single.encode(), '2:2');
      expect(next.handSizes, [2, 6]);
      expect(next.handOf(1), isEmpty);
      expect(next.turn, 0);
      expect(next.allHandsKnown, isFalse);
    });

    test('взятая из базара кость видна только тому, кто её взял', () {
      final state = GameState(
        playerCount: 2,
        hands: [
          const [],
          const [],
        ],
        sizes: [6, 7],
        bazaar: const [],
        bazaarTotal: 3,
        board: const Board.empty(),
        turn: 1,
      );
      final mine = rules.applyNetworkDraw(
        state,
        1,
        tile: const DominoTile(4, 5),
        ply: 1,
        sizes: [6, 8],
        bazaarCount: 2,
        turn: 1,
      );
      expect(mine.handOf(1), hasLength(1));
      expect(mine.bazaarCount, 2);

      final foreign = rules.applyNetworkDraw(
        state,
        1,
        ply: 1,
        sizes: [6, 8],
        bazaarCount: 2,
        turn: 1,
      );
      expect(foreign.handOf(1), isEmpty);
      expect(foreign.handSizes[1], 8);
      expect(foreign.bazaarCount, 2);
    });
  });
}
