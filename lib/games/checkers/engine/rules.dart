/// Правила шашек, отделённые от интерфейса.
///
/// Чистый Dart, без Flutter: те же правила проверяют ход человека, ход
/// компьютера и ход, пришедший по сети, — расхождения быть не может. Поведение
/// вариантов описано в `model.dart` (`VariantDetails`); здесь — точная механика
/// хода и взятия.
library;

import 'dart:math' as math;

import 'model.dart';

/// Чистая генерация ходов. Взятые шашки остаются блокерами до конца серии;
/// простая шашка в русских/поддавках становится дамкой немедленно, в
/// международных — в конце хода, в классических — превращение завершает ход.
///
/// Серии взятий различаются по вариантам:
/// * русские/поддавки — простая может остановиться после любой серии, дамка
///   обязана закончить серию, которую начала (поворот внутри серии разрешён);
/// * классические/американские — каждая серия играется до конца любой шашкой;
/// * международные — только серии с максимальным числом взятых шашек.
///
/// Правило максимального взятия универсально только для международных.
abstract interface class GameRules {
  GameVariant get variant;
  List<Move> legalMoves(GameState state);
  GameState apply(GameState state, Move move);
  Side? winner(GameState state);

  static GameRules forVariant(GameVariant variant) => switch (variant) {
    GameVariant.russian => const RussianRules(),
    GameVariant.american => const AmericanRules(),
    GameVariant.international => const InternationalRules(),
    GameVariant.giveaway => const GiveawayRules(),
  };
}

class StandardRules implements GameRules {
  const StandardRules(this.variant);
  @override
  final GameVariant variant;

  static const _directions = <(int, int)>[(-1, -1), (-1, 1), (1, -1), (1, 1)];

  @override
  List<Move> legalMoves(GameState state) {
    if (state.variant != variant || state.board.size != variant.boardSize) {
      throw ArgumentError('Правила не соответствуют позиции');
    }
    final captures = <Move>[];
    for (final entry in state.board.pieces.entries) {
      if (entry.value.side != state.turn) continue;
      _findCaptures(
        Map.of(state.board.pieces),
        state.board.size,
        entry.key,
        entry.key,
        entry.value,
        <Square>[],
        <Square>[],
        captures,
      );
    }
    if (captures.isNotEmpty) {
      // У русских/поддавков простая может прервать серию, поэтому один и тот же
      // ход может родиться дважды — оставляем первое вхождение.
      final unique = captures.toSet().toList();
      if (!variant.maximumCapture) return unique;
      final maximum = unique.map((m) => m.captures.length).reduce(math.max);
      return unique.where((move) => move.captures.length == maximum).toList();
    }

    final moves = <Move>[];
    for (final entry in state.board.pieces.entries) {
      final piece = entry.value;
      if (piece.side != state.turn) continue;
      for (final (dr, dc) in _directions) {
        if (!piece.king && dr != piece.side.forward) continue;
        var row = entry.key.row + dr;
        var col = entry.key.col + dc;
        while (Square(row, col).inside(state.board.size) &&
            state.board.at(Square(row, col)) == null) {
          moves.add(Move(from: entry.key, landings: [Square(row, col)]));
          if (!piece.king || !variant.flyingKings) break;
          row += dr;
          col += dc;
        }
      }
    }
    return moves;
  }

  void _findCaptures(
    Map<Square, Piece> board,
    int size,
    Square origin,
    Square current,
    Piece piece,
    List<Square> path,
    List<Square> taken,
    List<Move> result,
  ) {
    var found = false;
    for (final (dr, dc) in _directions) {
      if (!piece.king &&
          !variant.backwardsCapture &&
          dr != piece.side.forward) {
        continue;
      }
      var row = current.row + dr;
      var col = current.col + dc;
      if (piece.king && variant.flyingKings) {
        while (Square(row, col).inside(size) &&
            board[Square(row, col)] == null) {
          row += dr;
          col += dc;
        }
      }
      final victim = Square(row, col);
      final target = board[victim];
      if (!victim.inside(size) ||
          target == null ||
          target.side == piece.side ||
          taken.contains(victim)) {
        continue;
      }
      row += dr;
      col += dc;
      while (Square(row, col).inside(size) && board[Square(row, col)] == null) {
        found = true;
        final landing = Square(row, col);
        final promotes = !piece.king && _isCrownRow(landing, piece.side, size);
        final nextPiece =
            promotes &&
                (variant == GameVariant.russian ||
                    variant == GameVariant.giveaway)
            ? piece.crown()
            : piece;
        final nextBoard = Map<Square, Piece>.of(board)
          ..remove(current)
          ..[landing] = nextPiece;
        final nextPath = [...path, landing];
        final nextTaken = [...taken, victim];
        if (promotes && variant == GameVariant.american) {
          result.add(
            Move(from: origin, landings: nextPath, captures: nextTaken),
          );
        } else {
          _findCaptures(
            nextBoard,
            size,
            origin,
            landing,
            nextPiece,
            nextPath,
            nextTaken,
            result,
          );
          // Русские/поддавки: простая выбирает любую серию и может остановиться
          // после неё, даже если есть серия длиннее. Шашка, ставшая дамкой на
          // этом приземлении — уже дамка, и обязана продолжать, не добавляем.
          if (_manMayStopMidSeries(nextPiece)) {
            result.add(
              Move(from: origin, landings: nextPath, captures: nextTaken),
            );
          }
        }
        if (!piece.king || !variant.flyingKings) break;
        row += dr;
        col += dc;
      }
    }
    if (!found && taken.isNotEmpty) {
      result.add(Move(from: origin, landings: path, captures: taken));
    }
  }

  /// Можно ли прервать серию взятия посередине.
  ///
  /// Русские и поддавки: простая выбирает любую серию и может остановиться,
  /// дамка обязана закончить каждую начатую серию. Классические и
  /// международные: каждая серия играется до конца, остановка невозможна.
  /// Международные дополнительно оставляют только максимальные серии.
  bool _manMayStopMidSeries(Piece piece) =>
      (variant == GameVariant.russian || variant == GameVariant.giveaway) &&
      !piece.king;

  bool _isCrownRow(Square square, Side side, int size) =>
      square.row == (side == Side.white ? 0 : size - 1);

  @override
  GameState apply(GameState state, Move move) {
    if (!legalMoves(state).contains(move)) throw StateError('Недопустимый ход');
    return applyKnownLegal(state, move);
  }

  /// Применяет уже проверенный ход. Используется в поиске, когда ход взят из
  /// `legalMoves`.
  GameState applyKnownLegal(GameState state, Move move) {
    final pieces = Map<Square, Piece>.of(state.board.pieces);
    var piece = pieces.remove(move.from)!;
    for (final captured in move.captures) {
      pieces.remove(captured);
    }
    final wasRussianPromotion =
        variant == GameVariant.russian || variant == GameVariant.giveaway;
    if (_isCrownRow(move.to, piece.side, state.board.size) ||
        (wasRussianPromotion &&
            move.landings.any(
              (p) => _isCrownRow(p, piece.side, state.board.size),
            ))) {
      piece = piece.crown();
    }
    pieces[move.to] = piece;
    // Взятие или ход простой шашки обрывают тихую серию; ход дамки её
    // продолжает.
    final quiet = !move.isCapture && (state.board.at(move.from)?.king ?? false);
    return GameState(
      variant: variant,
      board: Board(state.board.size, pieces),
      turn: state.turn.opponent,
      ply: state.ply + 1,
      quietPlies: quiet ? state.quietPlies + 1 : 0,
    );
  }

  @override
  Side? winner(GameState state) {
    if (state.board.count(state.turn) == 0 || legalMoves(state).isEmpty) {
      return variant.reverseGoal ? state.turn : state.turn.opponent;
    }
    return null;
  }
}

class RussianRules extends StandardRules {
  const RussianRules() : super(GameVariant.russian);
}

class AmericanRules extends StandardRules {
  const AmericanRules() : super(GameVariant.american);
}

class InternationalRules extends StandardRules {
  const InternationalRules() : super(GameVariant.international);
}

class GiveawayRules extends StandardRules {
  const GiveawayRules() : super(GameVariant.giveaway);
}
