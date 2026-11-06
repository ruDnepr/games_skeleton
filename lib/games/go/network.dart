import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.go.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const goGameId = 'go';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для го это
/// переключатели отображения: подсветка и кнопка-подсказка. Каждое
/// устройство рисует по своим настройкам, но карта проверяется, чтобы чужое
/// лобби не пустило в партию неразборчивые данные.
///
/// Размер доски и режим партии в рукопожатие не входят: хост объявляет их
/// отдельно, как свою сторону, а клиенту достаточно знать gameId.
Map<String, Object?> goOptions(SettingsController settings) => {
      'hints': settings.flag(goGameId, 'hints'),
      'hintButton': settings.flag(goGameId, 'hintButton'),
    };

/// Опции го после разбора. Значения — только то, что игра умеет.
class GoOptions {
  const GoOptions({required this.hints, required this.hintButton});
  final bool hints;
  final bool hintButton;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
GoOptions goParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'hintButton'};
  final unknown =
      options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final hintButton = options['hintButton'];
  if (hints is! bool || hintButton is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return GoOptions(hints: hints, hintButton: hintButton);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния:
/// транспорт зовёт её до того, как ход увидит партия. Полная проверка по
/// правилам (с учётом позиции) делает сама партия через `GoRules.applyMove`,
/// когда применяет ход. Нелегальный ход там вызывает рассинхронизацию и
/// понятное сообщение, а здесь отсекается мусор и чужой формат.
///
/// Формат хода один и тот же для постановки камня и для паса:
/// `{"color": "black"|"white", "pass": bool, "point"?: [int, int]}`. Пас
/// шлётся тем же сообщением `move` с `pass: true` — отдельного типа `pass`
/// в протоколе нет.
void goValidateMove(Map<String, Object?> move) {
  final color = move['color'];
  if (color != 'black' && color != 'white') {
    throw const FormatException('Ход не распознан: цвет');
  }
  final pass = move['pass'];
  // `pass` может отсутствовать — тогда считаем, что это постановка камня.
  if (pass != null && pass is! bool) {
    throw const FormatException('Ход не распознан: пас');
  }
  if (pass == true) {
    // Для паса точка не нужна — ход допустим.
    return;
  }
  final point = move['point'];
  if (point is! List || point.length != 2) {
    throw const FormatException('Ход не распознан: точка');
  }
  final x = point[0];
  final y = point[1];
  if (x is! int || y is! int || x < 0 || x > 18 || y < 0 || y > 18) {
    throw const FormatException('Ход не распознан: точка');
  }
}

/// Сетевой формат хода. Делегирует в модель — единая точка правды о форме.
Map<String, Object?> moveToJson(GoMove move) => move.toJson();

/// Разбирает пришедший по сети ход в [GoMove] (полный разбор, для применения
/// партией). Бросает [FormatException] на чужую форму.
GoMove parseMove(Map<String, Object?> data) => GoMove.fromJson(data);
