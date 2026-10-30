import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/main.dart';

/// The frame a new game plugs into: splash, main window, the list of games and
/// the two screens of a game card.
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
    final settings = SettingsController();
    addTearDown(settings.dispose);
    // The app loads its settings before the first frame.
    await settings.load();
    settings.sound = false;
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

  testWidgets('«Играть» открывает список игр, карточка — игру-пример', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Играть'), findsOneWidget);

    await tester.tap(find.text('Играть'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('game-card-example')), findsOneWidget);
    expect(find.text('Игра-пример'), findsOneWidget);

    await tester.tap(find.byKey(const Key('game-card-example')));
    await tester.pumpAndSettle();

    expect(find.text('Здесь будет партия'), findsOneWidget);
    expect(find.text('Понятно'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-card-example')), findsOneWidget);
  });

  testWidgets('«Правила» и «Настройки» открываются из меню', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Правила'));
    await tester.pumpAndSettle();
    expect(find.text('Это просто!'), findsOneWidget);
    expect(find.byKey(const Key('rule-card-1')), findsOneWidget);

    // The last line of the rules sits below the fold of a phone screen.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.text('Ошибаться и пробовать снова — это нормально! ✨'),
      findsOneWidget,
    );

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

    await tester.tap(find.byKey(const Key('game-rules-example')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rule-card-1')), findsOneWidget);
    expect(find.text('Это просто!'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('game-settings-example')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-flag-example-reminder')), findsOneWidget);
    expect(find.byKey(const Key('game-flag-example-markers')), findsOneWidget);
    expect(find.byKey(const Key('nickname-field')), findsOneWidget);
  });

  testWidgets('«Сетевая игра» открывает выбор игры и экран сети', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Сетевая игра'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('game-card-example')), findsOneWidget);
    expect(
      find.text('Выбери игру, а потом создай её или подключись к другу по коду.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('game-card-example')));
    await tester.pumpAndSettle();

    expect(find.text('Создать игру'), findsOneWidget);
    expect(find.text('Найти игру / ввести код'), findsOneWidget);
  });
}
