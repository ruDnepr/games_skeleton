import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/checkers_harness.dart';

/// Две дамки, не бьющие друг друга ни на одной диагонали: можно ходить по кругу
/// и повторить позицию — классическая ничья по повторению.
GameState twoKings() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(0, 1): const Piece(Side.black, king: true),
  }),
  turn: Side.white,
);

/// Белая дамка и чёрная простая: порог — 30 тихих полуходов, потому что простая
/// ещё на доске.
GameState quietPosition({int quietPlies = 29}) => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(2, 1): const Piece(Side.black),
  }),
  turn: Side.white,
  quietPlies: quietPlies,
);

/// Только дамки — тихая серия может быть вдвое длиннее.
GameState kingsOnlyPosition({int quietPlies = 59}) => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 2): const Piece(Side.white, king: true),
    const Square(0, 1): const Piece(Side.black, king: true),
  }),
  turn: Side.white,
  quietPlies: quietPlies,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('третье повторение позиции даёт ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: twoKings(),
      size: const Size(400, 900),
    );
    const circle = [
      [Square(5, 2), Square(4, 1)],
      [Square(0, 1), Square(1, 2)],
      [Square(4, 1), Square(5, 2)],
      [Square(1, 2), Square(0, 1)],
    ];
    // Один круг возвращает позицию, но только дважды — ничьи ещё нет.
    for (final step in circle) {
      await playMove(tester, game, step.first, step.last);
    }
    expect(game.state.ply, 4);
    expect(game.isDraw, isFalse);
    expect(game.winner, isNull);
    for (final step in circle) {
      await playMove(tester, game, step.first, step.last);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.state.ply, 8);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(game.isOver, isTrue);
    expect(find.text('Ничья!'), findsOneWidget);
    expect(find.textContaining('позиция повторилась'), findsOneWidget);
    // После ничьей ходить нельзя.
    expect(game.canInteract, isFalse);
    expect(find.byKey(const Key('hint-button')), findsNothing);
  });

  testWidgets('30 тихих полуходов дают ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: quietPosition(),
      size: const Size(400, 900),
    );
    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.state.quietPlies, 30);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(find.text('Ничья!'), findsOneWidget);
  });

  testWidgets('на 29 тихих полуходах партия продолжается', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: quietPosition(quietPlies: 28),
      size: const Size(400, 900),
    );
    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
    expect(game.state.quietPlies, 29);
    expect(game.quietLimit, 30);
    expect(game.isDraw, isFalse);
    expect(game.isOver, isFalse);
    expect(find.text('Ничья!'), findsNothing);
  });

  testWidgets('когда остались только дамки, 30 тихих полуходов — не ничья', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    // Те же 30 тихих полуходов с простой на доске уже были бы ничьей, но у
    // одних дамок порог вдвое выше.
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: kingsOnlyPosition(quietPlies: 30),
      size: const Size(400, 900),
    );
    expect(game.quietLimit, 60);
    expect(game.state.quietPlies, 30);
    expect(game.isDraw, isFalse);
    expect(find.text('Ничья!'), findsNothing);
  });

  testWidgets('60 тихих полуходов у одних дамок дают ничью', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: kingsOnlyPosition(),
      size: const Size(400, 900),
    );
    await playMove(tester, game, const Square(5, 2), const Square(4, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(game.state.quietPlies, 60);
    expect(game.isDraw, isTrue);
    expect(game.winner, isNull);
    expect(find.text('Ничья!'), findsOneWidget);
  });

  testWidgets('ход простой шашкой обнуляет тихую серию', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: GameState(
        variant: GameVariant.russian,
        board: Board(GameVariant.russian.boardSize, {
          const Square(5, 2): const Piece(Side.white),
          const Square(2, 1): const Piece(Side.black),
        }),
        turn: Side.white,
        quietPlies: 25,
      ),
      size: const Size(400, 900),
    );
    await playMove(tester, game, const Square(5, 2), const Square(4, 3));
    expect(game.state.quietPlies, 0);
    expect(game.isDraw, isFalse);
  });
}
