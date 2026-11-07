import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:games_for_diana/games/checkers/network.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/checkers_harness.dart';

/// Позиция, где белые обязаны бить: простая на (5, 0) бьёт чёрную на (4, 1),
/// а простая на (5, 6) ничего не делает.
GameState forcedCapture() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 0): const Piece(Side.white),
    const Square(5, 6): const Piece(Side.white),
    const Square(4, 1): const Piece(Side.black),
    const Square(1, 0): const Piece(Side.black),
  }),
  turn: Side.white,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('подсказка появляется только после нажатия кнопки', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(tester, settings: settings);
    expect(game.suggestedMove, isNull);
    expect(game.hintText, isNull);
    expect(find.textContaining('подсвечен лучший ход'), findsNothing);
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
    // Тот же метод, что у кнопки; поиск идёт в изоляте, поэтому runAsync.
    await tester.runAsync(game.showHint);
    await tester.pump();
    expect(game.hintThinking, isFalse);
    expect(game.suggestedMove, isNotNull);
    expect(game.hintText, contains('подсвечен лучший ход'));
    expect(find.textContaining('подсвечен лучший ход'), findsOneWidget);
    // Пузырь можно закрыть вместе с подсветкой.
    await tester.tap(find.byKey(const Key('message-dismiss')));
    await tester.pump();
    expect(game.suggestedMove, isNull);
    expect(find.textContaining('подсвечен лучший ход'), findsNothing);
  });

  testWidgets('попытка походить без обязательного боя объясняется', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: forcedCapture(),
    );
    expect(game.hasCapture, isTrue);
    // До попытки походить об обязательном бое ничего не говорится.
    expect(find.text('Ходят белые'), findsOneWidget);
    game.tap(const Square(5, 6));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.selected, isNull);
    expect(game.notice, contains('бой обязателен'));
    expect(find.textContaining('Сейчас бой обязателен'), findsOneWidget);
    // Тап по пустой клетке — тот же отказ.
    game.tap(const Square(6, 1));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.notice, contains('обязателен'));
    expect(find.textContaining('спокойно походить нельзя'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message-dismiss')));
    await tester.pump();
    expect(find.text('Ходят белые'), findsOneWidget);
    expect(game.notice, isNull);
    // Бьющую шашку всё ещё можно выбрать и доиграть серию.
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.selected, const Square(5, 0));
    game.tap(const Square(3, 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 1);
  });

  testWidgets('без подсказок запрещённый ход тоже объясняется, но коротко', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await settings.setFlag(checkersGameId, 'hints', false);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: forcedCapture(),
    );
    expect(find.byKey(const Key('hint-button')), findsNothing);
    game.tap(const Square(5, 6));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.notice, 'Так ходить нельзя.');
    expect(find.text('Так ходить нельзя.'), findsOneWidget);
    // Правила всё равно действуют: взятие — единственный допустимый ход.
    expect(game.legalMoves, hasLength(1));
    expect(game.legalMoves.single.isCapture, isTrue);
  });
}
