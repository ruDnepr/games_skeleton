import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/battleship/battleship_controller.dart';
import 'package:games_for_diana/games/battleship/engine/ai.dart';
import 'package:games_for_diana/games/battleship/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Виджет-тест расстановки: арсенал, кнопки «Случайно»/«Очистить»/«В бой»,
/// переход к экрану партии после готовности флота.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> makeSettings() async {
    final settings = SettingsController();
    await settings.load();
    settings.sound = false;
    return settings;
  }

  testWidgets('экран расстановки показывает кнопку «В бой» и арсенал',
      (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipSetupPage(
          settings: settings,
          mode: GameMode.computer,
          difficulty: Difficulty.easy,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('В бой!'), findsOneWidget);
    expect(find.text('Арсенал'), findsOneWidget);
    expect(find.text('Случайно'), findsOneWidget);
    expect(find.text('Очистить'), findsOneWidget);
    // «В бой» изначально недоступен — флот ещё не расставлен.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('кнопка «Случайно» расставляет флот и включает «В бой»',
      (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipSetupPage(
          settings: settings,
          mode: GameMode.computer,
          difficulty: Difficulty.easy,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Случайно'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull,
        reason: 'После случайной расстановки «В бой» должен быть доступен');
  });

  testWidgets('кнопка «В бой» открывает экран партии', (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipSetupPage(
          settings: settings,
          mode: GameMode.computer,
          difficulty: Difficulty.easy,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Случайно'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('В бой!'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    // Должны были перейти на экран партии.
    expect(find.byType(BattleshipGamePage), findsOneWidget);
  });

  testWidgets('выбор режима показывает обе кнопки', (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(home: BattleshipModePage(settings: settings)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Играть с компьютером'), findsOneWidget);
    expect(find.text('Двое на одном устройстве'), findsOneWidget);
  });

  testWidgets('экран сложности показывает три уровня', (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipDifficultyPage(settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Лёгкий'), findsOneWidget);
    expect(find.text('Средний'), findsOneWidget);
    expect(find.text('Сложный'), findsOneWidget);
  });
}
