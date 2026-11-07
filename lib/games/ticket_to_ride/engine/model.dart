/// Модели «Билета на поезд»: города, карты, маршруты, путешествия, партия.
///
/// Чистый Dart: ни Flutter, ни сети, ни звука — только данные. Так движок
/// работает и в тестах, и в контроллере, и в сети. Состояние иммутабельное:
/// каждое правило возвращает новое состояние, а старое остаётся для отмены хода.
library;

import 'package:flutter/foundation.dart';

/// Город на карте. Шесть городов России — простая сеть для детской партии.
enum City {
  moscow('Москва'),
  spb('Санкт-Петербург'),
  novgorod('Новгород'),
  tver('Тверь'),
  yaroslavl('Ярославль'),
  vladimir('Владимир');

  const City(this.russianName);

  /// Имя для подписи на карте и в диалогах.
  final String russianName;
}

/// Цвет карты поезда. Локомотив — джокер: заменяет любой цвет.
enum CardColor {
  red('Красный'),
  blue('Синий'),
  green('Зелёный'),
  locomotive('Локомотив');

  const CardColor(this.russianName);

  final String russianName;

  /// Имя для сети и сохранений — латиница, без пробелов.
  String get wire => name;

  static CardColor fromWire(String value) {
    return switch (value) {
      'red' => CardColor.red,
      'blue' => CardColor.blue,
      'green' => CardColor.green,
      'locomotive' => CardColor.locomotive,
      _ => throw FormatException('Цвет карты не распознан: $value'),
    };
  }
}

/// Одна карта поезда. Равенство по цвету — для подсчёта карт в руке.
@immutable
class TrainCard {
  const TrainCard(this.color);
  final CardColor color;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TrainCard && other.color == color);

  @override
  int get hashCode => color.hashCode;

  @override
  String toString() => 'TrainCard(${color.wire})';
}

/// Маршрут между двумя городами на карте. Каждый маршрут можно занять один раз.
@immutable
class Route {
  const Route({
    required this.cityA,
    required this.cityB,
    required this.color,
    required this.length,
    this.claimedBy,
  }) : assert(length >= 1 && length <= 5);

  /// Один конец маршрута. Стороны равноправны, порядок — только для отрисовки.
  final City cityA;

  /// Второй конец маршрута.
  final City cityB;

  /// Цвет, которым нужно выложить карты, чтобы занять маршрут. Локомотив
  /// означает «любой цвет» — таких маршрутов на нашей карте нет, но поле
  /// готово под расширение.
  final CardColor color;

  /// Длина маршрута в вагонах. Это и число карт, и число поездов, и длина
  /// линии на карте.
  final int length;

  /// Кто занял маршрут (0 или 1) или `null`, если маршрут свободен.
  final int? claimedBy;

  bool get isClaimed => claimedBy != null;

  /// Соединяет ли маршрут два данных города (в любом порядке).
  bool connects(City a, City b) =>
      (cityA == a && cityB == b) || (cityA == b && cityB == a);

  /// Очки за занятие маршрута этой длины: 1→1, 2→3, 3→4, 4→7, 5→10.
  int get points => routePoints[length]!;

  /// Другой город маршрута (тот, что не равен [one]).
  City otherEnd(City one) => one == cityA ? cityB : cityA;

  Route copyWith({int? claimedBy}) => Route(
    cityA: cityA,
    cityB: cityB,
    color: color,
    length: length,
    claimedBy: claimedBy ?? this.claimedBy,
  );

  Map<String, Object?> toJson() => {
    'from': cityA.name,
    'to': cityB.name,
    'color': color.wire,
    'length': length,
    'claimedBy': claimedBy,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Route &&
          other.cityA == cityA &&
          other.cityB == cityB &&
          other.color == color &&
          other.length == length &&
          other.claimedBy == claimedBy;

  @override
  int get hashCode => Object.hash(cityA, cityB, color, length, claimedBy);
}

/// Очки за маршруты по длине. Длинный маршрут даёт больше очков, чем сумма
/// двух коротких — поэтому ребёнку выгодно копить карты на большие линии.
const Map<int, int> routePoints = {1: 1, 2: 3, 3: 4, 4: 7, 5: 10};

/// Карточка путешествия — задание соединить два города. Выполнишь —
/// получишь очки, не выполнишь — потеряешь.
@immutable
class Destination {
  const Destination({
    required this.from,
    required this.to,
    required this.points,
  }) : assert(points > 0);

  final City from;
  final City to;
  final int points;

  bool involves(City a, City b) =>
      (from == a && to == b) || (from == b && to == a);

  Map<String, Object?> toJson() => {
    'from': from.name,
    'to': to.name,
    'points': points,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Destination &&
          other.points == points && other.involves(from, to);

  @override
  int get hashCode => Object.hash(
    points,
    from.index < to.index ? from : to,
    from.index < to.index ? to : from,
  );

  @override
  String toString() => '${from.russianName} → ${to.russianName} ($points)';
}

/// Состояние одного игрока: имя, карты на руке, оставшиеся вагоны, выданные
/// путешествия и накопленные за маршруты очки.
@immutable
class PlayerState {
  const PlayerState({
    required this.name,
    required this.hand,
    required this.trainsLeft,
    required this.destinations,
    required this.score,
  });

  final String name;
  final List<TrainCard> hand;
  final int trainsLeft;
  final List<Destination> destinations;
  final int score;

  PlayerState copyWith({
    String? name,
    List<TrainCard>? hand,
    int? trainsLeft,
    List<Destination>? destinations,
    int? score,
  }) =>
      PlayerState(
        name: name ?? this.name,
        hand: hand ?? this.hand,
        trainsLeft: trainsLeft ?? this.trainsLeft,
        destinations: destinations ?? this.destinations,
        score: score ?? this.score,
      );
}

/// Фаза партии: чем сейчас занят активный игрок. Нужна, чтобы отличать
/// «выбираем действие» от «дотягиваем вторую карту» и «оставляем путешествия».
enum TtrPhase {
  /// Игрок выбирает, что делать: взять карты, занять маршрут или взять
  /// путешествия.
  main,

  /// Игрок уже взял одну карту (не локомотив) — нужно взять ещё одну, потом
  /// ход закончится.
  drawSecond,

  /// Игрок взял путешествия и выбирает, какие оставить себе.
  choosingDestinations,

  /// Партия окончена — никто больше не ходит.
  over,
}

/// Действие игрока или компьютера: одна из операций, доступных в свой ход.
///
/// Это и запись для сети, и аргумент для `TicketToRideRules.applyAction`. Сеть
/// передаёт ровно то же самое, что контроллер применяет локально.
@immutable
class TtrAction {
  const TtrAction._({
    required this.kind,
    this.routeIndex,
    this.faceUpIndex,
    this.keepIndices = const [],
    this.locomotiveCount,
  });

  /// Тип действия: `'claim'`, `'drawFaceUp'`, `'drawDeck'`,
  /// `'drawDestinations'`, `'keepDestinations'`.
  final String kind;
  final int? routeIndex;
  final int? faceUpIndex;
  final List<int> keepIndices;

  /// Сколько локомотивов потратить на занятие маршрута. `null` — правила
  /// списывают автоматически: сначала карты нужного цвета, потом локомотивы.
  /// Игрок через диалог может решить иначе: например, добить локомотивами,
  /// а цветные карты приберечь. ИИ и сеть передают `null`, когда выбор не нужен.
  final int? locomotiveCount;

  factory TtrAction.claim(int routeIndex, {int? locomotiveCount}) =>
      TtrAction._(
        kind: 'claim',
        routeIndex: routeIndex,
        locomotiveCount: locomotiveCount,
      );
  factory TtrAction.drawFaceUp(int faceUpIndex) =>
      TtrAction._(kind: 'drawFaceUp', faceUpIndex: faceUpIndex);
  // `drawDeck` и `drawDestinations` — без параметров, поэтому можно сделать
  // их редиректными `const`-конструкторами: тогда вызов
  // `const TtrAction.drawDeck()` даёт константный объект без лишних
  // распределений.
  const TtrAction.drawDeck() : this._(kind: 'drawDeck');
  const TtrAction.drawDestinations() : this._(kind: 'drawDestinations');
  factory TtrAction.keepDestinations(List<int> keepIndices) =>
      TtrAction._(kind: 'keepDestinations', keepIndices: keepIndices);

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'kind': kind};
    switch (kind) {
      case 'claim':
        if (routeIndex == null) {
          throw StateError('Действие claim без номера маршрута');
        }
        json['routeIndex'] = routeIndex;
        if (locomotiveCount != null) json['locomotiveCount'] = locomotiveCount;
      case 'drawFaceUp':
        if (faceUpIndex == null) {
          throw StateError('Действие drawFaceUp без номера карты');
        }
        json['index'] = faceUpIndex;
      case 'drawDeck':
      case 'drawDestinations':
        break;
      case 'keepDestinations':
        json['indices'] = List<int>.of(keepIndices);
    }
    return json;
  }

  static TtrAction fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    if (kind is! String) {
      throw const FormatException('Действие не распознано: тип');
    }
    return switch (kind) {
      'claim' => TtrAction.claim(
        _readInt(json, 'routeIndex'),
        locomotiveCount: _readOptionalInt(json, 'locomotiveCount'),
      ),
      'drawFaceUp' => TtrAction.drawFaceUp(_readInt(json, 'index')),
      'drawDeck' => const TtrAction.drawDeck(),
      'drawDestinations' => const TtrAction.drawDestinations(),
      'keepDestinations' => TtrAction.keepDestinations(
        _readIntList(json, 'indices'),
      ),
      _ => throw FormatException('Действие не распознано: $kind'),
    };
  }

  static int _readInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int || value < 0) {
      throw FormatException('Действие не распознано: $key');
    }
    return value;
  }

  static int? _readOptionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw FormatException('Действие не распознано: $key');
    }
    return value;
  }

  static List<int> _readIntList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List) {
      throw FormatException('Действие не распознано: $key');
    }
    final result = <int>[];
    for (final entry in value) {
      if (entry is! int || entry < 0) {
        throw FormatException('Действие не распознано: $key');
      }
      result.add(entry);
    }
    return result;
  }

  @override
  String toString() => toJson().toString();
}

/// Состояние партии в один момент. Каждое правило возвращает новый снимок, а
/// старый остаётся в истории — для отмены хода и для сравнения при отладке.
@immutable
class GameState {
  const GameState({
    required this.players,
    required this.routes,
    required this.faceUpCards,
    required this.deck,
    required this.destinationDeck,
    required this.discardPile,
    required this.turn,
    required this.phase,
    this.pendingDestinations = const [],
    this.winner,
  });

  /// Два игрока: место 0 — у хоста/первого, место 1 — соперник.
  final List<PlayerState> players;

  /// Все 10 маршрутов карты. Порядок фиксирован — индекс — это идентификатор
  /// маршрута в действиях и в сети.
  final List<Route> routes;

  /// Пять открытых карт, видных обоим игрокам.
  final List<TrainCard> faceUpCards;

  /// Колода карт рубашкой вверх.
  final List<TrainCard> deck;

  /// Колода невыданных карточек путешествий.
  final List<Destination> destinationDeck;

  /// Сбитые карты — сюда уходят карты с занятых маршрутов. Когда основная
  /// колода пуста, сброс тасуется и становится новой колодой.
  final List<TrainCard> discardPile;

  /// Чей сейчас ход: 0 или 1.
  final int turn;

  /// Фаза партии — что сейчас делает активный игрок.
  final TtrPhase phase;

  /// Путешествия, которые игрок только что вытянул и выбирает, какие оставить.
  /// Не пусто только в фазе `choosingDestinations`.
  final List<Destination> pendingDestinations;

  /// Победитель, если партия закончилась. `null` — партия ещё идёт.
  final int? winner;

  int get deckCount => deck.length;

  /// Карты в руке игрока [seat].
  List<TrainCard> handOf(int seat) => players[seat].hand;

  /// Число оставшихся вагонов у игрока [seat].
  int trainsOf(int seat) => players[seat].trainsLeft;

  /// Выданные путешествия игрока [seat].
  List<Destination> destinationsOf(int seat) => players[seat].destinations;

  /// Очки за маршруты игрока [seat] (без бонусов путешествий — те считаем в
  /// конце партии).
  int scoreOf(int seat) => players[seat].score;

  int get otherTurn => 1 - turn;

  bool get isOver => phase == TtrPhase.over || winner != null;

  GameState copyWith({
    List<PlayerState>? players,
    List<Route>? routes,
    List<TrainCard>? faceUpCards,
    List<TrainCard>? deck,
    List<Destination>? destinationDeck,
    List<TrainCard>? discardPile,
    int? turn,
    TtrPhase? phase,
    List<Destination>? pendingDestinations,
    int? winner,
  }) =>
      GameState(
        players: players ?? this.players,
        routes: routes ?? this.routes,
        faceUpCards: faceUpCards ?? this.faceUpCards,
        deck: deck ?? this.deck,
        destinationDeck: destinationDeck ?? this.destinationDeck,
        discardPile: discardPile ?? this.discardPile,
        turn: turn ?? this.turn,
        phase: phase ?? this.phase,
        pendingDestinations: pendingDestinations ?? this.pendingDestinations,
        winner: winner ?? this.winner,
      );
}

/// Параметры партии, которые не зависят от состояния. Хранятся как константы,
/// чтобы все части игры (движок, ИИ, сеть, интерфейс) видели одни и те же числа.
const int startingTrains = 10;
const int startingCards = 4;
const int faceUpCount = 5;
const int startingDestinations = 2;
const int drawnDestinations = 2;
const int minKeptDestinations = 1;
const int endGameTrains = 2;

/// Сколько карт каждого цвета в колоде. Локомотивов чуть меньше — иначе джокер
/// попадался бы слишком часто и цвет перестал бы иметь значение.
const Map<CardColor, int> deckComposition = {
  CardColor.red: 10,
  CardColor.blue: 10,
  CardColor.green: 10,
  CardColor.locomotive: 8,
};
