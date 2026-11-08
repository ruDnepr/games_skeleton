import 'package:flutter/material.dart';

/// Размер поля: 6x6 клеток.
const int boardSize = 6;

/// Ряд, в котором находится выезд с парковки.
const int exitRow = 2;

/// Идентификатор красной машины во всех уровнях.
const String redCarId = 'red';

/// Координаты клетки (row, col), 0..5.
class Position {
  const Position(this.row, this.col);

  final int row;
  final int col;

  /// Индекс клетки в одномерной записи 0..35 (используется в сетевом протоколе).
  int get index => row * boardSize + col;

  static Position fromIndex(int value) =>
      Position(value ~/ boardSize, value % boardSize);

  @override
  String toString() => '($row,$col)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Position && row == other.row && col == other.col);

  @override
  int get hashCode => row * boardSize + col;
}

/// Ось, вдоль которой может ехать машина.
///
/// Название отличается от `Axis` из Flutter, чтобы не было конфликта имён.
enum CarAxis { horizontal, vertical }

/// Машина на поле.
///
/// [position] — верхняя левая клетка для горизонтальной машины
/// и верхняя клетка для вертикальной.
class Car {
  const Car({
    required this.id,
    required this.color,
    required this.axis,
    required this.length,
    required this.position,
  });

  final String id;
  final Color color;
  final CarAxis axis;
  final int length;
  final Position position;

  bool get isHorizontal => axis == CarAxis.horizontal;

  bool get isRed => id == redCarId;

  /// Все клетки, которые занимает машина.
  List<Position> get cells => List<Position>.generate(
    length,
    (index) => isHorizontal
        ? Position(position.row, position.col + index)
        : Position(position.row + index, position.col),
    growable: false,
  );

  Car copyWith({Position? position}) => Car(
    id: id,
    color: color,
    axis: axis,
    length: length,
    position: position ?? this.position,
  );

  @override
  String toString() => '$id: $position ($axis, $length)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Car &&
          id == other.id &&
          color == other.color &&
          axis == other.axis &&
          length == other.length &&
          position == other.position);

  @override
  int get hashCode => Object.hash(id, color, axis, length, position);
}

/// Поле 6x6 с машинами.
class Grid {
  const Grid({required this.cars});

  final List<Car> cars;

  Car? carById(String id) {
    for (final car in cars) {
      if (car.id == id) return car;
    }
    return null;
  }

  Car? get redCar => carById(redCarId);

  Car? carAt(Position position) {
    for (final car in cars) {
      for (final cell in car.cells) {
        if (cell == position) return car;
      }
    }
    return null;
  }

  bool isInside(Position position) =>
      position.row >= 0 &&
      position.row < boardSize &&
      position.col >= 0 &&
      position.col < boardSize;

  /// Новое поле, в котором машина [id] стоит в [position].
  Grid withCarAt(String id, Position position) => Grid(
    cars: List<Car>.unmodifiable(
      cars.map(
        (car) => car.id == id ? car.copyWith(position: position) : car,
      ),
    ),
  );

  /// Новое поле с тем же набором машин (копия безопасна).
  Grid copy() => Grid(cars: List<Car>.unmodifiable(cars));

  /// Канонический ключ расстановки — используется в BFS-солвере.
  String get key {
    final buffer = StringBuffer();
    for (final car in cars) {
      buffer
        ..write(car.position.row)
        ..write(car.position.col);
    }
    return buffer.toString();
  }

  @override
  String toString() => 'Grid(${cars.join(', ')})';
}

/// Ход: машина сдвинулась на одну клетку вдоль своей оси.
class Move {
  const Move({required this.carId, required this.from, required this.to});

  final String carId;
  final Position from;
  final Position to;

  @override
  String toString() => '$carId: $from -> $to';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Move &&
          carId == other.carId &&
          from == other.from &&
          to == other.to);

  @override
  int get hashCode => Object.hash(carId, from, to);
}

/// Уровень кампании.
class Level {
  const Level({
    required this.number,
    required this.grid,
    required this.minMoves,
  });

  final int number;
  final Grid grid;

  /// Минимальное число ходов (шагов по одной клетке), посчитанное BFS.
  final int minMoves;

  String get title => 'Уровень $number';

  @override
  String toString() => 'Level $number (minMoves: $minMoves)';
}
