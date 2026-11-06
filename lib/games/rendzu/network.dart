import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.rendzu.<key>`) и в рукопожатие по сети, поэтому после первых партий
/// его не меняют.
const rendzuGameId = 'rendzu';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для рэндзю это два
/// переключателя отображения: подсказки и подсветка паттернов. Каждое
/// устройство рисует по своим настройкам, но карта проверяется, чтобы чужое
/// лобби не пустило в партию неразборчивые данные. Набор правил, размер доски
/// и цвет — выбираются на стороне хоста и не пересылаются (хост всегда играет
/// чёрными и ходит первым, как в шашках).
Map<String, Object?> rendzuOptions(SettingsController settings) => {
      'hints': settings.flag(rendzuGameId, 'hints'),
      'patternHighlight': settings.flag(rendzuGameId, 'patternHighlight'),
    };

/// Опции рэндзю после разбора. Только то, что игра умеет.
class RendzuOptions {
  const RendzuOptions({
    required this.hints,
    required this.patternHighlight,
  });
  final bool hints;
  final bool patternHighlight;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
RendzuOptions rendzuParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'patternHighlight'};
  final unknown = options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final patternHighlight = options['patternHighlight'];
  if (hints is! bool || patternHighlight is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return RendzuOptions(hints: hints, patternHighlight: patternHighlight);
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
