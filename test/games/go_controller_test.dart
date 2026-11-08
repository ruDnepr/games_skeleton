// Тесты контроллера го: постановка, захват, отмена, пас, подсказки, атари.
// Логика поверх движка, который уже покрыт go_rules_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/go/engine/ai.dart';
import 'package:games_for_diana/games/go/engine/model.dart';
import 'package:games_for_diana/games/go/go_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

AppGameSetup _captureSetup({
  int size = 9,
  StoneColor side = StoneColor.black,
  CaptureTarget target = CaptureTarget.one,
  AppGameMode appMode = AppGameMode.local,
}) =>
    AppGameSetup(
      mode: GoMode.capture,
      boardSize: size,
      playerSide: side,
      captureTarget: target,
      komi: GameSetup.defaultKomi(size),
      appMode: appMode,
      difficulty: Difficulty.easy,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;
  late RecordingBackend backend;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
    backend = RecordingBackend();
  });

  tearDown(() => settings.dispose());

  GameSounds sounds() => GameSounds(settings, backend: backend);

  test('контроллер инициализируется пустой доской 9x9 и ходом чёрных', () {
    final c = GoController(_captureSetup(), settings, sounds: sounds());
    addTearDown(c.dispose);
    expect(c.state.board.size, 9);
    expect(c.state.turn, StoneColor.black);
    expect(c.state.board.count(StoneColor.black), 0);
    expect(c.legalPlacements.length, 81);
  });

  test('тап ставит камень и передаёт ход соперникам', () async {
    final c = GoController(_captureSetup(), settings, sounds: sounds());
    addTearDown(c.dispose);
    c.tap(const Point(4, 4));
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(c.state.board.at(const Point(4, 4)), StoneColor.black);
    expect(c.state.turn, StoneColor.white);
  });

  test('захват через контроллер: чёрные снимают белый камень', () async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final c = GoController(
      setup,
      settings,
      sounds: sounds(),
      initialState: GameState(
        setup: setup.toEngine(),
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      ),
    );
    addTearDown(c.dispose);
    c.tap(const Point(0, 1)); // заполняет последнее дыхание белого
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(c.state.board.occupied(const Point(0, 0)), isFalse);
    expect(c.state.blackCaptured, 1);
    expect(c.isOver, isTrue);
    expect(c.winner, StoneColor.black);
  });

  test('отмена хода в офлайне возвращает предыдущее состояние', () async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final c = GoController(setup, settings, sounds: sounds());
    addTearDown(c.dispose);
    c.tap(const Point(4, 4));
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(c.state.board.occupied(const Point(4, 4)), isTrue);
    c.undo();
    expect(c.state.board.occupied(const Point(4, 4)), isFalse);
    expect(c.state.turn, StoneColor.black);
  });

  test('два паса в классике заканчивают партию', () async {
    final setup = AppGameSetup(
      mode: GoMode.classic,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final c = GoController(setup, settings, sounds: sounds());
    addTearDown(c.dispose);
    c.pass();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    c.pass();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(c.isOver, isTrue);
  });

  test('подсказка подсвечивает допустимую точку', () async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final c = GoController(setup, settings, sounds: sounds());
    addTearDown(c.dispose);
    await c.showHint().timeout(const Duration(seconds: 30));
    expect(c.suggestedMove, isNotNull);
    expect(c.legalPlacements.contains(c.suggestedMove), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('atariPoints подсвечивает группу под угрозой', () {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final c = GoController(
      setup,
      settings,
      sounds: sounds(),
      initialState: GameState(
        setup: setup.toEngine(),
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      ),
    );
    addTearDown(c.dispose);
    expect(c.atariPoints.contains(const Point(0, 0)), isTrue);
  });

  test('запрет ко: тап в ко-точку показывает сообщение, а не ход', () async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      captureTarget: CaptureTarget.three,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final koState = GameState(
      setup: setup.toEngine(),
      board: Board(9, {
        const Point(3, 4): StoneColor.black,
        const Point(4, 3): StoneColor.black,
        const Point(4, 5): StoneColor.black,
        const Point(4, 4): StoneColor.white,
        const Point(6, 4): StoneColor.white,
        const Point(5, 3): StoneColor.white,
        const Point(5, 5): StoneColor.white,
      }),
      turn: StoneColor.black,
    );
    final c = GoController(setup, settings, sounds: sounds(),
        initialState: koState);
    addTearDown(c.dispose);
    // Чёрные снимают белый (4,4) ходом (5,4).
    c.tap(const Point(5, 4));
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(c.state.koPoint, const Point(4, 4));
    // Белые пытаются сразу вернуть — теперь их ход.
    c.tap(const Point(4, 4));
    expect(c.notice, isNotNull);
    expect(c.state.board.occupied(const Point(4, 4)), isFalse);
  });
}
