import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/engine/rules.dart';

GameState position(
  GameVariant variant,
  Map<Square, Piece> pieces, {
  Side turn = Side.white,
}) => GameState(
  variant: variant,
  board: Board(variant.boardSize, pieces),
  turn: turn,
);

void main() {
  const white = Piece(Side.white);
  const black = Piece(Side.black);

  test('начальная позиция и первый ход зависят от варианта', () {
    for (final variant in GameVariant.values) {
      final state = GameState.initial(variant);
      expect(
        state.board.count(Side.white),
        variant == GameVariant.international ? 20 : 12,
      );
      expect(
        state.board.count(Side.black),
        variant == GameVariant.international ? 20 : 12,
      );
      expect(
        state.turn,
        variant == GameVariant.american ? Side.black : Side.white,
      );
      expect(GameRules.forVariant(variant).legalMoves(state), isNotEmpty);
    }
  });

  test('бой обязателен, простой в русских можно остановить в середине', () {
    final state = position(GameVariant.russian, {
      const Square(5, 0): white,
      const Square(4, 1): black,
      const Square(2, 3): black,
      const Square(5, 6): white,
    });
    const rules = RussianRules();
    final moves = rules.legalMoves(state);
    // Без тихих ходов, простая может остановиться после первого взятия или
    // доиграть серию.
    expect(moves.every((m) => m.isCapture), isTrue);
    expect(moves, hasLength(2));
    final short = moves.firstWhere((m) => m.landings.length == 1);
    final full = moves.firstWhere((m) => m.landings.length == 2);
    expect(short.landings, [const Square(3, 2)]);
    expect(short.captures, [const Square(4, 1)]);
    expect(full.landings, [const Square(3, 2), const Square(1, 4)]);
    expect(full.captures, [const Square(4, 1), const Square(2, 3)]);

    final afterShort = rules.apply(state, short);
    expect(afterShort.board.count(Side.black), 1);
    expect(afterShort.turn, Side.black);

    final afterFull = rules.apply(state, full);
    expect(afterFull.board.count(Side.black), 0);
    expect(rules.winner(afterFull), Side.white);

    expect(
      () => rules.apply(
        state,
        Move(from: const Square(5, 6), landings: [const Square(4, 7)]),
      ),
      throwsStateError,
    );
  });

  test('в поддавках простой тоже выбирает длину серии', () {
    final state = position(GameVariant.giveaway, {
      const Square(5, 0): white,
      const Square(4, 1): black,
      const Square(2, 3): black,
    });
    final moves = GiveawayRules().legalMoves(state);
    expect(moves.map((m) => m.captures.length).toSet(), {1, 2});
  });

  test('дамка обязана бить дальше, но может повернуть внутри серии', () {
    const king = Piece(Side.white, king: true);
    // Дамка бьёт (6, 1), может остановиться на (4, 3) — там бить нечем, — но
    // не может остановиться на (5, 2), откуда (4, 1) всё ещё доступно.
    final state = position(GameVariant.russian, {
      const Square(7, 0): king,
      const Square(6, 1): black,
      const Square(4, 1): black,
    });
    final moves = RussianRules().legalMoves(state);
    expect(
      moves.where((m) => m.captures.length == 1 && m.to == const Square(5, 2)),
      isEmpty,
      reason: 'с (5, 2) дамка обязана продолжить бой',
    );
    final turn = moves.firstWhere((m) => m.captures.length == 2);
    expect(turn.captures, [const Square(6, 1), const Square(4, 1)]);
    expect(turn.landings, [const Square(5, 2), const Square(3, 0)]);

    final giveaway = GiveawayRules().legalMoves(
      position(GameVariant.giveaway, state.board.pieces),
    );
    expect(
      giveaway.where((m) => m.captures.length == 1 && m.to == const Square(5, 2)),
      isEmpty,
    );
    expect(giveaway.any((m) => m.captures.length == 2), isTrue);
  });

  test('в чекерсе серия доигрывается до конца простой шашкой', () {
    final state = position(GameVariant.american, {
      const Square(5, 2): white,
      const Square(4, 3): black,
      const Square(2, 5): black,
    });
    final moves = AmericanRules().legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.captures, [const Square(4, 3), const Square(2, 5)]);
    expect(moves.single.landings, [const Square(3, 4), const Square(1, 6)]);
  });

  test('в международных серию прервать нельзя, берётся только максимум', () {
    final state = position(GameVariant.international, {
      const Square(5, 0): white,
      const Square(4, 1): black,
      const Square(2, 3): black,
    });
    final moves = InternationalRules().legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.captures, hasLength(2));
  });

  test('русская простая бьёт назад, американская — нет', () {
    final pieces = {const Square(3, 2): white, const Square(4, 3): black};
    final russian = RussianRules().legalMoves(
      position(GameVariant.russian, pieces),
    );
    final american = AmericanRules().legalMoves(
      position(GameVariant.american, pieces),
    );
    expect(
      russian.any((m) => m.to == const Square(5, 4) && m.isCapture),
      isTrue,
    );
    expect(american.every((m) => !m.isCapture && m.to.row == 2), isTrue);
  });

  test('летающая дамка ходит и бьёт на расстояние; классическая — нет', () {
    const king = Piece(Side.white, king: true);
    final free = {const Square(5, 2): king};
    expect(
      RussianRules()
          .legalMoves(position(GameVariant.russian, free))
          .any((m) => m.to == const Square(1, 6)),
      isTrue,
    );
    expect(
      AmericanRules()
          .legalMoves(position(GameVariant.american, free))
          .every((m) => (m.to.row - 5).abs() == 1),
      isTrue,
    );
    final withOpponent = {const Square(5, 2): king, const Square(3, 4): black};
    final captures = RussianRules().legalMoves(
      position(GameVariant.russian, withOpponent),
    );
    expect(
      captures.map((m) => m.to),
      containsAll([const Square(2, 5), const Square(1, 6), const Square(0, 7)]),
    );
    expect(captures.every((m) => m.isCapture), isTrue);
  });

  test('сбитые шашки остаются преградой до окончания серии', () {
    final state = position(GameVariant.russian, {
      const Square(5, 2): const Piece(Side.white, king: true),
      const Square(4, 3): black,
      const Square(6, 1): black,
    });
    final moves = RussianRules().legalMoves(state);
    expect(moves, isNotEmpty);
    expect(moves.every((m) => m.captures.length == 1), isTrue);
  });

  test('в русских шашках превращение происходит во время боя', () {
    final state = position(GameVariant.russian, {
      const Square(2, 1): white,
      const Square(1, 2): black,
      const Square(1, 4): black,
    });
    final moves = RussianRules().legalMoves(state);
    final move = moves.firstWhere((m) => m.to == const Square(4, 7));
    expect(move.landings, [const Square(0, 3), const Square(4, 7)]);
    expect(
      RussianRules().apply(state, move).board.at(const Square(4, 7))!.king,
      isTrue,
    );
  });

  test('в американских шашках превращение завершает цепочку', () {
    final state = position(GameVariant.american, {
      const Square(2, 1): white,
      const Square(1, 2): black,
      const Square(1, 4): black,
    });
    final move = AmericanRules().legalMoves(state).single;
    expect(move.landings, [const Square(0, 3)]);
    final next = AmericanRules().apply(state, move);
    expect(next.board.at(const Square(0, 3))!.king, isTrue);
    expect(next.board.count(Side.black), 1);
  });

  test('международные шашки требуют максимальное взятие', () {
    final state = position(GameVariant.international, {
      const Square(7, 2): white,
      const Square(6, 3): black,
      const Square(4, 5): black,
      const Square(7, 6): white,
      const Square(6, 7): black,
    });
    final moves = InternationalRules().legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.captures, [const Square(6, 3), const Square(4, 5)]);
    expect(moves.single.to, const Square(3, 6));
  });

  test('в международных шашках из равных серий игрок выбирает любую', () {
    final state = position(GameVariant.international, {
      const Square(7, 0): white,
      const Square(6, 1): black,
      const Square(4, 1): black,
      const Square(4, 3): black,
    });
    final moves = InternationalRules().legalMoves(state);
    expect(moves, hasLength(2));
    expect(moves.every((m) => m.captures.length == 2), isTrue);
    expect(
      moves.map((m) => m.to).toSet(),
      {const Square(3, 0), const Square(3, 4)},
    );
  });

  test('в поддавках бой тоже обязателен', () {
    final state = position(GameVariant.giveaway, {
      const Square(5, 0): white,
      const Square(4, 1): black,
      const Square(7, 6): white,
    });
    final moves = GiveawayRules().legalMoves(state);
    expect(moves, hasLength(1));
    expect(moves.single.isCapture, isTrue);
    expect(moves.single.to, const Square(3, 2));
  });

  test('в международных шашках проход через последнюю линию не даёт дамку', () {
    final state = position(GameVariant.international, {
      const Square(2, 1): white,
      const Square(1, 2): black,
      const Square(1, 4): black,
    });
    final move = InternationalRules().legalMoves(state).single;
    expect(move.landings, [const Square(0, 3), const Square(2, 5)]);
    expect(
      InternationalRules()
          .apply(state, move)
          .board
          .at(const Square(2, 5))!
          .king,
      isFalse,
    );
  });

  test('в поддавках игрок без хода или шашек выигрывает', () {
    final withoutPieces = position(GameVariant.giveaway, {
      const Square(1, 0): black,
    });
    expect(GiveawayRules().winner(withoutPieces), Side.white);
    final blocked = position(GameVariant.giveaway, {
      const Square(0, 1): white,
      const Square(7, 0): black,
    });
    expect(GiveawayRules().winner(blocked), Side.white);
    expect(
      RussianRules().winner(
        position(GameVariant.russian, blocked.board.pieces),
      ),
      Side.black,
    );
  });

  test('тихие полуходы: ход дамки считается, ход шашки и взятие — нет', () {
    // Ход дамки продолжает тихую серию.
    final kingState = position(GameVariant.russian, {
      const Square(5, 2): const Piece(Side.white, king: true),
      const Square(0, 1): const Piece(Side.black, king: true),
    });
    final kingMove = RussianRules()
        .legalMoves(kingState)
        .firstWhere(
          (m) => m.from == const Square(5, 2) && !m.isCapture,
        );
    expect(
      RussianRules().applyKnownLegal(kingState, kingMove).quietPlies,
      1,
    );

    // Ход простой шашки обрывает серию, даже без взятия.
    final manState = position(GameVariant.russian, {
      const Square(5, 2): const Piece(Side.white),
      const Square(2, 1): const Piece(Side.black),
    });
    final manMove = RussianRules()
        .legalMoves(manState)
        .firstWhere((m) => m.from == const Square(5, 2) && !m.isCapture);
    expect(RussianRules().applyKnownLegal(manState, manMove).quietPlies, 0);
    expect(
      RussianRules()
          .applyKnownLegal(
            GameState(
              variant: manState.variant,
              board: manState.board,
              turn: manState.turn,
              quietPlies: 12,
            ),
            manMove,
          )
          .quietPlies,
      0,
    );

    // Взятие тоже обрывает серию.
    final captureState = position(GameVariant.russian, {
      const Square(5, 0): const Piece(Side.white, king: true),
      const Square(4, 1): const Piece(Side.black),
    });
    final capture = RussianRules().legalMoves(captureState).first;
    expect(capture.isCapture, isTrue);
    expect(
      RussianRules()
          .applyKnownLegal(
            GameState(
              variant: captureState.variant,
              board: captureState.board,
              turn: captureState.turn,
              quietPlies: 7,
            ),
            capture,
          )
          .quietPlies,
      0,
    );
  });

  test('одинаковые позиции дают одинаковый ключ повторения', () {
    final board = Board(GameVariant.russian.boardSize, {
      const Square(5, 2): const Piece(Side.white, king: true),
      const Square(0, 1): const Piece(Side.black, king: true),
    });
    final first = GameState(
      variant: GameVariant.russian,
      board: board,
      turn: Side.white,
    );
    final later = GameState(
      variant: GameVariant.russian,
      board: board,
      turn: Side.white,
      ply: 12,
    );
    expect(later.positionKey, first.positionKey);
    final otherTurn = GameState(
      variant: GameVariant.russian,
      board: board,
      turn: Side.black,
    );
    expect(otherTurn.positionKey, isNot(first.positionKey));
    final otherVariant = GameState(
      variant: GameVariant.american,
      board: Board(GameVariant.american.boardSize, board.pieces),
      turn: Side.white,
    );
    expect(otherVariant.positionKey, isNot(first.positionKey));
    final movedBoard = Board(GameVariant.russian.boardSize, {
      const Square(4, 1): const Piece(Side.white, king: true),
      const Square(0, 1): const Piece(Side.black, king: true),
    });
    expect(
      GameState(
        variant: GameVariant.russian,
        board: movedBoard,
        turn: Side.white,
      ).positionKey,
      isNot(first.positionKey),
    );
  });

  test('ход проходит JSON round-trip и защищён от некорректных данных', () {
    final move = Move(
      from: const Square(5, 0),
      landings: [const Square(3, 2), const Square(1, 4)],
      captures: [const Square(4, 1), const Square(2, 3)],
    );
    expect(Move.fromJson(move.toJson()), move);
    expect(
      () => Move.fromJson({
        'from': [0, 1],
        'path': [],
        'captures': [],
      }),
      throwsFormatException,
    );
    expect(() => Square.fromJson([100, 1]), throwsFormatException);
  });
}
