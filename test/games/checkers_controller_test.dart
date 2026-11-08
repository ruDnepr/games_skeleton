import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/checkers/checkers_controller.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/network.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Логика контроллера без виджетов: ход, undo, hint, finishCapture и ничья.
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

  /// Создаёт контроллер с заданной позицией и режимом «вдвоём на одном
  /// устройстве» — самый простой режим без ИИ и сети.
  CheckersController localController({
    GameVariant variant = GameVariant.russian,
    GameState? state,
  }) {
    final controller = CheckersController(
      settings: settings,
      sounds: GameSounds(settings),
      variant: variant,
      mode: GameMode.local,
      humanColor: Side.white,
      animationPerLanding: Duration.zero,
      initialState: state,
    );
    return controller;
  }

  test('первый ход переключает сторону и записывается в историю', () async {
    final controller = localController();
    addTearDown(controller.dispose);
    expect(controller.state.turn, Side.white);
    expect(controller.history, isEmpty);
    controller.tap(const Square(5, 0));
    expect(controller.selected, const Square(5, 0));
    controller.tap(const Square(4, 1));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.turn, Side.black);
    expect(controller.history, hasLength(1));
    expect(controller.history.single.side, Side.white);
  });

  test('undo в локальном режиме отматывает один ход', () async {
    final controller = localController();
    addTearDown(controller.dispose);
    controller.tap(const Square(5, 0));
    controller.tap(const Square(4, 1));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.turn, Side.black);
    controller.undo();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.turn, Side.white);
    expect(controller.history, isEmpty);
  });

  test('hint подсвечивает ход и объясняет его', () async {
    final controller = localController();
    addTearDown(controller.dispose);
    expect(controller.suggestedMove, isNull);
    expect(controller.hintText, isNull);
    // Тот же путь, что и кнопка на экране: compute в изоляте + обновление
    // полей контроллера.
    await controller.showHint().timeout(const Duration(seconds: 30));
    expect(controller.suggestedMove, isNotNull);
    expect(controller.hintText, contains('подсвечен лучший ход'));
    // Подсказку можно убрать.
    controller.clearHint();
    expect(controller.suggestedMove, isNull);
    expect(controller.hintText, isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('finishCapture завершает серию после первого взятия', () async {
    // Белая простая может взять две чёрные подряд, но в русских можно
    // остановиться после первой.
    final controller = localController(
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 0): const Piece(Side.white),
          const Square(4, 1): const Piece(Side.black),
          const Square(2, 3): const Piece(Side.black),
        }),
        turn: Side.white,
      ),
    );
    addTearDown(controller.dispose);
    controller.tap(const Square(5, 0));
    expect(controller.selected, const Square(5, 0));
    controller.tap(const Square(3, 2));
    // Серию можно продолжить — кнопка «Закончить бой» видна.
    expect(controller.canFinishCapture, isTrue);
    expect(controller.selectedPath, [const Square(3, 2)]);
    controller.finishCapture();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.ply, 1);
    expect(controller.state.board.count(Side.black), 1);
    expect(controller.state.board.at(const Square(3, 2)), isNotNull);
  });

  test('третье повторение позиции даёт ничью', () async {
    // Две дамки, не бьющие друг друга: можно ходить по кругу и повторить
    // позицию трижды.
    final controller = localController(
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 2): const Piece(Side.white, king: true),
          const Square(0, 1): const Piece(Side.black, king: true),
        }),
        turn: Side.white,
      ),
    );
    addTearDown(controller.dispose);
    const circle = [
      [Square(5, 2), Square(4, 1)],
      [Square(0, 1), Square(1, 2)],
      [Square(4, 1), Square(5, 2)],
      [Square(1, 2), Square(0, 1)],
    ];
    // Первый круг — позиция встретилась дважды, ничьи ещё нет.
    for (final step in circle) {
      controller.tap(step.first);
      controller.tap(step.last);
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.isDraw, isFalse);
    // Второй круг — третье повторение.
    for (final step in circle) {
      controller.tap(step.first);
      controller.tap(step.last);
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.isDraw, isTrue);
    expect(controller.isOver, isTrue);
    expect(controller.winner, isNull);
  });

  test('notice объясняет отказ: «Так ходить нельзя.» без подсказок', () async {
    await settings.setFlag(checkersGameId, 'hints', false);
    final controller = localController(
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 0): const Piece(Side.white),
          const Square(4, 1): const Piece(Side.black),
          const Square(5, 6): const Piece(Side.white),
        }),
        turn: Side.white,
      ),
    );
    addTearDown(controller.dispose);
    // Тап по шашке, которая не бьёт, при обязательном взятии — короткий
    // отказ, потому что подсказки выключены.
    controller.tap(const Square(5, 6));
    expect(controller.notice, 'Так ходить нельзя.');
    expect(controller.state.ply, 0);
  });

  test('notice с подсказками подробно объясняет обязательный бой', () async {
    final controller = localController(
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 0): const Piece(Side.white),
          const Square(4, 1): const Piece(Side.black),
          const Square(5, 6): const Piece(Side.white),
        }),
        turn: Side.white,
      ),
    );
    addTearDown(controller.dispose);
    // Тап по шашке, которая не бьёт, при обязательном взятии — подробный
    // отказ с подсказками.
    controller.tap(const Square(5, 6));
    expect(controller.notice, contains('бой обязателен'));
    expect(controller.notice, contains(' эта шашка не бьёт'));
    // Тап по пустой клетке — тот же отказ, но другими словами.
    controller.tap(const Square(6, 1));
    expect(controller.notice, contains('спокойно походить нельзя'));
  });
}
