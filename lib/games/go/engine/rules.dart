/// Ядро правил го: группы, дыхания, захват, запрет самоубийства, правило ко.
///
/// Механика хода одинакова для обоих режимов — «Захват» и «Классическое го»
/// отличаются только условием победы и подсчётом очков. Поэтому ядро живёт
/// в абстрактном [GoRules] как готовые методы, а режимы переопределяют лишь
/// [isOver], [winner] и подсчёт.
library;

import 'model.dart';
import 'scoring.dart';

/// Результат применения хода: новое состояние и снятые камни.
class MoveResult {
  const MoveResult(this.state, {this.captured = const []});
  final GameState state;
  final List<Point> captured;
}

/// Базовые правила го. Подклассы ([CaptureGoRules], [ClassicGoRules]) задают
/// лишь условие победы и подсчёт очков; механика хода общая.
abstract class GoRules {
  GoRules(this.setup);
  final GameSetup setup;

  /// Поднять группу одного цвета, содержащую точку [start].
  /// Возвращает null, если точка пустая.
  static Group? groupAt(Board board, Point start) {
    final color = board.at(start);
    if (color == null) return null;
    final stones = <Point>{};
    final liberties = <Point>{};
    final queue = <Point>[start];
    stones.add(start);
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      for (final n in p.neighbors()) {
        if (!n.inside(board.size)) continue;
        final neighborColor = board.at(n);
        if (neighborColor == null) {
          liberties.add(n);
        } else if (neighborColor == color && !stones.contains(n)) {
          stones.add(n);
          queue.add(n);
        }
      }
    }
    return Group(stones: stones, liberties: liberties);
  }

  /// Все пересечения доски размера [size] — для перебора в правилах и ИИ.
  static List<Point> allPoints(int size) {
    final result = <Point>[];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        result.add(Point(x, y));
      }
    }
    return result;
  }

  /// Допустимый ли ход по механике го (захват, самоубийство, ко).
  bool isValidMove(GameState state, GoMove move);

  /// Все допустимые ходы-постановки (без паса) для текущего игрока.
  /// Пас всегда допустим, поэтому здесь не возвращается.
  List<Point> legalPlacements(GameState state);

  /// Применить ход и вернуть новое состояние. Бросает [StateError],
  /// если ход недопустим.
  GameState applyMove(GameState state, GoMove move) {
    if (!isValidMove(state, move)) {
      throw StateError('Недопустимый ход: $move');
    }
    return applyKnownLegal(state, move);
  }

  /// Применить заведомо допустимый ход — без повторной проверки.
  GameState applyKnownLegal(GameState state, GoMove move) {
    if (move.isPass) return passKnownLegal(state);
    return placeKnownLegal(state, move.point!);
  }

  /// Закончилась ли партия.
  bool isOver(GameState state);

  /// Победитель (null — пока не ясно или ничья).
  StoneColor? winner(GameState state);

  /// Подсчёт очков для классического режима. Для «Захвата» возвращает null.
  ScoreSummary? score(GameState state) => null;

  // ---- общая механика ----

  /// Поставить камень [color] в точку [point] на доске [state.board] и снять
  /// пленённые группы соперника. Возвращает промежуточную доску и список снятых.
  /// НЕ проверяет самоубийство и ко — это делает [isValidMove].
  static ({Board board, List<Point> captured}) place(
    Board board,
    Point point,
    StoneColor color,
  ) {
    final withStone = board.withStone(point, color);
    final opponent = color.opponent;
    final captured = <Point>[];
    // Проверяем только соседние группы соперника — дальние не меняются.
    for (final n in point.neighbors()) {
      if (!n.inside(board.size)) continue;
      if (withStone.at(n) != opponent) continue;
      final group = groupAt(withStone, n);
      if (group != null && group.isCaptured) {
        captured.addAll(group.stones);
      }
    }
    final afterCapture =
        captured.isEmpty ? withStone : withStone.without(captured);
    return (board: afterCapture, captured: captured);
  }

  /// Вычисляет новую запрещённую точку ко после хода.
  /// Классическое ко: если ход снял ровно один камень, а поставленная группа
  /// оказалась в атари (одно дыхание) — соперник не может немедленно снять
  /// наш камень обратно. Иначе ко нет.
  static Point? nextKo(
    Board before,
    Board after,
    Point point,
    StoneColor color,
    List<Point> captured,
  ) {
    if (captured.length != 1) return null;
    final group = groupAt(after, point);
    if (group == null || group.libertyCount != 1) return null;
    // Единственное дыхание должно быть той точкой, где стоял снятый камень,
    // иначе это не классическая форма ко.
    if (!group.liberties.contains(captured.first)) return null;
    return captured.first;
  }

  /// Применяет ход-постановку к проверенному состоянию.
  GameState placeKnownLegal(GameState state, Point point) {
    final color = state.turn;
    final placement = place(state.board, point, color);
    final captured = placement.captured;
    final newBoard = placement.board;
    // Самоубийство уже отсечено в isValidMove, но для надёжности проверим снова.
    final ownGroup = groupAt(newBoard, point);
    if (ownGroup != null && ownGroup.isCaptured) {
      throw StateError('Самоубийственный ход в $point');
    }
    final ko = nextKo(state.board, newBoard, point, color, captured);
    final nextTurn = color.opponent;
    final blackCaptured = color == StoneColor.black
        ? state.blackCaptured + captured.length
        : state.blackCaptured;
    final whiteCaptured = color == StoneColor.white
        ? state.whiteCaptured + captured.length
        : state.whiteCaptured;
    return state.copyWith(
      board: newBoard,
      turn: nextTurn,
      ply: state.ply + 1,
      koPoint: ko,
      consecutivePasses: 0,
      blackCaptured: blackCaptured,
      whiteCaptured: whiteCaptured,
      lastMove: GoMove.place(point, color: color),
      lastCaptured: List.unmodifiable(captured),
    );
  }

  /// Применяет пас к проверенному состоянию.
  GameState passKnownLegal(GameState state) {
    final move = GoMove.pass(color: state.turn);
    return state.copyWith(
      turn: state.turn.opponent,
      ply: state.ply + 1,
      koPoint: null,
      consecutivePasses: state.consecutivePasses + 1,
      lastMove: move,
      lastCaptured: const [],
    );
  }
}

/// Режим «Захват» (Capture Go) — упрощённые правила для первых партий.
///
/// Цель: первым снять заданное число камней соперника (1 или 3).
/// Территория и очки не считаются. Механика хода — как в классическом го:
/// захват групп без дыханий, запрет самоубийства, правило ко.
class CaptureGoRules extends GoRules {
  CaptureGoRules(GameSetup setup) : super(setup) {
    if (setup.mode != GoMode.capture) {
      throw ArgumentError('CaptureGoRules требует режим capture');
    }
  }

  int get target => setup.captureTarget.count;

  @override
  bool isValidMove(GameState state, GoMove move) {
    if (isOver(state)) return false;
    if (move.color != state.turn) return false;
    if (move.isPass) return true;
    final p = move.point!;
    if (!p.inside(state.board.size) || state.board.occupied(p)) return false;
    if (p == state.koPoint) return false;
    return !isSuicide(state.board, p, state.turn);
  }

  @override
  List<Point> legalPlacements(GameState state) {
    if (isOver(state)) return const [];
    final result = <Point>[];
    for (final p in GoRules.allPoints(state.board.size)) {
      if (state.board.occupied(p)) continue;
      if (p == state.koPoint) continue;
      if (isSuicide(state.board, p, state.turn)) continue;
      result.add(p);
    }
    return result;
  }

  /// Проверяет, является ли постановка камня в [point] самоубийством:
  /// после снятия пленённых групп соперника у своей группы нет дыханий.
  static bool isSuicide(Board board, Point point, StoneColor color) {
    final placement = GoRules.place(board, point, color);
    final group = GoRules.groupAt(placement.board, point);
    return group == null || group.isCaptured;
  }

  @override
  bool isOver(GameState state) =>
      state.blackCaptured >= target || state.whiteCaptured >= target;

  @override
  StoneColor? winner(GameState state) {
    if (state.blackCaptured >= target) return StoneColor.black;
    if (state.whiteCaptured >= target) return StoneColor.white;
    return null;
  }
}

/// Режим «Классическое го» — территория и очки.
///
/// Партия заканчивается после двух пасов подряд. Подсчёт — упрощённый
/// японский: территория + пленники + коми белым. Мёртвые камни определяются
/// автоматической эвристикой (см. [TerritoryScorer] в `scoring.dart`).
class ClassicGoRules extends GoRules {
  ClassicGoRules(GameSetup setup) : super(setup) {
    if (setup.mode != GoMode.classic) {
      throw ArgumentError('ClassicGoRules требует режим classic');
    }
  }

  @override
  bool isValidMove(GameState state, GoMove move) {
    if (isOver(state)) return false;
    if (move.color != state.turn) return false;
    if (move.isPass) return true;
    final p = move.point!;
    if (!p.inside(state.board.size) || state.board.occupied(p)) return false;
    if (p == state.koPoint) return false;
    return !CaptureGoRules.isSuicide(state.board, p, state.turn);
  }

  @override
  List<Point> legalPlacements(GameState state) {
    if (isOver(state)) return const [];
    final result = <Point>[];
    for (final p in GoRules.allPoints(state.board.size)) {
      if (state.board.occupied(p)) continue;
      if (p == state.koPoint) continue;
      if (CaptureGoRules.isSuicide(state.board, p, state.turn)) continue;
      result.add(p);
    }
    return result;
  }

  @override
  bool isOver(GameState state) => state.consecutivePasses >= 2;

  @override
  StoneColor? winner(GameState state) {
    if (!isOver(state)) return null;
    final s = score(state);
    if (s == null) return null;
    return s.leader;
  }

  @override
  ScoreSummary? score(GameState state) {
    if (!isOver(state)) return null;
    return TerritoryScorer.score(
      state.board,
      blackCaptured: state.blackCaptured,
      whiteCaptured: state.whiteCaptured,
      komi: setup.komi,
    );
  }
}
