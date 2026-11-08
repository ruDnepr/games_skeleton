import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/battleship/battleship_controller.dart';
import 'package:games_for_diana/games/battleship/engine/ai.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/engine/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Логика контроллера без виджетов: ход, результат, undo, hint. Главный тест —
/// после расстановки игрок может стрелять (canInteract = true).
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

  /// Создаёт контроллер с заданным флотом и флотом соперника.
  BattleshipController controllerFor({
    required Fleet myFleet,
    Fleet? enemyFleet,
    Difficulty difficulty = Difficulty.easy,
    bool iShootFirst = true,
  }) {
    final sounds = GameSounds(settings, backend: backend);
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet ?? battleshipRules.autoFleet(),
      iShootFirst: iShootFirst,
      difficulty: difficulty,
    );
    return BattleshipController(
      setup,
      settings,
      sounds: sounds,
      thinkingDelay: const Duration(milliseconds: 1),
    );
  }

  test('после расстановки canInteract = true и ход проходит', () async {
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
      Ship(
        type: ShipType.submarine,
        origin: const Square(5, 5),
        orientation: Orientation.horizontal,
      ),
    ]);
    final controller = controllerFor(myFleet: myFleet, enemyFleet: enemyFleet);
    addTearDown(controller.dispose);

    expect(controller.isOver, isFalse);
    expect(controller.canInteract, isTrue,
        reason: 'После расстановки игрок может стрелять');
    expect(controller.state.turn, Side.me);

    // Стреляем мимо (5,5 не занят врагом, ждём промаха).
    await controller.shoot(const Square(9, 9));
    // После промаха ход переходит к ИИ; ждём, пока ИИ ответит.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.state.enemyBoard.firedAt(const Square(9, 9)), isTrue);
  });

  test('попадание даёт дополнительный ход — turn остаётся me', () async {
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);
    final controller = controllerFor(myFleet: myFleet, enemyFleet: enemyFleet);
    addTearDown(controller.dispose);

    await controller.shoot(const Square(0, 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Попал — ход снова мой.
    expect(controller.state.turn, Side.me,
        reason: 'После попадания ход остаётся за игроком');
    expect(
      controller.state.enemyBoard.at(const Square(0, 0))?.result,
      ShotResult.hit,
    );
  });

  test('потопление последним выстрелом завершает партию победой', () async {
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.submarine,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);
    final controller = controllerFor(myFleet: myFleet, enemyFleet: enemyFleet);
    addTearDown(controller.dispose);

    await controller.shoot(const Square(0, 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.isOver, isTrue);
    expect(controller.winner, Side.me);
  });

  test('undo отменяет последний ход игрока и ответ ИИ', () async {
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);
    final controller = controllerFor(myFleet: myFleet, enemyFleet: enemyFleet);
    addTearDown(controller.dispose);

    // Стреляем мимо (9,9) — ход переходит к ИИ.
    await controller.shoot(const Square(9, 9));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final hadMyShot = controller.state.enemyBoard.firedAt(const Square(9, 9));
    expect(hadMyShot, isTrue);

    // ИИ стреляет — ждём, потом отменяем пару «мой + ИИ».
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (controller.canUndo) {
      controller.undo();
      await Future<void>.delayed(Duration.zero);
      // Моего выстрела больше нет.
      expect(
        controller.state.enemyBoard.firedAt(const Square(9, 9)),
        isFalse,
        reason: 'После undo мой выстрел исчез',
      );
    }
  });

  test('hint предлагает клетку и сбрасывается', () async {
    final myFleet = battleshipRules.autoFleet();
    final controller = controllerFor(myFleet: myFleet);
    addTearDown(controller.dispose);

    expect(controller.suggestedShot, isNull);
    await controller.showHint();
    expect(controller.suggestedShot, isNotNull);
    expect(controller.hintText, isNotNull);
    controller.clearHint();
    expect(controller.suggestedShot, isNull);
    expect(controller.hintText, isNull);
  });

  test('resign завершает партию поражением', () {
    final myFleet = battleshipRules.autoFleet();
    final controller = controllerFor(myFleet: myFleet);
    addTearDown(controller.dispose);

    expect(controller.isOver, isFalse);
    controller.resign();
    expect(controller.isOver, isTrue);
    expect(controller.winner, Side.enemy);
  });

  test('canInteract = false во время анимации', () async {
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.submarine,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);
    final controller = controllerFor(myFleet: myFleet, enemyFleet: enemyFleet);
    addTearDown(controller.dispose);

    expect(controller.canInteract, isTrue);
    // Стреляем — анимация запускается, canInteract становится false.
    final future = controller.shoot(const Square(0, 0));
    // В момент запуска анимации canInteract должен быть false.
    expect(controller.canInteract, isFalse,
        reason: 'Во время анимации нельзя ходить');
    await future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
