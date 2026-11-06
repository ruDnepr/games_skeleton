import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/main.dart';

/// Каркас, в который встроилась игра «Нарды»: заставка, главное окно, список
/// игр и два экрана карточки игры.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsController> pumpApp(
    WidgetTester tester, {
    bool splash = false,
  }) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController()..sound = false;
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: DianaApp(settings: settings, showSplash: splash),
      ),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('заставка уходит в главное окно', (tester) async {
    await pumpApp(tester, splash: true);
    expect(find.text('Игры для Дианы'), findsOneWidget);
    expect(find.text('Время играть и улыбаться!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Игры\nдля Дианы'), findsOneWidget);
    expect(find.text('Думай, играй и улыбайся!'), findsOneWidget);
    expect(find.text('Каждая партия — маленькое приключение ✨'), findsOneWidget);
    expect(find.text('Время играть и улыбаться!'), findsNothing);
  });

  testWidgets('«Играть» открывает список игр, карточка — выбор режима нард', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Играть'), findsOneWidget);

    await tester.tap(find.text('Играть'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('game-card-backgammon')), findsOneWidget);
    expect(find.text('Короткие нарды'), findsOneWidget);
    // В каталоге теперь две игры нард.
    expect(find.byKey(const Key('game-card-long_backgammon')), findsOneWidget);

    await tester.tap(find.byKey(const Key('game-card-backgammon')));
    await tester.pumpAndSettle();

    expect(find.text('С кем сыграем?'), findsOneWidget);
    expect(find.text('Против компьютера'), findsOneWidget);
    expect(find.byKey(const Key('backgammon-start')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-card-backgammon')), findsOneWidget);
  });

  testWidgets('«Правила» и «Настройки» открываются из меню', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Правила'));
    await tester.pumpAndSettle();
    expect(find.text('Это просто!'), findsOneWidget);
    expect(find.byKey(const Key('rule-card-1')), findsOneWidget);

    // Последняя строка правил — за сгибом экрана телефона. Карточек нард
    // десять и они длиннее, чем у заготовки, поэтому прокручиваем до неё:
    // слепой drag не дотягивает при разной высоте контента, так что крутим
    // пока закрывающая строка не построится.
    final closing = find.text('Ошибаться и пробовать снова — это нормально! ✨');
    for (var i = 0; i < 20 && find
        .descendant(
          of: find.byType(ListView),
          matching: closing,
        )
        .evaluate()
        .isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(closing, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Как тебе удобнее?'), findsOneWidget);
    expect(find.byKey(const Key('nickname-field')), findsOneWidget);
  });

  testWidgets('«Правила» и «Настройки» открываются с карточки игры', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Играть'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game-rules-backgammon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rule-card-1')), findsOneWidget);
    expect(find.text('Это просто!'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game-settings-backgammon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-flag-backgammon-hints')), findsOneWidget);
    expect(find.byKey(const Key('game-flag-backgammon-numbers')), findsOneWidget);
    expect(find.byKey(const Key('nickname-field')), findsOneWidget);
  });

  testWidgets('«Сетевая игра» открывает выбор игры и экран сети', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Сетевая игра'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('game-card-backgammon')), findsOneWidget);
    expect(
      find.text('Выбери игру, а потом создай её или подключись к другу по коду.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('game-card-backgammon')));
    await tester.pumpAndSettle();

    expect(find.text('Создать игру'), findsOneWidget);
    expect(find.text('Найти игру / ввести код'), findsOneWidget);
  });
}
