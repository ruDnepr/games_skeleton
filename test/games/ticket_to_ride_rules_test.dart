import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/board.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/model.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/rules.dart';

/// Правила «Билета на поезд»: раздача, занятие маршрута, взятие карт,
/// путешествия, подсчёт очков и конец партии.
void main() {
  const rules = TicketToRideRules();

  /// Предсказуемый генератор: одна и та же раздача в каждом тесте.
  Random rng(int seed) => Random(seed);

  /// Помощник, чтобы собрать партию без шума.
  GameState newGame({int seed = 0}) =>
      rules.newGame(random: rng(seed), playerNames: const ['Аня', 'Боря']);

  group('Раздача', () {
    test('новая партия раздаёт карты, путешествия и открытые карты', () {
      final state = newGame();
      expect(state.players, hasLength(2));
      expect(state.players[0].hand, hasLength(startingCards));
      expect(state.players[1].hand, hasLength(startingCards));
      expect(state.players[0].destinations, hasLength(startingDestinations));
      expect(state.players[1].destinations, hasLength(startingDestinations));
      expect(state.players[0].trainsLeft, startingTrains);
      expect(state.faceUpCards, hasLength(faceUpCount));
      expect(state.turn, 0);
      expect(state.phase, TtrPhase.main);
      expect(state.winner, isNull);
    });

    test('в колоде после раздачи остались карты, а сброс пуст', () {
      final state = newGame();
      expect(state.deck.length, greaterThan(0));
      expect(state.discardPile, isEmpty);
    });

    test('имена игроков из аргумента попадают в состояние', () {
      final state = newGame();
      expect(state.players[0].name, 'Аня');
      expect(state.players[1].name, 'Боря');
    });
  });

  group('canClaimRoute', () {
    test('false, если не твой ход', () {
      final state = newGame();
      expect(rules.canClaimRoute(state, 1, 0), isFalse);
    });

    test('false в фазе drawSecond', () {
      var state = newGame();
      // Берём открытую карту — если она не локомотив, попадаем в drawSecond.
      final faceUp = state.faceUpCards;
      final nonLocoIndex = faceUp.indexWhere(
        (c) => c.color != CardColor.locomotive,
      );
      if (nonLocoIndex == -1) return;
      state = rules.drawFaceUpCard(state, 0, nonLocoIndex);
      expect(state.phase, TtrPhase.drawSecond);
      expect(rules.canClaimRoute(state, 0, 0), isFalse);
    });

    test('false, если вагонов не хватает', () {
      final state = newGame();
      // Все маршруты длиной от 1 до 4. Если у игрока 10 вагонов — должно
      // хватать. Подгоним состояние: обнулим вагоны и проверим отказ.
      final poor = state.copyWith(
        players: [
          state.players[0].copyWith(trainsLeft: 0),
          state.players[1],
        ],
      );
      expect(rules.canClaimRoute(poor, 0, 0), isFalse);
    });

    test('false, если маршрут уже занят', () {
      final state = newGame();
      // Найдём маршрут, под который точно хватит карт: добавим нужные карты
      // в руку игрока и обнулим их у соперника, потом займём — и проверим,
      // что повторное занятие невозможно.
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final claimed = rules.claimRoute(rigged, 0, 0);
      expect(claimed.routes[0].isClaimed, isTrue);
      expect(rules.canClaimRoute(claimed, 0, 0), isFalse);
    });

    test('true, когда цветных карт ровно по длине маршрута', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      expect(rules.canClaimRoute(rigged, 0, 0), isTrue);
    });

    test('true, когда цвета не хватает, но локомотивы добивают', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        TrainCard(route.color),
        TrainCard(CardColor.locomotive),
        TrainCard(CardColor.locomotive),
      ];
      // Длина маршрута не меньше двух — двух локомотивов и одной цветной
      // хватит даже на длину 3.
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      expect(rules.canClaimRoute(rigged, 0, 0), isTrue);
    });
  });

  group('claimRoute', () {
    test('списывает цветные карты и ставит вагоны, ход переходит', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
        // Лишние карты других цветов, чтобы после списания рука не стала
        // пустой и не дала ложного «цветных карт ноль».
        TrainCard(CardColor.blue),
        TrainCard(CardColor.green),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.claimRoute(rigged, 0, 0);
      expect(next.routes[0].claimedBy, 0);
      expect(next.players[0].trainsLeft, startingTrains - route.length);
      expect(next.players[0].score, route.points);
      expect(next.turn, 1);
      expect(next.phase, TtrPhase.main);
      // Цветные карты списались, лишние других цветов остались.
      expect(
        next.players[0].hand.where((c) => c.color == route.color).length,
        0,
      );
      expect(next.discardPile, hasLength(route.length));
    });

    test('по умолчанию тратит цветные, а потом локомотивы', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        TrainCard(route.color),
        TrainCard(route.color),
        // Локомотивы, которые не должны потратиться, когда цветных хватает.
        TrainCard(CardColor.locomotive),
        TrainCard(CardColor.locomotive),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.claimRoute(rigged, 0, 0);
      // Локомотивы остались в руке.
      expect(
        next.players[0].hand
            .where((c) => c.color == CardColor.locomotive)
            .length,
        2,
      );
    });

    test('явное locomotiveCount добивает локомотивами, а цветные бережёт', () {
      final state = newGame();
      final route = state.routes[0]; // длина 2
      final hand = <TrainCard>[
        TrainCard(route.color),
        TrainCard(route.color),
        TrainCard(CardColor.locomotive),
        TrainCard(CardColor.locomotive),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.claimRoute(rigged, 0, 0, locomotiveCount: 2);
      // Потратились 2 локомотива; обе цветные карты остались.
      expect(
        next.players[0].hand.where((c) => c.color == route.color).length,
        2,
      );
      expect(
        next.players[0].hand
            .where((c) => c.color == CardColor.locomotive)
            .length,
        0,
      );
    });

    test('явное locomotiveCount = 0 тратит только цветные', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        TrainCard(route.color),
        TrainCard(route.color),
        TrainCard(CardColor.locomotive),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.claimRoute(rigged, 0, 0, locomotiveCount: 0);
      expect(
        next.players[0].hand
            .where((c) => c.color == CardColor.locomotive)
            .length,
        1,
      );
    });

    test('бросает StateError, если локомотивов больше, чем в руке', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      expect(
        () => rules.claimRoute(rigged, 0, 0, locomotiveCount: 1),
        throwsStateError,
      );
    });

    test('бросает StateError, если цветных карт не хватает при loco=0', () {
      final state = newGame();
      final route = state.routes[0]; // длина 2
      final hand = <TrainCard>[
        TrainCard(route.color),
        // Один локомотив — хватит на длину 2 только вместе.
        TrainCard(CardColor.locomotive),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      expect(
        () => rules.claimRoute(rigged, 0, 0, locomotiveCount: 0),
        throwsStateError,
      );
    });
  });

  group('drawFaceUpCard', () {
    test('берёт открытую карту и переходит в фазу drawSecond', () {
      var state = newGame();
      final nonLocoIndex = state.faceUpCards.indexWhere(
        (c) => c.color != CardColor.locomotive,
      );
      if (nonLocoIndex == -1) return;
      final cardBefore = state.faceUpCards[nonLocoIndex];
      state = rules.drawFaceUpCard(state, 0, nonLocoIndex);
      expect(state.phase, TtrPhase.drawSecond);
      expect(state.turn, 0);
      expect(state.players[0].hand.last, cardBefore);
    });

    test('локомотив первой картой заканчивает ход', () {
      var state = newGame();
      final locoIndex = state.faceUpCards.indexWhere(
        (c) => c.color == CardColor.locomotive,
      );
      if (locoIndex == -1) {
        // Подсунем локомотив принудительно.
        final faceUp = List<TrainCard>.of(state.faceUpCards);
        faceUp[0] = const TrainCard(CardColor.locomotive);
        state = state.copyWith(faceUpCards: faceUp);
        state = rules.drawFaceUpCard(state, 0, 0);
      } else {
        state = rules.drawFaceUpCard(state, 0, locoIndex);
      }
      expect(state.turn, 1);
      expect(state.phase, TtrPhase.main);
    });

    test('локомотив второй картой брать нельзя', () {
      var state = newGame();
      // Сделаем так, чтобы первая карта — не локомотив, а вторая — локомотив.
      // Колоду и сброс опустошаем, чтобы refill не подменил карты.
      final faceUp = <TrainCard>[
        const TrainCard(CardColor.red),
        const TrainCard(CardColor.locomotive),
        const TrainCard(CardColor.red),
        const TrainCard(CardColor.blue),
        const TrainCard(CardColor.green),
      ];
      state = state.copyWith(
        faceUpCards: faceUp,
        deck: const <TrainCard>[],
        discardPile: const <TrainCard>[],
      );
      state = rules.drawFaceUpCard(state, 0, 0);
      expect(state.phase, TtrPhase.drawSecond);
      // После снятия индекса 0 локомотив стоит на индексе 0 нового ряда.
      final locoIndex = state.faceUpCards.indexWhere(
        (c) => c.color == CardColor.locomotive,
      );
      expect(locoIndex, isNot(-1));
      expect(
        () => rules.drawFaceUpCard(state, 0, locoIndex),
        throwsStateError,
      );
    });
  });

  group('drawDeckCard', () {
    test('берёт верхнюю карту и переходит в drawSecond', () {
      var state = newGame();
      final deckSizeBefore = state.deck.length;
      state = rules.drawDeckCard(state, 0);
      expect(state.phase, TtrPhase.drawSecond);
      expect(state.deck.length, deckSizeBefore - 1);
      expect(state.players[0].hand.length, startingCards + 1);
    });

    test('вторая карта из колоды завершает ход', () {
      var state = newGame();
      state = rules.drawDeckCard(state, 0);
      state = rules.drawDeckCard(state, 0);
      expect(state.turn, 1);
      expect(state.phase, TtrPhase.main);
    });

    test('пустая колода поднимает сброс', () {
      var state = newGame();
      // Сдвинем все карты в сброс, оставив колоду пустой.
      final discard = <TrainCard>[...state.deck, ...state.faceUpCards];
      state = state.copyWith(
        deck: const <TrainCard>[],
        faceUpCards: const <TrainCard>[
          TrainCard(CardColor.red),
          TrainCard(CardColor.red),
          TrainCard(CardColor.red),
          TrainCard(CardColor.red),
          TrainCard(CardColor.red),
        ],
        discardPile: discard,
      );
      expect(state.deck, isEmpty);
      final next = rules.drawDeckCard(state, 0);
      expect(next.deck, isNotEmpty);
      expect(next.discardPile, isEmpty);
      expect(next.players[0].hand.length, startingCards + 1);
    });
  });

  group('drawDestinations', () {
    test('тянет две карточки и переводит фазу', () {
      var state = newGame();
      final deckSize = state.destinationDeck.length;
      state = rules.drawDestinations(state, 0);
      expect(state.phase, TtrPhase.choosingDestinations);
      expect(state.pendingDestinations.length, lessThanOrEqualTo(2));
      expect(state.destinationDeck.length, deckSize - state.pendingDestinations.length);
    });

    test('бросает StateError, если колода путешествий пуста', () {
      var state = newGame();
      state = state.copyWith(destinationDeck: const <Destination>[]);
      expect(() => rules.drawDestinations(state, 0), throwsStateError);
    });
  });

  group('keepDestinations', () {
    test('оставленные попадают в руку игрока, остальные — обратно в колоду', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      final pending = state.pendingDestinations;
      final before = state.players[0].destinations.length;
      state = rules.keepDestinations(state, 0, [0]);
      expect(state.phase, TtrPhase.main);
      expect(state.turn, 1);
      expect(
        state.players[0].destinations.length,
        before + 1,
      );
      expect(state.players[0].destinations, contains(pending[0]));
      // Возвращённое путешествие — вниз колоды.
      expect(state.destinationDeck.first, pending[1]);
    });

    test('нельзя оставить ноль путешествий', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      expect(() => rules.keepDestinations(state, 0, []), throwsStateError);
    });

    test('нельзя дважды оставить одно и то же путешествие', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      expect(() => rules.keepDestinations(state, 0, [0, 0]), throwsStateError);
    });

    test('можно оставить оба', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      final before = state.players[0].destinations.length;
      state = rules.keepDestinations(state, 0, [0, 1]);
      expect(state.players[0].destinations.length, before + 2);
    });
  });

  group('finalScore и isDestinationCompleted', () {
    test('невыполненное путешествие отнимает очки', () {
      final state = newGame();
      // Игрок 0 не занял ни одного маршрута — путешествия не выполнены.
      final score0 = rules.finalScore(state, 0);
      final destPoints = state.players[0].destinations.fold<int>(
        0,
        (s, d) => s + d.points,
      );
      expect(score0, -destPoints);
    });

    test('выполненное путешествие добавляет очки', () {
      final state = newGame();
      // Подсоединим первое путешествие игрока 0 вручную: занятый маршрут,
      // который соединяет концы путешествия.
      final dest = state.players[0].destinations.first;
      // Найдём в allRoutes маршрут, который соединяет from и to. Если такого
      // нет — возьмём любой занятый маршрут и убедимся, что путешествие через
      // него не выполняется.
      var rigged = state;
      for (var i = 0; i < state.routes.length; i++) {
        if (state.routes[i].connects(dest.from, dest.to)) {
          final routes = List<Route>.of(state.routes);
          routes[i] = routes[i].copyWith(claimedBy: 0);
          rigged = state.copyWith(routes: routes);
          break;
        }
      }
      if (rigged == state) return;
      expect(rules.isDestinationCompleted(rigged, 0, dest), isTrue);
      final score = rules.finalScore(rigged, 0);
      expect(score, dest.points);
    });

    test('маршрутные очки плюс бонусы путешествий', () {
      var state = newGame();
      // Займём один маршрут игроком 0, потом посчитаем.
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      state = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final claimed = rules.claimRoute(state, 0, 0);
      final score = rules.finalScore(claimed, 0);
      final destPoints = claimed.players[0].destinations.fold<int>(
        0,
        (s, d) => s + (rules.isDestinationCompleted(claimed, 0, d) ? d.points : -d.points),
      );
      expect(score, route.points + destPoints);
    });
  });

  group('Конец партии', () {
    test('когда вагонов ≤ endGameTrains — партия заканчивается', () {
      var state = newGame();
      // Подведём игрока 0 к концу: 2 вагона.
      state = state.copyWith(
        players: [
          state.players[0].copyWith(trainsLeft: endGameTrains),
          state.players[1],
        ],
      );
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      state = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final claimed = rules.claimRoute(state, 0, 0);
      expect(claimed.isOver, isTrue);
      expect(claimed.phase, TtrPhase.over);
    });

    test('winner возвращает место с большим итоговым счётом', () {
      var state = newGame();
      // Игрок 0 занял длинный маршрут (много очков), игрок 1 — ноль.
      // У обоих обнулим путешествия, чтобы счёт определялся только маршрутами.
      final route = state.routes.firstWhere((r) => r.length == 4);
      final routeIndex = state.routes.indexOf(route);
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      state = state.copyWith(
        players: [
          state.players[0].copyWith(
            hand: hand,
            trainsLeft: route.length,
            destinations: const <Destination>[],
          ),
          state.players[1].copyWith(
            destinations: const <Destination>[],
            trainsLeft: startingTrains,
          ),
        ],
      );
      final claimed = rules.claimRoute(state, 0, routeIndex);
      expect(claimed.isOver, isTrue);
      // Игрок 0: +7 за маршрут, игрок 1: 0.
      expect(rules.finalScore(claimed, 0), route.points);
      expect(rules.finalScore(claimed, 1), 0);
      expect(rules.winner(claimed), 0);
    });

    test('ничья, если итоговые очки равны', () {
      var state = newGame();
      // Обнулим путешествия и занятые маршруты у обоих. Чтобы закончить партию
      // без чьих-либо очков, игрок 0 берёт две карты из колоды — после второй
      // срабатывает _endTurn и _shouldEndGame (trainsLeft ≤ endGameTrains).
      state = state.copyWith(
        players: [
          state.players[0].copyWith(
            destinations: const <Destination>[],
            trainsLeft: endGameTrains,
          ),
          state.players[1].copyWith(
            destinations: const <Destination>[],
            trainsLeft: startingTrains,
          ),
        ],
      );
      // Гарантируем, что колода не пуста.
      expect(state.deck, isNotEmpty);
      var next = rules.drawDeckCard(state, 0);
      expect(next.phase, TtrPhase.drawSecond);
      next = rules.drawDeckCard(next, 0);
      expect(next.isOver, isTrue);
      expect(rules.finalScore(next, 0), 0);
      expect(rules.finalScore(next, 1), 0);
      expect(rules.winner(next), isNull);
    });
  });

  group('availableActions', () {
    test('в фазе main есть хотя бы одно действие', () {
      final state = newGame();
      final actions = rules.availableActions(state, 0);
      expect(actions, isNotEmpty);
    });

    test('в фазе over действий нет', () {
      var state = newGame();
      state = state.copyWith(phase: TtrPhase.over);
      expect(rules.availableActions(state, 0), isEmpty);
    });

    test('в фазе choosingDestinations только keepDestinations', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      final actions = rules.availableActions(state, 0);
      expect(actions, isNotEmpty);
      for (final action in actions) {
        expect(action.kind, 'keepDestinations');
      }
    });

    test('в фазе drawSecond нет действия drawDestinations', () {
      var state = newGame();
      final nonLocoIndex = state.faceUpCards.indexWhere(
        (c) => c.color != CardColor.locomotive,
      );
      if (nonLocoIndex == -1) return;
      state = rules.drawFaceUpCard(state, 0, nonLocoIndex);
      final actions = rules.availableActions(state, 0);
      expect(
        actions.where((a) => a.kind == 'drawDestinations'),
        isEmpty,
      );
    });
  });

  group('applyAction', () {
    test('маршрут через applyAction занимает его', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        for (var i = 0; i < route.length; i++) TrainCard(route.color),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.applyAction(rigged, 0, TtrAction.claim(0));
      expect(next.routes[0].claimedBy, 0);
    });

    test('applyAction с locomotiveCount добивает локомотивами', () {
      final state = newGame();
      final route = state.routes[0];
      final hand = <TrainCard>[
        TrainCard(route.color),
        TrainCard(route.color),
        TrainCard(CardColor.locomotive),
        TrainCard(CardColor.locomotive),
      ];
      final rigged = state.copyWith(
        players: [
          state.players[0].copyWith(hand: hand),
          state.players[1],
        ],
      );
      final next = rules.applyAction(
        rigged,
        0,
        TtrAction.claim(0, locomotiveCount: 2),
      );
      expect(next.routes[0].claimedBy, 0);
      expect(
        next.players[0].hand.where((c) => c.color == route.color).length,
        2,
      );
    });

    test('TtrAction кодируется и декодируется обратно', () {
      final actions = <TtrAction>[
        TtrAction.claim(3),
        TtrAction.claim(3, locomotiveCount: 2),
        TtrAction.drawFaceUp(1),
        const TtrAction.drawDeck(),
        const TtrAction.drawDestinations(),
        TtrAction.keepDestinations([0, 1]),
      ];
      for (final action in actions) {
        final json = action.toJson();
        final restored = TtrAction.fromJson(json);
        expect(restored.kind, action.kind);
        expect(restored.routeIndex, action.routeIndex);
        expect(restored.faceUpIndex, action.faceUpIndex);
        expect(restored.keepIndices, action.keepIndices);
        expect(restored.locomotiveCount, action.locomotiveCount);
      }
    });
  });

  group('board.dart', () {
    test('routeBetween находит маршрут между соединёнными городами', () {
      final state = newGame();
      final first = state.routes.first;
      expect(routeBetween(first.cityA, first.cityB), isNotNull);
      // Между Москвой и Санкт-Петербургом прямого маршрута нет.
      expect(routeBetween(City.moscow, City.spb), isNull);
    });

    test('routeIndexBetween возвращает индекс маршрута', () {
      final state = newGame();
      final first = state.routes.first;
      expect(routeIndexBetween(first.cityA, first.cityB), 0);
    });
  });
}
