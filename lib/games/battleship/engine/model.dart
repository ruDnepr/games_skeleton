/// Модели морского боя: корабли, флот, выстрелы, состояние партии.
///
/// Файл чистый Dart — без Flutter, — поэтому движок можно тестировать без
/// платформы и переиспользовать в любом интерфейсе. Поле 10×10, столбцы
/// подписаны буквами слова «РЕСПУБЛИКА» (Р Е С П У Б Л И К А), строки — 1..10.
/// Классический набор кораблей: 1 линкор (4), 2 крейсера (3), 3 эсминца (2)
/// и 4 подлодки (1) — 10 кораблей, 20 палуб всего. Корабли не касаются друг
/// друга ни бортом, ни углом.
library;

/// Буквы столбцов поля — слово «РЕСПУБЛИКА». Ровно 10 неповторяющихся букв,
/// поэтому координата «У4» или «К10» читается однозначно.
const List<String> columnLetters = [
  'Р',
  'Е',
  'С',
  'П',
  'У',
  'Б',
  'Л',
  'И',
  'К',
  'А',
];

/// Размер стороны поля морского боя.
const int boardSize = 10;

/// Тип корабля и его габариты: длина и сколько таких кораблей во флоте.
///
/// Порядок важен — от большого к маленькому: так удобнее расставлять и
/// показывать «арсенал» в интерфейсе.
enum ShipType {
  battleship(size: 4, count: 1, russianLabel: 'Линкор'),
  cruiser(size: 3, count: 2, russianLabel: 'Крейсер'),
  destroyer(size: 2, count: 3, russianLabel: 'Эсминец'),
  submarine(size: 1, count: 4, russianLabel: 'Подлодка');

  const ShipType({
    required this.size,
    required this.count,
    required this.russianLabel,
  });

  /// Число клеток, которые занимает корабль.
  final int size;

  /// Сколько таких кораблей в полном флоте.
  final int count;

  /// Детское название для интерфейса.
  final String russianLabel;
}

/// Сколько всего кораблей в стандартном флоте (1+2+3+4 = 10).
int get totalShips =>
    ShipType.values.fold(0, (sum, t) => sum + t.count);

/// Сколько всего палуб в стандартном флоте (4+6+6+4 = 20).
int get totalDecks =>
    ShipType.values.fold(0, (sum, t) => sum + t.size * t.count);

/// Ориентация корабля на поле.
enum Orientation { horizontal, vertical }

extension OrientationX on Orientation {
  /// Противоположная ориентация — для поворота корабля кнопкой.
  Orientation get flipped => this == Orientation.horizontal
      ? Orientation.vertical
      : Orientation.horizontal;

  /// Подпись для интерфейса.
  String get russianLabel =>
      this == Orientation.horizontal ? 'горизонтально' : 'вертикально';
}

/// Одна клетка поля 10×10. Равенство по координатам, поэтому годится как
/// ключ мапы.
class Square {
  const Square(this.row, this.col);

  /// Строка 0..9 (выводится как 1..10).
  final int row;

  /// Столбец 0..9 (выводится буквой из [columnLetters]).
  final int col;

  /// Лежит ли клетка в пределах поля 10×10.
  bool get inside =>
      row >= 0 && col >= 0 && row < boardSize && col < boardSize;

  /// Буква столбца («Р»…«А»).
  String get letter => columnLetters[col];

  /// Номер строки 1..10.
  int get number => row + 1;

  /// Координата вида «У4», «К10», «А1».
  @override
  String toString() => '$letter$number';

  /// Сетевой формат: пара чисел `[row, col]`.
  List<int> toJson() => [row, col];

  /// Обратный разбор — с проверкой, что пара лежит на доске 10×10.
  factory Square.fromJson(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! int ||
        value[1] is! int) {
      throw const FormatException('Некорректная клетка');
    }
    final square = Square(value[0] as int, value[1] as int);
    if (!square.inside) throw const FormatException('Клетка вне доски');
    return square;
  }

  /// Разбор координаты вида «У4», «К10», «а1» (буква нечувствительна к регистру).
  /// Бросает [FormatException] при ошибке — для текстового ввода и подсказок.
  factory Square.parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Пустая координата');
    }
    final upper = trimmed.toUpperCase();
    final byLetter = _matchLetter(upper);
    if (byLetter != null) return byLetter;
    // Запасной вариант: латиница A..J — на случай опечатки.
    if (upper.length >= 2 && upper.length <= 3) {
      final code = upper.codeUnitAt(0);
      if (code >= 0x41 && code <= 0x4A) {
        final col = code - 0x41;
        final n = int.tryParse(upper.substring(1));
        if (n != null && n >= 1 && n <= boardSize && col < boardSize) {
          return Square(n - 1, col);
        }
      }
    }
    throw const FormatException('Не разобрать координату');
  }

  static Square? _matchLetter(String upper) {
    if (upper.isEmpty) return null;
    final first = upper[0];
    final col = columnLetters.indexWhere(
      (l) => l == first || l.toUpperCase() == first,
    );
    if (col < 0) return null;
    final rest = upper.substring(1);
    final n = int.tryParse(rest);
    if (n == null || n < 1 || n > boardSize) return null;
    return Square(n - 1, col);
  }

  @override
  bool operator ==(Object other) =>
      other is Square && row == other.row && col == other.col;

  @override
  int get hashCode => Object.hash(row, col);
}

/// Корабль, поставленный на поле.
///
/// [origin] — верхняя-левая клетка корабля (минимальные row и col). Для
/// горизонтали корабль тянется вправо от [origin], для вертикали — вниз.
class Ship {
  const Ship({
    required this.type,
    required this.origin,
    required this.orientation,
  });

  final ShipType type;
  final Square origin;
  final Orientation orientation;

  /// Все клетки, занятые кораблём, по порядку от носа к корме.
  List<Square> get cells {
    final result = <Square>[];
    for (var i = 0; i < type.size; i++) {
      result.add(
        orientation == Orientation.horizontal
            ? Square(origin.row, origin.col + i)
            : Square(origin.row + i, origin.col),
      );
    }
    return result;
  }

  /// Помещается ли корабль целиком в пределах поля 10×10.
  bool get fits {
    for (final c in cells) {
      if (!c.inside) return false;
    }
    return true;
  }

  /// Стоит ли корабль в клетке [square].
  bool occupies(Square square) => cells.contains(square);

  /// Сетевой формат: [row, col, orientation, type]. В новой игре не используется
  /// (флоты по сети не пересылаются), но оставлен для тестов и сохранений.
  Map<String, Object> toJson() => {
        'row': origin.row,
        'col': origin.col,
        'horizontal': orientation == Orientation.horizontal,
        'type': type.name,
      };

  factory Ship.fromJson(Object? value) {
    if (value is! Map ||
        value['row'] is! int ||
        value['col'] is! int ||
        value['horizontal'] is! bool ||
        value['type'] is! String) {
      throw const FormatException('Некорректный корабль');
    }
    final type = ShipType.values
        .where((t) => t.name == value['type'])
        .firstOrNull;
    if (type == null) throw const FormatException('Неизвестный тип корабля');
    return Ship(
      type: type,
      origin: Square(value['row'] as int, value['col'] as int),
      orientation: value['horizontal'] as bool
          ? Orientation.horizontal
          : Orientation.vertical,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ship &&
      type == other.type &&
      origin == other.origin &&
      orientation == other.orientation;

  @override
  int get hashCode => Object.hash(type, origin, orientation);
}

/// Флот игрока: набор поставленных кораблей. Правила расстановки (без касаний)
/// проверяются в [BattleshipRules], а не здесь: флот может быть «в процессе
/// сборки» и временно неполным.
class Fleet {
  const Fleet(this.ships);

  final List<Ship> ships;

  /// Сколько кораблей каждого типа уже поставлено.
  int countOf(ShipType type) =>
      ships.where((s) => s.type == type).length;

  /// Все ли корабли нужных типов на месте.
  bool get isComplete =>
      ShipType.values.every((t) => countOf(t) == t.count);

  /// Занята ли клетка каким-либо кораблём флота.
  bool occupies(Square square) => ships.any((s) => s.occupies(square));

  /// Корабль, стоящий в клетке, или null.
  Ship? shipAt(Square square) {
    for (final s in ships) {
      if (s.occupies(square)) return s;
    }
    return null;
  }

  /// Все клетки, занятые кораблями флота.
  Set<Square> get occupiedCells =>
      ships.expand((s) => s.cells).toSet();

  /// Число палуб, в которые уже попали (по списку выстрелов по этому флоту).
  int hitsFrom(Iterable<Square> firedAt) {
    final occ = occupiedCells;
    var n = 0;
    for (final s in firedAt) {
      if (occ.contains(s)) n++;
    }
    return n;
  }

  /// Сетевой формат — список кораблей. В игре не используется (флоты по сети
  /// не пересылаются), но полезен для сохранений и тестов.
  List<Map<String, Object>> toJson() =>
      ships.map((s) => s.toJson()).toList();

  @override
  String toString() => 'Fleet(${ships.length} кораблей)';
}

/// Пустой флот — удобно для старта расстановки.
final Fleet emptyFleet = Fleet(const []);

/// Результат выстрела по клетке.
enum ShotResult {
  /// Мимо — клетка пустая.
  miss,

  /// Попадание в корабль, но корабль ещё не потоплен.
  hit,

  /// Попадание, добившее корабль: все его клетки теперь пробиты.
  sunk,
}

extension ShotResultX on ShotResult {
  String get russianLabel => switch (this) {
        ShotResult.miss => 'Мимо',
        ShotResult.hit => 'Попадание',
        ShotResult.sunk => 'Потоплен',
      };
}

/// Один выстрел: куда стреляли и что вышло.
class Shot {
  const Shot({required this.square, required this.result, this.sunkType});

  final Square square;
  final ShotResult result;

  /// Тип потопленного корабля, если [result] == [ShotResult.sunk]. Нужен,
  /// чтобы красиво обвести контур и сказать «Потоплен крейсер!».
  final ShipType? sunkType;

  Map<String, Object?> toJson() => {
        'square': square.toJson(),
        'result': result.name,
        if (sunkType != null) 'sunkType': sunkType!.name,
      };

  factory Shot.fromJson(Object? value) {
    if (value is! Map ||
        value['square'] is! List ||
        value['result'] is! String) {
      throw const FormatException('Некорректный выстрел');
    }
    final result = ShotResult.values
        .where((r) => r.name == value['result'])
        .firstOrNull;
    if (result == null) throw const FormatException('Неизвестный результат');
    final sunkName = value['sunkType'];
    ShipType? sunkType;
    if (sunkName is String) {
      sunkType = ShipType.values
          .where((t) => t.name == sunkName)
          .firstOrNull;
    }
    return Shot(
      square: Square.fromJson(value['square']),
      result: result,
      sunkType: sunkType,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Shot && square == other.square && result == other.result;

  @override
  int get hashCode => Object.hash(square, result);
}

/// Чей сейчас ход. В морском бое нет «цветов», но имя удобнее, чем булево.
enum Side { me, enemy }

extension SideX on Side {
  Side get opponent => this == Side.me ? Side.enemy : Side.me;

  String get russianLabel => this == Side.me ? 'Ты' : 'Соперник';
}

/// Поле одного игрока: свой флот + выстрелы противника по нему.
class MyBoard {
  const MyBoard({required this.fleet, required this.incoming});

  final Fleet fleet;

  /// Выстрелы соперника по моему полю: клетка → результат.
  final Map<Square, ShotResult> incoming;

  /// По клетке моего поля: стреляли ли в неё и каков итог.
  ShotResult? resultAt(Square square) => incoming[square];

  /// Жив ли ещё корабль (не все его клетки пробиты).
  bool isAlive(Ship ship) =>
      !ship.cells.every((c) => incoming[c] != null);

  /// Сколько моих кораблей потоплено.
  int get sunkCount => ships.where((s) => !isAlive(s)).length;

  /// Все мои корабли.
  List<Ship> get ships => fleet.ships;

  /// Все ли мои корабли потоплены — это поражение.
  bool get allSunk =>
      ships.isNotEmpty && ships.every((s) => !isAlive(s));
}

/// Поле соперника с моей точки зрения: куда я стрелял и что узнал. Кораблей
/// соперника не видно — «туман войны».
class EnemyBoard {
  const EnemyBoard(this.shots);

  /// Мои выстрелы по сопернику: клетка → выстрел с результатом.
  final Map<Square, Shot> shots;

  /// Был ли выстрел в эту клетку.
  bool firedAt(Square square) => shots.containsKey(square);

  Shot? at(Square square) => shots[square];

  /// Клетки с попаданием (hit или sunk) — для добивания ИИ и подсказок.
  Set<Square> get hits => shots.values
      .where((s) => s.result != ShotResult.miss)
      .map((s) => s.square)
      .toSet();

  /// Клетки, по которым ещё не стреляли.
  Set<Square> get unfired =>
      allSquares().where((s) => !shots.containsKey(s)).toSet();
}

/// Кто ходит, чьи выстрелы и где. Состояние партии без истории хода: история
/// хранится отдельно в [ShotHistory], а здесь — снимок «как сейчас».
class GameState {
  const GameState({
    required this.turn,
    required this.myBoard,
    required this.enemyBoard,
    this.winner,
  });

  /// Чей сейчас выстрел.
  final Side turn;

  /// Моё поле: мои корабли и выстрелы соперника по мне.
  final MyBoard myBoard;

  /// Поле соперника: мои выстрелы и их результаты.
  final EnemyBoard enemyBoard;

  /// Победитель, если партия окончена; иначе null.
  final Side? winner;

  bool get isOver => winner != null;

  /// Копия с изменённым состоянием.
  GameState copyWith({
    Side? turn,
    MyBoard? myBoard,
    EnemyBoard? enemyBoard,
    Side? winner,
  }) =>
      GameState(
        turn: turn ?? this.turn,
        myBoard: myBoard ?? this.myBoard,
        enemyBoard: enemyBoard ?? this.enemyBoard,
        winner: winner ?? this.winner,
      );
}

/// Все клетки поля в порядке «строки сверху вниз».
Iterable<Square> allSquares() sync* {
  for (var r = 0; r < boardSize; r++) {
    for (var c = 0; c < boardSize; c++) {
      yield Square(r, c);
    }
  }
}

/// Клетки, соседние с [center] по борту и углам (в пределах поля).
Iterable<Square> neighboursOf(Square center) sync* {
  const directions = [
    Square(-1, -1),
    Square(-1, 0),
    Square(-1, 1),
    Square(0, -1),
    Square(0, 1),
    Square(1, -1),
    Square(1, 0),
    Square(1, 1),
  ];
  for (final d in directions) {
    final s = Square(center.row + d.row, center.col + d.col);
    if (s.inside) yield s;
  }
}
