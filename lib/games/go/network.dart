import '../../app/settings.dart';
import '../definition.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.go.<key>`) и в рукопожатие по сети, поэтому после первых
/// партий его не меняют.
const goGameId = 'go';

/// Ключи выбора хоста перед сетевой партией. Сохраняются в настройках и
/// уезжают в рукопожатие через [goOptions], чтобы клиент открыл ту же партию.
const goHostModeKey = 'hostMode';
const goHostBoardKey = 'hostBoard';
const goHostTargetKey = 'hostTarget';
const goHostSideKey = 'hostSide';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для го это
/// переключатели отображения (подсветка и кнопка-подсказка) и выбор хоста
/// (режим, размер доски, цель захвата, сторона). Каждое устройство рисует
/// подсветку по своим настройкам, а параметры партии — общие.
Map<String, Object?> goOptions(SettingsController settings) => {
      'hints': settings.flag(goGameId, 'hints'),
      'hintButton': settings.flag(goGameId, 'hintButton'),
      'mode': settings.gameString(goGameId, goHostModeKey, 'capture'),
      'boardSize': int.parse(
        settings.gameString(goGameId, goHostBoardKey, '9'),
      ),
      'captureTarget': int.parse(
        settings.gameString(goGameId, goHostTargetKey, '1'),
      ),
      'hostSide': settings.gameString(goGameId, goHostSideKey, 'black'),
    };

/// Опции го после разбора. Значения — только то, что игра умеет.
class GoOptions {
  const GoOptions({
    required this.hints,
    required this.hintButton,
    required this.mode,
    required this.boardSize,
    required this.captureTarget,
    required this.hostSide,
  });
  final bool hints;
  final bool hintButton;
  final GoMode mode;
  final int boardSize;
  final CaptureTarget captureTarget;
  final StoneColor hostSide;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
GoOptions goParseOptions(Map<String, Object?> options) {
  const allowed = {
    'hints',
    'hintButton',
    'mode',
    'boardSize',
    'captureTarget',
    'hostSide',
  };
  final unknown =
      options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final hintButton = options['hintButton'];
  final modeStr = options['mode'];
  final boardSize = options['boardSize'];
  final targetNum = options['captureTarget'];
  final sideStr = options['hostSide'];
  if (hints is! bool ||
      hintButton is! bool ||
      modeStr is! String ||
      boardSize is! int ||
      targetNum is! int ||
      sideStr is! String) {
    throw const FormatException('Настройки игры не распознаны');
  }
  final mode = modeStr == 'classic' ? GoMode.classic : GoMode.capture;
  if (boardSize != 9 && boardSize != 13 && boardSize != 19) {
    throw const FormatException('Неподдерживаемый размер доски');
  }
  if (targetNum != 1 && targetNum != 3) {
    throw const FormatException('Неподдерживаемая цель захвата');
  }
  final side = sideStr == 'white' ? StoneColor.white : StoneColor.black;
  return GoOptions(
    hints: hints,
    hintButton: hintButton,
    mode: mode,
    boardSize: boardSize,
    captureTarget:
        targetNum == 1 ? CaptureTarget.one : CaptureTarget.three,
    hostSide: side,
  );
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

/// Сохраняет выбор хоста в настройках, чтобы [goOptions] мог его прочитать
/// при создании лобби.
Future<void> saveGoHostSetup(
  SettingsController settings, {
  required GoMode mode,
  required int boardSize,
  required CaptureTarget target,
  required StoneColor side,
}) async {
  await Future.wait([
    settings.setGameString(
      goGameId,
      goHostModeKey,
      mode == GoMode.classic ? 'classic' : 'capture',
    ),
    settings.setGameString(goGameId, goHostBoardKey, '$boardSize'),
    settings.setGameString(
      goGameId,
      goHostTargetKey,
      '${target == CaptureTarget.three ? 3 : 1}',
    ),
    settings.setGameString(
      goGameId,
      goHostSideKey,
      side == StoneColor.white ? 'white' : 'black',
    ),
  ]);
}

/// Опции го из уже согласованного лобби — для удобства экранов партии.
GoOptions optionsFromLobby(NetworkSession network) =>
    goParseOptions(network.lobby.options);
