/// Карта «Билета на поезд»: города, маршруты, координаты для отрисовки.
///
/// Чистый Dart: ни Flutter, ни сети. Координаты городов — на сетке 0..1, чтобы
/// карта масштабировалась под любой размер холста. Маршруты и путешествия —
/// статические списки, индексы в которых являются идентификаторами в действиях
/// и в сети: порядок маршрутов нельзя менять после публикации игры.
library;

import 'model.dart';

/// Все города карты в стабильном порядке. Порядок не должен меняться: индекс
/// города в этом списке — это его идентификатор в сети и в сохранениях.
final List<City> allCities = List.unmodifiable(City.values);

/// Все 10 маршрутов карты. Порядок важен — индекс маршрута в этом списке
/// является идентификатором в действиях игрока и в сети.
final List<Route> allRoutes = List.unmodifiable(const [
  Route(cityA: City.moscow, cityB: City.tver, color: CardColor.red, length: 2),
  Route(
    cityA: City.moscow,
    cityB: City.vladimir,
    color: CardColor.blue,
    length: 2,
  ),
  Route(
    cityA: City.moscow,
    cityB: City.yaroslavl,
    color: CardColor.green,
    length: 3,
  ),
  Route(cityA: City.tver, cityB: City.novgorod, color: CardColor.red, length: 2),
  Route(
    cityA: City.tver,
    cityB: City.spb,
    color: CardColor.blue,
    length: 3,
  ),
  Route(
    cityA: City.novgorod,
    cityB: City.spb,
    color: CardColor.green,
    length: 2,
  ),
  Route(
    cityA: City.yaroslavl,
    cityB: City.vladimir,
    color: CardColor.red,
    length: 1,
  ),
  Route(
    cityA: City.vladimir,
    cityB: City.novgorod,
    color: CardColor.blue,
    length: 3,
  ),
  // Длинный маршрут через всю карту.
  Route(
    cityA: City.moscow,
    cityB: City.novgorod,
    color: CardColor.green,
    length: 4,
  ),
  Route(
    cityA: City.tver,
    cityB: City.yaroslavl,
    color: CardColor.blue,
    length: 2,
  ),
]);

/// Колода карточек путешествий. Шесть разных заданий; в начале партии каждый
/// игрок получает по два, в колоде остаётся два — их можно подтянуть позже.
final List<Destination> allDestinations = List.unmodifiable(const [
  Destination(from: City.moscow, to: City.spb, points: 5),
  Destination(from: City.vladimir, to: City.novgorod, points: 4),
  Destination(from: City.yaroslavl, to: City.tver, points: 3),
  Destination(from: City.moscow, to: City.yaroslavl, points: 4),
  Destination(from: City.tver, to: City.vladimir, points: 4),
  Destination(from: City.spb, to: City.yaroslavl, points: 5),
]);

/// Маршрут между двумя городами или `null`, если такого маршрута на карте нет.
/// Если города соединены двумя разными маршрутами (параллельные), возвращается
/// первый по индексу — на нашей карте таких пар нет.
Route? routeBetween(City a, City b) {
  for (final route in allRoutes) {
    if (route.connects(a, b)) return route;
  }
  return null;
}

/// Индекс маршрута между двумя городами или `null`, если такого нет.
int? routeIndexBetween(City a, City b) {
  for (var i = 0; i < allRoutes.length; i++) {
    if (allRoutes[i].connects(a, b)) return i;
  }
  return null;
}

/// Все города, которые хоть раз встречаются в путешествиях игрока как концы
/// маршрутов. Нужна ИИ: туда он стремится проложить пути.
Set<City> citiesForDestinations(Iterable<Destination> destinations) {
  final set = <City>{};
  for (final d in destinations) {
    set.add(d.from);
    set.add(d.to);
  }
  return set;
}

/// Координаты города на сетке 0..1 для отрисовки карты. Подобраны так, чтобы
/// маршруты не слипались и каждый город было удобно тапнуть пальцем.
const Map<City, MapPoint> cityPositions = {
  City.spb: MapPoint(0.14, 0.16),
  City.tver: MapPoint(0.45, 0.20),
  City.novgorod: MapPoint(0.82, 0.18),
  City.moscow: MapPoint(0.38, 0.55),
  City.yaroslavl: MapPoint(0.84, 0.55),
  City.vladimir: MapPoint(0.62, 0.86),
};

/// Точка на сетке 0..1. Чистый Dart, без Flutter: для рисования на холсте
/// координаты умножаются на размер холста. На холсте движок превращается в
/// `Offset` — это забота интерфейса, не движка.
class MapPoint {
  const MapPoint(this.x, this.y);
  final double x;
  final double y;
}
