/// Компьютерный соперник «Билета на поезд».
///
/// Три уровня сложности, как в остальных играх каркаса:
///
/// * лёгкий — случайное доступное действие. Ребёнок часто выигрывает.
/// * средний — старается занять маршруты, которые помогают его путешествиям,
///   иначе копит карты нужных цветов.
/// * сложный — к стратегии среднего добавляет блокировку: занимает маршруты,
///   которые нужны сопернику, и бережёт локомотивы для длинных линий.
///
/// Чистый Dart, без Flutter: ИИ работает в тестах и в сети так же, как в
/// партии на экране. Алгоритм не заглядывает в чужую руку — только в открытую
/// информацию: занятые маршруты, открытые карты и число карт у соперника.
library;

import 'dart:math';

import 'model.dart';
import 'rules.dart';

/// Уровень сложности компьютера.
enum Difficulty {
  easy('Лёгкий', 'Ходит первой попавшейся картой'),
  medium('Средний', 'Старается завершить свои путешествия'),
  hard('Сложный', 'Ещё и мешает твоим путешествиям');

  const Difficulty(this.label, this.hint);

  final String label;
  final String hint;
}

/// Подбирает одно действие для игрока [seat], чья очередь в [state].
/// Возвращает `null`, если доступных действий нет (такого почти не бывает —
/// взять карту обычно можно всегда).
class TicketToRideAI {
  const TicketToRideAI._();

  static const _rules = TicketToRideRules();

  static TtrAction? findBestAction(
    GameState state,
    int seat,
    Difficulty difficulty,
    Random random,
  ) {
    if (state.turn != seat) return null;
    final actions = _rules.availableActions(state, seat);
    if (actions.isEmpty) return null;
    return switch (difficulty) {
      Difficulty.easy => _easy(state, seat, actions, random),
      Difficulty.medium => _medium(state, seat, actions, random),
      Difficulty.hard => _hard(state, seat, actions, random),
    };
  }

  // ---- Лёгкий: случайное доступное действие --------------------------------

  static TtrAction _easy(
    GameState state,
    int seat,
    List<TtrAction> actions,
    Random random,
  ) {
    // В фазе выбора путешествий оставляем первое — так ребёнку понятнее, что
    // компьютер не «жадничает».
    if (state.phase == TtrPhase.choosingDestinations) {
      return TtrAction.keepDestinations([0]);
    }
    return actions[random.nextInt(actions.length)];
  }

  // ---- Средний: помогает своим путешествиям -------------------------------

  static TtrAction _medium(
    GameState state,
    int seat,
    List<TtrAction> actions,
    Random random,
  ) {
    switch (state.phase) {
      case TtrPhase.choosingDestinations:
        return _chooseDestinations(state, seat, preferUseful: true);
      case TtrPhase.drawSecond:
        return _secondDraw(state, seat, actions, random);
      case TtrPhase.main:
        return _mainAction(state, seat, actions, random, blockOpponent: false);
      case TtrPhase.over:
        return actions.first;
    }
  }

  // ---- Сложный: средний + блокировка соперника ----------------------------

  static TtrAction _hard(
    GameState state,
    int seat,
    List<TtrAction> actions,
    Random random,
  ) {
    switch (state.phase) {
      case TtrPhase.choosingDestinations:
        return _chooseDestinations(state, seat, preferUseful: true);
      case TtrPhase.drawSecond:
        return _secondDraw(state, seat, actions, random);
      case TtrPhase.main:
        return _mainAction(state, seat, actions, random, blockOpponent: true);
      case TtrPhase.over:
        return actions.first;
    }
  }

  // ---- Фаза main: выбрать действие ----------------------------------------

  static TtrAction _mainAction(
    GameState state,
    int seat,
    List<TtrAction> actions,
    Random random, {
    required bool blockOpponent,
  }) {
    final me = state.players[seat];
    final opponent = state.players[1 - seat];
    final myDests = me.destinations;
    final opponentDests = opponent.destinations;

    final claimActions = actions.where((a) => a.kind == 'claim').toList();
    if (claimActions.isNotEmpty) {
      var best = claimActions.first;
      var bestScore = -1e9;
      for (final action in claimActions) {
        final route = state.routes[action.routeIndex!];
        var score = route.length.toDouble();
        // Помощь своим путешествиям — высший приоритет.
        for (final dest in myDests) {
          if (_rules.isDestinationCompleted(state, seat, dest)) continue;
          if (route.cityA == dest.from || route.cityA == dest.to ||
              route.cityB == dest.from || route.cityB == dest.to) {
            score += 50;
          }
          // Маршрут «замыкает» путешествие — добавим ещё.
          if (_wouldComplete(state, seat, route, dest)) {
            score += 100;
          }
        }
        // Блокировка чужих путешествий — для сложного уровня.
        if (blockOpponent) {
          for (final dest in opponentDests) {
            if (_rules.isDestinationCompleted(state, 1 - seat, dest)) continue;
            if (route.cityA == dest.from || route.cityA == dest.to ||
                route.cityB == dest.from || route.cityB == dest.to) {
              score += 30;
            }
          }
        }
        // Локомотивы бережём на сложном уровне: за трату локомотива — штраф,
        // если маршрут не помогает путешествиям.
        final needsLoco = _needsLocomotives(me.hand, route);
        if (needsLoco) {
          score += blockOpponent ? -2 : -8;
        }
        // Небольшой шум, чтобы одинаковые ходы не выбирались всегда.
        score += random.nextDouble() * 0.5;
        if (score > bestScore) {
          bestScore = score;
          best = action;
        }
      }
      // Если лучший ход заметно полезнее нейтрального — занимаем.
      final bestRoute = state.routes[best.routeIndex!];
      if (bestScore > bestRoute.length.toDouble() + 25) {
        return best;
      }
    }

    // Иначе копим карты: сначала открытый цвет, потом колода, потом путешествия.
    final faceUp = _pickUsefulFaceUp(state, seat, actions);
    if (faceUp != null) return faceUp;
    // Если рука уже большая, а путешествий мало — тянем новые.
    if (me.hand.length >= 6 &&
        state.destinationDeck.isNotEmpty &&
        actions.any((a) => a.kind == 'drawDestinations')) {
      return const TtrAction.drawDestinations();
    }
    if (actions.any((a) => a.kind == 'drawDeck')) {
      return const TtrAction.drawDeck();
    }
    return actions.first;
  }

  /// Проверяет, замкнёт ли маршрут путешествие игрока, если он его займёт.
  static bool _wouldComplete(
    GameState state,
    int seat,
    Route candidate,
    Destination dest,
  ) {
    final routes = <Route>[
      for (final r in state.routes)
        if (r.claimedBy == seat) r,
      candidate,
    ];
    final graph = <City, Set<City>>{};
    for (final r in routes) {
      (graph[r.cityA] ??= <City>{}).add(r.cityB);
      (graph[r.cityB] ??= <City>{}).add(r.cityA);
    }
    final visited = <City>{dest.from};
    final queue = <City>[dest.from];
    while (queue.isNotEmpty) {
      final city = queue.removeAt(0);
      if (city == dest.to) return true;
      for (final next in graph[city] ?? const <City>[]) {
        if (visited.add(next)) queue.add(next);
      }
    }
    return false;
  }

  /// Потребуется ли локомотив для занятия маршрута: карт нужного цвета меньше,
  /// чем длина маршрута.
  static bool _needsLocomotives(List<TrainCard> hand, Route route) {
    final colorCount = hand.where((c) => c.color == route.color).length;
    return colorCount < route.length;
  }

  /// Выбирает открытую карту цвета, который нужен под незавершённые
  /// путешествия. Возвращает `null`, если такой карты нет.
  static TtrAction? _pickUsefulFaceUp(
    GameState state,
    int seat,
    List<TtrAction> actions,
  ) {
    final me = state.players[seat];
    final needed = <CardColor>{};
    for (final dest in me.destinations) {
      if (_rules.isDestinationCompleted(state, seat, dest)) continue;
      // Все цвета маршрутов, которые соединяют концы путешествия.
      for (final route in state.routes) {
        if (route.isClaimed) continue;
        if (route.cityA == dest.from || route.cityA == dest.to ||
            route.cityB == dest.from || route.cityB == dest.to) {
          needed.add(route.color);
        }
      }
    }
    if (needed.isEmpty) {
      // Нет активных путешествий — берём любую цветную карту.
      needed
        ..add(CardColor.red)
        ..add(CardColor.blue)
        ..add(CardColor.green);
    }
    for (final action in actions) {
      if (action.kind != 'drawFaceUp') continue;
      final card = state.faceUpCards[action.faceUpIndex!];
      if (card.color == CardColor.locomotive) continue;
      if (needed.contains(card.color)) return action;
    }
    // Нет полезной цветной — берём локомотив, если он открыт (это закончит ход,
    // но локомотив всегда пригодится).
    for (final action in actions) {
      if (action.kind != 'drawFaceUp') continue;
      final card = state.faceUpCards[action.faceUpIndex!];
      if (card.color == CardColor.locomotive) return action;
    }
    return null;
  }

  // ---- Фаза drawSecond: взять вторую карту --------------------------------

  static TtrAction _secondDraw(
    GameState state,
    int seat,
    List<TtrAction> actions,
    Random random,
  ) {
    // Локомотив во вторую карту брать нельзя — правила это запрещают, и действий
    // для него в списке нет. Берём полезный цвет, иначе колоду.
    final useful = _pickUsefulFaceUp(state, seat, actions);
    if (useful != null) return useful;
    if (actions.any((a) => a.kind == 'drawDeck')) {
      return const TtrAction.drawDeck();
    }
    return actions[random.nextInt(actions.length)];
  }

  // ---- Фаза choosingDestinations: оставить путешествия -------------------

  static TtrAction _chooseDestinations(
    GameState state,
    int seat, {
    required bool preferUseful,
  }) {
    final pending = state.pendingDestinations;
    if (pending.isEmpty) {
      return TtrAction.keepDestinations([0]);
    }
    if (!preferUseful) {
      return TtrAction.keepDestinations([0]);
    }
    // Оценим каждое путешествие: чем больше уже занятых маршрутов на пути —
    // тем легче завершить. Оставим лучшие.
    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < pending.length; i++) {
      final dest = pending[i];
      var score = dest.points.toDouble();
      // Сколько моих занятых маршрутов касается концов путешествия.
      for (final route in state.routes) {
        if (route.claimedBy != seat) continue;
        if (route.cityA == dest.from || route.cityA == dest.to ||
            route.cityB == dest.from || route.cityB == dest.to) {
          score += 10;
        }
      }
      // Сколько у меня карт подходящих цветов.
      for (final route in state.routes) {
        if (route.isClaimed) continue;
        if (route.cityA == dest.from || route.cityA == dest.to ||
            route.cityB == dest.from || route.cityB == dest.to) {
          final have = state.players[seat].hand
              .where((c) => c.color == route.color)
              .length;
          score += have * 1.5;
        }
      }
      scored.add(MapEntry(i, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    // Оставляем первое (лучшее), если оно одно. Если есть выбор — оставим
    // лучшие, когда у нас ещё много вагонов, иначе только одно.
    if (state.players[seat].trainsLeft >= 6 && scored.length >= 2) {
      return TtrAction.keepDestinations([scored[0].key, scored[1].key]);
    }
    return TtrAction.keepDestinations([scored[0].key]);
  }
}
