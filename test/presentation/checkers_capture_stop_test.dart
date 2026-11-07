import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/checkers/engine/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/checkers_harness.dart';

/// Белая простая может взять одну чёрную, а потом вторую — серию можно
/// остановить после первого взятия (русские правила).
GameState twoCaptures() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(5, 0): const Piece(Side.white),
    const Square(4, 1): const Piece(Side.black),
    const Square(2, 3): const Piece(Side.black),
  }),
  turn: Side.white,
);

/// Дамка бьёт (6, 1) и обязана бить (4, 1); остановка на (5, 2) запрещена,
/// хотя клетка свободна.
GameState kingMustContinue() => GameState(
  variant: GameVariant.russian,
  board: Board(GameVariant.russian.boardSize, {
    const Square(7, 0): const Piece(Side.white, king: true),
    const Square(6, 1): const Piece(Side.black),
    const Square(4, 1): const Piece(Side.black),
  }),
  turn: Side.white,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('простая шашка может закончить бой после первой серии', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: twoCaptures(),
      size: const Size(400, 1100),
    );
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.selected, const Square(5, 0));
    game.tap(const Square(3, 2));
    await tester.pump();
    // Серия ещё не применена: можно продолжить второй частью.
    expect(game.state.ply, 0);
    expect(game.canFinishCapture, isTrue);
    expect(find.byKey(const Key('finish-capture-button')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('finish-capture-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-capture-button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 1);
    expect(game.state.board.at(const Square(3, 2)), isNotNull);
    expect(find.byKey(const Key('finish-capture-button')), findsNothing);
  });

  testWidgets('второе взятие доигрывает серию как раньше', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: twoCaptures(),
      size: const Size(400, 1100),
    );
    game.tap(const Square(5, 0));
    await tester.pump();
    game.tap(const Square(3, 2));
    await tester.pump();
    game.tap(const Square(1, 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 0);
    expect(game.state.board.at(const Square(1, 4)), isNotNull);
  });

  testWidgets('дамка не предлагает закончить бой досрочно', (tester) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: kingMustContinue(),
      size: const Size(400, 1100),
    );
    game.tap(const Square(7, 0));
    await tester.pump();
    game.tap(const Square(5, 2));
    await tester.pump();
    expect(game.state.ply, 0);
    expect(game.canFinishCapture, isFalse);
    expect(find.byKey(const Key('finish-capture-button')), findsNothing);
    game.tap(const Square(3, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(game.state.ply, 1);
    expect(game.state.board.count(Side.black), 0);
  });

  testWidgets('лампочка в шапке скрывает только кнопку подсказки', (
    tester,
  ) async {
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    final game = await pumpCheckers(
      tester,
      settings: settings,
      state: twoCaptures(),
      size: const Size(400, 1100),
    );
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hint-toggle')));
    await tester.pump();
    expect(game.hintButtonEnabled, isFalse);
    expect(find.byKey(const Key('hint-button')), findsNothing);
    // Сами подсветки остаются: ходы всё равно видны.
    expect(game.hintsEnabled, isTrue);
    expect(game.legalMoves, isNotEmpty);
    game.tap(const Square(5, 0));
    await tester.pump();
    expect(game.suggestedDestinations, isNotEmpty);
    await tester.tap(find.byKey(const Key('hint-toggle')));
    await tester.pump();
    expect(game.hintButtonEnabled, isTrue);
    expect(find.byKey(const Key('hint-button')), findsOneWidget);
  });
}
