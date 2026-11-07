import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/checkers_controller.dart';
import 'package:games_for_diana/games/checkers/engine/ai.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/checkers_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('после сдачи показывается результат и возврат в меню', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckersSessionPage(
                      settings: settings,
                      variant: GameVariant.russian,
                      mode: GameMode.local,
                      humanColor: Side.white,
                      animationPerLanding: const Duration(milliseconds: 20),
                    ),
                  ),
                ),
                child: const Text('Старт'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Старт'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CheckersSessionPage), findsOneWidget);
    await tester.ensureVisible(find.text('Сдаться'));
    await tester.tap(find.text('Сдаться'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сдаться'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Чёрные победили!'), findsOneWidget);
    expect(find.text('Играть снова'), findsOneWidget);
    await tester.tap(find.text('В меню'));
    for (var frame = 0; frame < 20; frame++) {
      if (find.byType(CheckersSessionPage).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CheckersSessionPage), findsNothing);
    expect(find.text('Старт'), findsOneWidget);
    expect(settings.gamesPlayed, 1);
    expect(settings.gamesWon, 0);
  });

  testWidgets('проигравший видит спокойный результат без фейерверка', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      mode: GameMode.computer,
      playerSide: Side.white,
      difficulty: Difficulty.easy,
    );
    // Сдача компьютеру — поражение, поэтому спокойный текст и мягкий звук
    // проигрыша.
    await tester.ensureVisible(find.text('Сдаться'));
    await tester.tap(find.text('Сдаться'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Сдаться'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Отличная партия!'), findsOneWidget);
    expect(find.text('В следующий раз обязательно получится!'), findsOneWidget);
  });

  testWidgets('международная доска 10×10 без подсказок сохраняет ходы', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await settings.setFlag(checkersGameId, 'hints', false);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      variant: GameVariant.international,
      mode: GameMode.local,
    );
    expect(find.byKey(const Key('hint-button')), findsNothing);
    expect(game.legalMoves, isNotEmpty);
    expect(game.state.board.size, 10);
    expect(game.state.board.count(Side.white), 20);
  });
}
