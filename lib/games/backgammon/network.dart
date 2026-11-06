import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.backgammon.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const backgammonGameId = 'backgammon';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для нард это
/// переключатели отображения: подсветка ходов, номера пунктов и авто-бросок.
/// Каждое устройство рисует по своим настройкам, но карта проверяется, чтобы
/// чужое лобби не пустило в партию неразборчивые данные.
Map<String, Object?> backgammonOptions(SettingsController settings) => {
  'hints': settings.flag(backgammonGameId, 'hints'),
  'numbers': settings.flag(backgammonGameId, 'numbers'),
  'autoRoll': settings.flag(backgammonGameId, 'autoRoll'),
};

/// Опции нард после разбора. Значения — только то, что игра умеет.
class BackgammonOptions {
  const BackgammonOptions({
    required this.hints,
    required this.numbers,
    required this.autoRoll,
  });
  final bool hints;
  final bool numbers;
  final bool autoRoll;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
BackgammonOptions backgammonParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'numbers', 'autoRoll'};
  final unknown = options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final numbers = options['numbers'];
  final autoRoll = options['autoRoll'];
  if (hints is! bool || numbers is! bool || autoRoll is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return BackgammonOptions(hints: hints, numbers: numbers, autoRoll: autoRoll);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния: транспорт
/// зовёт её до того, как ход увидит партия. Полная проверка по правилам (с
/// учётом позиции) делает сама партия через `BackgammonRules.applyTurn`, когда
/// применяет ход. Нелегальный ход там вызывает рассинхронизацию и понятное
/// сообщение, а здесь отсекается мусор и чужой формат.
void backgammonValidateMove(Map<String, Object?> move) {
  final player = move['player'];
  if (player != 'white' && player != 'black') {
    throw const FormatException('Ход не распознан: цвет');
  }
  final dice = move['dice'];
  if (dice is! List || dice.length != 2) {
    throw const FormatException('Ход не распознан: кости');
  }
  final d0 = dice[0];
  final d1 = dice[1];
  if (d0 is! int || d1 is! int || d0 < 1 || d0 > 6 || d1 < 1 || d1 > 6) {
    throw const FormatException('Ход не распознан: кости');
  }
  final moves = move['moves'];
  if (moves is! List || moves.length > 4) {
    throw const FormatException('Ход не распознан: шаги');
  }
  final allowedDice = {d0, d1};
  for (final entry in moves) {
    if (entry is! Map) {
      throw const FormatException('Ход не распознан: шаг');
    }
    final parsed = Move.fromJson(Map<String, Object?>.from(entry));
    if (parsed.player.name != player) {
      throw const FormatException('Ход не распознан: цвет шага');
    }
    if (!allowedDice.contains(parsed.die)) {
      throw const FormatException('Ход не распознан: кость шага');
    }
  }
}

/// Разбирает сообщение `dice` (бросок, пришедший от хоста) в цвет и кости.
/// Бросает [FormatException] на чужую форму.
({Player player, List<int> dice}) parseDiceMessage(Map<String, Object?> data) {
  final player = data['player'];
  if (player != 'white' && player != 'black') {
    throw const FormatException('Кости не распознаны: цвет');
  }
  final dice = data['dice'];
  if (dice is! List || dice.length != 2) {
    throw const FormatException('Кости не распознаны: форма');
  }
  final d0 = dice[0];
  final d1 = dice[1];
  if (d0 is! int || d1 is! int || d0 < 1 || d0 > 6 || d1 < 1 || d1 > 6) {
    throw const FormatException('Кости не распознаны: значения');
  }
  return (
    player: player == 'white' ? Player.white : Player.black,
    dice: [d0, d1],
  );
}

/// Сообщение `dice` для отправки хостом.
Map<String, Object?> diceMessage(Player player, List<int> dice) => {
  'player': player.name,
  'dice': List<int>.of(dice),
};

/// Сообщение `move` для отправки завершенного хода.
Map<String, Object?> moveMessage(Turn turn) => turn.toJson();

/// Разбирает пришедший `move` в [Turn] (полный разбор, для применения партией).
Turn parseTurn(Map<String, Object?> data) {
  final player = data['player'];
  if (player != 'white' && player != 'black') {
    throw const FormatException('Ход не распознан: цвет');
  }
  final dice = data['dice'];
  if (dice is! List || dice.length != 2) {
    throw const FormatException('Ход не распознан: кости');
  }
  final d0 = dice[0];
  final d1 = dice[1];
  if (d0 is! int || d1 is! int || d0 < 1 || d0 > 6 || d1 < 1 || d1 > 6) {
    throw const FormatException('Ход не распознан: кости');
  }
  final movesRaw = data['moves'];
  if (movesRaw is! List || movesRaw.length > 4) {
    throw const FormatException('Ход не распознан: шаги');
  }
  final moves = <Move>[];
  for (final entry in movesRaw) {
    if (entry is! Map) {
      throw const FormatException('Ход не распознан: шаг');
    }
    moves.add(Move.fromJson(Map<String, Object?>.from(entry)));
  }
  return Turn(
    player: player == 'white' ? Player.white : Player.black,
    dice: [d0, d1],
    moves: moves,
  );
}
