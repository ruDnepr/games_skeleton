/// Модели домино: кости, цепочка, ход, партия.
///
/// Чистый Dart: ни Flutter, ни Rivera, ни звука — только правила и данные.
/// Так движок работает и в тестах, и в контроллере, и в сети.
library;

import 'dart:math';

/// Сколько точек может быть на половине костяшки: 0…6.
const maxPip = 6;

/// Сколько костей получает каждый игрок при раздаче.
const tilesPerPlayer = 7;

/// Классический набор: 28 костей от 0:0 до 6:6.
const deckSize = 28;

const minPlayers = 2;
const maxPlayers = 4;

/// Сторона цепочки, к которой приставляют кость.
enum ChainSide {
  left('налево'),
  right('направо');

  const ChainSide(this.label);

  final String label;

  ChainSide get opposite =>
      this == ChainSide.left ? ChainSide.right : ChainSide.left;
}

/// Одна костяшка домино: две половинки с точками.
///
/// Кость 3:5 и кость 5:3 — это одна и та же кость, поэтому равенство идёт по
/// значениям без учёта порядка, а порядок нужен только для показа на экране.
class DominoTile {
  const DominoTile(this.a, this.b)
    : assert(a >= 0 && a <= maxPip),
      assert(b >= 0 && b <= maxPip);

  final int a;
  final int b;

  /// Читает кость из строки «3:5».
  factory DominoTile.parse(String text) {
    final parts = text.split(':');
    if (parts.length != 2) {
      throw FormatException('Кость записана неверно: $text');
    }
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null || a < 0 || a > maxPip || b < 0 || b > maxPip) {
      throw FormatException('Кость записана неверно: $text');
    }
    return DominoTile(a, b);
  }

  /// Разбирает значение, пришедшее из сети.
  factory DominoTile.fromJson(Object? data) {
    if (data is String) return DominoTile.parse(data);
    if (data is Map && data['a'] is int && data['b'] is int) {
      return DominoTile(data['a'] as int, data['b'] as int);
    }
    throw const FormatException('Кость не распознана');
  }

  bool get isDouble => a == b;

  int get sum => a + b;

  /// Сумма очков: дубль стоит вдвое больше, поэтому его выгодно выложить.
  int get weight => isDouble ? sum * 2 : sum;

  /// Есть ли на кости нужное число точек.
  bool matches(int pip) => a == pip || b == pip;

  /// Второе число кости, если первое равно [pip].
  int other(int pip) => a == pip ? b : a;

  DominoTile get flipped => DominoTile(b, a);

  /// Каноническая запись без учёта порядка — годится для ключей и сравнений.
  String get label => a <= b ? '$a:$b' : '$b:$a';

  /// Запись для ключей виджетов.
  String get key => 'tile-${a <= b ? a : b}-${a <= b ? b : a}';

  Map<String, Object> toJson() => {'a': a, 'b': b};

  @override
  bool operator ==(Object other) =>
      other is DominoTile &&
      ((other.a == a && other.b == b) || (other.a == b && other.b == a));

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => label;

  static int compare(DominoTile first, DominoTile second) {
    final byA = first.a.compareTo(second.a);
    return byA != 0 ? byA : first.b.compareTo(second.b);
  }
}

/// Все 28 костей набора.
List<DominoTile> fullDeck() => [
  for (var a = 0; a <= maxPip; a++)
    for (var b = a; b <= maxPip; b++) DominoTile(a, b),
];

/// Кость, которая уже лежит в цепочке.
///
/// [left] — число, смотрящее в левый конец цепочки, [right] — в правый.
/// У дубля оба числа одинаковы, и на столе он рисуется поперёк цепочки.
class PlacedTile {
  const PlacedTile({required this.tile, required this.left, required this.right});

  final DominoTile tile;
  final int left;
  final int right;

  /// Дубль выкладывается поперёк цепочки.
  bool get isAcross => left == right;

  /// Собирает кость, которую приставляют к концу со значением [end].
  factory PlacedTile.facing(DominoTile tile, ChainSide side, int end) {
    if (!tile.matches(end)) {
      throw ArgumentError('Кость $tile не подходит к концу $end');
    }
    final far = tile.other(end);
    return side == ChainSide.left
        ? PlacedTile(tile: tile, left: far, right: end)
        : PlacedTile(tile: tile, left: end, right: far);
  }

  /// Читает кость из записи «3:5», где первое число смотрит налево.
  factory PlacedTile.parse(String text) {
    final parts = text.split(':');
    if (parts.length != 2) {
      throw FormatException('Кость в цепочке записана неверно: $text');
    }
    final left = int.tryParse(parts[0]);
    final right = int.tryParse(parts[1]);
    if (left == null ||
        right == null ||
        left < 0 ||
        left > maxPip ||
        right < 0 ||
        right > maxPip) {
      throw FormatException('Кость в цепочке записана неверно: $text');
    }
    return PlacedTile(tile: DominoTile(left, right), left: left, right: right);
  }

  String encode() => '$left:$right';

  @override
  bool operator ==(Object other) =>
      other is PlacedTile &&
      other.left == left &&
      other.right == right &&
      other.tile == tile;

  @override
  int get hashCode => Object.hash(tile, left, right);

  @override
  String toString() => '$left:$right';
}

/// Цепочка костей на столе вместе с открытыми концами.
class Board {
  Board([List<PlacedTile> chain = const []])
    : chain = List<PlacedTile>.unmodifiable(chain);

  const Board.empty() : chain = const [];

  /// Читает цепочку из списка записей «3:5».
  factory Board.fromJson(Object? data) {
    if (data == null) return const Board.empty();
    if (data is! List) throw const FormatException('Цепочка не распознана');
    return Board([for (final entry in data) PlacedTile.parse('$entry')]);
  }

  final List<PlacedTile> chain;

  bool get isEmpty => chain.isEmpty;
  bool get isNotEmpty => chain.isNotEmpty;
  int get length => chain.length;

  /// Число точек на левом конце, если цепочка уже начата.
  int? get leftEnd => chain.isEmpty ? null : chain.first.left;

  /// Число точек на правом конце, если цепочка уже начата.
  int? get rightEnd => chain.isEmpty ? null : chain.last.right;

  /// Кости, которые уже лежат на столе.
  List<DominoTile> get tiles => [for (final placed in chain) placed.tile];

  /// К каким концам подходит кость. Пустая цепочка принимает любую кость.
  List<ChainSide> sidesFor(DominoTile tile) {
    if (chain.isEmpty) return const [ChainSide.right];
    final sides = <ChainSide>[];
    if (tile.matches(leftEnd!)) sides.add(ChainSide.left);
    if (tile.matches(rightEnd!)) sides.add(ChainSide.right);
    return sides;
  }

  bool canPlace(DominoTile tile) => sidesFor(tile).isNotEmpty;

  /// Ставит кость к выбранному концу. Кость должна подходить.
  Board place(DominoTile tile, ChainSide side) {
    if (chain.isEmpty) {
      return Board([PlacedTile(tile: tile, left: tile.a, right: tile.b)]);
    }
    final end = side == ChainSide.left ? leftEnd! : rightEnd!;
    final placed = PlacedTile.facing(tile, side, end);
    return side == ChainSide.left
        ? Board([placed, ...chain])
        : Board([...chain, placed]);
  }

  List<String> toJson() => [for (final placed in chain) placed.encode()];

  /// Короткая подпись цепочки — для проверки, что у всех сторон одна позиция.
  String get fingerprint =>
      chain.map((placed) => placed.encode()).join(',');

  @override
  bool operator ==(Object other) =>
      other is Board && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;

  @override
  String toString() => fingerprint;
}

/// Один ход: какую кость и к какому концу поставить.
class DominoMove {
  const DominoMove({required this.tile, required this.side});

  final DominoTile tile;
  final ChainSide side;

  /// Запись для сети и истории: `{'tile': '3:5', 'side': 'right'}`.
  Map<String, Object> toJson() => {'tile': tile.label, 'side': side.name};

  factory DominoMove.fromJson(Object? data) {
    if (data is! Map || data['tile'] is! String || data['side'] is! String) {
      throw const FormatException('Ход не распознан');
    }
    final side = ChainSide.values
        .where((value) => value.name == data['side'])
        .firstOrNull;
    if (side == null) throw const FormatException('Сторона хода неизвестна');
    return DominoMove(
      tile: DominoTile.parse(data['tile'] as String),
      side: side,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DominoMove && other.tile == tile && other.side == side;

  @override
  int get hashCode => Object.hash(tile, side);

  @override
  String toString() => '${tile.label} ${side.label}';
}

/// Чем закончилась партия.
enum ResultKind {
  /// Кто-то выложил все свои кости.
  win,

  /// «Рыба»: ходов нет ни у кого и базар пуст.
  fish,

  /// «Рыба» с равной суммой очков на руках.
  draw,
}

class GameResult {
  const GameResult({required this.kind, required this.sums, this.winner});

  final ResultKind kind;

  /// Номер места победителя; у ничьей победителя нет.
  final int? winner;

  /// Сумма очков на руках у каждого игрока в момент окончания.
  final List<int> sums;

  bool get isDraw => winner == null;
  bool get isFish => kind == ResultKind.fish;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'winner': winner,
    'sums': sums,
  };

  factory GameResult.fromJson(Object? data) {
    if (data is! Map || data['kind'] is! String || data['sums'] is! List) {
      throw const FormatException('Итог партии не распознан');
    }
    final kind = ResultKind.values
        .where((value) => value.name == data['kind'])
        .firstOrNull;
    final winner = data['winner'];
    if (kind == null || (winner != null && winner is! int)) {
      throw const FormatException('Итог партии не распознан');
    }
    final sums = <int>[];
    for (final value in data['sums'] as List) {
      if (value is! int) {
        throw const FormatException('Суммы не распознаны');
      }
      sums.add(value);
    }
    return GameResult(kind: kind, winner: winner as int?, sums: sums);
  }

  @override
  bool operator ==(Object other) =>
      other is GameResult &&
      other.kind == kind &&
      other.winner == winner &&
      other.sums.length == sums.length &&
      Iterable<int>.generate(sums.length).every(
        (i) => other.sums[i] == sums[i],
      );

  @override
  int get hashCode => Object.hash(kind, winner, Object.hashAll(sums));
}

const _unset = Object();

/// Всё состояние партии: стол, руки, базар и чья очередь.
///
/// В сетевой игре каждое устройство знает только свою руку: чужие руки здесь
/// пустые, а их размер лежит в [handSizes]. Так гость не может подсмотреть
/// кости соперника, хотя играет по тем же правилам.
class GameState {
  GameState({
    required this.playerCount,
    required List<List<DominoTile>> hands,
    List<int>? sizes,
    List<DominoTile> bazaar = const [],
    int? bazaarTotal,
    this.board = const Board.empty(),
    required this.turn,
    this.ply = 0,
    Set<int> inactive = const {},
    this.result,
  }) : assert(playerCount >= minPlayers && playerCount <= maxPlayers),
       assert(turn >= 0 && turn < playerCount),
       hands = _freezeHands(hands),
       handSizes = _freezeSizes(hands, sizes),
       bazaar = List<DominoTile>.unmodifiable(bazaar),
       bazaarCount = bazaarTotal ?? bazaar.length,
       inactive = Set<int>.unmodifiable(inactive),
       assert(sizes == null || sizes.length == playerCount),
       assert(bazaarTotal == null || bazaarTotal >= 0);

  static List<List<DominoTile>> _freezeHands(List<List<DominoTile>> hands) =>
      List<List<DominoTile>>.unmodifiable([
        for (final hand in hands) List<DominoTile>.unmodifiable(hand),
      ]);

  static List<int> _freezeSizes(
    List<List<DominoTile>> hands,
    List<int>? sizes,
  ) => List<int>.unmodifiable([
    for (var seat = 0; seat < hands.length; seat++)
      sizes != null && seat < sizes.length ? sizes[seat] : hands[seat].length,
  ]);

  final int playerCount;

  /// Кости на руках. У чужих игроков в сети список пуст: содержимое неизвестно.
  final List<List<DominoTile>> hands;

  /// Сколько костей на руке у каждого игрока — это известно всегда.
  final List<int> handSizes;

  /// Кости, которые лежат в базаре и известны этому устройству.
  final List<DominoTile> bazaar;

  /// Сколько всего костей в базаре, включая неизвестные.
  final int bazaarCount;

  final Board board;

  /// Чья очередь ходить.
  final int turn;

  /// Сколько действий сделано с начала партии.
  final int ply;

  /// Игроки, которые вышли из партии: их ход пропускается.
  final Set<int> inactive;

  final GameResult? result;

  bool get isOver => result != null;

  int get activePlayers => playerCount - inactive.length;

  List<DominoTile> handOf(int seat) => hands[seat];

  int tilesLeft(int seat) => handSizes[seat];

  /// Все ли руки известны этому устройству целиком.
  bool get allHandsKnown {
    for (var seat = 0; seat < playerCount; seat++) {
      if (hands[seat].length != handSizes[seat]) return false;
    }
    return true;
  }

  /// Сумма очков на руке игрока — нужна для «рыбы» и для подсказок.
  int sumOf(int seat) => hands[seat].fold(0, (sum, tile) => sum + tile.sum);

  /// Суммы очков всех игроков; для неизвестных рук — 0.
  List<int> get sums => [
    for (var seat = 0; seat < playerCount; seat++) sumOf(seat),
  ];

  /// Кости, которые этот игрок уже видел: свои и лежащие на столе.
  List<DominoTile> get visibleTiles => [
    ...board.tiles,
    for (var seat = 0; seat < playerCount; seat++) ...hands[seat],
  ];

  bool isActive(int seat) => !inactive.contains(seat);

  String get fingerprint =>
      '${board.fingerprint}|${handSizes.join('-')}|$bazaarCount|$turn|$ply|'
      '${inactive.toList()..sort()}|${result?.winner}';

  GameState copyWith({
    int? playerCount,
    List<List<DominoTile>>? hands,
    List<int>? sizes,
    List<DominoTile>? bazaar,
    int? bazaarTotal,
    Board? board,
    int? turn,
    int? ply,
    Set<int>? inactive,
    Object? result = _unset,
  }) => GameState(
    playerCount: playerCount ?? this.playerCount,
    hands: hands ?? this.hands,
    // Размеры рук и остаток базара пересчитываются сами, если поменялись
    // сами руки или список костей базара.
    sizes: sizes ?? (hands == null ? handSizes : null),
    bazaar: bazaar ?? this.bazaar,
    bazaarTotal: bazaarTotal ?? (bazaar == null ? bazaarCount : null),
    board: board ?? this.board,
    turn: turn ?? this.turn,
    ply: ply ?? this.ply,
    inactive: inactive ?? this.inactive,
    result: identical(result, _unset) ? this.result : result as GameResult?,
  );

  /// Снимок стола для показа в истории и для отмены хода.
  String describe() {
    final ends = board.isEmpty
        ? 'пусто'
        : '${board.leftEnd} … ${board.rightEnd}';
    return 'стол: $ends; базар: $bazaarCount; ход: ${turn + 1}';
  }

  @override
  String toString() =>
      'GameState(${board.fingerprint}, turn=$turn, ply=$ply)';
}

/// Перемешивает колоду предсказуемым образом, если передан [random].
List<DominoTile> shuffledDeck([Random? random]) {
  final tiles = fullDeck();
  tiles.shuffle(random ?? Random());
  return tiles;
}
