/// Модели лото: бочонки, карточки, игроки и партия.
///
/// Файл чистый Dart — без Flutter, — поэтому движок можно тестировать без
/// платформы и переиспользовать в любом интерфейсе. Структура повторяет
/// `domain/` оригинальной игры «Лото для Дианы»: мешок из 90 бочонков,
/// карточка 3×9 с пятью числами в строке, победа по строке или по всей
/// карточке. Каждое действие возвращает новое состояние, поэтому отмена хода
/// сводится к возврату предыдущего снимка.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'rules.dart';

/// Бочонок с числом от 1 до 90.
@immutable
class Barrel {
  const Barrel(this.number);

  final int number;

  static const min = 1;
  static const max = 90;
  static const total = max;

  bool get isValid => number >= min && number <= max;

  /// Прибаутка ведущего: «барабанные палочки» для одиннадцати.
  String get nickname => barrelNickname(number) ?? 'бочонок';

  /// То, что ведущий объявляет вслух: число и его прозвище, если оно есть.
  String get announcement {
    final nick = barrelNickname(number);
    return nick == null ? 'Бочонок $number' : '$number — $nick';
  }

  @override
  bool operator ==(Object other) =>
      other is Barrel && other.number == number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => 'Barrel($number)';
}

/// Классические прозвища бочонков русского лото.
///
/// Список не обязан покрывать все девяносто чисел: у остальных объявление
/// звучит просто «Бочонок 42». Важнее, что прозвища короткие, добрые и
/// понятны ребёнку девяти лет.
const Map<int, String> barrelNicknames = {
  1: 'колышек',
  2: 'пара',
  3: 'тройка',
  4: 'стул',
  5: 'пятёрочка',
  6: 'шестёрка',
  7: 'кочерга',
  8: 'бублик',
  9: 'воздушный шарик',
  10: 'червонец',
  11: 'барабанные палочки',
  12: 'дюжина',
  13: 'чёртова дюжина',
  14: 'полторы дюжины',
  17: 'невезучий бочонок',
  20: 'двадцать',
  21: 'очко',
  22: 'гуси-лебеди',
  24: 'часы в сутках',
  25: 'четверть сотни',
  30: 'тридцать',
  33: 'тридцать три богатыря',
  36: 'круглое число',
  40: 'сороконожка',
  44: 'стульчики',
  45: 'баба-яга',
  50: 'полтинник',
  55: 'пуговички',
  60: 'шейсят',
  66: 'валенки',
  69: 'шестьдесят девять',
  70: 'топорик',
  77: 'топорики',
  80: 'восемьдесят',
  88: 'снеговики',
  89: 'снеговик с метлой',
  90: 'дедушка',
};

/// Прозвище числа или `null`, если для него нет прибаутки.
String? barrelNickname(int number) => barrelNicknames[number];

/// Мешок с бочонками. Порядок известен заранее — это перемешанный список
/// чисел, поэтому вытягивание никогда не повторяется.
///
/// Мешок неизменяемый: вытянуть бочонок — значит получить новый мешок без
/// него. Так же устроена вся игра: каждое действие возвращает новое состояние,
/// и отмена последнего хода — это просто возврат к предыдущему состоянию.
@immutable
class BarrelBag {
  const BarrelBag._(this._left);

  factory BarrelBag.empty() => const BarrelBag._([]);

  /// Полный мешок, перемешанный случайно или по переданному порядку.
  factory BarrelBag.shuffled({Random? random}) {
    final numbers = List<int>.generate(Barrel.total, (index) => index + 1)
      ..shuffle(random ?? Random());
    return BarrelBag._(List<int>.unmodifiable(numbers));
  }

  /// Мешок с заданным порядком вытягивания — нужен тестам и отмене хода.
  factory BarrelBag.fromOrder(Iterable<int> order) {
    final numbers = order.toList();
    if (numbers.any((number) => number < Barrel.min || number > Barrel.max)) {
      throw ArgumentError.value(order, 'order', 'В мешке не бочонки');
    }
    if (numbers.toSet().length != numbers.length) {
      throw ArgumentError.value(order, 'order', 'Бочонки повторяются');
    }
    return BarrelBag._(List<int>.unmodifiable(numbers));
  }

  static const total = Barrel.total;

  final List<int> _left;

  int get remaining => _left.length;

  bool get isEmpty => _left.isEmpty;

  /// Следующий бочонок, не доставая его из мешка.
  int? get next => _left.isEmpty ? null : _left.first;

  /// Все бочонки, которые ещё в мешке, в порядке вытягивания.
  List<int> get left => _left;

  /// Мешок без следующего бочонка.
  BarrelBag take() =>
      BarrelBag._(List<int>.unmodifiable(_left.skip(1)));

  /// Возвращает бочонок обратно в мешок — он окажется следующим.
  BarrelBag putBack(int number) => BarrelBag._(
    List<int>.unmodifiable(<int>[number, ..._left]),
  );
}

/// Карточка лото: три строки и девять столбцов, по пять чисел в строке.
///
/// Числа столбца берутся из своего десятка — как на настоящем картонном лото:
/// в первом столбце 1–9, во втором 10–19, в последнем 80–90. Поэтому по
/// карточке сразу видно, где искать вытянутый бочонок.
@immutable
class LotoCard {
  const LotoCard._(this.rows);

  static const rowCount = 3;
  static const columnCount = 9;
  static const numbersPerRow = 5;
  static const totalNumbers = rowCount * numbersPerRow;

  /// Строки карточки: три списка по девять клеток, `null` — пустая клетка.
  final List<List<int?>> rows;

  /// Составляет случайную карточку.
  ///
  /// Сначала каждая строка выбирает свои пять столбцов, затем проверяется, что
  /// ни один столбец не остался пустым — пустая колонка выглядит как ошибка.
  /// Числа внутри столбца расставляются по возрастанию сверху вниз, как на
  /// напечатанных карточках, поэтому глаз ребёнка быстро находит число.
  factory LotoCard.generate({Random? random}) {
    final rng = random ?? Random();
    for (var attempt = 0; attempt < 400; attempt++) {
      final rows = List.generate(
        rowCount,
        (_) => List<int?>.filled(columnCount, null),
      );
      final columns = List.generate(rowCount, (_) {
        final pool = List<int>.generate(columnCount, (column) => column)
          ..shuffle(rng);
        return pool.take(numbersPerRow).toList()..sort();
      });
      final perColumn = List<int>.filled(columnCount, 0);
      for (final row in columns) {
        for (final column in row) {
          perColumn[column]++;
        }
      }
      if (perColumn.any((count) => count == 0)) continue;

      for (var column = 0; column < columnCount; column++) {
        final from = columnRange(column).start;
        final to = columnRange(column).end;
        final values = List<int>.generate(to - from + 1, (i) => from + i)
          ..shuffle(rng);
        var next = 0;
        for (var row = 0; row < rowCount; row++) {
          if (columns[row].contains(column)) {
            rows[row][column] = values[next++];
          }
        }
      }
      _sortColumns(rows);
      return LotoCard._(
        List<List<int?>>.unmodifiable(
          rows.map((row) => List<int?>.unmodifiable(row)),
        ),
      );
    }
    // 400 попыток почти никогда не заканчиваются, но без этого ветка не
    // доказала бы, что карточка всегда есть.
    throw StateError('Не удалось составить карточку');
  }

  /// Восстанавливает карточку из сообщения сети.
  ///
  /// Данные приходят от другого устройства, поэтому проверяется всё: размер,
  /// количество чисел, попадание числа в свой столбец и отсутствие повторов.
  factory LotoCard.fromJson(Object? data) {
    if (data is! Map) throw const FormatException('Карточка не распознана');
    final rows = data['rows'];
    if (rows is! List || rows.length != rowCount) {
      throw const FormatException('В карточке не три строки');
    }
    final parsed = <List<int?>>[];
    final seen = <int>{};
    for (final row in rows) {
      if (row is! List || row.length != columnCount) {
        throw const FormatException('В строке карточки не девять клеток');
      }
      final cells = <int?>[];
      var filled = 0;
      for (var column = 0; column < columnCount; column++) {
        final value = row[column];
        if (value == null) {
          cells.add(null);
          continue;
        }
        if (value is! int ||
            !columnContains(column, value) ||
            !seen.add(value)) {
          throw const FormatException('Число в карточке не подходит');
        }
        filled++;
        cells.add(value);
      }
      if (filled != numbersPerRow) {
        throw const FormatException('В строке не пять чисел');
      }
      parsed.add(List<int?>.unmodifiable(cells));
    }
    return LotoCard._(List<List<int?>>.unmodifiable(parsed));
  }

  Map<String, Object?> toJson() => {
    'rows': [for (final row in rows) List<Object?>.from(row)],
  };

  /// Диапазон чисел столбца. Первый столбец короче (1–9), последний длиннее
  /// (80–90) — так устроены все карточки русского лото.
  static ({int start, int end}) columnRange(int column) {
    final start = column == 0 ? 1 : column * 10;
    final end = column == columnCount - 1 ? 90 : column * 10 + 9;
    return (start: start, end: end);
  }

  static bool columnContains(int column, int number) {
    if (column < 0 || column >= columnCount) return false;
    final range = columnRange(column);
    return number >= range.start && number <= range.end;
  }

  static void _sortColumns(List<List<int?>> rows) {
    for (var column = 0; column < columnCount; column++) {
      final values = [
        for (var row = 0; row < rowCount; row++) rows[row][column],
      ].whereType<int>().toList()..sort();
      var next = 0;
      for (var row = 0; row < rowCount; row++) {
        if (rows[row][column] != null) rows[row][column] = values[next++];
      }
    }
  }

  /// Все пятнадцать чисел карточки.
  Iterable<int> get numbers =>
      rows.expand((row) => row).whereType<int>();

  Set<int> get numberSet => Set<int>.unmodifiable(numbers);

  List<int> numbersOfRow(int row) => rows[row].whereType<int>().toList();

  bool contains(int number) => numberSet.contains(number);

  /// Номер строки, в которой стоит число, или `null`, если числа нет.
  int? rowOf(int number) {
    for (var row = 0; row < rowCount; row++) {
      if (rows[row].contains(number)) return row;
    }
    return null;
  }

  /// Номер столбца, в котором стоит число, или `null`, если числа нет.
  int? columnOf(int number) {
    for (var column = 0; column < columnCount; column++) {
      for (var row = 0; row < rowCount; row++) {
        if (rows[row][column] == number) return column;
      }
    }
    return null;
  }

  @override
  String toString() => 'LotoCard(${numbers.join(',')})';
}

/// Как выиграть партию.
///
/// Детская версия — закрыть одну строку: это быстро, понятно и всегда
/// получается. Вся карточка — вариант «посложнее», его включают в настройках
/// или в лобби сетевой игры.
enum WinMode {
  row('Закрыть строку', 'Пять чисел в одной строке — и победа!'),
  fullCard('Закрыть всю карточку', 'Все пятнадцать чисел. Для самых смелых!');

  const WinMode(this.label, this.description);

  final String label;
  final String description;

  static WinMode fromName(Object? name) => WinMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => WinMode.row,
  );
}

/// Чем закончилась попытка закрыть число.
enum CloseStatus {
  closed,
  alreadyClosed,
  notOnCard,
  notDrawn,
  unknownPlayer,
  gameOver,
}

/// Подсказка для ребёнка: почему число не закрылось.
extension CloseStatusHint on CloseStatus {
  String get hint => switch (this) {
    CloseStatus.closed => '',
    CloseStatus.alreadyClosed => 'Это число уже закрыто',
    CloseStatus.notOnCard => 'Этого числа нет на карточке',
    CloseStatus.notDrawn => 'Этот бочонок ещё в мешке',
    CloseStatus.unknownPlayer => 'Такого игрока нет',
    CloseStatus.gameOver => 'Партия уже закончилась',
  };
}

/// Участник партии: имя, карточка и закрытые числа.
///
/// Одна и та же модель описывает и живого игрока, и компьютерного соперника,
/// и соседа по сети. Флаги [connected] и [ready] нужны лобби сетевой игры,
/// остальные поля — самой партии.
@immutable
class LotoPlayer {
  const LotoPlayer({
    required this.id,
    required this.name,
    required this.card,
    this.isComputer = false,
    this.isHost = false,
    this.ready = false,
    this.connected = true,
    this.closed = const <int>{},
  });

  final String id;
  final String name;
  final LotoCard card;
  final bool isComputer;
  final bool isHost;
  final bool ready;
  final bool connected;

  /// Числа карточки, закрытые жетонами.
  final Set<int> closed;

  bool get isHuman => !isComputer;

  int get closedCount => closed.length;

  bool hasWon(WinMode mode) => LotoRules.hasWon(
    card: card,
    closed: closed,
    mode: mode,
  );

  /// Сколько вытянутых чисел ещё ждут своего жетона.
  int pendingClose(Iterable<int> drawn) => LotoRules.pendingClose(
    card: card,
    closed: closed,
    drawn: drawn,
  );

  LotoPlayer copyWith({
    String? name,
    bool? isComputer,
    bool? isHost,
    bool? ready,
    bool? connected,
    Set<int>? closed,
  }) => LotoPlayer(
    id: id,
    name: name ?? this.name,
    card: card,
    isComputer: isComputer ?? this.isComputer,
    isHost: isHost ?? this.isHost,
    ready: ready ?? this.ready,
    connected: connected ?? this.connected,
    closed: closed ?? this.closed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'card': card.toJson(),
    'isComputer': isComputer,
    'isHost': isHost,
    'closed': List<int>.of(closed, growable: false),
  };

  factory LotoPlayer.fromJson(Object? data) {
    if (data is! Map) {
      throw const FormatException('Игрок не распознан');
    }
    final id = data['id'];
    final name = data['name'];
    final cardRaw = data['card'];
    final isComputer = data['isComputer'];
    final isHost = data['isHost'];
    final closedRaw = data['closed'];
    if (id is! String || name is! String) {
      throw const FormatException('Игрок не распознан: имя');
    }
    if (isComputer is! bool || isHost is! bool) {
      throw const FormatException('Игрок не распознан: флаги');
    }
    if (closedRaw is! List) {
      throw const FormatException('Игрок не распознан: закрытые');
    }
    final closed = <int>{};
    for (final value in closedRaw) {
      if (value is! int ||
          value < Barrel.min ||
          value > Barrel.max ||
          !closed.add(value)) {
        throw const FormatException('Игрок не распознан: закрытые');
      }
    }
    return LotoPlayer(
      id: id,
      name: name,
      card: LotoCard.fromJson(cardRaw),
      isComputer: isComputer,
      isHost: isHost,
      closed: Set<int>.unmodifiable(closed),
    );
  }

  @override
  String toString() => 'LotoPlayer($id, $name)';
}

/// Итог попытки закрыть число вместе с новым состоянием партии.
@immutable
class CloseOutcome {
  const CloseOutcome(this.game, this.status);

  final LotoGame game;
  final CloseStatus status;

  bool get accepted => status == CloseStatus.closed;
}

/// Партия в лото целиком: игроки, мешок, вытянутые бочонки и победитель.
///
/// Состояние неизменяемое. Вытянуть бочонок или закрыть число — значит
/// получить новое состояние, поэтому отмена хода в одиночной игре и в сети
/// сводится к возврату предыдущего состояния: ничего не нужно «разбирать»
/// вручную и невозможно забыть вернуть бочонок в мешок.
@immutable
class LotoGame {
  const LotoGame._({
    required this.players,
    required this.winMode,
    required this.bag,
    required this.drawn,
    this.winnerId,
    this.winningRow,
  });

  /// Раздача: карточки уже готовы, мешок перемешан.
  factory LotoGame.start({
    required List<LotoPlayer> players,
    required WinMode winMode,
    Random? random,
    BarrelBag? bag,
  }) => LotoGame._(
    players: List<LotoPlayer>.unmodifiable(players),
    winMode: winMode,
    bag: bag ?? BarrelBag.shuffled(random: random),
    drawn: const [],
  );

  /// Копия партии на другом устройстве.
  ///
  /// Мешок клиенту не нужен: он не тянет бочонки сам, а показывает то, что
  /// объявил хост. Число оставшихся бочонков считается по истории.
  factory LotoGame.replica({
    required List<LotoPlayer> players,
    required WinMode winMode,
    required List<int> drawn,
    String? winnerId,
    int? winningRow,
  }) => LotoGame._(
    players: List<LotoPlayer>.unmodifiable(players),
    winMode: winMode,
    bag: BarrelBag.empty(),
    drawn: List<int>.unmodifiable(drawn),
    winnerId: winnerId,
    winningRow: winningRow,
  );

  final List<LotoPlayer> players;
  final WinMode winMode;
  final BarrelBag bag;

  /// История вытянутых чисел в том порядке, в котором их объявляли.
  final List<int> drawn;

  final String? winnerId;

  /// Строка, которую закрыл победитель (для значка «закрыл строку»).
  final int? winningRow;

  bool get isOver => winnerId != null;

  int get barrelsLeft => BarrelBag.total - drawn.length;

  bool get isBagEmpty => barrelsLeft <= 0;

  Barrel? get lastBarrel => drawn.isEmpty ? null : Barrel(drawn.last);

  Set<int> get drawnSet => drawn.toSet();

  LotoPlayer? get winner =>
      winnerId == null ? null : playerById(winnerId!);

  LotoPlayer? playerById(String id) {
    for (final player in players) {
      if (player.id == id) return player;
    }
    return null;
  }

  int indexOf(String id) {
    for (var index = 0; index < players.length; index++) {
      if (players[index].id == id) return index;
    }
    return -1;
  }

  /// Игроки, которые ещё не закрыли последний вытянутый бочонок.
  ///
  /// Компьютер-ведущий смотрит на этот список и не тянет следующий бочонок,
  /// пока ребёнок не закроет свой: догонять игру никогда не приходится.
  List<LotoPlayer> get pendingClosers {
    final barrel = lastBarrel;
    if (barrel == null) return const [];
    return [
      for (final player in players)
        if (LotoRules.canClose(
          card: player.card,
          closed: player.closed,
          drawn: drawn,
          number: barrel.number,
        ))
          player,
    ];
  }

  bool get waitsForPlayers => pendingClosers.isNotEmpty;

  /// Вытягивает следующий бочонок. Когда мешок пуст или партия закончена,
  /// возвращается то же состояние.
  LotoGame draw() {
    final number = bag.next;
    if (number == null || isOver) return this;
    return _copy(
      bag: bag.take(),
      drawn: List<int>.unmodifiable([...drawn, number]),
    );
  }

  /// Объявляет бочонок на устройстве клиента: мешка там нет, история есть.
  LotoGame announce(int number) => _copy(
    drawn: List<int>.unmodifiable([...drawn, number]),
  );

  CloseOutcome close({required String playerId, required int number}) {
    if (isOver) return CloseOutcome(this, CloseStatus.gameOver);
    final player = playerById(playerId);
    if (player == null) return CloseOutcome(this, CloseStatus.unknownPlayer);
    final status = LotoRules.checkCloseFields(
      card: player.card,
      closed: player.closed,
      drawn: drawn,
      number: number,
    );
    if (status != CloseStatus.closed) return CloseOutcome(this, status);
    final closed = Set<int>.unmodifiable({...player.closed, number});
    final updated = player.copyWith(closed: closed);
    var next = replacePlayer(updated);
    if (LotoRules.hasWon(card: updated.card, closed: closed, mode: winMode)) {
      next = LotoGame._(
        players: next.players,
        winMode: winMode,
        bag: next.bag,
        drawn: next.drawn,
        winnerId: playerId,
        winningRow: LotoRules.closedRowIndex(
          card: updated.card,
          closed: closed,
        ),
      );
    }
    return CloseOutcome(next, CloseStatus.closed);
  }

  LotoGame replacePlayer(LotoPlayer player) => LotoGame._(
    players: List<LotoPlayer>.unmodifiable([
      for (final existing in players)
        if (existing.id == player.id) player else existing,
    ]),
    winMode: winMode,
    bag: bag,
    drawn: drawn,
    winnerId: winnerId,
    winningRow: winningRow,
  );

  LotoGame withPlayers(List<LotoPlayer> updated) => LotoGame._(
    players: List<LotoPlayer>.unmodifiable(updated),
    winMode: winMode,
    bag: bag,
    drawn: drawn,
    winnerId: winnerId,
    winningRow: winningRow,
  );

  LotoGame declareWinner(String playerId, {int? row}) => LotoGame._(
    players: players,
    winMode: winMode,
    bag: bag,
    drawn: drawn,
    winnerId: playerId,
    winningRow: row,
  );

  LotoGame _copy({BarrelBag? bag, List<int>? drawn}) => LotoGame._(
    players: players,
    winMode: winMode,
    bag: bag ?? this.bag,
    drawn: drawn ?? this.drawn,
    winnerId: winnerId,
    winningRow: winningRow,
  );

  @override
  String toString() =>
      'LotoGame(players=${players.length}, drawn=${drawn.length})';
}
