/// Правила «Билета на поезд»: раздача, занятие маршрута, взятие карт и
/// путешествий, подсчёт очков и конец партии.
///
/// Класс иммутабельный и без состояния — каждое правило возвращает новый снимок
/// `GameState`. Так историю для отмены можно хранить как список прошлых
/// состояний, а сетевая партия проверяет ход повторным применением правил к
/// своему состоянию. Все алгоритмы — без Flutter, чистый Dart: карты тасуются
/// функцией [Random], граф для путешествий обходится обычным BFS.
library;

import 'dart:math';

import 'board.dart';
import 'model.dart';

/// Бесстрановые правила «Билета на поезд». Один экземпляр — на всю партию;
/// состояние хранится в `GameState`, а не здесь.
class TicketToRideRules {
  const TicketToRideRules();

  // ---- Раздача -------------------------------------------------------------

  /// Готовит новую партию: тасует колоду, раздаёт карты и путешествия,
  /// выкладывает пять открытых карт. Ход у места 0 (хост/первый игрок).
  GameState newGame({Random? random, List<String>? playerNames}) {
    final rng = random ?? Random();
    final names = playerNames ?? const ['Игрок 1', 'Игрок 2'];
    final deck = _buildDeck()..shuffle(rng);
    final destinations = List<Destination>.of(allDestinations)..shuffle(rng);

    final hands = <List<TrainCard>>[
      <TrainCard>[for (var i = 0; i < startingCards; i++) deck.removeLast()],
      <TrainCard>[for (var i = 0; i < startingCards; i++) deck.removeLast()],
    ];
    final faceUp = <TrainCard>[
      for (var i = 0; i < faceUpCount && deck.isNotEmpty; i++) deck.removeLast(),
    ];
    final initialDestinations = <List<Destination>>[
      <Destination>[
        for (var i = 0; i < startingDestinations; i++)
          destinations.removeLast(),
      ],
      <Destination>[
        for (var i = 0; i < startingDestinations; i++)
          destinations.removeLast(),
      ],
    ];

    return GameState(
      players: [
        PlayerState(
          name: names[0],
          hand: hands[0],
          trainsLeft: startingTrains,
          destinations: initialDestinations[0],
          score: 0,
        ),
        PlayerState(
          name: names[1],
          hand: hands[1],
          trainsLeft: startingTrains,
          destinations: initialDestinations[1],
          score: 0,
        ),
      ],
      routes: allRoutes,
      faceUpCards: faceUp,
      deck: deck,
      destinationDeck: destinations,
      discardPile: const [],
      turn: 0,
      phase: TtrPhase.main,
    );
  }

  /// Собирает новую колоду по составу: 10 красных, 10 синих, 10 зелёных,
  /// 8 локомотивов. Порядок — детерминированный, тасование делает `newGame`.
  List<TrainCard> _buildDeck() {
    final cards = <TrainCard>[];
    deckComposition.forEach((color, count) {
      for (var i = 0; i < count; i++) {
        cards.add(TrainCard(color));
      }
    });
    return cards;
  }

  // ---- Занятие маршрута ----------------------------------------------------

  /// Можно ли занять маршрут [routeIndex] игроком [seat]: маршрут свободен,
  /// вагонов хватает, и подходящих карт хватает (цвет + локомотивы-джокеры).
  bool canClaimRoute(GameState state, int seat, int routeIndex) {
    if (state.phase != TtrPhase.main) return false;
    if (state.turn != seat) return false;
    if (routeIndex < 0 || routeIndex >= state.routes.length) return false;
    final route = state.routes[routeIndex];
    if (route.isClaimed) return false;
    final player = state.players[seat];
    if (player.trainsLeft < route.length) return false;
    final colorCount = player.hand.where((c) => c.color == route.color).length;
    final locoCount =
        player.hand.where((c) => c.color == CardColor.locomotive).length;
    return colorCount + locoCount >= route.length;
  }

  /// Занимает маршрут: списывает карты, ставит вагоны, начисляет очки и
  /// завершает ход. Бросает [StateError], если маршрут занять нельзя.
  GameState claimRoute(GameState state, int seat, int routeIndex) {
    if (!canClaimRoute(state, seat, routeIndex)) {
      throw StateError('Маршрут нельзя занять');
    }
    final route = state.routes[routeIndex];
    final player = state.players[seat];
    final split = _spendForRoute(player.hand, route);
    final newDiscard = [...state.discardPile, ...split.spent];
    final newRoutes = List<Route>.of(state.routes);
    newRoutes[routeIndex] = route.copyWith(claimedBy: seat);
    final newPlayers = List<PlayerState>.of(state.players);
    newPlayers[seat] = player.copyWith(
      hand: split.kept,
      trainsLeft: player.trainsLeft - route.length,
      score: player.score + route.points,
    );
    final next = state.copyWith(
      players: newPlayers,
      routes: newRoutes,
      discardPile: newDiscard,
    );
    return _endTurn(next);
  }

  /// Списывает с руки карты нужного цвета и локомотивы под маршрут. Сначала
  /// берём карты цвета маршрута, потом добиваем локомотивами. Возвращает пару
  /// «оставшиеся карты» и «потраченные карты» — порядок в обеих списках тот же,
  /// что и в исходной руке, без перемешивания.
  ({List<TrainCard> kept, List<TrainCard> spent}) _spendForRoute(
    List<TrainCard> hand,
    Route route,
  ) {
    final colorCount = hand.where((c) => c.color == route.color).length;
    final colorToSpend = colorCount >= route.length
        ? route.length
        : colorCount;
    final locoToSpend = route.length - colorToSpend;
    final kept = <TrainCard>[];
    final spent = <TrainCard>[];
    var colorSpent = 0;
    var locoSpent = 0;
    for (final card in hand) {
      if (card.color == route.color && colorSpent < colorToSpend) {
        colorSpent++;
        spent.add(card);
        continue;
      }
      if (card.color == CardColor.locomotive && locoSpent < locoToSpend) {
        locoSpent++;
        spent.add(card);
        continue;
      }
      kept.add(card);
    }
    return (kept: kept, spent: spent);
  }

  // ---- Взятие карт ---------------------------------------------------------

  /// Берёт открытую карту [index] из ряда. Если карта — локомотив, это единственная
  /// карта за ход; иначе игроку нужно взять ещё одну (фаза `drawSecond`). Когда
  /// взята вторая карта, ход завершается. Бросает [StateError] при нелегальном
  /// действии.
  GameState drawFaceUpCard(GameState state, int seat, int index) {
    if (state.turn != seat) {
      throw StateError('Не твой ход');
    }
    if (state.phase != TtrPhase.main && state.phase != TtrPhase.drawSecond) {
      throw StateError('Сейчас нельзя брать карты');
    }
    if (index < 0 || index >= state.faceUpCards.length) {
      throw StateError('Нет такой открытой карты');
    }
    final card = state.faceUpCards[index];
    final isLocomotive = card.color == CardColor.locomotive;
    // В фазе `drawSecond` локомотив брать нельзя: правило «локомотив — только
    // первой картой».
    if (state.phase == TtrPhase.drawSecond && isLocomotive) {
      throw StateError('Локомотив можно брать только первой картой');
    }
    final newHand = [...state.players[seat].hand, card];
    final newFaceUp = List<TrainCard>.of(state.faceUpCards)..removeAt(index);
    final refilled = _refillFaceUp(state.copyWith(), newFaceUp);
    final newPlayers = List<PlayerState>.of(refilled.players);
    newPlayers[seat] = refilled.players[seat].copyWith(hand: newHand);
    final withCard = refilled.copyWith(players: newPlayers);
    if (isLocomotive) {
      return _endTurn(withCard);
    }
    if (state.phase == TtrPhase.main) {
      return withCard.copyWith(phase: TtrPhase.drawSecond);
    }
    // phase == drawSecond: вторая карта — ход завершён.
    return _endTurn(withCard);
  }

  /// Берёт верхнюю карту из колоды. Если колода пуста, сначала поднимает сброс.
  /// Бросает [StateError], если действие нелегально.
  GameState drawDeckCard(GameState state, int seat) {
    if (state.turn != seat) {
      throw StateError('Не твой ход');
    }
    if (state.phase != TtrPhase.main && state.phase != TtrPhase.drawSecond) {
      throw StateError('Сейчас нельзя брать карты');
    }
    var working = state;
    if (working.deck.isEmpty) {
      if (working.discardPile.isEmpty) {
        throw StateError('Колода пуста');
      }
      final recycled = List<TrainCard>.of(working.discardPile)..shuffle();
      working = working.copyWith(
        deck: recycled,
        discardPile: const [],
      );
    }
    final card = working.deck.last;
    final newDeck = List<TrainCard>.of(working.deck)..removeLast();
    final newHand = [...working.players[seat].hand, card];
    final newPlayers = List<PlayerState>.of(working.players);
    newPlayers[seat] = working.players[seat].copyWith(hand: newHand);
    final next = working.copyWith(players: newPlayers, deck: newDeck);
    if (state.phase == TtrPhase.main) {
      return next.copyWith(phase: TtrPhase.drawSecond);
    }
    return _endTurn(next);
  }

  /// Пополняет ряд открытых карт из колоды (или из сброса, если колода пуста).
  GameState _refillFaceUp(GameState state, List<TrainCard> currentFaceUp) {
    var working = state;
    var faceUp = List<TrainCard>.of(currentFaceUp);
    while (faceUp.length < faceUpCount) {
      if (working.deck.isEmpty) {
        if (working.discardPile.isEmpty) break;
        final recycled = List<TrainCard>.of(working.discardPile)..shuffle();
        working = working.copyWith(
          deck: recycled,
          discardPile: const [],
        );
      }
      faceUp.add(working.deck.last);
      final newDeck = List<TrainCard>.of(working.deck)..removeLast();
      working = working.copyWith(deck: newDeck);
    }
    return working.copyWith(faceUpCards: faceUp);
  }

  // ---- Путешествия ---------------------------------------------------------

  /// Тянет две карточки путешествий (или сколько осталось) и переводит фазу в
  /// `choosingDestinations`. Бросает [StateError], если действие нелегально.
  GameState drawDestinations(GameState state, int seat) {
    if (state.turn != seat) {
      throw StateError('Не твой ход');
    }
    if (state.phase != TtrPhase.main) {
      throw StateError('Сейчас нельзя тянуть путешествия');
    }
    if (state.destinationDeck.isEmpty) {
      throw StateError('Путешествий больше нет');
    }
    final drawCount =
        state.destinationDeck.length >= drawnDestinations
        ? drawnDestinations
        : state.destinationDeck.length;
    final drawn = state.destinationDeck.sublist(
      state.destinationDeck.length - drawCount,
    );
    final newDeck = state.destinationDeck.sublist(
      0,
      state.destinationDeck.length - drawCount,
    );
    return state.copyWith(
      destinationDeck: newDeck,
      pendingDestinations: drawn,
      phase: TtrPhase.choosingDestinations,
    );
  }

  /// Оставляет себе путешествия по индексам из `pendingDestinations`. Остальные
  /// возвращаются вниз колоды путешествий. Ход завершается. Бросает [StateError]
  /// при нелегальном действии.
  GameState keepDestinations(GameState state, int seat, List<int> indices) {
    if (state.turn != seat) {
      throw StateError('Не твой ход');
    }
    if (state.phase != TtrPhase.choosingDestinations) {
      throw StateError('Сейчас не выбираем путешествия');
    }
    final pending = state.pendingDestinations;
    if (pending.isEmpty) {
      throw StateError('Нечего оставлять');
    }
    // Дедупликация и проверка диапазона.
    final seen = <int>{};
    for (final i in indices) {
      if (i < 0 || i >= pending.length) {
        throw StateError('Неверный индекс путешествия');
      }
      if (!seen.add(i)) {
        throw StateError('Индекс путешествия повторяется');
      }
    }
    if (indices.length < minKeptDestinations && pending.isNotEmpty) {
      throw StateError('Оставь хотя бы одно путешествие');
    }
    final kept = <Destination>[];
    final returned = <Destination>[];
    for (var i = 0; i < pending.length; i++) {
      if (indices.contains(i)) {
        kept.add(pending[i]);
      } else {
        returned.add(pending[i]);
      }
    }
    final player = state.players[seat];
    final newDestinations = [...player.destinations, ...kept];
    final newPlayers = List<PlayerState>.of(state.players);
    newPlayers[seat] = player.copyWith(destinations: newDestinations);
    final next = state.copyWith(
      players: newPlayers,
      pendingDestinations: const [],
      destinationDeck: [...returned, ...state.destinationDeck],
    );
    return _endTurn(next);
  }

  // ---- Завершение хода и партии --------------------------------------------

  /// Передаёт ход сопернику и сбрасывает фазу в `main`. Если у кого-то
  /// осталось `endGameTrains` вагонов или меньше — заканчивает партию.
  GameState _endTurn(GameState state) {
    if (state.phase == TtrPhase.over) return state;
    if (_shouldEndGame(state)) {
      return _finishGame(state);
    }
    return state.copyWith(turn: state.otherTurn, phase: TtrPhase.main);
  }

  /// Условие конца партии: у любого игрока вагонов не больше `endGameTrains`.
  bool _shouldEndGame(GameState state) {
    return state.players.any((p) => p.trainsLeft <= endGameTrains);
  }

  /// Заканчивает партию: фаза `over`, победитель — тот, у кого больше очков с
  /// учётом путешествий. Ничья оставляет `winner` равным `null`.
  GameState _finishGame(GameState state) {
    final score0 = finalScore(state, 0);
    final score1 = finalScore(state, 1);
    final winner = score0 == score1 ? null : (score0 > score1 ? 0 : 1);
    return state.copyWith(phase: TtrPhase.over, winner: winner);
  }

  /// Завершилась ли партия.
  bool isGameOver(GameState state) => state.isOver;

  /// Итоговые очки игрока: за маршруты + бонусы путешествий − штрафы.
  int finalScore(GameState state, int seat) {
    final player = state.players[seat];
    var score = player.score;
    for (final dest in player.destinations) {
      if (isDestinationCompleted(state, seat, dest)) {
        score += dest.points;
      } else {
        score -= dest.points;
      }
    }
    return score;
  }

  /// Победитель (0 или 1), `null` при ничьей или если партия ещё не кончилась.
  int? winner(GameState state) {
    if (!state.isOver) return null;
    final score0 = finalScore(state, 0);
    final score1 = finalScore(state, 1);
    if (score0 == score1) return null;
    return score0 > score1 ? 0 : 1;
  }

  /// Соединены ли города путешествия маршрутами игрока [seat]. Обычный BFS по
  /// графу занятых игроком маршрутов.
  bool isDestinationCompleted(GameState state, int seat, Destination dest) {
    final graph = <City, Set<City>>{};
    for (final route in state.routes) {
      if (route.claimedBy != seat) continue;
      (graph[route.cityA] ??= <City>{}).add(route.cityB);
      (graph[route.cityB] ??= <City>{}).add(route.cityA);
    }
    final visited = <City>{};
    final queue = <City>[dest.from];
    visited.add(dest.from);
    while (queue.isNotEmpty) {
      final city = queue.removeAt(0);
      if (city == dest.to) return true;
      for (final next in graph[city] ?? const <City>[]) {
        if (visited.add(next)) queue.add(next);
      }
    }
    return false;
  }

  // ---- Применение действия -------------------------------------------------

  /// Применяет любое действие [action] от лица игрока [seat]. Используется
  /// сетью: хост получил действие от клиента — применил его и разослал снимок.
  /// Бросает [StateError] при нелегальном действии — это рассинхрон.
  GameState applyAction(GameState state, int seat, TtrAction action) {
    return switch (action.kind) {
      'claim' => claimRoute(state, seat, action.routeIndex!),
      'drawFaceUp' => drawFaceUpCard(state, seat, action.faceUpIndex!),
      'drawDeck' => drawDeckCard(state, seat),
      'drawDestinations' => drawDestinations(state, seat),
      'keepDestinations' => keepDestinations(state, seat, action.keepIndices),
      _ => throw StateError('Неизвестное действие: ${action.kind}'),
    };
  }

  /// Какие действия сейчас доступны игроку [seat] — для подсказки и для ИИ.
  /// В фазах `drawSecond` и `choosingDestinations` доступны только
  /// соответствующие действия.
  List<TtrAction> availableActions(GameState state, int seat) {
    if (state.phase == TtrPhase.over) return const [];
    if (state.turn != seat) return const [];
    final actions = <TtrAction>[];
    switch (state.phase) {
      case TtrPhase.main:
        for (var i = 0; i < state.routes.length; i++) {
          if (canClaimRoute(state, seat, i)) {
            actions.add(TtrAction.claim(i));
          }
        }
        if (state.faceUpCards.isNotEmpty) {
          for (var i = 0; i < state.faceUpCards.length; i++) {
            actions.add(TtrAction.drawFaceUp(i));
          }
        }
        if (state.deck.isNotEmpty || state.discardPile.isNotEmpty) {
          actions.add(const TtrAction.drawDeck());
        }
        if (state.destinationDeck.isNotEmpty) {
          actions.add(const TtrAction.drawDestinations());
        }
      case TtrPhase.drawSecond:
        // Вторая карта: любая открытая, кроме локомотива; или из колоды.
        for (var i = 0; i < state.faceUpCards.length; i++) {
          if (state.faceUpCards[i].color != CardColor.locomotive) {
            actions.add(TtrAction.drawFaceUp(i));
          }
        }
        if (state.deck.isNotEmpty || state.discardPile.isNotEmpty) {
          actions.add(const TtrAction.drawDeck());
        }
      case TtrPhase.choosingDestinations:
        if (state.pendingDestinations.isEmpty) break;
        // Любой набор, в котором хотя бы одно путешествие.
        final n = state.pendingDestinations.length;
        final subsets = _subsets(n, minKeptDestinations);
        for (final subset in subsets) {
          actions.add(TtrAction.keepDestinations(subset));
        }
      case TtrPhase.over:
        break;
    }
    return actions;
  }

  /// Все наборы индексов длины 0..n, в которых не меньше [minKeep] элементов.
  /// Нужно для выбора путешествий: «оставь хотя бы одно» — значит, доступны все
  /// наборы размера ≥1.
  static List<List<int>> _subsets(int n, int minKeep) {
    final result = <List<int>>[];
    void recurse(int start, List<int> current) {
      if (current.length >= minKeep) {
        result.add(List<int>.of(current));
      }
      if (current.length == n) return;
      for (var i = start; i < n; i++) {
        current.add(i);
        recurse(i + 1, current);
        current.removeLast();
      }
    }

    recurse(0, []);
    return result;
  }
}
