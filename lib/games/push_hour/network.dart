import '../../app/settings.dart';
import 'engine/levels.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.push_hour.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const String pushHourGameId = 'push_hour';

/// Уровень, с которого начинается партия на одном устройстве. У сетевой игры
/// уровень сообщает хост в опциях лобби.
int pushHourStartLevel(SettingsController settings) {
  // Каркасный контроллер не хранит «открытый уровень» конкретной игры, поэтому
  // по умолчанию начинаем с первого. Реальный прогресс по уровням ведёт сам
  // PushHourProgress в отдельном файле; лобби нужен только номер для старта.
  return 1;
}

/// Данные, которые хозяин передаёт гостям: только общий для всех уровень.
/// Личные настройки (подсказки, звук) остаются на своём устройстве.
Map<String, Object?> pushHourOptions(SettingsController settings) => {
  'level': pushHourStartLevel(settings),
};

/// Проверка и разбор опций лобби. Номера вне кампании прижимаются к границам.
int pushHourParseOptions(Map<String, Object?> options) {
  const allowed = {'level'};
  final unknown =
      options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final rawLevel = options['level'];
  if (rawLevel == null) return 1;
  if (rawLevel is! int) {
    throw const FormatException('Номер уровня не распознан');
  }
  if (rawLevel < 1) return 1;
  if (rawLevel > campaignLevels.length) return campaignLevels.length;
  return rawLevel;
}

/// Проверка формата хода, полученного по сети.
///
/// Клетка передаётся одним числом 0..35: `row * 6 + col`. За один ход — одна
/// клетка вдоль оси машины, поэтому Манхэттенское расстояние между «от» и «до»
/// равно 1.
void pushHourValidateMove(Map<String, Object?> move) {
  final from = move['from'];
  final to = move['to'];
  if (from is! int || to is! int) {
    throw const FormatException('Ход не распознан');
  }
  if (from < 0 || from >= boardSize * boardSize) {
    throw const FormatException('Ход не распознан');
  }
  if (to < 0 || to >= boardSize * boardSize) {
    throw const FormatException('Ход не распознан');
  }
  final start = Position.fromIndex(from);
  final end = Position.fromIndex(to);
  final distance = (start.row - end.row).abs() + (start.col - end.col).abs();
  if (distance != 1) {
    throw const FormatException('За один ход — одна клетка');
  }
}
