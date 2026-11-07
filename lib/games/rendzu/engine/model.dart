/// Модели рэндзю: точка, доска, камень, ход, конфигурация партии.
///
/// Чистый Dart, без Flutter: правила, ИИ и сетевой обмен оперируют только
/// этими типами. Сетка — пересечения линий, как в го: камень ставится в точку
/// [Point], а не в клетку.
library;

import 'package:flutter/foundation.dart';

/// Цвет камня. Чёрные ходят первыми.
enum StoneColor { black, white }

extension StoneColorX on StoneColor {
  /// Соперник.
  StoneColor get opponent =>
      this == StoneColor.black ? StoneColor.white : StoneColor.black;

  /// Русское название для подписей и подсказок.
  String get russianName => this == StoneColor.black ? 'Чёрные' : 'Белые';
}

/// Точка на доске — координаты пересечения линий.
/// (0, 0) — левый верхний угол. [x] — колонка, [y] — строка.
@immutable
class Point implements Comparable<Point> {
  const Point(this.x, this.y);

  final int x;
  final int y;

  /// Соседняя точка в направлении [dir] (dx, dy).
  Point step(Direction dir) => Point(x + dir.dx, y + dir.dy);

  /// Лежит ли точка на доске размера [size].
  bool inBounds(int size) => x >= 0 && y >= 0 && x < size && y < size;

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

  /// Сериализация в JSON: плоская карта `{"x": int, "y": int}`.
  Map<String, Object?> toJson() => {'x': x, 'y': y};

  /// Обратный разбор. Бросает [FormatException] на чужую форму.
  static Point fromJson(Map<String, Object?> json) {
    final x = json['x'];
    final y = json['y'];
    if (x is! int || y is! int || x < 0 || y < 0) {
      throw const FormatException('Точка не распознана');
    }
    return Point(x, y);
  }
}

/// Направление на доске. Четыре оси покрывают все линии: горизонталь,
/// вертикаль и две диагонали. Для каждой оси есть пара противоположных
/// направлений — это нужно, чтобы пройти серию камней в обе стороны.
class Direction {
  const Direction(this.dx, this.dy);

  final int dx;
  final int dy;

  /// 4 оси (по одному направлению из каждой пары).
  static const List<Direction> axes = [
    Direction(1, 0), // горизонталь →
    Direction(0, 1), // вертикаль ↓
    Direction(1, 1), // диагональ ↘
    Direction(1, -1), // диагональ ↗
  ];

  /// Противоположное направление.
  Direction get opposite => Direction(-dx, -dy);

  @override
  String toString() => 'dir($dx,$dy)';
}

/// Игровое поле размера [size]×[size]. Камни хранятся в плоском списке для
/// скорости; `null` — пустое пересечение.
class Board {
  Board(this.size) : _cells = List<StoneColor?>.filled(size * size, null);

  Board.fromCells(this.size, List<StoneColor?> cells)
      : _cells = List<StoneColor?>.of(cells);

  final int size;
  final List<StoneColor?> _cells;

  int _blackCount = 0;
  int _whiteCount = 0;

  /// Доска пустая — нет ни одного камня.
  bool get isEmpty => _blackCount == 0 && _whiteCount == 0;

  /// Всего камней на доске.
  int get stoneCount => _blackCount + _whiteCount;

  int get blackCount => _blackCount;
  int get whiteCount => _whiteCount;

  /// Доска заполнена — ничья, если никто не победил.
  bool get isFull => stoneCount == size * size;

  int _idxPoint(Point p) => p.y * size + p.x;

  /// Камень в координатах [x], [y] или `null`, если точка вне доски.
  StoneColor? get(int x, int y) {
    if (x < 0 || y < 0 || x >= size || y >= size) return null;
    return _cells[y * size + x];
  }

  /// Камень в точке [p] или `null` для пустой/внедосковой точки.
  StoneColor? at(Point p) {
    if (!p.inBounds(size)) return null;
    return _cells[_idxPoint(p)];
  }

  /// Занята ли точка.
  bool isOccupied(Point p) => at(p) != null;

  /// Свободна ли точка (и в пределах доски).
  bool isEmptyCell(Point p) => p.inBounds(size) && at(p) == null;

  /// Ставит камень без проверок (низкоуровневая операция). Бросает [StateError],
  /// если клетка занята.
  void place(Point p, StoneColor color) {
    if (!p.inBounds(size)) {
      throw ArgumentError('Точка $p вне доски $size×$size');
    }
    final i = _idxPoint(p);
    if (_cells[i] != null) {
      throw StateError('Клетка $p уже занята');
    }
    _cells[i] = color;
    if (color == StoneColor.black) {
      _blackCount++;
    } else {
      _whiteCount++;
    }
  }

  /// Снимает камень с доски (для отмены хода). Молча игнорирует пустую клетку.
  void remove(Point p) {
    if (!p.inBounds(size)) return;
    final i = _idxPoint(p);
    final prev = _cells[i];
    if (prev == null) return;
    _cells[i] = null;
    if (prev == StoneColor.black) {
      _blackCount--;
    } else {
      _whiteCount--;
    }
  }

  /// Все занятые точки, в порядке слева направо и сверху вниз.
  Iterable<Point> occupiedPoints() sync* {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (_cells[y * size + x] != null) {
          yield Point(x, y);
        }
      }
    }
  }

  /// Глубокая копия доски. Нужна правилам и ИИ — они ставят камень во временную
  /// копию, чтобы проверить гипотезу, не ломая саму партию.
  Board copy() {
    final b = Board(size);
    for (var i = 0; i < _cells.length; i++) {
      b._cells[i] = _cells[i];
    }
    b._blackCount = _blackCount;
    b._whiteCount = _whiteCount;
    return b;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final c = _cells[y * size + x];
        sb.write(c == null ? '.' : (c == StoneColor.black ? 'X' : 'O'));
      }
      sb.writeln();
    }
    return sb.toString();
  }
}

/// Один ход игры: игрок цвета [color] ставит камень в точку [point].
/// [number] — порядковый номер хода в партии (с 1), выводится из длины истории.
@immutable
class Move {
  const Move({required this.point, required this.color, this.number = 0});

  final Point point;
  final StoneColor color;
  final int number;

  Move copyWith({int? number}) =>
      Move(point: point, color: color, number: number ?? this.number);

  /// Сериализация для сети и хранения. Формат упрощённый: точка «развёрнута»,
  /// номер опущен — он выводится из длины истории на принимающей стороне.
  Map<String, Object?> toJson() => {
        'x': point.x,
        'y': point.y,
        'color': color.name,
      };

  @override
  String toString() => '#$number $color→$point';
}

/// Набор правил. Гомоку — свободное пять в ряд без запретов; рэндзю — с
/// запрещёнными ходами для чёрных (двойное три, двойное четыре, оверлайн).
enum Ruleset { gomoku, renju }

extension RulesetX on Ruleset {
  String get russianName => this == Ruleset.gomoku ? 'Гомоку' : 'Рэндзю';

  /// Описание набора правил для экрана выбора — текст дословно из оригинала.
  String get russianDescription => switch (this) {
        Ruleset.gomoku => 'Свободное пять в ряд — без запрещённых ходов',
        Ruleset.renju =>
          'Рэндзю — у чёрных есть запрещённые ходы (двойное три, двойное четыре, оверлайн)',
      };
}

/// Размер доски. 9×9 — быстрее и понятнее ребёнку; 15×15 — классический рэндзю.
enum BoardSize { small9, standard15 }

extension BoardSizeX on BoardSize {
  int get dimension => switch (this) {
        BoardSize.small9 => 9,
        BoardSize.standard15 => 15,
      };

  String get russianName => '$dimension×$dimension';

  static BoardSize fromDimension(int d) =>
      d <= 9 ? BoardSize.small9 : BoardSize.standard15;
}

/// Уровень сложности компьютера.
enum Difficulty { easy, medium, hard }

extension DifficultyX on Difficulty {
  String get russianName => switch (this) {
        Difficulty.easy => 'Лёгкий',
        Difficulty.medium => 'Средний',
        Difficulty.hard => 'Сложный',
      };

  /// Описание уровня для экрана выбора — текст дословно из оригинала.
  String get russianDescription => switch (this) {
        Difficulty.easy => 'ИИ видит только ближайшие угрозы — можно выиграть',
        Difficulty.medium => 'ИИ оценивает паттерны и блокирует атаки',
        Difficulty.hard => 'ИИ просчитывает глубоко и не делает запрещённых ходов',
      };
}
