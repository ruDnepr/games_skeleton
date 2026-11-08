import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.battleship.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const battleshipGameId = 'battleship';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для морского боя это
/// один переключатель — подсказки. Каждое устройство рисует по своим
/// настройкам, но карта проверяется, чтобы чужое лобби не пустило в партию
/// неразборчивые данные. Флоты по сети не пересылаются — только выстрелы и
/// их результаты, так что чужие настройки нам и не нужны.
Map<String, Object?> battleshipOptions(SettingsController settings) => {
      'hints': settings.flag(battleshipGameId, 'hints'),
    };

/// Опции морского боя после разбора. Только то, что игра умеет.
class BattleshipOptions {
  const BattleshipOptions({required this.hints});
  final bool hints;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
BattleshipOptions battleshipParseOptions(Map<String, Object?> options) {
  const allowed = {'hints'};
  final unknown =
      options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  if (hints is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return BattleshipOptions(hints: hints);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния: транспорт
/// зовёт её до того, как ход увидит партия. Полная проверка по правилам (не
/// стреляли ли уже в эту клетку) делает сама партия, когда применяет ход.
///
/// Выстрел в морском бое — это и есть «ход» с точки зрения протокола: клетка
/// `[row, col]` с row и col от 0 до 9. Номер хода [ply] протоколу не нужен, но
/// мы его допускаем — он помогает отлаживать и не нарушает форму.
void battleshipValidateMove(Map<String, Object?> move) {
  final square = move['square'];
  if (square is! List || square.length != 2) {
    throw const FormatException('Ход не распознан: клетка');
  }
  final r = square[0];
  final c = square[1];
  if (r is! int || c is! int || r < 0 || r > 9 || c < 0 || c > 9) {
    throw const FormatException('Ход не распознан: координаты');
  }
}

/// Сообщение `move` для отправки выстрела: кто стрелял (по порядку) и куда.
/// Флот соперника никогда не передаётся — только клетка.
Map<String, Object?> shotToJson(Square square, int ply) => {
      'ply': ply,
      'square': square.toJson(),
    };

/// Разбирает пришедший `move`-выстрел. Возвращает номер хода и клетку.
/// Бросает [FormatException] на чужую форму.
({int ply, Square square}) parseShot(Map<String, Object?> data) {
  final squareRaw = data['square'];
  if (squareRaw is! List || squareRaw.length != 2) {
    throw const FormatException('Ход не распознан: клетка');
  }
  final r = squareRaw[0];
  final c = squareRaw[1];
  if (r is! int || c is! int || r < 0 || r > 9 || c < 0 || c > 9) {
    throw const FormatException('Ход не распознан: координаты');
  }
  final plyRaw = data['ply'];
  final ply = plyRaw is int ? plyRaw : 0;
  return (ply: ply, square: Square(r, c));
}

/// Сообщение `event` с результатом выстрела. Его отправляет тот, по кому
/// стреляли: он знает свой флот и вычисляет miss/hit/sunk. `nextTurn` сообщает
/// стрелявшему, чья теперь очередь: «me» — стрелявший стреляет ещё раз (попал),
/// «enemy» — ход переходит к обороняющемуся (промах).
Map<String, Object?> shotResultToJson({
  required int ply,
  required Square square,
  required ShotResult result,
  ShipType? sunkType,
  required String nextTurn,
}) {
  final map = <String, Object?>{
    'kind': 'shotResult',
    'ply': ply,
    'square': square.toJson(),
    'result': result.name,
    'nextTurn': nextTurn,
  };
  if (sunkType != null) map['sunkType'] = sunkType.name;
  return map;
}

/// Разобранный результат выстрела: кто стрелял, куда, чем кончилось и чей
/// теперь ход. `sunkType` заполнен только при потоплении — нужен для обводки
/// контура и сообщения «Потоплен крейсер!».
class ParsedShotResult {
  const ParsedShotResult({
    required this.ply,
    required this.square,
    required this.result,
    required this.nextTurn,
    this.sunkType,
  });

  final int ply;
  final Square square;
  final ShotResult result;
  final ShipType? sunkType;

  /// «me» — стрелявший стреляет ещё раз, «enemy» — ход переходит к
  /// обороняющемуся. По умолчанию «enemy» (на случай, если поле забыли).
  final String nextTurn;
}

/// Разбирает пришедший `event` с результатом выстрела. Бросает [FormatException]
/// на чужую форму.
ParsedShotResult parseShotResult(Map<String, Object?> data) {
  if (data['kind'] != 'shotResult') {
    throw const FormatException('Событие не распознано: kind');
  }
  final squareRaw = data['square'];
  if (squareRaw is! List || squareRaw.length != 2) {
    throw const FormatException('Результат не распознан: клетка');
  }
  final r = squareRaw[0];
  final c = squareRaw[1];
  if (r is! int || c is! int || r < 0 || r > 9 || c < 0 || c > 9) {
    throw const FormatException('Результат не распознан: координаты');
  }
  final resultName = data['result'];
  if (resultName is! String) {
    throw const FormatException('Результат не распознан: тип');
  }
  final result = ShotResult.values
      .where((t) => t.name == resultName)
      .firstOrNull;
  if (result == null) {
    throw const FormatException('Результат не распознан: тип');
  }
  final plyRaw = data['ply'];
  final ply = plyRaw is int ? plyRaw : 0;
  ShipType? sunkType;
  final sunkName = data['sunkType'];
  if (sunkName is String) {
    sunkType = ShipType.values
        .where((t) => t.name == sunkName)
        .firstOrNull;
  }
  final nextTurnRaw = data['nextTurn'];
  final nextTurn = nextTurnRaw == 'me' ? 'me' : 'enemy';
  return ParsedShotResult(
    ply: ply,
    square: Square(r, c),
    result: result,
    sunkType: sunkType,
    nextTurn: nextTurn,
  );
}

/// Сообщение `event` о готовности флота: «я расставил корабли, можно начинать».
Map<String, Object?> fleetReadyToJson() => const {
      'kind': 'fleetReady',
      'ready': true,
    };

/// Правда ли, что в карте пришло сообщение о готовности флота.
bool isFleetReadyEvent(Map<String, Object?> data) =>
    data['kind'] == 'fleetReady' && data['ready'] == true;
