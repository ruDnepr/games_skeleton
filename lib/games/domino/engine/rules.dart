/// Правила классического домино с дублями.
///
/// Все правила живут здесь: экран только показывает то, что вернули эти
/// методы, поэтому одинаковые действия на разных устройствах дают одинаковый
/// результат, а сетевой игре не нужны сообщения о состоянии — хост присылает
/// полный снимок.
library;

import 'dart:math';

import 'model.dart';

/// Кость, с которой начинается партия, и место, которому она принадлежит.
class StartingTile {
  const StartingTile({
    required this.seat,
    required this.tile,
    required this.fromDouble,
  });

  final int seat;
  final DominoTile tile;

  /// Старт выбрали по дублю (1:1, потом 2:2 и так далее) или по сумме очков.
  final bool fromDouble;

  DominoMove get move => DominoMove(tile: tile, side: ChainSide.right);
}

/// Правила классического домино.
///
/// Класс иммутабельный и без состояния — каждое правило возвращает новое
/// состояние, а старое остаётся в истории для отмены хода.
class DominoRules {
  const DominoRules();

  /// Раздаёт кости и решает, кто открывает партию.
  ///
  /// [order] позволяет задать порядок колоды целиком — так тесты играют
  /// заранее известную партию. Кости раздаются с начала списка, базар — хвост.
  GameState initial({
    required int players,
    List<DominoTile>? order,
    Random? random,
  }) {
    if (players < minPlayers || players > maxPlayers) {
      throw ArgumentError('Играют от $minPlayers до $maxPlayers игроков');
    }
    final deck =
        order == null ? shuffledDeck(random) : List<DominoTile>.of(order);
    if (deck.length != deckSize || deck.toSet().length != deckSize) {
      throw ArgumentError('В колоде должно быть $deckSize разных костей');
    }
    final hands = <List<DominoTile>>[
      for (var seat = 0; seat < players; seat++)
        deck.sublist(seat * tilesPerPlayer, (seat + 1) * tilesPerPlayer),
    ];
    final bazaar = deck.sublist(players * tilesPerPlayer);
    final starting = startingTileFor(hands);
    return GameState(
      playerCount: players,
      hands: hands,
      bazaar: bazaar,
      turn: starting.seat,
    );
  }

  /// Кто открывает партию и какой костью.
  ///
  /// Сначала ищется дубль 1:1, затем 2:2 и так до 6:6. Если дублей нет ни у
  /// кого, играет кость с наибольшей суммой; при равенстве — та, у которой
  /// больше вторая половина, затем первая, затем место с меньшим номером.
  /// Дубль 0:0 стартовым не считается: сумма у него нулевая.
  StartingTile startingTileFor(List<List<DominoTile>> hands) {
    for (var pip = 1; pip <= maxPip; pip++) {
      final doubleTile = DominoTile(pip, pip);
      for (var seat = 0; seat < hands.length; seat++) {
        if (hands[seat].contains(doubleTile)) {
          return StartingTile(seat: seat, tile: doubleTile, fromDouble: true);
        }
      }
    }
    StartingTile? best;
    for (var seat = 0; seat < hands.length; seat++) {
      for (final tile in hands[seat]) {
        if (best == null) {
          best = StartingTile(seat: seat, tile: tile, fromDouble: false);
          continue;
        }
        final better = tile.sum > best.tile.sum ||
            (tile.sum == best.tile.sum && tile.b > best.tile.b) ||
            (tile.sum == best.tile.sum &&
                tile.b == best.tile.b &&
                tile.a > best.tile.a);
        if (better) {
          best = StartingTile(seat: seat, tile: tile, fromDouble: false);
        }
      }
    }
    if (best == null) {
      throw ArgumentError('Нельзя начать партию без костей');
    }
    return best;
  }

  /// Первая кость партии, посчитанная по уже разданным рукам.
  ///
  /// После [initial] поле `state.turn` уже указывает на это место: игроки
  /// ничего не выбирают, партию открывает самая старшая кость.
  StartingTile firstTile(GameState state) => startingTileFor(state.hands);

  /// Куда можно походить в этой позиции. Пустой список — ходить нечем.
  List<DominoMove> getValidMoves(GameState state) {
    if (state.isOver || !state.isActive(state.turn)) return const [];
    final board = state.board;
    final moves = <DominoMove>[];
    for (final tile in state.handOf(state.turn)) {
      for (final side in board.sidesFor(tile)) {
        moves.add(DominoMove(tile: tile, side: side));
      }
    }
    return moves;
  }

  /// Подходит ли кость к столу. Без кости — есть ли хоть один ход.
  bool canPlay(GameState state, [DominoTile? tile]) =>
      tile == null ? getValidMoves(state).isNotEmpty : state.board.canPlace(tile);

  /// Есть ли у игрока подходящая кость — нужно для «рыбы».
  bool seatCanPlay(GameState state, int seat) {
    if (!state.isActive(seat)) return false;
    final board = state.board;
    return state.handOf(seat).any(board.canPlace);
  }

  bool anyoneCanPlay(GameState state) {
    for (var seat = 0; seat < state.playerCount; seat++) {
      if (seatCanPlay(state, seat)) return true;
    }
    return false;
  }

  /// Выкладывает кость того игрока, чья сейчас очередь.
  GameState applyMove(GameState state, DominoMove move) {
    if (state.isOver) throw StateError('Партия уже закончена');
    final seat = state.turn;
    final hand = state.handOf(seat);
    final index = hand.indexOf(move.tile);
    if (index < 0) {
      throw ArgumentError('Кости ${move.tile} нет на руке');
    }
    if (!state.board.sidesFor(move.tile).contains(move.side)) {
      throw ArgumentError('Кость ${move.tile} не подходит к этому концу');
    }
    final hands = _copyHands(state);
    hands[seat].removeAt(index);
    final next = state.copyWith(
      hands: hands,
      board: state.board.place(move.tile, move.side),
      turn: nextSeat(state, from: seat),
      ply: state.ply + 1,
      result: null,
    );
    return settle(next);
  }

  /// Забирает одну кость из базара. Очередь хода не меняется: взяв кость,
  /// игрок продолжает искать, чем походить.
  GameState drawFromBazaar(GameState state) {
    if (state.isOver) throw StateError('Партия уже закончена');
    if (state.bazaar.isEmpty) throw StateError('Базар пуст');
    final tile = state.bazaar.first;
    final hands = _copyHands(state);
    hands[state.turn].add(tile);
    final next = state.copyWith(
      hands: hands,
      bazaar: state.bazaar.sublist(1),
      ply: state.ply + 1,
      result: null,
    );
    return settle(next);
  }

  /// Пропуск хода: подходящих костей нет, а базар пуст.
  GameState pass(GameState state) {
    if (state.isOver) throw StateError('Партия уже закончена');
    final seat = state.turn;
    final next = state.copyWith(
      turn: nextSeat(state, from: seat),
      ply: state.ply + 1,
      result: null,
    );
    return settle(next);
  }

  /// Досчитывает итог, если партия только что закончилась.
  GameResult? checkWin(GameState state) => state.result ?? _resultFor(state);

  /// Возвращает состояние с итогом, если партия закончилась.
  GameState settle(GameState state) {
    if (state.isOver) return state;
    final result = _resultFor(state);
    return result == null ? state : state.copyWith(result: result);
  }

  /// Следующее место по кругу, не пропуская вышедших игроков.
  int nextSeat(GameState state, {required int from}) {
    for (var step = 1; step <= state.playerCount; step++) {
      final candidate = (from + step) % state.playerCount;
      if (state.isActive(candidate)) return candidate;
    }
    return from;
  }

  /// Применяет ход соперника, пришедший по сети.
  ///
  /// Доска у всех одинаковая, поэтому ход виден всем. Содержимое чужих рук на
  /// этом устройстве неизвестно: очередь, размеры рук и итог приходят от хоста.
  GameState applyNetworkMove(
    GameState state,
    int seat,
    DominoMove move, {
    required int ply,
    required int turn,
    required List<int> sizes,
    required int bazaarCount,
    GameResult? result,
  }) {
    final hands = _copyHands(state);
    final index = hands[seat].indexOf(move.tile);
    if (index >= 0) hands[seat].removeAt(index);
    return state.copyWith(
      hands: hands,
      sizes: sizes,
      board: state.board.place(move.tile, move.side),
      bazaarTotal: bazaarCount,
      turn: turn,
      ply: ply,
      result: result,
    );
  }

  /// Применяет взятие из базара, пришедшее по сети.
  ///
  /// Кость знает только тот, кто её взял, поэтому [tile] передаётся лишь в его
  /// сообщении.
  GameState applyNetworkDraw(
    GameState state,
    int seat, {
    DominoTile? tile,
    required int ply,
    required List<int> sizes,
    required int bazaarCount,
    required int turn,
    GameResult? result,
  }) {
    final hands = _copyHands(state);
    if (tile != null && !hands[seat].contains(tile)) hands[seat].add(tile);
    final bazaar = state.bazaar.contains(tile)
        ? (List<DominoTile>.of(state.bazaar)..remove(tile))
        : state.bazaar;
    return state.copyWith(
      hands: hands,
      sizes: sizes,
      bazaar: bazaar,
      bazaarTotal: bazaarCount,
      turn: turn,
      ply: ply,
      result: result,
    );
  }

  /// Применяет пропуск хода, пришедший по сети.
  GameState applyNetworkPass(
    GameState state, {
    required int ply,
    required int turn,
    GameResult? result,
  }) => state.copyWith(turn: turn, ply: ply, result: result);

  /// Игрок вышел из партии: его кости уходят в базар, а ход переходит дальше.
  GameState abandonSeat(GameState state, int seat) {
    if (!state.isActive(seat)) return state;
    final hands = _copyHands(state);
    final moved = hands[seat];
    hands[seat] = <DominoTile>[];
    final bazaar = [...state.bazaar, ...moved];
    final inactive = {...state.inactive, seat};
    final next = state.copyWith(
      hands: hands,
      bazaar: bazaar,
      inactive: inactive,
      turn: state.turn == seat
          ? nextActiveSeat(state.playerCount, inactive, seat)
          : state.turn,
      result: null,
    );
    return settle(next);
  }

  /// Следующее активное место, когда состав игроков уже изменился.
  int nextActiveSeat(int playerCount, Set<int> inactive, int from) {
    for (var step = 1; step <= playerCount; step++) {
      final candidate = (from + step) % playerCount;
      if (!inactive.contains(candidate)) return candidate;
    }
    return from;
  }

  GameResult? _resultFor(GameState state) {
    // Если остался один игрок, партия заканчивается его победой.
    if (state.activePlayers <= 1) {
      final only = [
        for (var seat = 0; seat < state.playerCount; seat++)
          if (state.isActive(seat)) seat,
      ].firstOrNull;
      return GameResult(kind: ResultKind.win, winner: only, sums: state.sums);
    }
    for (var seat = 0; seat < state.playerCount; seat++) {
      if (state.isActive(seat) && state.tilesLeft(seat) == 0) {
        return GameResult(kind: ResultKind.win, winner: seat, sums: state.sums);
      }
    }
    if (state.bazaarCount > 0) return null;
    if (!state.allHandsKnown) return null;
    if (anyoneCanPlay(state)) return null;
    return _fishResult(state);
  }

  GameResult _fishResult(GameState state) {
    final sums = [
      for (var seat = 0; seat < state.playerCount; seat++)
        state.isActive(seat) ? state.sumOf(seat) : 0,
    ];
    int? best;
    var tied = false;
    for (var seat = 0; seat < state.playerCount; seat++) {
      if (!state.isActive(seat)) continue;
      if (best == null || sums[seat] < sums[best]) {
        best = seat;
        tied = false;
      } else if (sums[seat] == sums[best]) {
        tied = true;
      }
    }
    return GameResult(
      kind: tied ? ResultKind.draw : ResultKind.fish,
      winner: tied ? null : best,
      sums: sums,
    );
  }

  List<List<DominoTile>> _copyHands(GameState state) => [
    for (final hand in state.hands) List<DominoTile>.of(hand),
  ];
}
