/// Правила коротких нард, отделённые от интерфейса.
///
/// Класс без состояния: каждый метод принимает состояние и возвращает новое.
/// Так один и тот же код проверяет ход человека, ход ИИ и ход, пришедший по
/// сети, — расхождения быть не может. Подробные правила — в `rules.dart`
/// экрана правил; здесь — точная механика.
///
/// Соглашения о доске — в `model.dart`: белые идут к 0, чёрные к 23, дом белых
/// 0..5, дом чёрных 18..23.
library;

import 'model.dart';
// Отдельный импорт под префиксом — чтобы статический метод expandDice мог
// вызвать функцию модели expandDice, не уходя в бесконечную рекурсию.
import 'model.dart' as model;

/// Бесстатусные правила коротких нард.
class BackgammonRules {
  const BackgammonRules._();

  /// Сколько ходов даёт бросок. Дубль — четыре движения одной кости.
  /// Делегирует в функцию модели model.expandDice — единое место расширения
  /// для withRoll. Префикс обязателен: иначе имя разрешается в этот же
  /// статический метод (бесконечная рекурсия).
  static List<int> expandDice(List<int> rolled) {
    if (rolled.length != 2) {
      throw ArgumentError.value(rolled, 'rolled', 'нужно две кости');
    }
    return model.expandDice(rolled);
  }

  /// Пункт, в который шашка с бара входит костью [die]. Белые входят в дом
  /// чёрных (18..23), чёрные — в дом белых (0..5).
  static int barEntry(Player player, int die) {
    if (die < 1 || die > 6) {
      throw ArgumentError.value(die, 'die', 'кость 1..6');
    }
    return player == Player.white ? 24 - die : die - 1;
  }

  /// Все 15 шашек цвета в доме и ни одной на баре — можно выносить.
  static bool canBearOff(Board board, Player player) {
    if (board.hasBar(player)) return false;
    for (var i = 0; i < 24; i++) {
      if (board.at(i, player) == 0) continue;
      if (!player.homePoints.contains(i)) return false;
    }
    return true;
  }

  /// Самый дальний от выноса пункт цвета в его доме. Для белых это наибольший
  /// индекс (вынос ниже 0), для чёрных — наименьший (вынос выше 23). Нужен для
  /// правила «лишняя кость выносит самую дальнюю шашку».
  static int? furthestFromOff(Board board, Player player) {
    if (player == Player.white) {
      for (var i = 5; i >= 0; i--) {
        if (board.at(i, player) > 0) return i;
      }
    } else {
      for (var i = 18; i <= 23; i++) {
        if (board.at(i, player) > 0) return i;
      }
    }
    return null;
  }

  /// Можно ли вынести шашку с пункта [point] костью [die].
  static bool canBearOffFrom(Board board, Player player, int point, int die) {
    if (!canBearOff(board, player)) return false;
    if (!player.homePoints.contains(point)) return false;
    if (board.at(point, player) == 0) return false;
    final exact = player == Player.white ? die == point + 1 : die == 24 - point;
    if (exact) return true;
    // Лишняя кость выносит только самую дальнюю шашку.
    final overshoots =
        player == Player.white ? die > point + 1 : die > 24 - point;
    if (!overshoots) return false;
    return furthestFromOff(board, player) == point;
  }

  /// Все легальные шаги одной костью [die] из состояния [state]. Учитывают бар
  /// (с бара ходят только входом) и вынос. Шаги уникальны по (откуда, куда).
  ///
  /// В длинных нардах чужой пункт блокирует ход даже с одной шашкой —
  /// выбивания нет. В коротких одиночную чужую шашку можно выбить.
  static List<Move> movesForDie(GameState state, int die) {
    final player = state.turn;
    final board = state.board;
    if (state.winner != null) return const [];
    if (die < 1 || die > 6) return const [];

    // Длинные нарды: на чужой пункт (даже с одной шашкой) вставать нельзя.
    final isLong = state.variant == BackgammonVariant.long;
    bool canLand(int point) => isLong
        ? board.opponentAt(point, player) == 0
        : board.opponentAt(point, player) <= 1;

    final moves = <Move>{}; // дедупликация по (from, to)
    void add(Move m) => moves.add(m);

    if (board.hasBar(player)) {
      final dest = barEntry(player, die);
      if (dest >= 0 && dest < 24 && canLand(dest)) {
        add(Move(player: player, die: die, from: null, to: dest));
      }
      return moves.toList();
    }

    for (var p = 0; p < 24; p++) {
      if (board.at(p, player) == 0) continue;
      final dest = p + player.direction * die;
      // Обычный ход внутри доски.
      if (dest >= 0 && dest < 24 && canLand(dest)) {
        add(Move(player: player, die: die, from: p, to: dest));
      }
      // Вынос — отдельная возможность, если все шашки дома.
      if (canBearOffFrom(board, player, p, die)) {
        add(Move(player: player, die: die, from: p, to: null));
      }
    }
    return moves.toList();
  }

  /// Все легальные шаги любой из доступных костей. Для подсветки на доске.
  static List<Move> allMoves(GameState state) {
    final seen = <Move>{};
    for (final die in state.available) {
      for (final move in movesForDie(state, die)) {
        seen.add(move);
      }
    }
    return seen.toList();
  }

  /// Легален ли одиночный шаг в текущем состоянии. Проверяет и бар-приоритет,
  /// и наличие кости, и блок, и условия выноса.
  static bool isLegal(GameState state, Move move) {
    if (state.winner != null) return false;
    if (move.player != state.turn) return false;
    if (move.die < 1 || move.die > 6) return false;
    if (!state.available.contains(move.die)) return false;
    return movesForDie(state, move.die).any((m) => _sameMove(m, move));
  }

  static bool _sameMove(Move a, Move b) =>
      a.from == b.from && a.to == b.to && a.die == b.die;

  /// Применяет один шаг к доске и возвращает новую доску. Предполагает, что шаг
  /// легален. Состояние (чей ход, кости) здесь не меняется — только доска.
  static Board applyMoveToBoard(Board board, Move move) {
    final player = move.player;
    final points = List<int>.of(board.points);
    var whiteBar = board.whiteBar;
    var blackBar = board.blackBar;
    var whiteOff = board.whiteOff;
    var blackOff = board.blackOff;

    if (move.fromBar) {
      if (player == Player.white) {
        whiteBar -= 1;
      } else {
        blackBar -= 1;
      }
    } else {
      final from = move.from!;
      if (board.at(from, player) == 0) {
        throw StateError('нет шашки на пункте $from');
      }
      points[from] += player == Player.white ? -1 : 1;
    }

    if (move.bearOff) {
      if (player == Player.white) {
        whiteOff += 1;
      } else {
        blackOff += 1;
      }
    } else {
      final dest = move.to!;
      // Выбивание одиночной чужой шашки — она уходит на бар.
      if (board.opponentAt(dest, player) == 1) {
        if (player == Player.white) {
          blackBar += 1;
        } else {
          whiteBar += 1;
        }
        points[dest] = 0;
      }
      points[dest] += player == Player.white ? 1 : -1;
    }
    return Board(
      points: points,
      whiteBar: whiteBar,
      blackBar: blackBar,
      whiteOff: whiteOff,
      blackOff: blackOff,
    );
  }

  /// Применяет один шаг к состоянию: обновляет доску, убирает кость из
  /// доступных, фиксирует победителя, если вынесена 15-я шашка. Чей ход — не
  /// меняет: ход заканчивается отдельно, через [endTurn].
  static GameState applyMove(GameState state, Move move) {
    if (!isLegal(state, move)) {
      throw StateError('нелегальный ход: $move');
    }
    final board = applyMoveToBoard(state.board, move);
    final remaining = List<int>.of(state.available);
    remaining.remove(move.die);
    Player? winner;
    if (board.off(move.player) >= 15) winner = move.player;
    return state.copyWith(
      board: board,
      available: remaining,
      winner: winner,
    );
  }

  /// Заканчивает ход: передаёт очередь сопернику и стирает кости. Победитель
  /// остаётся, если уже есть.
  static GameState endTurn(GameState state) {
    if (state.winner != null) return state;
    return state.withTurn(state.turn.other);
  }

  /// Прогрывает целый ход [turn] из состояния [state] и возвращает новое.
  /// Бросает [FormatException], если кости не совпадают с объявленными или
  /// хоть один шаг нелегален. Так сеть проверяет пришедший ход одним вызовом.
  static GameState applyTurn(GameState state, Turn turn) {
    if (turn.player != state.turn) {
      throw const FormatException('Ход не распознан: не твой цвет');
    }
    if (!_diceMatch(turn.dice, state.rolled)) {
      throw const FormatException('Ход не распознан: кости не те');
    }
    var current = state.withRoll(turn.dice);
    for (final move in turn.moves) {
      if (!isLegal(current, move)) {
        throw FormatException('Ход не распознан: $move');
      }
      current = applyMove(current, move);
    }
    if (current.winner != null) return current;
    return endTurn(current);
  }

  /// Можно ли сыграть хоть одну кость из [dice] в состоянии [state].
  static bool canPlayAny(GameState state, List<int> dice) {
    for (final die in dice) {
      if (movesForDie(state, die).isNotEmpty) return true;
    }
    return false;
  }

  /// Все максимальные последовательности шагов на брошенные кости [dice]:
  /// перебирает порядок костей и выбор шашек. «Максимальные» — продолжать
  /// нельзя ни одной костью. Нужно ИИ и для проверки, что ход использует все
  /// playable кости. Дубликаты по итоговой доске убраны.
  static List<List<Move>> allTurnSequences(GameState state, List<int> dice) {
    final results = <List<Move>>[];
    _recurse(state, List<int>.of(dice), <Move>[], results);
    if (results.isEmpty) return const [];
    final maxLen =
        results.fold<int>(0, (m, seq) => seq.length > m ? seq.length : m);
    final maximal = results.where((seq) => seq.length == maxLen).toList();
    // Дедупликация по итоговой доске.
    final seen = <Board>{};
    final unique = <List<Move>>[];
    for (final seq in maximal) {
      var s = state.withRoll(dice);
      for (final m in seq) {
        s = applyMove(s, m);
      }
      if (seen.add(s.board)) unique.add(seq);
    }
    return unique;
  }

  static void _recurse(
    GameState state,
    List<int> remaining,
    List<Move> current,
    List<List<Move>> results,
  ) {
    var extended = false;
    // Перебираем уникальные значения костей, чтобы не дублировать одинаковые.
    for (final die in {...remaining}) {
      for (final move in movesForDie(state, die)) {
        final next = applyMove(state, move);
        final nextRemaining = List<int>.of(remaining);
        nextRemaining.remove(die);
        final nextCurrent = List<Move>.of(current)..add(move);
        extended = true;
        _recurse(next, nextRemaining, nextCurrent, results);
      }
    }
    if (!extended) {
      results.add(List<Move>.of(current));
    }
  }

  /// Победитель партии, если кто-то вынес 15 шашек.
  static Player? winner(Board board) {
    if (board.whiteOff >= 15) return Player.white;
    if (board.blackOff >= 15) return Player.black;
    return null;
  }

  static bool _diceMatch(List<int> a, List<int> b) {
    if (a.length != 2 || b.length != 2) return false;
    final ca = List<int>.of(a)..sort();
    final cb = List<int>.of(b)..sort();
    return ca[0] == cb[0] && ca[1] == cb[1];
  }
}
