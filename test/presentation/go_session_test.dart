// Виджет-тесты го: выбор режима, выбор размера доски, экран жеребьёвки цвета
// и сама доска рендерится и ставит камень по тапу. Адаптировано из оригинального
// `test/widgets_test.dart`.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/go/board_game.dart';
import 'package:games_for_diana/games/go/engine/model.dart';
import 'package:games_for_diana/games/go/go_controller.dart';
import 'package:games_for_diana/games/go/score_screen.dart';
import 'package:games_for_diana/games/go/setup_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pumpPage(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(430, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  testWidgets('экран выбора режима содержит «Захват» и «Классическое го»',
      (tester) async {
    await pumpPage(tester, GoModePage(settings: settings));
    expect(find.text('Во что сыграем?'), findsOneWidget);
    expect(find.text('Захват'), findsOneWidget);
    expect(find.text('Классическое го'), findsOneWidget);
  });

  testWidgets('выбор размера доски показывает 9, 13, 19', (tester) async {
    await pumpPage(
      tester,
      GoBoardSizePage(settings: settings, mode: GoMode.capture),
    );
    expect(find.text('Какая доска?'), findsOneWidget);
    expect(find.text('9×9'), findsOneWidget);
    expect(find.text('13×13'), findsOneWidget);
    expect(find.text('19×19'), findsOneWidget);
  });

  testWidgets('экран жеребьёвки цвета показывает обе руки и интро',
      (tester) async {
    await pumpPage(
      tester,
      GoColorGuessPage(
        settings: settings,
        random: _AlwaysZero(),
        revealDelay: const Duration(milliseconds: 50),
      ),
    );
    expect(find.text('В какой руке\nчёрный камень?'), findsOneWidget);
    expect(find.byKey(const Key('hand-left')), findsOneWidget);
    expect(find.byKey(const Key('hand-right')), findsOneWidget);
    expect(find.text('Левая'), findsOneWidget);
    expect(find.text('Правая'), findsOneWidget);
    expect(find.text('Готова? Доверься интуиции ✨'), findsOneWidget);
  });

  testWidgets('доска рендерится и ставит камень по тапу', (tester) async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final controller = GoController(setup, settings);
    addTearDown(controller.dispose);
    await pumpPage(
      tester,
      Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: GoBoardView(controller: controller),
        ),
      ),
    );
    await tester.tap(find.byType(GoBoardView));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(controller.state.board.count(StoneColor.black), 1);
  });

  testWidgets('экран счёта «Захват» показывает победителя и захваты',
      (tester) async {
    final setup = AppGameSetup(
      mode: GoMode.capture,
      boardSize: 9,
      playerSide: StoneColor.black,
      captureTarget: CaptureTarget.one,
      komi: 6.5,
      appMode: AppGameMode.local,
    );
    final controller = GoController(
      setup,
      settings,
      initialState: GameState(
        setup: setup.toEngine(),
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      ),
    );
    addTearDown(controller.dispose);
    // Снимаем белый камень, заполнив последнее дыхание (0,1) — партия
    // завершится. Состояние обновляется синхронно, так что экран счёта
    // сразу видит победителя.
    controller.tap(const Point(0, 1));
    await pumpPage(
      tester,
      GoScoreScreen(settings: settings, controller: controller),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Чёрные победили!'), findsOneWidget);
    expect(find.text('Играть снова'), findsOneWidget);
    expect(find.text('Чёрные сняли'), findsOneWidget);
    expect(find.text('Белые сняли'), findsOneWidget);
    expect(find.text('Цель'), findsOneWidget);
  });
}

/// Всегда возвращает 0 — детерминированная жеребьёвка для тестов.
class _AlwaysZero implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}
