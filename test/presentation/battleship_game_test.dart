import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/battleship/battleship_controller.dart';
import 'package:games_for_diana/games/battleship/engine/ai.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/engine/rules.dart';
import 'package:games_for_diana/games/battleship/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Виджет-тест экрана партии: можно стрелять по полю соперника, ход
/// переключается, статусная строка обновляется.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> makeSettings() async {
    final settings = SettingsController();
    await settings.load();
    settings.sound = false;
    return settings;
  }

  testWidgets('экран партии показывает два поля и счётчики', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);

    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = battleshipRules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: Difficulty.easy,
    );
    final controller = BattleshipController(
      setup,
      settings,
      sounds: sounds,
      thinkingDelay: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipGamePage(
          setup: setup,
          settings: settings,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Оба поля нарисованы.
    expect(find.byType(BattleshipBoardWidget), findsNWidgets(2));
    // Подписи полей.
    expect(find.text('Поле соперника'), findsOneWidget);
    expect(find.text('Моё поле'), findsOneWidget);
    // Счётчики.
    expect(find.textContaining('Потоплено'), findsOneWidget);
    expect(find.textContaining('Потеряно'), findsOneWidget);
    // Статусная строка показывает «Твой ход».
    expect(find.textContaining('Твой ход'), findsOneWidget);
  });

  testWidgets('тап по полю соперника стреляет и обновляет состояние',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);

    // Вражеский флот — один эсминец в (0,0)-(0,1).
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = Fleet([
      Ship(
        type: ShipType.destroyer,
        origin: const Square(0, 0),
        orientation: Orientation.horizontal,
      ),
    ]);
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: Difficulty.easy,
    );
    final controller = BattleshipController(
      setup,
      settings,
      sounds: sounds,
      thinkingDelay: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipGamePage(
          setup: setup,
          settings: settings,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Находим первое поле (поле соперника) и тапаем по центру.
    final firstBoard =
        tester.widget<BattleshipBoardWidget>(find.byType(BattleshipBoardWidget).first);
    expect(firstBoard.canTap, isTrue, reason: 'Поле соперника должно быть тапаемым');

    // Тапаем по клетке (9,9) — мимо. Координаты в пикселях вычисляются по
    // размеру поля и позиции клетки.
    final boardBox = tester.getRect(find.byType(BattleshipBoardWidget).first);
    // Клетка (9,9): правый нижний угол минус пол-клетки.
    final cellSize = boardBox.width / 11; // 10 клеток + колонка меток
    final tapX = boardBox.left + cellSize + 9 * cellSize + cellSize / 2;
    final tapY = boardBox.top + cellSize + 9 * cellSize + cellSize / 2;
    await tester.tapAt(Offset(tapX, tapY));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Выстрел зарегистрирован.
    expect(controller.state.enemyBoard.firedAt(const Square(9, 9)), isTrue);
  });

  testWidgets('подсказка показывает клетку для выстрела', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);

    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = battleshipRules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: Difficulty.medium,
    );
    final controller = BattleshipController(
      setup,
      settings,
      sounds: sounds,
      thinkingDelay: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipGamePage(
          setup: setup,
          settings: settings,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.suggestedShot, isNull);
    // Кнопка подсказки — gps_fixed_rounded.
    final hintButton = find.byIcon(Icons.gps_fixed_rounded);
    expect(hintButton, findsOneWidget);
    await tester.tap(hintButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(controller.suggestedShot, isNotNull);
  });
}
