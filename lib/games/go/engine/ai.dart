/// ИИ для го. Три уровня сложности:
///
/// * [Difficulty.easy] — случайные ходы, в режиме «Захват» иногда «не замечает»
///   простой захват, чтобы ребёнок мог выигрывать первые партии;
/// * [Difficulty.medium] — жадная эвристика: захватывает, защищает группы в
///   атари, держится формы;
/// * [Difficulty.hard] — MCTS с тайм-лимитом, осмысленно защищается и
///   захватывает.
///
/// Все вычисления чистые: контроллер сам решает, в каком потоке их запускать.
library;

import 'dart:math';
import 'dart:typed_data';

import 'model.dart';
import 'rules.dart';
import 'scoring.dart';

/// Уровень сложности ИИ.
enum Difficulty { easy, medium, hard }

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'Лёгкий',
        Difficulty.medium => 'Средний',
        Difficulty.hard => 'Сложный',
      };

  String get hint => switch (this) {
        Difficulty.easy => 'Учимся без спешки',
        Difficulty.medium => 'Защищается и захватывает',
        Difficulty.hard => 'Думает на 1–2 секунды вперёд',
      };
}

class GoAI {
  GoAI({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Лучший ход для текущего игрока. null — лучше пасовать (ходов нет).
  Point? findBestMove(
    GameState state,
    GoRules rules,
    Difficulty difficulty, {
    Duration? timeLimit,
  }) {
    if (rules.isOver(state)) return null;
    final legal = rules.legalPlacements(state);
    if (legal.isEmpty) return null;

    switch (difficulty) {
      case Difficulty.easy:
        return _easy(state, rules, legal);
      case Difficulty.medium:
        return _medium(state, rules, legal) ?? _easy(state, rules, legal);
      case Difficulty.hard:
        return MctsSearch(
          rules: rules,
          random: _random,
          timeLimit:
              timeLimit ?? const Duration(seconds: 1, milliseconds: 500),
        ).search(state, legal);
    }
  }

  // ---- Лёгкий уровень ----

  Point _easy(GameState state, GoRules rules, List<Point> legal) {
    final capturing =
        legal.where((p) => _captures(state, rules, p)).toList();
    final safe =
        legal.where((p) => !_selfAtari(state, rules, p)).toList();

    // В режиме «Захват» ИИ иногда «не замечает» доступный захват —
    // ребёнок получает шанс снять камень первым.
    final isCaptureMode = state.setup.mode == GoMode.capture;
    final missCapture = isCaptureMode &&
        capturing.isNotEmpty &&
        _random.nextDouble() < 0.55;

    if (missCapture) {
      final pool = safe.isNotEmpty ? safe : legal;
      return pool[_random.nextInt(pool.length)];
    }
    if (capturing.isNotEmpty && _random.nextDouble() < 0.7) {
      // Когда всё-таки «замечает», предпочитает захват.
      return capturing[_random.nextInt(capturing.length)];
    }
    final pool = safe.isNotEmpty ? safe : legal;
    return pool[_random.nextInt(pool.length)];
  }

  // ---- Средний уровень ----

  /// Жадная одноходовая эвристика: сначала захват, потом спасение своих
  /// групп в атари, потом ход, максимизирующий дыхания и уменьшающий
  /// дыхания соперника.
  Point? _medium(GameState state, GoRules rules, List<Point> legal) {
    // 1. Захватить, если можно.
    final capturing = legal
        .map((p) => MapEntry(p, _captureCount(state, rules, p)))
        .where((e) => e.value > 0)
        .toList();
    if (capturing.isNotEmpty) {
      capturing.sort((a, b) => b.value.compareTo(a.value));
      return capturing.first.key;
    }

    // 2. Спасать свою группу в атари — поставить камень, дающий дыхание.
    final myAtari = _groupsInAtari(state.board, state.turn);
    if (myAtari.isNotEmpty) {
      for (final group in myAtari) {
        final liberty = group.liberties.first;
        if (legal.contains(liberty)) {
          final newState = rules.applyKnownLegal(
            state,
            GoMove.place(liberty, color: state.turn),
          );
          final saved = GoRules.groupAt(newState.board, liberty);
          if (saved != null && saved.libertyCount > 1) {
            return liberty;
          }
        }
      }
    }

    // 3. Эвристика формы: максимум своих дыханий, минимум дыханий соперника,
    //    не ставить себя в атари.
    Point? best;
    var bestScore = double.negativeInfinity;
    for (final p in legal) {
      final score = _shapeScore(state, rules, p);
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return best;
  }

  int _captureCount(GameState state, GoRules rules, Point p) {
    final placement = GoRules.place(state.board, p, state.turn);
    return placement.captured.length;
  }

  bool _captures(GameState state, GoRules rules, Point p) =>
      _captureCount(state, rules, p) > 0;

  /// Ставит ли ход свой камень в атари (опасно — можно потерять).
  bool _selfAtari(GameState state, GoRules rules, Point p) {
    final placement = GoRules.place(state.board, p, state.turn);
    final group = GoRules.groupAt(placement.board, p);
    return group != null && group.libertyCount <= 1;
  }

  List<Group> _groupsInAtari(Board board, StoneColor color) {
    final result = <Group>[];
    final seen = <Point>{};
    for (final p in GoRules.allPoints(board.size)) {
      if (seen.contains(p) || board.at(p) != color) continue;
      final group = GoRules.groupAt(board, p)!;
      seen.addAll(group.stones);
      if (group.inAtari) result.add(group);
    }
    return result;
  }

  /// Оценка хода по форме: дыхания своей группы после хода минус
  /// потеря дыханий соперника, штраф за самоатари.
  double _shapeScore(GameState state, GoRules rules, Point p) {
    final placement = GoRules.place(state.board, p, state.turn);
    final ownGroup = GoRules.groupAt(placement.board, p);
    if (ownGroup == null) return -1000;
    var score = ownGroup.libertyCount.toDouble();

    // Штраф за самоатари.
    if (ownGroup.libertyCount <= 1) score -= 8;

    // Бонус за уменьшение дыханий соседних групп соперника.
    for (final n in p.neighbors()) {
      if (!n.inside(state.board.size)) continue;
      final before = GoRules.groupAt(state.board, n);
      final after = GoRules.groupAt(placement.board, n);
      if (before != null &&
          after != null &&
          before.stones.first == after.stones.first &&
          before.libertyCount > after.libertyCount) {
        score += (before.libertyCount - after.libertyCount).toDouble();
      }
    }

    // Лёгкое предпочтение звёздных точек и центральной зоны на раннем этапе.
    if (state.ply < 6) {
      final stars = state.board.starPoints();
      if (stars.contains(p)) score += 2;
    }
    return score;
  }
}

/// Monte Carlo Tree Search для сложного уровня ИИ.
///
/// UCB1-выбор, случайные rollout-ы до конца партии или лимита ходов,
/// оценка результата: в «Захвате» — по победителю/захватам, в классике —
/// по знаку разницы очков.
class MctsSearch {
  MctsSearch({
    required this.rules,
    required this.random,
    required this.timeLimit,
    this.rolloutCapFactor = 2,
  });

  final GoRules rules;
  final Random random;
  final Duration timeLimit;
  final int rolloutCapFactor;

  Point? search(GameState root, List<Point> rootLegal) {
    if (rootLegal.isEmpty) return null;
    final rootColor = root.turn;
    final root0 = _Node(state: root, parent: null, move: null);
    final sw = Stopwatch()..start();
    var iterations = 0;

    while (sw.elapsed < timeLimit && iterations < 20000) {
      iterations++;
      final leaf = _select(root0);
      final expanded = _expand(leaf);
      final reward = _simulate(expanded.state, rootColor);
      _backprop(expanded, reward);
    }

    // Выбираем самый посещаемый ребёнок корня.
    _Node? best;
    var bestVisits = -1;
    for (final child in root0.children) {
      if (child.visits > bestVisits) {
        bestVisits = child.visits;
        best = child;
      }
    }
    return best?.move;
  }

  _Node _select(_Node root) {
    var node = root;
    // Спускаемся, пока узел полностью раскрыт (нет неперебранных ходов)
    // и не терминальный — тогда выбираем ребёнка по UCB1.
    while (node.children.isNotEmpty &&
        (node.untried == null || node.untried!.isEmpty) &&
        !rules.isOver(node.state)) {
      node = _ucbSelect(node);
    }
    return node;
  }

  _Node _ucbSelect(_Node node) {
    const c = 1.4; // sqrt(2)
    _Node? best;
    var bestValue = double.negativeInfinity;
    for (final child in node.children) {
      if (child.visits == 0) continue;
      final exploit = child.reward / child.visits;
      final explore = c * sqrt((2 * log(node.visits)) / child.visits);
      final value = exploit + explore;
      if (value > bestValue) {
        bestValue = value;
        best = child;
      }
    }
    return best ?? node.children.first;
  }

  _Node _expand(_Node leaf) {
    if (rules.isOver(leaf.state)) return leaf;
    var untried = leaf.untried;
    if (untried == null) {
      final placements = rules.legalPlacements(leaf.state);
      // Пас — опция только для внутренних узлов (роллауты классики должны
      // доходить до двух пасов). Корень никогда не рекомендует пас: если
      // ходить некуда, findBestMove вернёт null, и контроллер сам пасует.
      if (leaf.parent == null || placements.isEmpty) {
        untried = <dynamic>[...placements];
      } else {
        untried = <dynamic>[...placements, _passSentinel];
      }
      leaf.untried = untried;
    }
    if (untried.isEmpty) return leaf;
    final move = untried.removeLast();
    final child = _applyMove(leaf, move);
    leaf.children.add(child);
    return child;
  }

  double _simulate(GameState state, StoneColor rootColor) {
    var current = state;
    final cap = current.board.size * current.board.size * rolloutCapFactor;
    var plies = 0;
    while (!rules.isOver(current) && plies < cap) {
      final move = _rolloutMove(current);
      current = rules.applyKnownLegal(current, move);
      plies++;
    }
    return _reward(current, rootColor);
  }

  GoMove _rolloutMove(GameState state) {
    final legal = rules.legalPlacements(state);
    if (legal.isEmpty) return GoMove.pass(color: state.turn);

    // Лёгкая политика: с малой вероятностью пасуем в классике —
    // так rollout быстрее доходит до двух пасов.
    if (state.setup.mode == GoMode.classic &&
        random.nextDouble() < 0.04 &&
        state.board.count(state.turn) > 0) {
      return GoMove.pass(color: state.turn);
    }

    // Предпочитаем захваты, если они есть — rollout осмысленнее.
    for (final p in legal) {
      final placement = GoRules.place(state.board, p, state.turn);
      if (placement.captured.isNotEmpty && random.nextDouble() < 0.7) {
        return GoMove.place(p, color: state.turn);
      }
    }
    final point = legal[random.nextInt(legal.length)];
    return GoMove.place(point, color: state.turn);
  }

  double _reward(GameState state, StoneColor rootColor) {
    if (state.setup.mode == GoMode.capture) {
      final target = state.setup.captureTarget.count;
      if (state.blackCaptured >= target) {
        return rootColor == StoneColor.black ? 1.0 : 0.0;
      }
      if (state.whiteCaptured >= target) {
        return rootColor == StoneColor.white ? 1.0 : 0.0;
      }
      final mine = rootColor == StoneColor.black
          ? state.blackCaptured
          : state.whiteCaptured;
      final theirs = rootColor == StoneColor.black
          ? state.whiteCaptured
          : state.blackCaptured;
      // Сглаженная оценка прогресса.
      return 0.5 + 0.5 * (mine - theirs) / (target * 2).clamp(1, 99);
    }

    // Классика: оценка по территории и пленным на момент остановки.
    final summary = TerritoryScorer.score(
      state.board,
      blackCaptured: state.blackCaptured,
      whiteCaptured: state.whiteCaptured,
      komi: state.setup.komi,
    );
    final diff = rootColor == StoneColor.black
        ? summary.blackScore - summary.whiteScore
        : summary.whiteScore - summary.blackScore;
    if (diff.abs() < 0.5) return 0.5;
    // Сигмоид — сглаживает уверенность.
    return 1.0 / (1.0 + exp(-diff / 6.0));
  }

  void _backprop(_Node node, double reward) {
    _Node? n = node;
    while (n != null) {
      n.visits++;
      n.reward += reward;
      n = n.parent;
    }
  }

  _Node _applyMove(_Node parent, dynamic move) {
    final state = move == _passSentinel
        ? rules.applyKnownLegal(
            parent.state, GoMove.pass(color: parent.state.turn))
        : rules.applyKnownLegal(
            parent.state,
            GoMove.place(move as Point, color: parent.state.turn),
          );
    return _Node(
      state: state,
      parent: parent,
      move: move == _passSentinel ? null : move as Point,
    );
  }
}

class _Node {
  _Node({required this.state, required this.parent, required this.move});

  final GameState state;
  final _Node? parent;
  final Point? move;

  final List<_Node> children = [];
  List<dynamic>? untried;
  int visits = 0;
  double reward = 0.0;
}

// Сентинел «пас» для очереди неперебранных ходов в узле.
final _passSentinel = Uint8List(0);
