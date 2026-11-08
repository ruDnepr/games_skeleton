import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/push_hour/engine/levels.dart';
import 'package:games_for_diana/games/push_hour/engine/model.dart';
import 'package:games_for_diana/games/push_hour/engine/rules.dart';

/// Кампания «Push Hour»: 100 уровней, 10 наборов по 10. Все уровни должны быть
/// решаемы за число ходов, посчитанное солвером, и не должны содержать машин
/// вне поля или наезжающих друг на друга.
void main() {
  // Полный перебор BFS по 100 уровням занимает несколько десятков секунд.
  test('все уровни кампании решаются за minMoves', () {
    expect(campaignLevels.length, campaignSize);
    expect(levelSets.length, campaignSize ~/ 10);
    for (final set in levelSets) {
      expect(set.length, 10);
    }

    for (final level in campaignLevels) {
      final red = level.grid.redCar;
      expect(red, isNotNull, reason: 'уровень ${level.number}');
      expect(red!.position.row, exitRow, reason: 'уровень ${level.number}');
      expect(red.length, 2, reason: 'уровень ${level.number}');

      final occupied = <Position>{};
      for (final car in level.grid.cars) {
        for (final cell in car.cells) {
          expect(
            level.grid.isInside(cell),
            isTrue,
            reason: 'уровень ${level.number}: машина вне поля',
          );
          expect(
            occupied.add(cell),
            isTrue,
            reason: 'уровень ${level.number}: машины наезжают друг на друга',
          );
        }
      }

      // Тот же лимит, что и у подсказки в приложении: она должна
      // укладываться в него на любом уровне кампании.
      final solution = RushHourSolver.solve(level.grid, limit: 120000);
      expect(solution, isNotNull, reason: 'уровень ${level.number} без решения');
      expect(
        solution!.length,
        level.minMoves,
        reason: 'уровень ${level.number}',
      );
      // _apply заодно проверяет, что каждый ход решения допустим.
      expect(RushHourRules.isSolved(_apply(level.grid, solution)), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('сложность растёт: первые уровни не решаются в два хода', () {
    expect(campaignLevels.first.minMoves, greaterThanOrEqualTo(6));
    for (var index = 1; index < campaignLevels.length; index++) {
      expect(
        campaignLevels[index].minMoves,
        greaterThanOrEqualTo(campaignLevels[index - 1].minMoves),
        reason: 'уровень ${index + 1} проще предыдущего',
      );
    }
    expect(campaignLevels.last.minMoves, greaterThanOrEqualTo(25));
  });

  test('уровень по номеру прижимается к границам', () {
    expect(levelByNumber(1).number, 1);
    expect(levelByNumber(campaignSize).number, campaignSize);
    expect(levelByNumber(0).number, 1);
    expect(levelByNumber(campaignSize + 5).number, campaignSize);
  });

  test('первый уровень не решён сразу', () {
    expect(RushHourRules.isSolved(campaignLevels.first.grid), isFalse);
  });

  test('названия наборов заполнены и их десять', () {
    expect(campaignSetTitles, hasLength(10));
    for (final title in campaignSetTitles) {
      expect(title.trim(), isNotEmpty);
    }
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
