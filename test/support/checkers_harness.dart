import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/checkers_controller.dart';
import 'package:games_for_diana/games/checkers/engine/ai.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/session_page.dart';

export 'async_wait.dart';

/// Накачивает экран партии на фиксированном виртуальном устройстве и
/// возвращает контроллер. Все виджет-тесты партии повторяли одни и те же
/// двадцать строк: размер устройства, его отмена, длительность анимации. Живут
/// здесь один раз.
Future<CheckersController> pumpCheckers(
  WidgetTester tester, {
  required SettingsController settings,
  GameState? state,
  GameVariant variant = GameVariant.russian,
  GameMode mode = GameMode.local,
  Side playerSide = Side.white,
  Difficulty difficulty = Difficulty.easy,
  Size size = const Size(400, 1000),
  Duration animationPerLanding = const Duration(milliseconds: 20),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: CheckersSessionPage(
        settings: settings,
        variant: state?.variant ?? variant,
        mode: mode,
        difficulty: difficulty,
        humanColor: playerSide,
        animationPerLanding: animationPerLanding,
        initialState: state,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return tester
      .widget<CheckersBoardView>(find.byType(CheckersBoardView))
      .controller;
}

/// Играет один полный ход: тап по стартовой клетке, тап по адресату.
Future<void> playMove(
  WidgetTester tester,
  CheckersController game,
  Square from,
  Square to, {
  Duration settle = const Duration(milliseconds: 60),
}) async {
  game.tap(from);
  await tester.pump();
  game.tap(to);
  await tester.pump(settle);
}
