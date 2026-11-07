import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.loto.<key>`) и в рукопожатие по сети, поэтому после первых партий
/// его не меняют.
const lotoGameId = 'loto';

/// Ключ, под которым выбранный режим победы лежит в настройках. Хост выбирает
/// его на отдельном экране перед лобби (`preNetwork`), и тот же ключ читает
/// [lotoOptions] при сборке рукопожатия.
const lotoWinModeKey = 'winMode';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для лото это три
/// переключателя отображения и озвучки плюс режим победы, который выбрал хост.
/// Каждое устройство рисует по своим настройкам, но карта проверяется, чтобы
/// чужое лобби не пустило в партию неразборчивые данные.
Map<String, Object?> lotoOptions(SettingsController settings) => {
  'hints': settings.flag(lotoGameId, 'hints'),
  'hintButton': settings.flag(lotoGameId, 'hintButton'),
  'voice': settings.flag(lotoGameId, 'voice'),
  'winMode': settings.gameString(lotoGameId, lotoWinModeKey, WinMode.row.name),
};

/// Опции лото после разбора. Значения — только то, что игра умеет.
class LotoOptions {
  const LotoOptions({
    required this.hints,
    required this.hintButton,
    required this.voice,
  });

  final bool hints;
  final bool hintButton;
  final bool voice;

  /// Режим победы приходит отдельным полем `winMode` — его выбирает хост на
  /// экране старта и пересылает вместе с опциями. Клиент доверяет выбранному
  /// хостом режиму, потому что обе карточки играют по одним правилам.
  static WinMode winModeFromOptions(Map<String, Object?> options) =>
      WinMode.fromName(options['winMode']);
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
LotoOptions lotoParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'hintButton', 'voice', 'winMode'};
  final unknown =
      options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final hintButton = options['hintButton'];
  final voice = options['voice'];
  if (hints is! bool || hintButton is! bool || voice is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  // winMode факультативен: хост указывает его, клиент без него играет по строке.
  final winMode = options['winMode'];
  if (winMode != null && winMode is! String) {
    throw const FormatException('Настройки игры не распознаны: режим победы');
  }
  return LotoOptions(hints: hints, hintButton: hintButton, voice: voice);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния:
/// транспорт зовёт её до того, как ход увидит партия. Полная проверка по
/// правилам (с учётом позиции) делает сама партия через `LotoGame.close`,
/// когда применяет закрытие. Незаконное закрытие там вызывает рассинхронизацию
/// и понятное сообщение, а здесь отсекается мусор и чужой формат.
///
/// Единственный ход лото — закрыть число: `{'number': int 1..90}`. Бочонки
/// раздаёт хост сообщением `event`, поэтому они сюда не попадают.
void lotoValidateMove(Map<String, Object?> move) {
  final number = move['number'];
  if (number is! int || number < 1 || number > 90) {
    throw const FormatException('Ход не распознан: число бочонка');
  }
}

// ---- Сообщения `event` ----------------------------------------------------

/// Сообщение `event` с `kind: 'barrel'`: хост объявляет вытянутый бочонок.
/// `count` — сколько бочонков осталось в мешке после этой вытянутки.
Map<String, Object?> barrelMessageToJson(int number, int count) => {
  'kind': 'barrel',
  'number': number,
  'left': count,
};

/// Разбирает сообщение `event` с `kind: 'barrel'`. Бросает [FormatException]
/// на чужую форму.
({int number, int left}) parseBarrelMessage(Map<String, Object?> data) {
  if (data['kind'] != 'barrel') {
    throw const FormatException('Событие не распознано: тип');
  }
  final number = data['number'];
  final left = data['left'];
  if (number is! int || number < 1 || number > 90) {
    throw const FormatException('Событие не распознано: бочонок');
  }
  if (left is! int || left < 0 || left > 90) {
    throw const FormatException('Событие не распознано: остаток');
  }
  return (number: number, left: left);
}

/// Сообщение `move` для закрытия числа: клиент → хост.
Map<String, Object?> closeNumberToJson(String playerId, int number) => {
  'playerId': playerId,
  'number': number,
};

/// Разбирает пришедший `move` в идентификатор игрока и число. Полная проверка
/// формы — `playerId` это строка, `number` это int 1..90. Бросает
/// [FormatException].
({String playerId, int number}) parseCloseNumber(Map<String, Object?> data) {
  final playerId = data['playerId'];
  final number = data['number'];
  if (playerId is! String || playerId.isEmpty) {
    throw const FormatException('Ход не распознан: игрок');
  }
  if (number is! int || number < 1 || number > 90) {
    throw const FormatException('Ход не распознан: число бочонка');
  }
  return (playerId: playerId, number: number);
}

/// Сообщение `event` с `kind: 'closeNumber'`: хост подтверждает закрытие числа
/// игрока и рассылает его всем. Если [accepted] ложь, в [reason] лежит текст
/// отказа (например, «Этот бочонок ещё в мешке»).
Map<String, Object?> closeEventToJson({
  required String playerId,
  required int number,
  required bool accepted,
  String? reason,
}) => {
  'kind': 'closeNumber',
  'playerId': playerId,
  'number': number,
  'accepted': accepted,
  'reason': ?reason,
};

/// Разбирает `event` с `kind: 'closeNumber'`. Бросает [FormatException].
({
  String playerId,
  int number,
  bool accepted,
  String? reason,
}) parseCloseEvent(Map<String, Object?> data) {
  if (data['kind'] != 'closeNumber') {
    throw const FormatException('Событие не распознано: тип');
  }
  final playerId = data['playerId'];
  final number = data['number'];
  final accepted = data['accepted'];
  final reason = data['reason'];
  if (playerId is! String || playerId.isEmpty) {
    throw const FormatException('Событие не распознано: игрок');
  }
  if (number is! int || number < 1 || number > 90) {
    throw const FormatException('Событие не распознано: число бочонка');
  }
  if (accepted is! bool) {
    throw const FormatException('Событие не распознано: результат');
  }
  if (reason != null && reason is! String) {
    throw const FormatException('Событие не распознано: причина');
  }
  return (
    playerId: playerId,
    number: number,
    accepted: accepted,
    reason: reason is String ? reason : null,
  );
}

/// Сообщение `event` с `kind: 'snapshot'`: полный снимок партии — хост шлёт
/// его при переподключении или старте, чтобы клиент показал то же состояние.
Map<String, Object?> snapshotToJson({
  required LotoGame game,
  required String hostPlayerId,
  required String clientPlayerId,
}) => {
  'kind': 'snapshot',
  'winMode': game.winMode.name,
  'drawn': List<int>.of(game.drawn, growable: false),
  'players': [
    for (final player in game.players) player.toJson(),
  ],
  'winnerId': game.winnerId,
  'winningRow': game.winningRow,
  'hostPlayerId': hostPlayerId,
  'clientPlayerId': clientPlayerId,
};

/// Разбирает `event` с `kind: 'snapshot'`. Бросает [FormatException].
({
  LotoGame game,
  String hostPlayerId,
  String clientPlayerId,
}) parseSnapshot(Map<String, Object?> data) {
  if (data['kind'] != 'snapshot') {
    throw const FormatException('Снимок не распознан: тип');
  }
  final winModeRaw = data['winMode'];
  final drawnRaw = data['drawn'];
  final playersRaw = data['players'];
  final winnerId = data['winnerId'];
  final winningRow = data['winningRow'];
  final hostPlayerId = data['hostPlayerId'];
  final clientPlayerId = data['clientPlayerId'];
  if (winModeRaw is! String) {
    throw const FormatException('Снимок не распознан: режим победы');
  }
  if (drawnRaw is! List) {
    throw const FormatException('Снимок не распознан: история');
  }
  final drawn = <int>{};
  for (final value in drawnRaw) {
    if (value is! int || value < 1 || value > 90 || !drawn.add(value)) {
      throw const FormatException('Снимок не распознан: история');
    }
  }
  final drawnList = List<int>.unmodifiable(drawn);
  if (playersRaw is! List || playersRaw.isEmpty || playersRaw.length > 4) {
    throw const FormatException('Снимок не распознан: игроки');
  }
  final players = <LotoPlayer>[];
  for (final entry in playersRaw) {
    players.add(LotoPlayer.fromJson(entry));
  }
  if (winnerId != null && winnerId is! String) {
    throw const FormatException('Снимок не распознан: победитель');
  }
  if (winningRow != null && winningRow is! int) {
    throw const FormatException('Снимок не распознан: строка победы');
  }
  if (hostPlayerId is! String || clientPlayerId is! String) {
    throw const FormatException('Снимок не распознан: стороны');
  }
  final game = LotoGame.replica(
    players: players,
    winMode: WinMode.fromName(winModeRaw),
    drawn: drawnList,
    winnerId: winnerId is String ? winnerId : null,
    winningRow: winningRow is int ? winningRow : null,
  );
  return (game: game, hostPlayerId: hostPlayerId, clientPlayerId: clientPlayerId);
}
