import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/loto/loto_controller.dart';
import 'package:games_for_diana/games/loto/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Экран партии: карточка показывает числа, бочонок закрывается жетоном,
/// отменяется и подсвечивается. Повторяет оригинальный
/// `test/presentation/game_page_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const fast = Duration(milliseconds: 5);

  Future<LotoController> pumpGame(
    WidgetTester tester, {
    LotoMode mode = LotoMode.humanHost,
    int seed = 5,
    bool hints = true,
  }) async {
    tester.view.physicalSize = const Size(430, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await tester.runAsync(settings.load);
    settings.sound = false;
    await settings.setFlag('loto', 'hints', hints);
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    final setup = GameSetup(
      mode: mode,
      seed: seed,
      firstDrawDelay: fast,
      drawDelay: fast,
      rivalReaction: fast,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LotoSessionPage(
          settings: settings,
          setup: setup,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    controller.start(setup);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    return controller;
  }

  /// Тянет бочонки, пока не выпадет число с моей карточки.
  Future<int> drawMine(
    WidgetTester tester,
    LotoController controller,
  ) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      controller.drawBarrel();
      await tester.pump(const Duration(milliseconds: 700));
      final pending = controller.myPendingBarrel;
      if (pending != null) return pending;
    }
    fail('бочонок с моей карточки так и не выпал');
  }

  Color? cellColor(WidgetTester tester, int number) {
    final finder = find.descendant(
      of: find.byKey(Key('card-cell-$number')),
      matching: find.byType(AnimatedContainer),
    );
    if (finder.evaluate().isEmpty) return null;
    final cell = tester.widget<AnimatedContainer>(finder.first);
    final decoration = cell.decoration;
    return decoration is BoxDecoration ? decoration.color : null;
  }

  testWidgets('карточка показывает все пятнадцать чисел', (tester) async {
    final controller = await pumpGame(tester);
    expect(controller.me, isNotNull);
    expect(controller.me!.card.numbers, hasLength(15));
    for (final number in controller.me!.card.numbers) {
      expect(find.text('$number'), findsWidgets,
          reason: 'число $number должно быть на карточке');
    }
    expect(find.text('пока пусто'), findsOneWidget);
  });

  testWidgets('в режиме ведущего-человека бочонок достаёт кнопка', (
    tester,
  ) async {
    final controller = await pumpGame(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.game.drawn, isEmpty, reason: 'сам не тянет');
    await tester.tap(find.byKey(const Key('draw-barrel')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.game.drawn, hasLength(1));
  });

  testWidgets('вытянутый бочонок закрывается жетоном', (tester) async {
    final controller = await pumpGame(tester);
    final number = await drawMine(tester, controller);
    await tester.ensureVisible(find.byKey(Key('card-cell-$number')).first);
    await tester.pump();
    await tester.tap(find.byKey(Key('card-cell-$number')).first);
    await tester.pump(const Duration(milliseconds: 320));
    expect(controller.me!.closed, contains(number));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.textContaining('вытянуто'), findsOneWidget);
  });

  testWidgets('чужое число закрыть нельзя', (tester) async {
    final controller = await pumpGame(tester);
    final number = await drawMine(tester, controller);
    final other = controller.me!.card.numbers.firstWhere(
      (value) => value != number,
    );
    await tester.ensureVisible(find.byKey(Key('card-cell-$other')).first);
    await tester.pump();
    await tester.tap(find.byKey(Key('card-cell-$other')).first);
    await tester.pump(const Duration(milliseconds: 320));
    expect(controller.me!.closed, isEmpty);
    expect(find.text('Этот бочонок ещё в мешке'), findsOneWidget);
  });

  testWidgets('отмена хода возвращает последний бочонок в мешок', (
    tester,
  ) async {
    final controller = await pumpGame(tester);
    await drawMine(tester, controller);
    final before = controller.game.drawn.toList();
    expect(before, isNotEmpty);
    await tester.tap(find.byKey(const Key('undo-button')));
    await tester.pump(const Duration(milliseconds: 320));
    final after = controller.game.drawn.toList();
    expect(after, before.sublist(0, before.length - 1));
    expect(
      find.text(after.isEmpty ? 'пока пусто' : 'вытянуто ${after.length}'),
      findsOneWidget,
    );
  });

  testWidgets('подсказка подсвечивает клетку с бочонком', (tester) async {
    final controller = await pumpGame(tester, hints: true);
    final number = await drawMine(tester, controller);
    final card = controller.me!.card;
    final plain = card.numbers.firstWhere((value) => value != number);
    expect(
      cellColor(tester, number),
      isNot(cellColor(tester, plain)),
      reason: 'клетка с бочонком должна отличаться от остальных',
    );
  });

  testWidgets('без подсказок в настройках клетки одинаковые', (tester) async {
    final controller = await pumpGame(tester, hints: false);
    final number = await drawMine(tester, controller);
    final card = controller.me!.card;
    final plain = card.numbers.firstWhere((value) => value != number);
    expect(cellColor(tester, number), cellColor(tester, plain));
  });
}
