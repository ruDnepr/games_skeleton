/// Чистая логика морского боя: правила расстановки, выстрелы, победа.
///
/// Класс без состояния, не знает про UI или сеть. Методы возвращают новые
/// неизменяемые объекты — историю для отмены можно хранить просто как список
/// прошлых состояний, а сеть проверяет ход повторным применением правил к
/// своему состоянию.
library;

import 'dart:math';

import 'model.dart';

class BattleshipRules {
  const BattleshipRules();

  /// Помещается ли корабль в поле и не пересекается ли он по клеткам с уже
  /// стоящими кораблями флота.
  bool fitsAndFree(Fleet fleet, Ship ship) {
    if (!ship.fits) return false;
    final occupied = fleet.occupiedCells;
    for (final c in ship.cells) {
      if (occupied.contains(c)) return false;
    }
    return true;
  }

  /// Главная проверка расстановки: корабль в поле, не пересекается и **не
  /// касается** других кораблей ни бортом, ни углом.
  bool canPlace(Fleet fleet, Ship ship) {
    if (!fitsAndFree(fleet, ship)) return false;
    // Запрещаем касание: ни одна клетка корабля не должна быть соседом клетки
    // уже стоящего корабля (8 направлений, включая диагонали).
    final forbidden = <Square>{};
    for (final s in fleet.ships) {
      for (final c in s.cells) {
        for (final n in neighboursOf(c)) {
          forbidden.add(n);
        }
      }
    }
    for (final c in ship.cells) {
      if (forbidden.contains(c)) return false;
    }
    return true;
  }

  /// Добавляет корабль во флот. Предполагает, что [canPlace] уже вернул true;
  /// иначе бросает [StateError] — это ошибка программирования, а не игрока.
  Fleet withShip(Fleet fleet, Ship ship) {
    if (!canPlace(fleet, ship)) {
      throw StateError('Корабль нельзя поставить сюда');
    }
    return Fleet([...fleet.ships, ship]);
  }

  /// Убирает корабль, стоящий в клетке [cell], из флота. Если в клетке корабля
  /// нет — возвращает флот без изменений.
  Fleet withoutShipAt(Fleet fleet, Square cell) {
    final ship = fleet.shipAt(cell);
    if (ship == null) return fleet;
    return Fleet(fleet.ships.where((s) => s != ship).toList());
  }

  /// Случайная корректная расстановка полного флота. Ставит корабли от больших
  /// к маленьким: так проще соблюсти правило «без касаний». Делается фиксированное
  /// число попыток — для 10 кораблей на поле 10×10 этого всегда хватает.
  Fleet autoFleet([Random? rng]) {
    final random = rng ?? Random();
    for (var attempt = 0; attempt < 500; attempt++) {
      final fleet = _tryAutoFleet(random);
      if (fleet != null) return fleet;
    }
    // На практике не случается, но нужен запасной план.
    return _fallbackFleet();
  }

  Fleet? _tryAutoFleet(Random random) {
    var fleet = emptyFleet;
    for (final type in ShipType.values) {
      for (var i = 0; i < type.count; i++) {
        final placed = _tryPlaceOne(fleet, type, random);
        if (placed == null) return null;
        fleet = placed;
      }
    }
    return fleet.isComplete ? fleet : null;
  }

  Fleet? _tryPlaceOne(Fleet fleet, ShipType type, Random random) {
    final candidates = <Ship>[];
    for (final origin in allSquares()) {
      for (final o in Orientation.values) {
        final ship = Ship(type: type, origin: origin, orientation: o);
        if (canPlace(fleet, ship)) candidates.add(ship);
      }
    }
    if (candidates.isEmpty) return null;
    return withShip(fleet, candidates[random.nextInt(candidates.length)]);
  }

  /// Гарантированная расстановка: проверенная вручную «ёлочка».
  Fleet _fallbackFleet() => Fleet([
        Ship(
          type: ShipType.battleship,
          origin: const Square(0, 0),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.cruiser,
          origin: const Square(2, 0),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.cruiser,
          origin: const Square(4, 0),
          orientation: Orientation.vertical,
        ),
        Ship(
          type: ShipType.destroyer,
          origin: const Square(4, 2),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.destroyer,
          origin: const Square(6, 0),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.destroyer,
          origin: const Square(0, 5),
          orientation: Orientation.vertical,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(2, 4),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(8, 4),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(6, 6),
          orientation: Orientation.horizontal,
        ),
        Ship(
          type: ShipType.submarine,
          origin: const Square(2, 8),
          orientation: Orientation.horizontal,
        ),
      ]);

  /// Потоплен ли корабль с учётом уже сделанных по нему попаданий. Карта
  /// [shots] содержит выстрелы по этому флоту: клетки и их результаты.
  bool isSunkShip(Ship ship, Map<Square, Shot> shots) {
    for (final c in ship.cells) {
      final s = shots[c];
      if (s == null || s.result == ShotResult.miss) return false;
    }
    return true;
  }

  /// Результат выстрела по клетке [target] поля соперника с флотом [enemy].
  ///
  /// Бросает [StateError], если в эту клетку уже стреляли — повторный выстрел
  /// запрещён правилами. Возвращает [Shot] с результатом miss / hit / sunk; при
  /// потоплении заполняет [Shot.sunkType].
  Shot shootResult(
    Fleet enemy,
    Map<Square, Shot> prior,
    Square target,
  ) {
    if (!target.inside) {
      throw RangeError('Клетка вне поля: $target');
    }
    if (prior.containsKey(target)) {
      throw StateError('В клетку $target уже стреляли');
    }
    final ship = enemy.shipAt(target);
    if (ship == null) {
      return Shot(square: target, result: ShotResult.miss);
    }
    // Промоделируем попадание и проверим, добит ли корабль.
    final trial = Map<Square, Shot>.from(prior);
    trial[target] = Shot(square: target, result: ShotResult.hit);
    if (isSunkShip(ship, trial)) {
      return Shot(
        square: target,
        result: ShotResult.sunk,
        sunkType: ship.type,
      );
    }
    return Shot(square: target, result: ShotResult.hit);
  }

  /// Весь флот потоплен? [shots] — выстрелы по этому флоту.
  bool fleetSunk(Fleet fleet, Map<Square, Shot> shots) =>
      fleet.ships.every((s) => isSunkShip(s, shots));

  /// Сколько кораблей флота уже потоплено.
  int sunkCount(Fleet fleet, Map<Square, Shot> shots) =>
      fleet.ships.where((s) => isSunkShip(s, shots)).length;

  /// Все потопленные корабли — для обведения контуром в UI.
  List<Ship> sunkShips(Fleet fleet, Map<Square, Shot> shots) =>
      fleet.ships.where((s) => isSunkShip(s, shots)).toList();
}

/// Синглтон-правила: в приложении нужна одна копия.
final BattleshipRules battleshipRules = BattleshipRules();
