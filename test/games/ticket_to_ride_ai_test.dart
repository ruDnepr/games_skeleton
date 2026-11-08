import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/ai.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/model.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/rules.dart';

/// ИИ «Билета на поезд»: три уровня сложности. Лёгкий — любое доступное
/// действие; средний — помогает своим путешествиям; сложный — ещё и мешает
/// чужим. Все уровни должны возвращать только легальные действия.
void main() {
  const rules = TicketToRideRules();
  Random rng(int seed) => Random(seed);

  /// Помощник: новая партия с предсказуемой раздачей.
  GameState newGame({int seed = 0}) =>
      rules.newGame(random: rng(seed), playerNames: const ['Аня', 'Боря']);

  /// Проверяет, что действие разрешено правилами в данном состоянии.
  bool isLegal(GameState state, int seat, TtrAction? action) {
    if (action == null) return false;
    final actions = rules.availableActions(state, seat);
    return actions.any((a) {
      if (a.kind != action.kind) return false;
      return switch (action.kind) {
        'claim' => a.routeIndex == action.routeIndex,
        'drawFaceUp' => a.faceUpIndex == action.faceUpIndex,
        'drawDeck' || 'drawDestinations' => true,
        'keepDestinations' => setEquals(
            a.keepIndices.toSet(),
            action.keepIndices.toSet(),
          ),
        _ => false,
      };
    });
  }

  group('легальный ход', () {
    test('лёгкий уровень всегда возвращает легальное действие', () {
      final state = newGame();
      final random = rng(1);
      for (var i = 0; i < 30; i++) {
        final action = TicketToRideAI.findBestAction(
          state,
          0,
          Difficulty.easy,
          random,
        );
        expect(action, isNotNull);
        expect(isLegal(state, 0, action), isTrue, reason: '$action');
      }
    });

    test('средний уровень всегда возвращает легальное действие', () {
      final state = newGame();
      final random = rng(2);
      for (var i = 0; i < 30; i++) {
        final action = TicketToRideAI.findBestAction(
          state,
          0,
          Difficulty.medium,
          random,
        );
        expect(action, isNotNull);
        expect(isLegal(state, 0, action), isTrue);
      }
    });

    test('сложный уровень всегда возвращает легальное действие', () {
      final state = newGame();
      final random = rng(3);
      for (var i = 0; i < 30; i++) {
        final action = TicketToRideAI.findBestAction(
          state,
          0,
          Difficulty.hard,
          random,
        );
        expect(action, isNotNull);
        expect(isLegal(state, 0, action), isTrue);
      }
    });

    test('в фазе choosingDestinations возвращает keepDestinations', () {
      var state = newGame();
      state = rules.drawDestinations(state, 0);
      for (final level in Difficulty.values) {
        final action = TicketToRideAI.findBestAction(
          state,
          0,
          level,
          rng(4),
        );
        expect(action, isNotNull);
        expect(action!.kind, 'keepDestinations');
        expect(isLegal(state, 0, action), isTrue);
      }
    });

    test('в фазе drawSecond нельзя взять локомотив', () {
      var state = newGame();
      // Найдём не-локомотив в открытых.
      final idx = state.faceUpCards.indexWhere(
        (c) => c.color != CardColor.locomotive,
      );
      if (idx == -1) return;
      state = rules.drawFaceUpCard(state, 0, idx);
      for (final level in Difficulty.values) {
        final action = TicketToRideAI.findBestAction(state, 0, level, rng(5));
        if (action == null) continue;
        if (action.kind == 'drawFaceUp') {
          expect(
            state.faceUpCards[action.faceUpIndex!].color,
            isNot(CardColor.locomotive),
          );
        }
      }
    });
  });

  group('если ход не твой — null', () {
    test('not your turn → null', () {
      final state = newGame();
      expect(
        TicketToRideAI.findBestAction(state, 1, Difficulty.easy, rng(6)),
        isNull,
      );
    });
  });

  group('стратегия', () {
    test('средний уровень занимает маршрут, завершающий путешествие', () {
      // Соберём позицию: у игрока 0 есть путешествие Москва — Тверь. Маршрут
      // Москва—Тверь (индекс 0, красный, длина 2) свободен, и в руке две
      // красные карты. Средний уровень должен его занять.
      final base = newGame();
      final dest = Destination(
        from: City.moscow,
        to: City.tver,
        points: 4,
      );
      // Убираем все путешествия, кроме нужного, и даём карты.
      final state = base.copyWith(
        players: [
          base.players[0].copyWith(
            hand: const [
              TrainCard(CardColor.red),
              TrainCard(CardColor.red),
            ],
            destinations: [dest],
          ),
          base.players[1].copyWith(destinations: const []),
        ],
      );
      final action = TicketToRideAI.findBestAction(
        state,
        0,
        Difficulty.medium,
        rng(7),
      );
      expect(action, isNotNull);
      expect(action!.kind, 'claim');
      expect(action.routeIndex, 0);
    });

    test('лёгкий уровень не заглядывает в стратегию — ходит легально', () {
      // Тот же расклад, что и выше, но лёгкий уровень. Он может выбрать что
      // угодно из availableActions — главное, что ход не нарушает правила.
      final base = newGame();
      final dest = Destination(
        from: City.moscow,
        to: City.tver,
        points: 4,
      );
      final state = base.copyWith(
        players: [
          base.players[0].copyWith(
            hand: const [
              TrainCard(CardColor.red),
              TrainCard(CardColor.red),
            ],
            destinations: [dest],
          ),
          base.players[1].copyWith(destinations: const []),
        ],
      );
      final action = TicketToRideAI.findBestAction(
        state,
        0,
        Difficulty.easy,
        rng(8),
      );
      expect(action, isNotNull);
      expect(isLegal(state, 0, action), isTrue);
    });

    test('сложный уровень блокирует соперника, когда может', () {
      // У соперника (seat 1) путешествие Ярославль — Владимир. Маршрут
      // Ярославль—Владимир (индекс 6, красный, длина 1) свободен. У игрока 0
      // в руке красная карта. Сложный уровень должен занять этот маршрут,
      // чтобы помешать.
      final base = newGame();
      final opponentDest = Destination(
        from: City.yaroslavl,
        to: City.vladimir,
        points: 3,
      );
      final state = base.copyWith(
        players: [
          base.players[0].copyWith(
            hand: const [
              TrainCard(CardColor.red),
              TrainCard(CardColor.red),
            ],
            destinations: const [],
          ),
          base.players[1].copyWith(destinations: [opponentDest]),
        ],
      );
      final action = TicketToRideAI.findBestAction(
        state,
        0,
        Difficulty.hard,
        rng(9),
      );
      expect(action, isNotNull);
      // Должен занять либо маршрут 6 (блок), либо какой-то другой с большой
      // длиной. Сложный уровень предпочтёт блок.
      expect(action!.kind, 'claim');
      // Проверим, что выбранный маршрут касается путешествия соперника.
      final route = state.routes[action.routeIndex!];
      expect(
        route.connects(opponentDest.from, opponentDest.to) ||
            route.cityA == opponentDest.from ||
            route.cityA == opponentDest.to ||
            route.cityB == opponentDest.from ||
            route.cityB == opponentDest.to,
        isTrue,
        reason: 'сложный уровень должен блокировать чужие путешествия',
      );
    });
  });

  group('применение хода', () {
    test('ход компьютера всегда можно применить к позиции', () {
      final state = newGame();
      for (final level in Difficulty.values) {
        final action = TicketToRideAI.findBestAction(state, 0, level, rng(10));
        expect(action, isNotNull);
        final next = rules.applyAction(state, 0, action!);
        expect(next, isNotNull);
      }
    });

    test('после хода компьютера состояние меняется', () {
      final state = newGame();
      final action = TicketToRideAI.findBestAction(
        state,
        0,
        Difficulty.medium,
        rng(11),
      );
      expect(action, isNotNull);
      final next = rules.applyAction(state, 0, action!);
      // Ход компьютера что-то сделал: рука или занятые маршруты поменялись.
      final changed = next.players[0].hand.length != state.players[0].hand.length ||
          next.routes.any((r) => r.isClaimed) !=
              state.routes.any((r) => r.isClaimed) ||
          next.turn != state.turn;
      expect(changed, isTrue);
    });
  });

  group('Difficulty enum', () {
    test('три уровня сложности с подписями', () {
      expect(Difficulty.values, hasLength(3));
      expect(Difficulty.easy.label, 'Лёгкий');
      expect(Difficulty.medium.label, 'Средний');
      expect(Difficulty.hard.label, 'Сложный');
    });
  });
}
