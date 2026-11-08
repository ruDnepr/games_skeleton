import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/push_hour/engine/model.dart';
import 'package:games_for_diana/games/push_hour/engine/rules.dart';

/// Логика «Push Hour»: ходы по одной клетке вдоль оси, блокировка соседями,
/// выезд красной машины с парковки и солвер. Перенесено из оригинального
/// `test/models/rules_test.dart`.
void main() {
  test('ход на одну клетку в свободную сторону разрешён', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
      ],
    );

    expect(RushHourRules.canMove(grid, 'red', 1), isTrue);
    expect(RushHourRules.canMove(grid, 'red', -1), isFalse);

    final moved = RushHourRules.move(grid, 'red', 1);
    expect(moved!.redCar!.position, const Position(2, 1));
    expect(RushHourRules.isSolved(moved), isFalse);
  });

  test('машина на краю не выезжает за пределы поля', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 4),
        ),
      ],
    );

    expect(RushHourRules.move(grid, 'red', 1), isNull);
    // Красная машина на правой клетке поля — это и есть выезд.
    expect(RushHourRules.isSolved(grid), isTrue);
  });

  test('сквозь другую машину проехать нельзя', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
        Car(
          id: 'c1',
          color: Color(0xFF8266D5),
          axis: CarAxis.vertical,
          length: 3,
          position: Position(1, 2),
        ),
        Car(
          id: 'c2',
          color: Color(0xFFFFD66D),
          axis: CarAxis.vertical,
          length: 2,
          position: Position(4, 2),
        ),
      ],
    );

    // Красная машина упирается в вертикальную c1, c1 — в c2 снизу.
    expect(RushHourRules.canMove(grid, 'red', 1), isFalse);
    expect(RushHourRules.canMove(grid, 'red', -1), isFalse);
    expect(RushHourRules.canMove(grid, 'c1', 1), isFalse);
    expect(RushHourRules.canMove(grid, 'c1', -1), isTrue);
  });

  test('вертикальная машина ходит вдоль своей оси', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
        Car(
          id: 'c1',
          color: Color(0xFF8266D5),
          axis: CarAxis.vertical,
          length: 3,
          position: Position(1, 2),
        ),
      ],
    );

    // Вверх — можно, вниз — можно (внизу свободно до конца поля).
    expect(RushHourRules.canMove(grid, 'c1', -1), isTrue);
    expect(RushHourRules.canMove(grid, 'c1', 1), isTrue);

    final moved = RushHourRules.move(grid, 'c1', -1);
    expect(moved!.carById('c1')!.position, const Position(0, 2));
  });

  test('солвер находит минимальное число ходов', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
        Car(
          id: 'c1',
          color: Color(0xFF8266D5),
          axis: CarAxis.vertical,
          length: 2,
          position: Position(1, 2),
        ),
      ],
    );

    final solution = RushHourSolver.solve(grid);
    expect(solution, isNotNull);
    // Вертикальная машина уезжает вверх (1 шаг), красная едет вправо (4 шага).
    expect(solution!.length, 5);
    expect(solution.first.carId, 'c1');
    expect(RushHourRules.isSolved(_apply(grid, solution)), isTrue);
    expect(RushHourSolver.hint(grid), solution.first);
  });

  test('уже решённое поле возвращает пустое решение', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 4),
        ),
      ],
    );

    expect(RushHourRules.isSolved(grid), isTrue);
    expect(RushHourSolver.solve(grid), isEmpty);
  });

  test('дети расстановки дают все допустимые ходы', () {
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
      ],
    );

    final children = RushHourRules.children(grid).toList();
    expect(children, hasLength(1));
    expect(children.first.$1.carId, 'red');
    expect(children.first.$2.redCar!.position, const Position(2, 1));
  });
}

Grid _apply(Grid grid, List<Move> moves) {
  var current = grid;
  for (final move in moves) {
    final step = move.from.row != move.to.row
        ? (move.to.row > move.from.row ? 1 : -1)
        : (move.to.col > move.from.col ? 1 : -1);
    final next = RushHourRules.move(current, move.carId, step);
    expect(next, isNotNull, reason: 'ход $move должен быть допустим');
    current = next!;
  }
  return current;
}
