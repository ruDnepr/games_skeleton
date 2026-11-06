/// Модели игры «Го»: цвет камня, точка пересечения, доска, группа с дыханиями,
/// ход и состояние партии. Чистый Dart — без Flutter, — поэтому движок можно
/// тестировать без платформы и переиспользовать в любом интерфейсе.
///
/// Чёрные ходят первыми — так ребёнку проще начать партию.
/// Камни ставятся на пересечения линий, координаты 0..size-1, (0,0) — левый
/// нижний угол.
library;

import 'dart:collection';

/// Цвет камня. В го чёрные всегда ходят первыми.
enum StoneColor { black, white }

extension StoneColorX on StoneColor {
  /// Соперник.
  StoneColor get opponent =>
      this == StoneColor.black ? StoneColor.white : StoneColor.black;

  /// Название для подсказок и интерфейса.
  String get label => this == StoneColor.black ? 'Чёрные' : 'Белые';
}

/// Пересечение линий на доске. Координаты с нуля: (0,0) — левый нижний угол.
class Point implements Comparable<Point> {
  const Point(this.x, this.y);

  final int x;
  final int y;

  bool inside(int size) => x >= 0 && y >= 0 && x < size && y < size;

  /// Соседи по горизонтали и вертикали — только по ним считается «дыхание».
  List<Point> neighbors() => [
        Point(x - 1, y),
        Point(x + 1, y),
        Point(x, y - 1),
        Point(x, y + 1),
      ];

  /// Сетевой формат: пара целых `[x, y]`.
  List<int> toJson() => [x, y];

  factory Point.fromJson(Object? value) {
    if (value is! List ||
        value.length != 2 ||
        value[0] is! int ||
        value[1] is! int) {
      throw const FormatException('Некорректная точка');
    }
    return Point(value[0] as int, value[1] as int);
  }

  /// Столбец буквой (A, B, ...), ряд — цифрой с 1. Как в шахматной нотации го.
  String toNotation() {
    final letter =
        String.fromCharCode(65 + (x >= 8 ? x + 1 : x)); // пропускаем I
    return '$letter${y + 1}';
  }

  @override
  int compareTo(Point other) {
    final r = y.compareTo(other.y);
    return r != 0 ? r : x.compareTo(other.x);
  }

  @override
  bool operator ==(Object other) =>
      other is Point && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// Доска го: сетка пересечений и стоящие на них камни.
class Board {
  Board(this.size, Map<Point, StoneColor> stones)
      : stones = UnmodifiableMapView(Map.of(stones)) {
    if (size != 9 && size != 13 && size != 19) {
      throw ArgumentError.value(size, 'size', 'поддерживаются 9, 13 и 19');
    }
    for (final p in stones.keys) {
      if (!p.inside(size)) {
        throw ArgumentError('Камень $p вне доски $size×$size');
      }
    }
  }

  /// Пустая доска заданного размера.
  factory Board.empty(int size) => Board(size, const {});

  final int size;
  final Map<Point, StoneColor> stones;

  StoneColor? at(Point p) => stones[p];

  bool occupied(Point p) => stones.containsKey(p);

  int count(StoneColor color) =>
      stones.values.where((c) => c == color).length;

  /// Камней какого цвета снято, если с доски [other] убрать камни этой.
  int removedCount(Board other, StoneColor color) =>
      count(color) - other.count(color);

  /// Возвращает новую доску с поставленным камнем (без учёта захватов).
  Board withStone(Point p, StoneColor color) {
    if (occupied(p)) {
      throw StateError('Точка $p уже занята');
    }
    final next = Map<Point, StoneColor>.from(stones);
    next[p] = color;
    return Board(size, next);
  }

  /// Возвращает новую доску без указанных камней.
  Board without(Iterable<Point> points) {
    if (points.isEmpty) return this;
    final next = Map<Point, StoneColor>.from(stones);
    for (final p in points) {
      next.remove(p);
    }
    return Board(size, next);
  }

  /// Звёздные точки (хоси) для ориентира на доске.
  List<Point> starPoints() => switch (size) {
        9 => const [
            Point(2, 2),
            Point(6, 2),
            Point(2, 6),
            Point(6, 6),
            Point(4, 4),
          ],
        13 => const [
            Point(3, 3),
            Point(9, 3),
            Point(3, 9),
            Point(9, 9),
            Point(6, 6),
          ],
        19 => const [
            Point(3, 3),
            Point(9, 3),
            Point(15, 3),
            Point(3, 9),
            Point(9, 9),
            Point(15, 9),
            Point(3, 15),
            Point(9, 15),
            Point(15, 15),
          ],
        _ => const [],
      };

  /// Короткое строковое представление для отладки.
  String grid() {
    final buf = StringBuffer();
    for (var y = size - 1; y >= 0; y--) {
      for (var x = 0; x < size; x++) {
        final s = at(Point(x, y));
        buf.write(s == null ? '.' : (s == StoneColor.black ? 'X' : 'O'));
      }
      buf.writeln();
    }
    return buf.toString();
  }
}

/// Группа камней одного цвета и её «дыхания» — свободные соседние пересечения.
class Group {
  const Group({required this.stones, required this.liberties});

  final Set<Point> stones;
  final Set<Point> liberties;

  int get libertyCount => liberties.length;

  /// Группу можно захватить следующим ходом соперника.
  bool get inAtari => libertyCount == 1;

  bool get isCaptured => libertyCount == 0;

  @override
  String toString() => 'Group(${stones.length} камней, $libertyCount дых.)';
}

/// Режим правил: «Захват» (Capture Go) для первых партий или «Классическое го».
enum GoMode { capture, classic }

extension GoModeX on GoMode {
  String get label => switch (this) {
        GoMode.capture => 'Захват',
        GoMode.classic => 'Классическое го',
      };

  String get subtitle => switch (this) {
        GoMode.capture => 'Первым захвати камень — это просто и весело',
        GoMode.classic => 'Территория и очки, как в настоящем го',
      };
}

/// Цель режима «Захват»: кто первым снимет столько камней соперника.
enum CaptureTarget { one, three }

extension CaptureTargetX on CaptureTarget {
  int get count => switch (this) {
        CaptureTarget.one => 1,
        CaptureTarget.three => 3,
      };
  String get label => '$count ${count == 1 ? 'камень' : 'камня'}';
}

/// Полная конфигурация партии.
class GameSetup {
  const GameSetup({
    required this.mode,
    required this.boardSize,
    this.captureTarget = CaptureTarget.one,
    this.komi = 6.5,
  });

  final GoMode mode;
  final int boardSize; // 9, 13, 19
  final CaptureTarget captureTarget;
  final double komi; // компенсация белым за второй ход

  /// Коми по умолчанию для размера доски.
  static double defaultKomi(int size) => size == 19 ? 7.5 : 6.5;
}

/// Действие игрока: поставить камень в точку [point] или пасовать.
///
/// Пас — пропуск хода. Два паса подряд завершают классическую партию.
class GoMove {
  const GoMove.place(this.point, {required this.color}) : assert(point != null);

  const GoMove.pass({required this.color}) : point = null;

  final Point? point;
  final StoneColor color;

  bool get isPass => point == null;

  Map<String, Object?> toJson() => {
        'color': color.name,
        if (point != null) 'point': point!.toJson(),
        'pass': isPass,
      };

  factory GoMove.fromJson(Object? value) {
    if (value is! Map || value['color'] is! String) {
      throw const FormatException('Некорректный ход');
    }
    final color = StoneColor.values
        .where((c) => c.name == value['color'])
        .firstOrNull;
    if (color == null) {
      throw const FormatException('Некорректный ход');
    }
    final isPass = value['pass'] == true;
    if (isPass) {
      return GoMove.pass(color: color);
    }
    if (value['point'] == null) {
      throw const FormatException('Некорректный ход');
    }
    return GoMove.place(Point.fromJson(value['point']), color: color);
  }

  @override
  bool operator ==(Object other) =>
      other is GoMove && color == other.color && point == other.point;

  @override
  int get hashCode => Object.hash(color, point);

  @override
  String toString() =>
      isPass ? '${color.label}: пас' : '${color.label}: $point';
}

/// Состояние партии го: доска, чей ход, номер хода, счётчик захватов,
/// запрещённая точка ко, число подряд пасов и последний ход.
class GameState {
  const GameState({
    required this.setup,
    required this.board,
    required this.turn,
    this.ply = 0,
    this.koPoint,
    this.consecutivePasses = 0,
    this.blackCaptured = 0,
    this.whiteCaptured = 0,
    this.lastMove,
    this.lastCaptured = const [],
  });

  factory GameState.initial(GameSetup setup) => GameState(
        setup: setup,
        board: Board.empty(setup.boardSize),
        turn: StoneColor.black,
      );

  final GameSetup setup;
  final Board board;
  final StoneColor turn;
  final int ply;

  /// Точка, куда нельзя ходить в этот ход (правило ко). null — ограничений нет.
  final Point? koPoint;

  /// Число пасов подряд. Два паса заканчивают классическую партию.
  final int consecutivePasses;

  /// Сколько камней соперника снял чёрный / белый за партию.
  final int blackCaptured;
  final int whiteCaptured;

  final GoMove? lastMove;

  /// Камни, снятые последним ходом, — для анимации захвата.
  final List<Point> lastCaptured;

  StoneColor get opponent => turn.opponent;

  /// Стабильный отпечаток позиции с номером хода — для протокола и проверки
  /// рассинхрона. Не зависит от порядка перебора карты.
  String get fingerprint => _hash(includePly: true);

  /// Хэш позиции без номера хода: для повтора и правила ко.
  String get positionKey => _hash(includePly: false);

  String _hash({required bool includePly}) {
    var hash = 0x811c9dc5;
    void mix(int n) {
      hash = ((hash ^ n) * 0x01000193) & 0xffffffff;
    }

    mix(setup.boardSize);
    mix(setup.mode.index);
    mix(turn.index);
    if (includePly) mix(ply);
    if (koPoint != null) mix(koPoint!.x * 31 + koPoint!.y);
    for (var y = 0; y < board.size; y++) {
      for (var x = 0; x < board.size; x++) {
        final s = board.at(Point(x, y));
        mix(s == null ? 0 : 1 + s.index);
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Копия состояния с заменой отдельных полей. `koPoint` принимает null:
  /// пас, например, обнуляет запрещённую точку. Поэтому используется
  /// внутренний сентинель — иначе `null` трактовался бы как «оставить старое».
  GameState copyWith({
    Board? board,
    StoneColor? turn,
    int? ply,
    Object? koPoint = _unset,
    int? consecutivePasses,
    int? blackCaptured,
    int? whiteCaptured,
    GoMove? lastMove,
    List<Point>? lastCaptured,
  }) =>
      GameState(
        setup: setup,
        board: board ?? this.board,
        turn: turn ?? this.turn,
        ply: ply ?? this.ply,
        koPoint: identical(koPoint, _unset)
            ? this.koPoint
            : koPoint as Point?,
        consecutivePasses:
            consecutivePasses ?? this.consecutivePasses,
        blackCaptured: blackCaptured ?? this.blackCaptured,
        whiteCaptured: whiteCaptured ?? this.whiteCaptured,
        lastMove: lastMove ?? this.lastMove,
        lastCaptured: lastCaptured ?? this.lastCaptured,
      );
}

/// Сентинель «значение не передано» для [GameState.copyWith].
const _unset = Object();
