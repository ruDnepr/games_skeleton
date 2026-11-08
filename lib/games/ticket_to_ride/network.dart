import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.ticket_to_ride.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const ticketToRideGameId = 'ticket_to_ride';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для «Билета на поезд»
/// это один переключатель: подсветка доступных маршрутов. Каждое устройство
/// рисует по своим настройкам, но карта проверяется, чтобы чужое лобби не
/// пустило в партию неразборчивые данные.
Map<String, Object?> ticketToRideOptions(SettingsController settings) => {
  'hints': settings.flag(ticketToRideGameId, 'hints'),
};

/// Опции «Билета на поезд» после разбора. Значения — только то, что игра умеет.
class TicketToRideOptions {
  const TicketToRideOptions({required this.hints});
  final bool hints;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
TicketToRideOptions ticketToRideParseOptions(Map<String, Object?> options) {
  const allowed = {'hints'};
  final unknown = options.keys
      .where((key) => !allowed.contains(key))
      .toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  if (hints is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return TicketToRideOptions(hints: hints);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния:
/// транспорт зовёт её до того, как ход увидит партия. Полная проверка по
/// правилам делает сама партия через `TicketToRideRules.applyAction`, когда
/// применяет ход. Нелегальный ход там вызывает рассинхронизацию и понятное
/// сообщение, а здесь отсекается мусор и чужой формат.
void ticketToRideValidateMove(Map<String, Object?> move) {
  final kind = move['kind'];
  if (kind is! String) {
    throw const FormatException('Ход не распознан: тип');
  }
  switch (kind) {
    case 'claim':
      final routeIndex = move['routeIndex'];
      if (routeIndex is! int || routeIndex < 0 || routeIndex > 100) {
        throw const FormatException('Ход не распознан: маршрут');
      }
      final loco = move['locomotiveCount'];
      if (loco != null && (loco is! int || loco < 0 || loco > 10)) {
        throw const FormatException('Ход не распознан: локомотивы');
      }
    case 'drawFaceUp':
      final index = move['index'];
      if (index is! int || index < 0 || index > 10) {
        throw const FormatException('Ход не распознан: карта');
      }
    case 'drawDeck':
    case 'drawDestinations':
      break;
    case 'keepDestinations':
      final indices = move['indices'];
      if (indices is! List || indices.isEmpty) {
        throw const FormatException('Ход не распознан: путешествия');
      }
      for (final entry in indices) {
        if (entry is! int || entry < 0 || entry > 10) {
          throw const FormatException('Ход не распознан: путешествие');
        }
      }
    default:
      throw FormatException('Ход не распознан: $kind');
  }
}

// ---- Действия в сеть и обратно --------------------------------------------

/// Сообщение `move` для отправки действия. Просто повторяет JSON действия:
/// форма у него уже нужная.
Map<String, Object?> actionToJson(TtrAction action) => action.toJson();

/// Разбирает пришедший `move` в [TtrAction]. Бросает [FormatException] на чужую
/// форму.
TtrAction parseAction(Map<String, Object?> data) => TtrAction.fromJson(data);

// ---- Снимок состояния в сеть и обратно ------------------------------------

/// Снимок партии для клиента: открытые карты, размер колоды, своя рука и
/// число карт у соперника, занятые маршруты, свои путешествия и их статус,
/// счёт, чей ход, фаза, победитель. Хост присылает этот снимок после каждого
/// действия; клиент не применяет ходы сам, а просто заменяет состояние снимком.
///
/// [viewerSeat] — место клиента (1, потому что хост — место 0). Снимок включает
/// только его руку; рука соперника не видна, видно лишь число карт.
/// Путешествия соперника приходят всегда — для счётчика в панели; на экране
/// виден только их номер, а сами города — только в конце партии для подсчёта
/// очков (см. `_showOverDialog`).
Map<String, Object?> snapshotToJson(GameState state, int viewerSeat) {
  final opponentSeat = 1 - viewerSeat;
  return {
    'kind': 'snapshot',
    'hand': [for (final card in state.players[viewerSeat].hand) card.color.wire],
    'faceUp': [for (final card in state.faceUpCards) card.color.wire],
    'deckCount': state.deck.length,
    'discardCount': state.discardPile.length,
    'opponentHandSize': state.players[opponentSeat].hand.length,
    'routes': [
      for (final route in state.routes) {
        'from': route.cityA.name,
        'to': route.cityB.name,
        'color': route.color.wire,
        'length': route.length,
        'claimedBy': route.claimedBy,
      },
    ],
    'destinations': [
      for (final dest in state.players[viewerSeat].destinations) {
        'from': dest.from.name,
        'to': dest.to.name,
        'points': dest.points,
      },
    ],
    'opponentDestinations': [
      for (final dest in state.players[opponentSeat].destinations) {
        'from': dest.from.name,
        'to': dest.to.name,
        'points': dest.points,
      },
    ],
    'scores': [
      state.players[0].score,
      state.players[1].score,
    ],
    'trainsLeft': [
      state.players[0].trainsLeft,
      state.players[1].trainsLeft,
    ],
    'turn': state.turn,
    'phase': state.phase.name,
    'winner': state.winner,
    'pendingDestinations': [
      for (final dest in state.pendingDestinations) {
        'from': dest.from.name,
        'to': dest.to.name,
        'points': dest.points,
      },
    ],
  };
}

/// Разбирает снимок, пришедший от хоста, в [GameState]. Чужая рука и чужие
/// путешествия остаются пустыми: видны только свои. Поле `players[1]` (место
/// клиента) заполняется из снимка, `players[0]` — частично (только число карт,
/// путешествий и очки).
GameState parseSnapshot(Map<String, Object?> data) {
  final handRaw = data['hand'];
  if (handRaw is! List) {
    throw const FormatException('Снимок не распознан: рука');
  }
  final hand = <TrainCard>[
    for (final entry in handRaw) TrainCard(_parseColor(entry)),
  ];

  final faceUpRaw = data['faceUp'];
  if (faceUpRaw is! List) {
    throw const FormatException('Снимок не распознан: открытые карты');
  }
  final faceUp = <TrainCard>[
    for (final entry in faceUpRaw) TrainCard(_parseColor(entry)),
  ];

  final deckCount = data['deckCount'];
  if (deckCount is! int || deckCount < 0) {
    throw const FormatException('Снимок не распознан: колода');
  }
  final discardCount = data['discardCount'];
  if (discardCount is! int || discardCount < 0) {
    throw const FormatException('Снимок не распознан: сброс');
  }
  final opponentHandSize = data['opponentHandSize'];
  if (opponentHandSize is! int || opponentHandSize < 0) {
    throw const FormatException('Снимок не распознан: рука соперника');
  }

  final routesRaw = data['routes'];
  if (routesRaw is! List) {
    throw const FormatException('Снимок не распознан: маршруты');
  }
  final routes = <Route>[];
  for (final entry in routesRaw) {
    if (entry is! Map) {
      throw const FormatException('Снимок не распознан: маршрут');
    }
    routes.add(_parseRoute(Map<String, Object?>.from(entry)));
  }

  final destsRaw = data['destinations'];
  if (destsRaw is! List) {
    throw const FormatException('Снимок не распознан: путешествия');
  }
  final destinations = <Destination>[];
  for (final entry in destsRaw) {
    if (entry is! Map) {
      throw const FormatException('Снимок не распознан: путешествие');
    }
    destinations.add(_parseDestination(Map<String, Object?>.from(entry)));
  }

  // Путешествия соперника приходят всегда: число нужно для счётчика в панели
  // во время игры, а сами города — для подсчёта очков в конце партии.
  final oppDestsRaw = data['opponentDestinations'] ?? const [];
  if (oppDestsRaw is! List) {
    throw const FormatException('Снимок не распознан: путешествия соперника');
  }
  final opponentDestinations = <Destination>[];
  for (final entry in oppDestsRaw) {
    if (entry is! Map) {
      throw const FormatException('Снимок не распознан: путешествие соперника');
    }
    opponentDestinations.add(_parseDestination(Map<String, Object?>.from(entry)));
  }

  final scoresRaw = data['scores'];
  if (scoresRaw is! List || scoresRaw.length != 2) {
    throw const FormatException('Снимок не распознан: счёт');
  }
  final scores = <int>[];
  for (final entry in scoresRaw) {
    if (entry is! int) {
      throw const FormatException('Снимок не распознан: очки');
    }
    scores.add(entry);
  }

  final trainsRaw = data['trainsLeft'];
  if (trainsRaw is! List || trainsRaw.length != 2) {
    throw const FormatException('Снимок не распознан: вагоны');
  }
  final trains = <int>[];
  for (final entry in trainsRaw) {
    if (entry is! int || entry < 0) {
      throw const FormatException('Снимок не распознан: вагоны');
    }
    trains.add(entry);
  }

  final turn = data['turn'];
  if (turn is! int || turn < 0 || turn > 1) {
    throw const FormatException('Снимок не распознан: ход');
  }

  final phaseName = data['phase'];
  if (phaseName is! String) {
    throw const FormatException('Снимок не распознан: фаза');
  }
  final phase = _parsePhase(phaseName);

  final winner = data['winner'];
  if (winner != null && winner is! int) {
    throw const FormatException('Снимок не распознан: победитель');
  }

  final pendingRaw = data['pendingDestinations'] ?? const [];
  if (pendingRaw is! List) {
    throw const FormatException('Снимок не распознан: ожидающие путешествия');
  }
  final pending = <Destination>[];
  for (final entry in pendingRaw) {
    if (entry is! Map) {
      throw const FormatException('Снимок не распознан: ожидающее путешествие');
    }
    pending.add(_parseDestination(Map<String, Object?>.from(entry)));
  }

  // Клиент — всегда место 1, хост — место 0. Поэтому свою руку кладём в
  // `players[1]`, размер руки соперника — в `players[0].hand` как заглушку.
  // Путешествия соперника попадают в `players[0].destinations` только когда
  // партия окончена — для подсчёта очков в конце.
  return GameState(
    players: [
      PlayerState(
        name: 'Хост',
        hand: const [],
        trainsLeft: trains[0],
        destinations: opponentDestinations,
        score: scores[0],
      ),
      PlayerState(
        name: 'Я',
        hand: hand,
        trainsLeft: trains[1],
        destinations: destinations,
        score: scores[1],
      ),
    ],
    routes: routes,
    faceUpCards: faceUp,
    deck: List.filled(deckCount, const TrainCard(CardColor.red)),
    destinationDeck: const [],
    discardPile: List.filled(discardCount, const TrainCard(CardColor.red)),
    turn: turn,
    phase: phase,
    pendingDestinations: pending,
    winner: winner as int?,
  );
}

CardColor _parseColor(Object? value) {
  if (value is! String) {
    throw const FormatException('Цвет карты не распознан');
  }
  return CardColor.fromWire(value);
}

Route _parseRoute(Map<String, Object?> json) {
  final from = _parseCity(json['from']);
  final to = _parseCity(json['to']);
  final color = _parseColor(json['color']);
  final length = json['length'];
  if (length is! int || length < 1 || length > 5) {
    throw const FormatException('Маршрут не распознан: длина');
  }
  final claimedBy = json['claimedBy'];
  if (claimedBy != null && claimedBy is! int) {
    throw const FormatException('Маршрут не распознан: владелец');
  }
  return Route(
    cityA: from,
    cityB: to,
    color: color,
    length: length,
    claimedBy: claimedBy as int?,
  );
}

Destination _parseDestination(Map<String, Object?> json) {
  final from = _parseCity(json['from']);
  final to = _parseCity(json['to']);
  final points = json['points'];
  if (points is! int || points <= 0) {
    throw const FormatException('Путешествие не распознано: очки');
  }
  return Destination(from: from, to: to, points: points);
}

City _parseCity(Object? value) {
  if (value is! String) {
    throw const FormatException('Город не распознан');
  }
  for (final city in City.values) {
    if (city.name == value) return city;
  }
  throw FormatException('Город не распознан: $value');
}

TtrPhase _parsePhase(String value) {
  return switch (value) {
    'main' => TtrPhase.main,
    'drawSecond' => TtrPhase.drawSecond,
    'choosingDestinations' => TtrPhase.choosingDestinations,
    'over' => TtrPhase.over,
    _ => throw FormatException('Фаза не распознана: $value'),
  };
}
