import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/backgammon/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Экран выбора режима: переключение «против компьютера / вдвоём», выбор
/// уровня сложности и цвета, кнопка старта.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> pumpMode(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await tester.runAsync(settings.load);
    settings.sound = false;
    await tester.pumpWidget(
      MaterialApp(home: BackgammonModePage(settings: settings)),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('показывает режимы и кнопку старта', (tester) async {
    await pumpMode(tester);
    expect(find.text('С кем сыграем?'), findsOneWidget);
    expect(find.text('Против компьютера'), findsOneWidget);
    expect(find.text('Двое на одном устройстве'), findsOneWidget);
    expect(find.text('Начать партию'), findsOneWidget);
    // По умолчанию выбран ИИ — видны уровень и цвет.
    expect(find.text('Уровень сложности'), findsOneWidget);
    expect(find.text('Твой цвет'), findsOneWidget);
    expect(find.text('Лёгкий'), findsOneWidget);
  });

  testWidgets('можно выбрать «двое» — уровень и цвет скрываются', (tester) async {
    await pumpMode(tester);
    await tester.tap(find.text('Двое на одном устройстве'));
    await tester.pump();
    expect(find.text('Уровень сложности'), findsNothing);
    expect(find.text('Твой цвет'), findsNothing);
  });

  testWidgets('можно выбрать сложный уровень и чёрный цвет', (tester) async {
    await pumpMode(tester);
    await tester.tap(find.text('Сложный'));
    await tester.pump();
    await tester.tap(find.text('Чёрные'));
    await tester.pump();
    // Выбор подсвечен — кнопка старта осталась.
    expect(find.text('Начать партию'), findsOneWidget);
  });
}
