import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/backgammon/game.dart';
import 'package:games_for_diana/presentation/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Поле имени — единственное место, где ребёнок печатает, поэтому оно
/// проверяется отдельно: фокус, ввод без борьбы страницы и сохранение. Тут же
/// проверяются переключатели игры.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Высокая поверхность, чтобы вся страница настроек (и поле имени) строилась
  /// и могла получить фокус без прокрутки.
  Future<SettingsController> pumpSettings(
    WidgetTester tester, {
    bool withGame = false,
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController();
    addTearDown(settings.dispose);
    // Хранилище открывается вне фейковых часов виджет-теста: ожидание реального
    // вызова плагина внутри теста никогда бы не завершилось.
    await tester.runAsync(settings.load);
    settings.sound = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settings: settings,
          game: withGame ? backgammonGame : null,
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  Future<void> tearDownPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  final field = find.byKey(const Key('nickname-field'));

  testWidgets('поле имени получает фокус и не теряет набранный текст', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    expect(field, findsOneWidget);

    final node = tester.widget<TextField>(field).focusNode!;
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.enterText(field, 'Алиса');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Алиса');
    expect(node.hasFocus, isTrue);

    node.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings.nickname, 'Алиса');

    await tearDownPage(tester);
  });

  testWidgets('пустое имя заменяется именем по умолчанию', (tester) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;

    await tester.enterText(field, '   ');
    await tester.pump();
    node.unfocus();
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.nickname, 'Диана');
    expect(tester.widget<TextField>(field).controller!.text, 'Диана');

    await tearDownPage(tester);
  });

  testWidgets('имя сохраняется по «Готово» и обрезается до двадцати символов', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;

    node.requestFocus();
    await tester.pump();
    await tester.enterText(field, 'Диана-Василиса-Премудрая');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));

    expect(settings.nickname.runes.length, 20);
    expect(settings.nickname.startsWith('Диана-Василиса'), isTrue);
    expect(node.hasFocus, isFalse);

    await tearDownPage(tester);
  });

  testWidgets('имя сохраняется, даже если уйти со страницы во время набора', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);
    final node = tester.widget<TextField>(field).focusNode!;
    node.requestFocus();
    await tester.pump();

    await tester.enterText(field, 'Маша');
    await tester.pump();

    await tearDownPage(tester);
    await tester.pump();

    expect(settings.nickname, 'Маша');
  });

  testWidgets('переключатель игры сохраняется и переживает load', (tester) async {
    final settings = await pumpSettings(tester, withGame: true);
    final switchKey = const Key('game-flag-backgammon-numbers');
    expect(find.byKey(switchKey), findsOneWidget);
    expect(settings.flag('backgammon', 'numbers'), isFalse);

    await tester.tap(find.byKey(switchKey));
    await tester.pump();
    expect(settings.flag('backgammon', 'numbers'), isTrue);

    // Другой переключатель той же игры не тронут.
    expect(settings.flag('backgammon', 'hints'), isTrue);
    expect(field, findsOneWidget);

    await tearDownPage(tester);

    // Перезапуск приложения читает то же значение.
    final restored = SettingsController();
    await restored.load();
    expect(restored.flag('backgammon', 'numbers'), isTrue);

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: restored, game: backgammonGame)),
    );
    await tester.pump();
    final tile = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(switchKey),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.value, isTrue);

    await tearDownPage(tester);
    restored.dispose();
  });
}
