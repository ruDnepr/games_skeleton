import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.rendzu.<key>`) и в рукопожатие по сети, поэтому после первых партий
/// его не меняют.
const rendzuGameId = 'rendzu';

/// Ключ, под которым хранится выбранный хостом набор правил для сетевой игры.
const rendzuRulesetKey = 'ruleset';

/// Ключ, под которым хранится выбранный хостом размер доски для сетевой игры.
const rendzuBoardSizeKey = 'boardSize';

/// Значение по умолчанию для набора правил в сетевой игре — рэндзю с запретами.
const rendzuDefaultRuleset = 'renju';

/// Значение по умолчанию для размера доски в сетевой игре — 9×9.
const rendzuDefaultBoardSize = 'small9';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для рэндзю это два
/// переключателя отображения (подсказки и подсветка паттернов) и выбранные
/// хостом набор правил и размер доски. Каждое устройство рисует по своим
/// настройкам, но карта проверяется, чтобы чужое лобби не пустило в партию
/// неразборчивые данные. Цвет в сети фиксирован: хост играет чёрными и ходит
/// первым — так же, как белые в нардах.
Map<String, Object?> rendzuOptions(SettingsController settings) => {
      'hints': settings.flag(rendzuGameId, 'hints'),
      'patternHighlight': settings.flag(rendzuGameId, 'patternHighlight'),
      'ruleset': settings.gameString(
        rendzuGameId,
        rendzuRulesetKey,
        rendzuDefaultRuleset,
      ),
      'boardSize': settings.gameString(
        rendzuGameId,
        rendzuBoardSizeKey,
        rendzuDefaultBoardSize,
      ),
    };

/// Опции рэндзю после разбора. Только то, что игра умеет.
class RendzuOptions {
  const RendzuOptions({
    required this.hints,
    required this.patternHighlight,
    required this.ruleset,
    required this.boardSize,
  });
  final bool hints;
  final bool patternHighlight;

  /// `'gomoku'` или `'renju'`. Хост выбирает до создания сетевой игры; клиент
  /// принимает тот, что пришёл в рукопожатии.
  final String ruleset;

  /// `'small9'` или `'standard15'`.
  final String boardSize;

  Ruleset get rulesetEnum =>
      ruleset == 'renju' ? Ruleset.renju : Ruleset.gomoku;

  BoardSize get boardSizeEnum =>
      boardSize == 'standard15' ? BoardSize.standard15 : BoardSize.small9;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
RendzuOptions rendzuParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'patternHighlight', 'ruleset', 'boardSize'};
  final unknown = options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final patternHighlight = options['patternHighlight'];
  final ruleset = options['ruleset'];
  final boardSize = options['boardSize'];
  if (hints is! bool || patternHighlight is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  if (ruleset is! String || (ruleset != 'gomoku' && ruleset != 'renju')) {
    throw const FormatException('Настройки игры не распознаны: набор правил');
  }
  if (boardSize is! String ||
      (boardSize != 'small9' && boardSize != 'standard15')) {
    throw const FormatException('Настройки игры не распознаны: размер доски');
  }
  return RendzuOptions(
    hints: hints,
    patternHighlight: patternHighlight,
    ruleset: ruleset,
    boardSize: boardSize,
  );
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния: транспорт
/// зовёт её до того, как ход увидит партия. Полная проверка по правилам (с
/// учётом позиции и запрещённых ходов) делает сама партия, когда применяет ход.
/// Нелегальный ход там вызывает рассинхронизацию и понятное сообщение, а здесь
/// отсекается мусор и чужой формат.
void rendzuValidateMove(Map<String, Object?> move) {
  final x = move['x'];
  final y = move['y'];
  final color = move['color'];
  if (x is! int || y is! int || x < 0 || y < 0 || x > 14 || y > 14) {
    throw const FormatException('Ход не распознан: координаты');
  }
  if (color != 'black' && color != 'white') {
    throw const FormatException('Ход не распознан: цвет');
  }
}

/// Сообщение `move` для отправки. Формат упрощённый: точка «развёрнута», номер
/// хода опущен — он выводится из длины истории на принимающей стороне.
Map<String, Object?> moveToJson(Point point, StoneColor color) => {
      'x': point.x,
      'y': point.y,
      'color': color.name,
    };

/// Разбирает пришедший `move` в точку и цвет. Полная проверка формы —
/// координаты 0..14, цвет «black» или «white». Бросает [FormatException].
({Point point, StoneColor color}) parseMove(Map<String, Object?> data) {
  final x = data['x'];
  final y = data['y'];
  final color = data['color'];
  if (x is! int || y is! int || x < 0 || y < 0 || x > 14 || y > 14) {
    throw const FormatException('Ход не распознан: координаты');
  }
  if (color == 'black') {
    return (point: Point(x, y), color: StoneColor.black);
  }
  if (color == 'white') {
    return (point: Point(x, y), color: StoneColor.white);
  }
  throw const FormatException('Ход не распознан: цвет');
}
