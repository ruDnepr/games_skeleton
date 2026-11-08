import 'model.dart';

/// Правила «пробки» (Rush Hour) для поля 6x6.
///
/// За один ход машина сдвигается на одну клетку вдоль своей оси.
class RushHourRules {
  const RushHourRules._();

  /// Можно ли сдвинуть машину [carId] на [step] клеток (-1 или +1).
  static bool canMove(Grid grid, String carId, int step) =>
      move(grid, carId, step) != null;

  /// Новое поле после хода или null, если ход невозможен.
  static Grid? move(Grid grid, String carId, int step) {
    if (step != 1 && step != -1) return null;
    final car = grid.carById(carId);
    if (car == null) return null;
    final target = _shifted(car, car.position, step);
    if (target == null) return null;
    for (final other in grid.cars) {
      if (other.id == carId) continue;
      for (final cell in other.cells) {
        if (_covers(car, target, cell)) return null;
      }
    }
    return grid.withCarAt(carId, target);
  }

  /// Пары «ход и поле после него» — основа солвера и отрисовки подсказок.
  static Iterable<(Move, Grid)> children(Grid grid) sync* {
    for (final car in grid.cars) {
      for (final step in const <int>[-1, 1]) {
        final target = _shifted(car, car.position, step);
        if (target == null) continue;
        var blocked = false;
        for (final other in grid.cars) {
          if (other.id == car.id) continue;
          for (final cell in other.cells) {
            if (_covers(car, target, cell)) {
              blocked = true;
              break;
            }
          }
          if (blocked) break;
        }
        if (blocked) continue;
        yield (
          Move(carId: car.id, from: car.position, to: target),
          grid.withCarAt(car.id, target),
        );
      }
    }
  }

  /// Проверка «красная машина выехала»: третий ряд, правая клетка поля.
  static bool isSolved(Grid grid) {
    final red = grid.redCar;
    if (red == null) return false;
    return red.position.row == exitRow &&
        red.position.col + red.length - 1 == boardSize - 1;
  }

  /// Новая позиция машины после шага [step] или null, если шаг невозможен.
  static Position? _shifted(Car car, Position from, int step) {
    final row = car.isHorizontal ? from.row : from.row + step;
    final col = car.isHorizontal ? from.col + step : from.col;
    if (car.isHorizontal) {
      if (col < 0 || col + car.length > boardSize) return null;
      if (row < 0 || row >= boardSize) return null;
    } else {
      if (row < 0 || row + car.length > boardSize) return null;
      if (col < 0 || col >= boardSize) return null;
    }
    return Position(row, col);
  }

  /// Занимает ли машина [car], стоящая в [position], клетку [cell].
  static bool _covers(Car car, Position position, Position cell) {
    if (car.isHorizontal) {
      return position.row == cell.row &&
          cell.col >= position.col &&
          cell.col < position.col + car.length;
    }
    return position.col == cell.col &&
        cell.row >= position.row &&
        cell.row < position.row + car.length;
  }
}

/// Поиск решения в ширину (BFS): минимальное число шагов до выезда.
class RushHourSolver {
  const RushHourSolver._();

  /// Решение уровня или null, если решения нет (защита от долгого поиска — [limit]).
  ///
  /// Самый сложный уровень кампании требует около 27 000 состояний, поэтому
  /// ограничение по умолчанию — 200 000.
  static List<Move>? solve(Grid grid, {int limit = 200000}) {
    if (RushHourRules.isSolved(grid)) return const <Move>[];

    final states = <Grid>[grid];
    final keys = <String>{grid.key};
    final parents = <String, String>{};
    final parentMoves = <String, Move>{};
    var head = 0;

    while (head < states.length) {
      if (head > limit) return null;
      final state = states[head];
      head++;
      for (final (move, next) in RushHourRules.children(state)) {
        final key = next.key;
        if (keys.contains(key)) continue;
        keys.add(key);
        parents[key] = state.key;
        parentMoves[key] = move;
        if (RushHourRules.isSolved(next)) {
          return _rebuild(parentMoves, parents, key);
        }
        states.add(next);
      }
    }
    return null;
  }

  /// Первый ход решения — для подсказки.
  static Move? hint(Grid grid, {int limit = 200000}) {
    final solution = solve(grid, limit: limit);
    if (solution == null || solution.isEmpty) return null;
    return solution.first;
  }

  static List<Move> _rebuild(
    Map<String, Move> parentMoves,
    Map<String, String> parents,
    String lastKey,
  ) {
    final path = <Move>[];
    var key = lastKey;
    while (parentMoves.containsKey(key)) {
      final move = parentMoves[key]!;
      path.add(move);
      final parent = parents[key];
      if (parent == null) break;
      key = parent;
    }
    return path.reversed.toList(growable: false);
  }
}
