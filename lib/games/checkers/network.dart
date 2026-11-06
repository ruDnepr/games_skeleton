import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.checkers.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const checkersGameId = 'checkers';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для шашек это
/// переключатели отображения: подсветка и кнопка-подсказка. Каждое устройство
/// рисует по своим настройкам, но карта проверяется, чтобы чужое лобби не
/// пустило в партию неразборчивые данные.
Map<String, Object?> checkersOptions(SettingsController settings) => {
  'hints': settings.flag(checkersGameId, 'hints'),
  'hintButton': settings.flag(checkersGameId, 'hintButton'),
};

/// Опции шашек после разбора. Значения — только то, что игра умеет.
class CheckersOptions {
  const CheckersOptions({required this.hints, required this.hintButton});
  final bool hints;
  final bool hintButton;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
CheckersOptions checkersParseOptions(Map<String, Object?> options) {
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
  return CheckersOptions(hints: hints, hintButton: hintButton);
}

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния: транспорт
/// зовёт её до того, как ход увидит партия. Полная проверка по правилам (с
/// учётом позиции) делает сама партия через `GameRules.apply`, когда применяет
/// ход. Нелегальный ход там вызывает рассинхронизацию и понятное сообщение, а
/// здесь отсекается мусор и чужой формат.
void checkersValidateMove(Map<String, Object?> move) {
  // `from` — пара целых в пределах доски до 10×10.
  final from = move['from'];
  if (from is! List || from.length != 2) {
    throw const FormatException('Ход не распознан: стартовая клетка');
  }
  final fromR = from[0];
  final fromC = from[1];
  if (fromR is! int || fromC is! int ||
      fromR < 0 || fromR > 9 || fromC < 0 || fromC > 9) {
    throw const FormatException('Ход не распознан: стартовая клетка');
  }
  // `path` — непустой список пар целых в пределах 10×10.
  final path = move['path'];
  if (path is! List || path.isEmpty || path.length > 20) {
    throw const FormatException('Ход не распознан: путь');
  }
  for (final entry in path) {
    _checkSquare(entry, 'путь');
  }
  // `captures` — список пар целых; той же длины, что и `path`, для взятия, и
  // пустой для тихого хода.
  final captures = move['captures'];
  if (captures is! List || captures.length > 20) {
    throw const FormatException('Ход не распознан: взятия');
  }
  for (final entry in captures) {
    _checkSquare(entry, 'взятия');
  }
  if (captures.isNotEmpty && captures.length != path.length) {
    throw const FormatException('Ход не распознан: длина взятий');
  }
}

void _checkSquare(Object? value, String what) {
  if (value is! List || value.length != 2) {
    throw FormatException('Ход не распознан: $what');
  }
  final r = value[0];
  final c = value[1];
  if (r is! int || c is! int || r < 0 || r > 9 || c < 0 || c > 9) {
    throw FormatException('Ход не распознан: $what');
  }
}

/// Сетевой формат хода. Делегирует в модель — единая точка правды о форме.
Map<String, Object> moveToJson(Move move) => move.toJson();

/// Разбирает пришедший по сети ход в [Move] (полный разбор, для применения
/// партией). Бросает [FormatException] на чужую форму.
Move parseMove(Map<String, Object?> data) => Move.fromJson(data);
