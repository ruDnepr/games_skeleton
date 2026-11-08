import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/domino/domino_controller.dart';
import 'package:games_for_diana/games/domino/engine/ai.dart';
import 'package:games_for_diana/games/domino/engine/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Логика контроллера без виджетов: ход, undo, hint, ИИ и победа — без Flame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
  });
  tearDown(() => settings.dispose());

  /// Собирает позицию из читаемых записей: руки, базар и цепочка.
  GameState table({
    required List<List<String>> hands,
    List<String> board = const [],
    int turn = 0,
    List<String> bazaar = const [],
  }) {
    var chain = const Board.empty();
      for (final label in board) {
        chain = chain.place(DominoTile.parse(label), ChainSide.right);
      }
      return GameState(
        playerCount: hands.length,
        hands: [
          for (final hand in hands)
            [for (final label in hand) DominoTile.parse(label)],
        ],
        bazaar: [for (final label in bazaar) DominoTile.parse(label)],
        board: chain,
        turn: turn,
      );
  }

  /// Создаёт контроллер с заданной позицией; режим — локальный (вдвоём на одном
  /// устройстве), без анимации, без ИИ.
  DominoController localController(GameState state) {
    final controller = DominoController(
      settings: settings,
      sounds: GameSounds(settings),
      animationDuration: Duration.zero,
    );
    controller.startLocalWithState(state);
    return controller;
  }

  /// Создаёт контроллер против компьютера с заданной позицией.
  DominoController aiController(GameState state, {Difficulty difficulty = Difficulty.medium}) {
    final controller = DominoController(
      settings: settings,
      sounds: GameSounds(settings),
      animationDuration: Duration.zero,
    );
    controller.startComputerWithState(state, difficulty);
    return controller;
  }

  test('игрок выкладывает кость, и ход переходит дальше', () async {
    final controller = localController(
      table(
        hands: [
          ['1:2', '0:0'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    expect(controller.canInteract, isTrue);
    expect(controller.legalMoves, hasLength(1));
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(controller.state.board.length, 2);
    expect(controller.state.turn, 1);
    // Играем вдвоём за одним устройством: внизу рука того, чья очередь.
    expect(controller.myHand.map((tile) => tile.label), ['3:4']);
  });

  test('подсказка работает и подсвечивает кость', () {
    final controller = localController(
      table(
        hands: [
          ['1:2', '4:4'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    expect(controller.activeSide == DominoActive.me, isTrue);
    expect(
      controller.playableTiles.map((tile) => tile.label).toList(),
      ['1:2'],
    );
    controller.showHint();
    expect(controller.hintText, isNotNull);
    expect(controller.suggestedMove?.tile.label, '1:2');
    expect(controller.selectedTile?.label, '1:2');
    controller.clearHint();
    expect(controller.hintText, isNull);
    expect(controller.suggestedMove, isNull);
  });

  test('взятие из базара оставляет ход за игроком', () async {
    final controller = localController(
      table(
        hands: [
          ['0:0'],
          ['3:4'],
        ],
        board: ['6:6'],
        bazaar: ['5:5', '1:2'],
      ),
    );
    addTearDown(controller.dispose);
    expect(controller.canDraw, isTrue);
    await controller.drawFromBazaar();
    expect(controller.state.bazaarCount, 1);
    expect(
      controller.myHand.map((tile) => tile.label).toList(),
      contains('5:5'),
    );
    expect(controller.history.last.text, contains('из базара'));
  });

  test('отмена хода возвращает прежнюю позицию и историю', () async {
    final controller = localController(
      table(
        hands: [
          ['1:2', '0:0'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    final before = controller.state.fingerprint;
    final historyBefore = controller.history.length;
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.state.fingerprint, before);
    expect(controller.history, hasLength(historyBefore));
    expect(controller.state.turn, 0);
  });

  test('выложенная последняя кость заканчивает партию', () async {
    final controller = localController(
      table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(controller.isOver, isTrue);
    expect(controller.winner, 0);
    expect(controller.isDraw, isFalse);
    expect(controller.result?.kind, ResultKind.win);
  });

  test('компьютер отвечает сам после хода игрока', () async {
    final controller = aiController(
      table(
        hands: [
          ['1:2', '0:0'],
          ['1:3'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(
      controller.state.board.length,
      3,
      reason: 'первая кость, ход игрока и ответ компьютера',
    );
    expect(controller.state.turn, 0, reason: 'ход снова за игроком');
    expect(controller.computerThinking, isFalse);
  });

  test('компьютер сам берёт кость из базара, если ходить нечем', () async {
    final controller = aiController(
      table(
        hands: [
          ['1:2', '1:3'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
        bazaar: ['6:5'],
      ),
    );
    addTearDown(controller.dispose);
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(
      controller.computerThinking,
      isFalse,
      reason: 'после взятия из базара компьютер не должен «зависать»',
    );
    expect(controller.state.bazaarCount, 0);
    expect(
      controller.state.board.length,
      3,
      reason: 'компьютер взял 5:6 из базара и поставил её',
    );
    expect(
      controller.history.map((record) => record.text).join(' '),
      contains('берёт 5:6 из базара'),
    );
    expect(controller.state.turn, 0, reason: 'ход снова за игроком');
  });

  test('компьютер пропускает ход, когда базар пуст', () async {
    final controller = aiController(
      table(
        hands: [
          ['1:2', '1:3'],
          ['4:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(controller.computerThinking, isFalse);
    expect(
      controller.history.map((record) => record.text).join(' '),
      contains('пропускает ход'),
    );
    expect(controller.state.turn, 0, reason: 'ход снова за игроком');
  });

  test('history хранит описание каждого хода', () async {
    final controller = localController(
      table(
        hands: [
          ['1:2'],
          ['3:4'],
        ],
        board: ['2:5'],
        turn: 0,
      ),
    );
    addTearDown(controller.dispose);
    await controller.playMove(
      const DominoMove(tile: DominoTile(1, 2), side: ChainSide.left),
    );
    expect(controller.history, isNotEmpty);
    expect(controller.history.last.seat, 0);
    expect(controller.history.last.text, contains('ставит'));
  });
}
