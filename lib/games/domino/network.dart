import '../../app/settings.dart';
import 'engine/model.dart';

/// Идентификатор игры — латиница, без пробелов. Попадает в ключи хранения
/// (`game.domino.<key>`) и в рукопожатие по сети, поэтому после первых партий
/// его не меняют.
const dominoGameId = 'domino';

/// Что игра рассказывает сопернику о себе в рукопожатии. Для домино это
/// переключатели отображения: подсветка и кнопка-подсказка. Каждое устройство
/// рисует по своим настройкам, но карта проверяется, чтобы чужое лобби не
/// пустило в партию неразборчивые данные.
Map<String, Object?> dominoOptions(SettingsController settings) => {
  'hints': settings.flag(dominoGameId, 'hints'),
  'hintButton': settings.flag(dominoGameId, 'hintButton'),
};

/// Опции домино после разбора. Значения — только то, что игра умеет.
class DominoOptions {
  const DominoOptions({required this.hints, required this.hintButton});
  final bool hints;
  final bool hintButton;
}

/// Разбирает опции соперника и бросает [FormatException] на чужое: неизвестные
/// ключи, недостающие ключи, неверные типы. Транспорт зовёт это до начала
/// партии, так что чужая игра или чужие данные отказываются у двери.
DominoOptions dominoParseOptions(Map<String, Object?> options) {
  const allowed = {'hints', 'hintButton'};
  final unknown = options.keys
      .where((key) => !allowed.contains(key))
      .toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final hints = options['hints'];
  final hintButton = options['hintButton'];
  if (hints is! bool || hintButton is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return DominoOptions(hints: hints, hintButton: hintButton);
}

final _tileLabelPattern = RegExp(r'^[0-6]:[0-6]$');

/// Проверяет пришедший по сети ход. Это проверка формы, без состояния: транспорт
/// зовёт её до того, как ход увидит партия. Полная проверка по правилам (с
/// учётом позиции) делает сама партия через `DominoRules.applyMove`, когда
/// применяет ход. Нелегальный ход там вызывает рассинхронизацию и понятное
/// сообщение, а здесь отсекается мусор и чужой формат.
void dominoValidateMove(Map<String, Object?> move) {
  final tile = move['tile'];
  if (tile is! String || !_tileLabelPattern.hasMatch(tile)) {
    throw const FormatException('Ход не распознан: кость');
  }
  // Каноническая запись — меньшее число первым: 3:5, а не 5:3.
  final parts = tile.split(':');
  final a = int.parse(parts[0]);
  final b = int.parse(parts[1]);
  if (a > b) {
    throw const FormatException('Ход не распознан: кость');
  }
  final side = move['side'];
  if (side != 'left' && side != 'right') {
    throw const FormatException('Ход не распознан: сторона');
  }
}

/// Сообщение `move` для отправки хода камнем.
Map<String, Object?> moveToJson(DominoMove move) => {
  'tile': move.tile.label,
  'side': move.side.name,
};

/// Разбирает пришедший `move` в [DominoMove]. Бросает [FormatException] на чужую
/// форму.
DominoMove parseMove(Map<String, Object?> data) => DominoMove.fromJson(data);

/// Снимок стола для клиента: цепочка, размер базара, своя рука и количество
/// костей у соперника, чей ход и итог.
///
/// Хост присылает этот снимок после каждого действия. Клиент не применяет ходы
/// сам — у него нет чужой руки, чтобы проверить legality — а просто заменяет
/// своё состояние пришедшим снимком.
Map<String, Object?> snapshotToJson(GameState state, int viewerSeat) {
  final opponentSeat = viewerSeat == 0 ? 1 : 0;
  return {
    'board': state.board.toJson(),
    'bazaarCount': state.bazaarCount,
    'hand': [
      for (final tile in state.handOf(viewerSeat)) tile.label,
    ],
    'opponentHandSize': state.handSizes[opponentSeat],
    'turn': state.turn,
    'ply': state.ply,
    'result': state.result?.toJson(),
  };
}

/// Разбирает снимок, пришедший от хоста, в [GameState]. Чужая рука остаётся
/// пустой: видны только своя рука и количество костей соперника.
GameState parseSnapshot(Map<String, Object?> data) {
  final boardRaw = data['board'];
  if (boardRaw is! List) {
    throw const FormatException('Снимок не распознан: стол');
  }
  final bazaarCount = data['bazaarCount'];
  if (bazaarCount is! int || bazaarCount < 0) {
    throw const FormatException('Снимок не распознан: базар');
  }
  final handRaw = data['hand'];
  if (handRaw is! List) {
    throw const FormatException('Снимок не распознан: рука');
  }
  final hand = <DominoTile>[];
  for (final entry in handRaw) {
    if (entry is! String) {
      throw const FormatException('Снимок не распознан: кость руки');
    }
    hand.add(DominoTile.parse(entry));
  }
  final opponentSize = data['opponentHandSize'];
  if (opponentSize is! int || opponentSize < 0) {
    throw const FormatException('Снимок не распознан: размер руки соперника');
  }
  final turn = data['turn'];
  if (turn is! int || turn < 0 || turn > 1) {
    throw const FormatException('Снимок не распознан: ход');
  }
  final ply = data['ply'];
  if (ply is! int || ply < 0) {
    throw const FormatException('Снимок не распознан: шаг');
  }
  final resultRaw = data['result'];
  GameResult? result;
  if (resultRaw != null) {
    result = GameResult.fromJson(resultRaw);
  }
  final board = Board.fromJson(boardRaw);
  // Снимок пришёл клиенту, а клиент — всегда место 1 (хост — место 0).
  // Поэтому полученную руку кладём в `hands[1]`, а размер руки соперника — в
  // `handSizes[0]`.
  return GameState(
    playerCount: 2,
    hands: [const [], hand],
    sizes: [opponentSize, hand.length],
    bazaar: const [],
    bazaarTotal: bazaarCount,
    board: board,
    turn: turn,
    ply: ply,
    result: result,
  );
}
