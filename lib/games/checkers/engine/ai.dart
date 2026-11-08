/// ИИ шашек: три уровня сложности.
///
/// - [Difficulty.easy] — глубина 1, материал без позиции: часто зевает, ребёнок
///   регулярно выигрывает.
/// - [Difficulty.medium] — глубина 3, материал плюс лёгкая позиционная оценка.
/// - [Difficulty.hard] — глубина 5, тот же оценщик, но видит дальше.
///
/// Минимакс с альфа-бета отсечением по полным ходам; листья продлеваются
/// взятиями (quiescence), чтобы оценка не обрывалась на полуобмене.
library;

import 'dart:math';

import 'model.dart';
import 'rules.dart';

/// Уровень сложности компьютера.
enum Difficulty { easy, medium, hard }

extension DifficultyDetails on Difficulty {
  /// Подпись для интерфейса.
  String get label => switch (this) {
    Difficulty.easy => 'Лёгкий',
    Difficulty.medium => 'Средний',
    Difficulty.hard => 'Сложный',
  };

  /// Глубина поиска в полуходах. На лёгком уровне — только свой ход с
  /// материальной оценкой, поэтому ИИ зевает как новичок и остаётся победимым.
  int get depth => switch (this) {
    Difficulty.easy => 1,
    Difficulty.medium => 3,
    Difficulty.hard => 5,
  };

  /// Минимальная эвристика: только материал, без позиции.
  bool get materialOnly => this == Difficulty.easy;
}

/// Бросается, когда проход поиска не уложился в бюджет узлов.
///
/// Проход отбрасывается, ответ предыдущего, более дешёвого прохода остаётся.
/// Иначе дерево, обрезанное посередине, ошибочно считалось бы законченным:
/// листья оценивались бы сразу после своего хода, ответ соперника
/// игнорировался, и движок спокойно отдавал бы шашки.
class _SearchAborted implements Exception {
  const _SearchAborted();
}

/// Минимакс по полным ходам с альфа-бета отсечением.
///
/// Поиск углубляется по одному полуходу и сохраняет результат последнего
/// **законченного** прохода. Проход, упёршийся в [nodeBudget], отбрасывается,
/// поэтому ответ всегда честно-глубокий. Листья продлеваются ходами-взятиями
/// ([quiescencePlies]), чтобы оценка не обрывалась на полуобмене, где шашка
/// уже под боем.
class CheckersAI {
  CheckersAI({
    Random? random,
    this.nodeBudget = 50000,
    this.quiescencePlies = 3,
  }) : _random = random ?? Random();
  final Random _random;
  final int nodeBudget;

  /// Дополнительные полуходы только-взятий в листьях.
  final int quiescencePlies;
  int _nodes = 0;

  /// Глубина последнего полностью законченного прохода.
  int lastDepth = 0;

  Move? findBestMove(
    GameState state,
    int depth, {
    bool easyNoise = false,
    bool materialOnly = false,
  }) {
    if (depth < 1) throw ArgumentError.value(depth, 'depth');
    lastDepth = 0;
    Move? best;
    for (var pass = 1; pass <= depth; pass++) {
      try {
        final move = _searchRoot(state, pass, easyNoise, materialOnly);
        if (move == null) return null;
        best = move;
        lastDepth = pass;
      } on _SearchAborted {
        // Сохраняем ответ последнего законченного прохода и не углубляемся:
        // следующий проход больше и тоже будет обрезан.
        break;
      }
    }
    // Не уложился даже первый проход (огромная доска или крошечный бюджет в
    // тесте). Запасной ход всё ещё безопасен: смотрит на каждый легальный ход
    // и на каждый ответ соперника, поэтому не порекомендует просто так отдать
    // шашку.
    return best ?? _safeMove(state, materialOnly);
  }

  /// Два полухода без бюджета: худший ответ соперника на каждый свой ход.
  /// Дёшево, ограничено и не слепо к немедленному взятию.
  Move? _safeMove(GameState state, bool materialOnly) {
    final rules = GameRules.forVariant(state.variant) as StandardRules;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty) return null;
    final root = state.turn;
    var best = legal.first;
    var bestScore = double.negativeInfinity;
    for (final move in _ordered(legal)) {
      final after = rules.applyKnownLegal(state, move);
      final replies = rules.legalMoves(after);
      if (replies.isEmpty || after.board.count(after.turn) == 0) {
        final score = _endScore(after, root, 0);
        if (score > bestScore) {
          bestScore = score;
          best = move;
        }
        continue;
      }
      var score = double.infinity;
      for (final reply in replies) {
        score = min(
          score,
          _evaluate(rules.applyKnownLegal(after, reply), root, materialOnly),
        );
      }
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
    }
    return best;
  }

  Move? _searchRoot(
    GameState state,
    int depth,
    bool easyNoise,
    bool materialOnly,
  ) {
    _nodes = 0;
    final rules = GameRules.forVariant(state.variant) as StandardRules;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty) return null;
    final root = state.turn;
    var bestScore = double.negativeInfinity;
    var best = legal.first;
    var alpha = double.negativeInfinity;
    for (final move in _ordered(legal)) {
      final next = rules.applyKnownLegal(state, move);
      var score = _search(
        next,
        rules,
        depth - 1,
        alpha,
        double.infinity,
        root,
        materialOnly,
      );
      // Лёгкое разнообразие касается только лёгкого уровня, не подсказки.
      if (easyNoise && score.abs() < 100000) {
        score += (_random.nextDouble() - 0.5) * 0.5;
      }
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
      if (score > alpha) alpha = score;
    }
    return best;
  }

  double _search(
    GameState state,
    StandardRules rules,
    int depth,
    double alpha,
    double beta,
    Side root,
    bool materialOnly,
  ) {
    _visit();
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      return _endScore(state, root, depth);
    }
    if (depth == 0) {
      return _quiesce(
        state,
        rules,
        alpha,
        beta,
        root,
        materialOnly,
        quiescencePlies,
      );
    }
    final maximizing = state.turn == root;
    var best = maximizing ? double.negativeInfinity : double.infinity;
    for (final move in _ordered(legal)) {
      final value = _search(
        rules.applyKnownLegal(state, move),
        rules,
        depth - 1,
        alpha,
        beta,
        root,
        materialOnly,
      );
      if (maximizing) {
        best = max(best, value);
        alpha = max(alpha, best);
      } else {
        best = min(best, value);
        beta = min(beta, best);
      }
      if (beta <= alpha) break;
    }
    return best;
  }

  /// Проигрывает доступные в листе взятия. Взятие обязательно в любом варианте,
  /// поэтому тихая оценка такой позиции была бы просто неверной: шашка уже
  /// фактически взята.
  double _quiesce(
    GameState state,
    StandardRules rules,
    double alpha,
    double beta,
    Side root,
    bool materialOnly,
    int plies,
  ) {
    _visit();
    final legal = rules.legalMoves(state);
    if (legal.isEmpty || state.board.count(state.turn) == 0) {
      return _endScore(state, root, 0);
    }
    final captures = [
      for (final move in legal)
        if (move.isCapture) move,
    ];
    if (plies <= 0 || captures.isEmpty) {
      return _evaluate(state, root, materialOnly);
    }
    final maximizing = state.turn == root;
    var best = maximizing ? double.negativeInfinity : double.infinity;
    for (final move in captures) {
      final value = _quiesce(
        rules.applyKnownLegal(state, move),
        rules,
        alpha,
        beta,
        root,
        materialOnly,
        plies - 1,
      );
      if (maximizing) {
        best = max(best, value);
        alpha = max(alpha, best);
      } else {
        best = min(best, value);
        beta = min(beta, best);
      }
      if (beta <= alpha) break;
    }
    return best;
  }

  void _visit() {
    _nodes++;
    if (_nodes >= nodeBudget) throw const _SearchAborted();
  }

  double _endScore(GameState state, Side root, int depth) {
    final winner =
        state.variant.reverseGoal ? state.turn : state.turn.opponent;
    return winner == root ? 1000000.0 + depth : -1000000.0 - depth;
  }

  List<Move> _ordered(List<Move> moves) =>
      [...moves]
        ..sort((a, b) => b.captures.length.compareTo(a.captures.length));

  double _evaluate(GameState state, Side root, bool materialOnly) {
    var value = 0.0;
    final size = state.board.size;
    for (final entry in state.board.pieces.entries) {
      final piece = entry.value;
      final square = entry.key;
      final progress = piece.side == Side.white
          ? size - 1 - square.row
          : square.row;
      final double weight;
      if (materialOnly) {
        // Материал плюс лёгкий толчок к превращению, чтобы лёгкий ИИ всё же шёл
        // вперёд, а не топтался.
        weight = (piece.king ? 3 : 1) + (piece.king ? 0 : progress * 0.05);
      } else {
        final center =
            1 - ((square.col - (size - 1) / 2).abs() / (size / 2));
        final edgeSafety =
            (square.col == 0 || square.col == size - 1) ? 0.12 : 0.0;
        weight =
            (piece.king ? 3.1 : 1.0 + progress * 0.07) +
            center * 0.15 +
            edgeSafety;
      }
      value += piece.side == root ? weight : -weight;
    }
    return state.variant.reverseGoal ? -value : value;
  }
}
