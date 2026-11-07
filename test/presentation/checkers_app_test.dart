import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/checkers_controller.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/checkers_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('выбор варианта, режима, сложности и жеребьёвки цвета', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CheckersVariantPage(settings: settings)),
    );
    expect(find.text('Русские шашки'), findsOneWidget);
    expect(find.text('Международные шашки'), findsOneWidget);
    await tester.tap(find.text('Русские шашки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Против компьютера'));
    await tester.pumpAndSettle();
    expect(find.text('Лёгкий'), findsOneWidget);
    expect(find.text('Средний'), findsOneWidget);
    expect(find.text('Сложный'), findsOneWidget);
    await tester.tap(find.text('Лёгкий'));
    // GuessPage крутит бесконечную анимацию покачивания — pumpAndSettle
    // не закончится. Качаем вручную на несколько кадров.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('hand-left')), findsOneWidget);
    expect(find.byKey(const Key('hand-right')), findsOneWidget);
  });

  testWidgets('жеребьёвка возвращает согласованный цвет', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    Side? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.push<Side>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GuessPage(
                        settings: settings,
                        random: Random(7),
                        revealDelay: const Duration(milliseconds: 500),
                      ),
                    ),
                  );
                },
                child: const Text('Начать'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Начать'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('hand-left')), findsOneWidget);
    expect(find.byKey(const Key('hand-right')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hand-left')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('ТЫ ИГРАЕШЬ'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result, Random(7).nextInt(2) == 0 ? Side.white : Side.black);
  });

  testWidgets('доска, активная сторона, подсказка и отмена работают', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(tester, settings: settings);
    expect(find.byType(CheckersBoardView), findsOneWidget);
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
    // В локальном режиме верхняя панель переворачивается, чтобы игрок по ту
    // сторону стола читал её нормально.
    expect(
      find.ancestor(
        of: find.byKey(const Key('top-player-panel')),
        matching: find.byType(RotatedBox),
      ),
      findsOneWidget,
    );
    await tester.runAsync(game.showHint);
    await tester.pump();
    expect(game.suggestedMove, isNotNull);
    final before = game.state.fingerprint;
    game.tap(const Square(5, 0));
    game.tap(const Square(4, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.state.turn, Side.black);
    expect(find.text('Ходят чёрные'), findsOneWidget);
    await tester.tap(find.byKey(const Key('undo-button')));
    await tester.pump();
    expect(game.state.fingerprint, before);
    await settings.setFlag(checkersGameId, 'hints', false);
    await tester.pump();
    expect(find.byKey(const Key('hint-button')), findsNothing);
    expect(game.legalMoves, isNotEmpty);
  });
}
