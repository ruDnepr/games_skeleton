/// Компьютерный соперник домино.
///
/// Уровни отличаются только оценкой хода, правила одни и те же:
///
/// * лёгкий — берёт случайную подходящую кость;
/// * средний — оставляет себе больше вариантов на следующий ход;
/// * сложный — ещё и считает, какие числа могли остаться у соперника, и
///   старается оставить ему концы, к которым у него меньше всего костей.
library;

import 'dart:math';

import 'model.dart';
import 'rules.dart';

/// Уровень игры компьютера.
enum Difficulty {
  easy('Лёгкий', 'Компьютер ходит первой подходящей костью'),
  medium('Средний', 'Компьютер оставляет себе больше вариантов'),
  hard('Сложный', 'Компьютер следит за твоими костями');

  const Difficulty(this.label, this.hint);

  final String label;
  final String hint;
}

/// Подбирает ход за место [seat], чья очередь в [state].
///
/// Возвращает `null`, если подходящих костей нет: пора идти в базар или
/// пропускать ход. Сторона, чей сейчас ход, определяется `state.turn`;
/// параметр [seat] нужен только для ясности и должен с ним совпадать.
class DominoAI {
  const DominoAI._();

  static DominoMove? findBestMove(
    GameState state,
    int seat,
    Difficulty difficulty,
    Random random,
  ) {
    // Тихая проверка: если просят не за того, кто ходит, ходов нет.
    if (state.turn != seat) return null;
    final rules = const DominoRules();
    final moves = rules.getValidMoves(state);
    if (moves.isEmpty) return null;
    return switch (difficulty) {
      Difficulty.easy => moves[random.nextInt(moves.length)],
      Difficulty.medium => _best(state, moves, _mediumScore),
      Difficulty.hard => _best(state, moves, _hardScore),
    };
  }

  /// Первый из лучших ходов: при равной оценке выбор не «прыгает», поэтому
  /// подсказка и ответ компьютера всегда одинаковы в одинаковой позиции.
  static DominoMove _best(
    GameState state,
    List<DominoMove> moves,
    int Function(GameState state, DominoMove move) score,
  ) {
    var best = moves.first;
    var bestScore = score(state, best);
    for (final move in moves.skip(1)) {
      final value = score(state, move);
      if (value > bestScore) {
        best = move;
        bestScore = value;
      }
    }
    return best;
  }

  /// Средний уровень: главное — чтобы после хода было чем ходить дальше.
  /// При равных вариантах выгоднее сбросить тяжёлую кость или дубль.
  static int _mediumScore(GameState state, DominoMove move) {
    final rest = _restOfHand(state, move.tile);
    final board = state.board.place(move.tile, move.side);
    final options = rest.where(board.canPlace).length;
    return options * 10 + move.tile.weight;
  }

  /// Сложный уровень: к своим вариантам добавляется давление на соперника.
  ///
  /// Давление — сколько ещё не виданных костей подходит к новым концам. Чем
  /// меньше таких костей, тем вероятнее, что соперник не сможет походить.
  /// Когда базар пуст, блокировать особенно выгодно: взять кость негде.
  static int _hardScore(GameState state, DominoMove move) {
    final rest = _restOfHand(state, move.tile);
    final board = state.board.place(move.tile, move.side);
    final options = rest.where(board.canPlace).length;
    final pressure = _pressure(board, unseenPips(state));
    final blocked = state.bazaarCount == 0 ? 2 : 1;
    final stuck = rest.isNotEmpty && options == 0 && state.bazaarCount == 0
        ? -400
        : 0;
    final finish = rest.isEmpty ? 10000 : 0;
    return finish +
        stuck -
        pressure * 12 * blocked +
        options * 8 +
        move.tile.weight * 2;
  }

  /// Сколько невиданных костей подходит к концам доски.
  static int _pressure(Board board, List<int> unseen) {
    final left = board.leftEnd;
    final right = board.rightEnd;
    if (left == null || right == null) return 0;
    return left == right ? unseen[left] : unseen[left] + unseen[right];
  }

  /// Сколько невиданных костей содержит каждое число точек.
  ///
  /// Видно только то, что знает сам игрок: свою руку и стол. Кости соперников
  /// и базар считаются неизвестными, иначе компьютер просто подглядывал бы.
  static List<int> unseenPips(GameState state) {
    final known = <String>{
      for (final tile in state.handOf(state.turn)) tile.label,
      for (final tile in state.board.tiles) tile.label,
    };
    final counts = List<int>.filled(maxPip + 1, 0);
    for (final tile in fullDeck()) {
      if (known.contains(tile.label)) continue;
      counts[tile.a]++;
      if (tile.b != tile.a) counts[tile.b]++;
    }
    return counts;
  }

  static List<DominoTile> _restOfHand(GameState state, DominoTile played) => [
    for (final tile in state.handOf(state.turn))
      if (tile != played) tile,
  ];
}
