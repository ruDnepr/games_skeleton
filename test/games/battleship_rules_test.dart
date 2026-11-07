import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/engine/rules.dart';

/// Правила морского боя: расстановка, выстрелы, победа. Порт оригинального
/// `rules_test.dart` — те же инварианты, те же названия.
void main() {
  final rules = const BattleshipRules();

  group('Расстановка', () {
    test('поле 10×10, слово РЕСПУБЛИКА — 10 уникальных букв', () {
      expect(columnLetters, hasLength(10));
      expect(columnLetters.toSet(), hasLength(10));
      expect(columnLetters.first, 'Р');
      expect(columnLetters.last, 'А');
    });

    test('координата читается как «У4», «К10»', () {
      expect(const Square(3, 4).toString(), 'У4'); // col 4 → У
      expect(const Square(9, 9).toString(), 'А10'); // col 9 → А
      expect(const Square(0, 0).toString(), 'Р1');
    });

    test('parse обратим для всех клеток', () {
      for (final s in allSquares()) {
        expect(Square.parse(s.toString()), s);
      }
    });

    test('корабль помещается в поле и не пересекается', () {
      final fleet = emptyFleet;
      final ship = Ship(
        type: ShipType.battleship,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      );
      expect(rules.canPlace(fleet, ship), isTrue);
      final placed = rules.withShip(fleet, ship);
      expect(placed.ships, hasLength(1));
    });

    test('корабль не может выходить за пределы поля', () {
      final ship = Ship(
        type: ShipType.battleship,
        origin: const Square(0, 7),
        orientation: Orientation.horizontal,
      );
      expect(ship.fits, isFalse);
      expect(rules.canPlace(emptyFleet, ship), isFalse);
    });

    test('корабли не могут касаться друг друга даже по диагонали', () {
      final first = Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      );
      final fleet = rules.withShip(emptyFleet, first);
      // По диагонали вниз-вправо — нельзя.
      final diagonal = Ship(
        type: ShipType.submarine,
        origin: const Square(1, 1),
        orientation: Orientation.horizontal,
      );
      expect(rules.canPlace(fleet, diagonal), isFalse);
      // Через одну клетку по диагонали — можно.
      final far = Ship(
        type: ShipType.submarine,
        origin: const Square(2, 2),
        orientation: Orientation.horizontal,
      );
      expect(rules.canPlace(fleet, far), isTrue);
      // Сосед по борту — нельзя.
      final side = Ship(
        type: ShipType.submarine,
        origin: const Square(1, 0),
        orientation: Orientation.horizontal,
      );
      expect(rules.canPlace(fleet, side), isFalse);
    });

    test('авто-расставка даёт полный корректный флот', () {
      final fleet = rules.autoFleet();
      expect(fleet.isComplete, isTrue);
      expect(fleet.ships, hasLength(10));
      // Все корабли не касаются друг друга: попарная проверка.
      for (var i = 0; i < fleet.ships.length; i++) {
        for (var j = i + 1; j < fleet.ships.length; j++) {
          final a = fleet.ships[i];
          final b = fleet.ships[j];
          for (final ca in a.cells) {
            for (final cb in b.cells) {
              final dr = (ca.row - cb.row).abs();
              final dc = (ca.col - cb.col).abs();
              expect(dr + dc, greaterThan(1),
                  reason: 'Корабли касаются: $a и $b');
            }
          }
        }
      }
    });

    test('уборка корабля по клетке', () {
      final ship = Ship(
        type: ShipType.cruiser,
        origin: const Square(0, 0),
        orientation: Orientation.vertical,
      );
      var fleet = rules.withShip(emptyFleet, ship);
      expect(fleet.ships, hasLength(1));
      fleet = rules.withoutShipAt(fleet, const Square(1, 0));
      expect(fleet.ships, isEmpty);
    });
  });

  group('Выстрелы', () {
    final fleet = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);

    test('промах по пустой клетке', () {
      final shot = rules.shootResult(fleet, {}, const Square(5, 5));
      expect(shot.result, ShotResult.miss);
    });

    test('попадание без потопления', () {
      final shot = rules.shootResult(fleet, {}, const Square(0, 0));
      expect(shot.result, ShotResult.hit);
    });

    test('потопление последним попаданием', () {
      final prior = {
        const Square(0, 0):
            const Shot(square: Square(0, 0), result: ShotResult.hit),
      };
      final shot = rules.shootResult(fleet, prior, const Square(0, 1));
      expect(shot.result, ShotResult.sunk);
      expect(shot.sunkType, ShipType.destroyer);
    });

    test('повторный выстрел в ту же клетку запрещён', () {
      final prior = {
        const Square(0, 0):
            const Shot(square: Square(0, 0), result: ShotResult.hit),
      };
      expect(
        () => rules.shootResult(fleet, prior, const Square(0, 0)),
        throwsStateError,
      );
    });

    test('выстрел вне поля невозможен', () {
      expect(
        () => rules.shootResult(fleet, {}, const Square(-1, 0)),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('Победа', () {
    test('флот потоплен, когда все корабли добиты', () {
      final fleet = Fleet([
        Ship(
          type: ShipType.destroyer,
          origin: const Square(0, 0),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(5, 5),
          orientation: Orientation.horizontal,
        ),
      ]);
      final shots = <Square, Shot>{
        for (final s in [
          const Square(0, 0),
          const Square(0, 1),
          const Square(5, 5),
        ])
          s: Shot(square: s, result: ShotResult.hit),
      };
      expect(rules.fleetSunk(fleet, shots), isTrue);
      expect(rules.sunkCount(fleet, shots), 2);
    });

    test('флот не потоплен, если хотя бы один корабль жив', () {
      final fleet = Fleet([
        Ship(
          type: ShipType.submarine,
          origin: const Square(0, 0),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(5, 5),
          orientation: Orientation.horizontal,
        ),
      ]);
      final shots = <Square, Shot>{
        const Square(0, 0):
            const Shot(square: Square(0, 0), result: ShotResult.hit),
      };
      expect(rules.fleetSunk(fleet, shots), isFalse);
      expect(rules.sunkCount(fleet, shots), 1);
    });
  });
}
