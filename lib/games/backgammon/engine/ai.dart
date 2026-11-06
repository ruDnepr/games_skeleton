/// ИИ коротких нард: три уровня сложности.
///
/// - [Difficulty.easy] — случайный допустимый ход: ребёнок часто выигрывает.
/// - [Difficulty.medium] — жадная эвристика: блоки, продвижение к дому,
///   безопасность шашек (не оставлять «голые» под боем).
/// - [Difficulty.hard] — ожидиминимакс глубины 2: после своего хода учитывает
///   вероятный ответ соперника (среднее по 21 броску), с тайм-лимитом и отходом
///   к эвристике, если время вышло.
///
/// ИИ вызывается после броска костей компьютера и возвращает готовый [Turn].
library;

import 'dart:math';

import 'model.dart';
import 'rules.dart';

/// Уровень сложности компьютера.
enum Difficulty { easy, medium, hard }

/// Подбирает ход за цвет, чья очередь в [state]. Кости уже брошены — они в
/// `state.rolled`. Возвращает [Turn] с этими костями и выбранными шагами
/// (возможно, пустыми, если ни одна кость не ходит).
class BackgammonAI {
  const BackgammonAI._();

  static Turn findBestTurn(
    GameState state, {
    Difficulty level = Difficulty.medium,
    Random? random,
    Duration timeLimit = const Duration(milliseconds: 1500),
  }) {
    final rng = random ?? Random();
    final dice = BackgammonRules.expandDice(state.rolled);
    final sequences = BackgammonRules.allTurnSequences(state, dice);
    if (sequences.isEmpty) {
      return Turn(player: state.turn, dice: state.rolled, moves: const []);
    }
    switch (level) {
      case Difficulty.easy:
        return _turn(state, sequences[rng.nextInt(sequences.length)]);
      case Difficulty.medium:
        return _turn(state, _bestByHeuristic(state, sequences, rng));
      case Difficulty.hard:
        return _turn(state, _expectiminimax(state, sequences, rng, timeLimit));
    }
  }

  static Turn _turn(GameState state, List<Move> moves) =>
      Turn(player: state.turn, dice: state.rolled, moves: moves);

  /// Лучшая последовательность по эвристике без заглядывания вперёд.
  static List<Move> _bestByHeuristic(
    GameState state,
    List<List<Move>> sequences,
    Random rng,
  ) {
    var best = sequences.first;
    var bestScore = -1e18;
    for (final seq in sequences) {
      var s = state.withRoll(state.rolled);
      for (final m in seq) {
        s = BackgammonRules.applyMove(s, m);
      }
      final score = evaluate(s.board, state.turn);
      // Лёгкий шум, чтобы одинаковые по эвристике ходы не выбирались всегда
      // одинаково — партия живая.
      final noisy = score + rng.nextDouble() * 0.01;
      if (noisy > bestScore) {
        bestScore = noisy;
        best = seq;
      }
    }
    return best;
  }

  /// Ожидиминимакс глубины 2: свой ход + средний ответ соперника по 21 броску.
  /// Ответ соперника жадный (по эвристике), иначе перебор взорвался бы. Тайм-
  /// лимит обрывает перебор; в этом случае возвращается лучший из досчитанных.
  static List<Move> _expectiminimax(
    GameState state,
    List<List<Move>> sequences,
    Random rng,
    Duration timeLimit,
  ) {
    final ai = state.turn;
    final watch = Stopwatch()..start();
    final Duration deadline = watch.elapsed + timeLimit;

    // Ограничим число кандидатов, чтобы уложиться во время на слабых телефонах:
    // возьмём топ-12 по эвристике и досчитаем риск по ответу соперника.
    final ranked = [...sequences]..sort((a, b) {
      final sa = _scoreAfter(state, a, ai);
      final sb = _scoreAfter(state, b, ai);
      return sb.compareTo(sa);
    });
    final candidates = ranked.take(12).toList();

    var best = candidates.first;
    var bestScore = -1e18;
    for (final seq in candidates) {
      if (watch.elapsed > deadline) break;
      var s1 = state.withRoll(state.rolled);
      for (final m in seq) {
        s1 = BackgammonRules.applyMove(s1, m);
      }
      if (s1.winner == ai) {
        return seq; // выигрыш — дальше искать незачем
      }
      final expected = _expectedOpponentValue(s1, ai, deadline, watch);
      final score = evaluate(s1.board, ai) - expected;
      if (score > bestScore) {
        bestScore = score;
        best = seq;
      }
    }
    return best;
  }

  /// Эвристика после применения последовательности, без учёта ответа.
  static double _scoreAfter(GameState state, List<Move> seq, Player ai) {
    var s = state.withRoll(state.rolled);
    for (final m in seq) {
      s = BackgammonRules.applyMove(s, m);
    }
    return evaluate(s.board, ai);
  }

  /// Средний ущерб, который соперник нанесёт из [state1] (ход уже за соперником):
  /// среднее по 21 броску лучшего жадного хода соперника, переведённое в потерю
  /// наших пунктов. Тайм-лимит обрывает перебор бросков досрочно.
  static double _expectedOpponentValue(
    GameState state1,
    Player ai,
    Duration deadline,
    Stopwatch watch,
  ) {
    final opp = ai.other;
    var sum = 0.0;
    var n = 0;
    for (final roll in _allRolls()) {
      if (watch.elapsed > deadline) {
        // Времени не хватило — оцениваем по оставшимся как нулевой ущерб, чтобы
        // не загрублять выбор в худшую сторону: лучше вернуть то, что есть.
        continue;
      }
      final raw =
          roll[0] == roll[1] ? [roll[0], roll[0]] : [roll[0], roll[1]];
      // Дубль даёт 4 хода — расширяем, иначе симуляция соперника сыграет
      // только 2 и недооценит его двойные броски.
      final dice = BackgammonRules.expandDice(raw);
      final s = state1.copyWith(turn: opp, rolled: const [], available: const []);
      final seqs = BackgammonRules.allTurnSequences(s.withRoll(raw), dice);
      if (seqs.isEmpty) {
        n++;
        continue;
      }
      var worstForAi = 1e18;
      for (final seq in seqs) {
        var after = s.withRoll(raw);
        for (final m in seq) {
          after = BackgammonRules.applyMove(after, m);
        }
        final v = evaluate(after.board, ai);
        if (v < worstForAi) worstForAi = v;
      }
      sum += worstForAi;
      n++;
    }
    if (n == 0) return 0;
    final expectedAfter = sum / n;
    return (evaluate(state1.board, ai) - expectedAfter).clamp(0.0, 1e9);
  }

  /// Все 21 равновозможные броски двух костей (дубль один раз).
  static List<List<int>> _allRolls() {
    final rolls = <List<int>>[];
    for (var a = 1; a <= 6; a++) {
      for (var b = a; b <= 6; b++) {
        rolls.add([a, b]);
      }
    }
    return rolls;
  }

  /// Эвристика позиции для [player]: чем больше, тем лучше. Учитывает «пипсы»
  /// (расстояние до выноса), вынос, бар соперника, сделанные пункты и риск
  /// одиночных шашек под боем.
  static double evaluate(Board board, Player player) {
    final opp = player.other;
    final myPip = _pip(board, player);
    final oppPip = _pip(board, opp);
    var score = (oppPip - myPip).toDouble();

    // Вынос — самое важное: каждая шашка ближе к победе.
    score += 35.0 * board.off(player);
    score -= 35.0 * board.off(opp);

    // Соперник на баре — ему приходится входить, мы выигрываем темп.
    score += 22.0 * board.bar(opp);
    score -= 18.0 * board.bar(player);

    // Сделанные пункты (две и более шашек) — опора и блок.
    for (var i = 0; i < 24; i++) {
      final mine = board.at(i, player);
      if (mine >= 2) {
        score += 4.0;
        // Пункты в своём доме и на полпути домой ценнее.
        if (player.homePoints.contains(i)) score += 3.0;
      }
    }

    // Одиночные шашки («блот») под боем — минус, пропорц. шансу удара.
    for (var i = 0; i < 24; i++) {
      if (board.at(i, player) == 1) {
        score -= _hitRisk(board, player, i);
      }
    }
    return score;
  }

  /// Сумма «пипсов»: сколько очков на костях нужно, чтобы привести все шашки
  /// домой и вынести. Меньше — лучше.
  static int _pip(Board board, Player player) {
    var pip = 0;
    for (var i = 0; i < 24; i++) {
      final count = board.at(i, player);
      if (count == 0) continue;
      pip += count * (player == Player.white ? i + 1 : 24 - i);
    }
    // Шашка на баре входит с самого дальнего пункта — 25 пипсов.
    pip += board.bar(player) * 25;
    return pip;
  }

  /// Оценка риска одиночной шашки на пункте [point]: сколько бросков соперника
  /// её выбивают. Простая аппроксимация: считаем число костей 1..6, которыми
  /// соперник может попасть на пункт с любой своей шашки или с бара.
  static double _hitRisk(Board board, Player player, int point) {
    final opp = player.other;
    var hits = 0;
    for (var die = 1; die <= 6; die++) {
      final from = opp == Player.white ? point + die : point - die;
      if (from >= 0 && from < 24 && board.at(from, opp) > 0) hits++;
      // С бара соперник тоже может войти сюда.
      final barDest = BackgammonRules.barEntry(opp, die);
      if (barDest == point && board.hasBar(opp)) hits++;
    }
    // 0..6 возможных ударных костей. Шанс удара растёт с их числом.
    return 1.0 + hits * 1.5;
  }
}
