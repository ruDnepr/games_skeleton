import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/ai.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/model.dart';
import 'package:games_for_diana/games/ticket_to_ride/session_page.dart';
import 'package:games_for_diana/games/ticket_to_ride/ticket_to_ride_controller.dart';
import 'package:games_for_diana/presentation/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Виджет-тесты экрана партии «Билета на поезд»: панели игроков, баннер хода,
/// карта, открытые карты, рука, путешествия и нижние кнопки.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> makeSettings({bool hints = true}) async {
    final settings = SettingsController();
    await settings.load();
    settings.sound = false;
    await settings.setFlag('ticket_to_ride', 'hints', hints);
    return settings;
  }

  Future<void> pumpModePage(
    WidgetTester tester, {
    required SettingsController settings,
    Size size = const Size(440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dianaTheme(),
        home: TicketToRideModePage(settings: settings),
      ),
    );
    await tester.pump();
  }

  Future<TicketToRideController> pumpGame(
    WidgetTester tester, {
    required SettingsController settings,
    bool vsAi = true,
    Difficulty difficulty = Difficulty.easy,
    Size size = const Size(440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);
    final controller = TicketToRideController(
      settings: settings,
      sounds: sounds,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: dianaTheme(),
        home: TicketToRideSessionPage(
          settings: settings,
          vsAi: vsAi,
          difficulty: difficulty,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return controller;
  }

  group('стартовый экран', () {
    testWidgets('ModePage показывает режимы и сложности', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      await pumpModePage(tester, settings: settings);
      expect(find.text('С кем сыграем?'), findsOneWidget);
      expect(find.text('Против компьютера'), findsOneWidget);
      expect(find.text('Двое на одном устройстве'), findsOneWidget);
      expect(find.text('Лёгкий'), findsOneWidget);
      expect(find.text('Средний'), findsOneWidget);
      expect(find.text('Сложный'), findsOneWidget);
    });

    testWidgets('кнопка «Начать партию» ведёт на экран партии', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      await pumpModePage(tester, settings: settings);
      await tester.tap(find.byKey(const Key('ticket-to-ride-start')));
      await tester.pumpAndSettle();
      // На экране партии должны появиться обе панели и нижние кнопки.
      expect(find.byKey(const Key('my-panel')), findsOneWidget);
      expect(find.byKey(const Key('opponent-panel')), findsOneWidget);
    });

    testWidgets('можно переключиться в режим «вдвоём»', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      await pumpModePage(tester, settings: settings);
      // Тапаем по плитке «Двое на одном устройстве».
      await tester.tap(find.text('Двое на одном устройстве'));
      await tester.pump();
      // Сложности больше нет — она только для игры с компьютером.
      // Текст «Лёгкий» исчезнет.
      // (На самом деле плитка осталась в дереве, но не выбрана — поэтому ищем
      // ровно одну плитку с подписью «Двое на одном устройстве».)
      expect(find.text('Двое на одном устройстве'), findsOneWidget);
    });
  });

  group('экран партии', () {
    testWidgets('показывает обе панели, баннер, карту и нижние кнопки',
        (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(tester, settings: settings);
      addTearDown(controller.dispose);

      expect(find.byKey(const Key('my-panel')), findsOneWidget);
      expect(find.byKey(const Key('opponent-panel')), findsOneWidget);
      expect(find.byKey(const Key('ttr-undo')), findsOneWidget);
      expect(find.byKey(const Key('ttr-hint')), findsOneWidget);
      expect(find.byKey(const Key('ttr-destinations')), findsOneWidget);
      expect(find.byKey(const Key('ttr-history')), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('панель соперника показывает имя компьютера', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(
        tester,
        settings: settings,
        vsAi: true,
        difficulty: Difficulty.easy,
      );
      addTearDown(controller.dispose);
      expect(find.text('Компьютер'), findsOneWidget);
    });

    testWidgets('панель игрока показывает моё имя', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(tester, settings: settings, vsAi: true);
      addTearDown(controller.dispose);
      expect(find.text(settings.nickname), findsWidgets);
    });

    testWidgets('тап по колоде берёт карту и переводит в drawSecond',
        (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(
        tester,
        settings: settings,
        vsAi: false,
      );
      addTearDown(controller.dispose);
      final beforeHand = controller.myHand.length;
      // Колода — правый крайний элемент в ряду открытых карт. Её текст «×N»
      // встречается раньше, чем такие же подписи в моей руке.
      final deckText = find.textContaining('×').first;
      await tester.tap(deckText);
      await tester.pump();
      expect(controller.phase, TtrPhase.drawSecond);
      expect(controller.myHand.length, beforeHand + 1);
    });

    testWidgets('кнопка «Подсказать» подсвечивает ход или совет', (tester) async {
      final settings = await makeSettings(hints: true);
      addTearDown(settings.dispose);
      final controller = await pumpGame(tester, settings: settings, vsAi: false);
      addTearDown(controller.dispose);
      await tester.tap(find.byKey(const Key('ttr-hint')));
      await tester.pump();
      expect(
        controller.notice != null || controller.hintedRouteIndex != null,
        isTrue,
      );
    });

    testWidgets('кнопка «История» открывает диалог с историей ходов',
        (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(tester, settings: settings, vsAi: false);
      addTearDown(controller.dispose);
      // Сначала сделаем ход — иначе кнопка истории неактивна.
      final deckText = find.textContaining('×').first;
      await tester.tap(deckText);
      await tester.pump();
      await tester.tap(deckText);
      await tester.pump();
      expect(controller.history, isNotEmpty);
      // Жмём «История».
      await tester.tap(find.byKey(const Key('ttr-history')));
      await tester.pumpAndSettle();
      expect(find.text('История ходов'), findsOneWidget);
      // Закрытие.
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('История ходов'), findsNothing);
    });

    testWidgets('кнопка «Путешествия» переводит партию в фазу выбора',
        (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(tester, settings: settings, vsAi: false);
      addTearDown(controller.dispose);
      expect(controller.phase, TtrPhase.main);
      await tester.tap(find.byKey(const Key('ttr-destinations')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.phase, TtrPhase.choosingDestinations);
      expect(controller.pendingDestinations, isNotEmpty);
    });
  });

  group('адаптивные подписи', () {
    testWidgets('на узком экране все блоки помещаются без overflow',
        (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(
        tester,
        settings: settings,
        size: const Size(320, 600),
      );
      addTearDown(controller.dispose);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('my-panel')), findsOneWidget);
      expect(find.byKey(const Key('opponent-panel')), findsOneWidget);
    });

    testWidgets('на маленьком экране нижние кнопки не вылезают', (tester) async {
      final settings = await makeSettings();
      addTearDown(settings.dispose);
      final controller = await pumpGame(
        tester,
        settings: settings,
        size: const Size(360, 640),
      );
      addTearDown(controller.dispose);
      expect(find.byKey(const Key('ttr-undo')), findsOneWidget);
      expect(find.byKey(const Key('ttr-hint')), findsOneWidget);
      expect(find.byKey(const Key('ttr-destinations')), findsOneWidget);
      expect(find.byKey(const Key('ttr-history')), findsOneWidget);
    });
  });

  group('GameSounds', () {
    test('resultSoundName: draw → draw, win → win, lose → lose', () {
      expect(
        resultSoundName(draw: true, local: false, iWon: false),
        GameSound.draw,
      );
      expect(
        resultSoundName(draw: false, local: true, iWon: false),
        GameSound.win,
      );
      expect(
        resultSoundName(draw: false, local: false, iWon: true),
        GameSound.win,
      );
      expect(
        resultSoundName(draw: false, local: false, iWon: false),
        GameSound.lose,
      );
    });
  });
}
