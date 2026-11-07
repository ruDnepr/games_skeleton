import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/loto/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Экран выбора режима: три режима (компьютер-ведущий, два игрока,
/// ведущий-человек) и выбор режима победы. Повторяет оригинальный
/// `test/presentation/menu_test.dart` (часть про новую партию).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> pumpMode(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await tester.runAsync(settings.load);
    settings.sound = false;
    await tester.pumpWidget(
      MaterialApp(home: LotoModePage(settings: settings)),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('показывает шаги и три режима', (tester) async {
    await pumpMode(tester);
    expect(find.text('С кем играем?'), findsOneWidget);
    expect(find.text('Как побеждаем?'), findsOneWidget);
    expect(find.text('Ведущий-компьютер'), findsOneWidget);
    expect(find.text('Два игрока'), findsOneWidget);
    expect(find.text('Ведущий-человек'), findsOneWidget);
    expect(find.text('Начать игру'), findsOneWidget);
  });

  testWidgets('можно выбрать ведущего-человека и победу по строке', (
    tester,
  ) async {
    await pumpMode(tester);
    await tester.tap(find.byKey(const Key('mode-humanHost')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('win-row')));
    await tester.pump();
    expect(find.text('Начать игру'), findsOneWidget);
  });

  testWidgets('кнопка старта открывает экран партии с выбранным режимом', (
    tester,
  ) async {
    await pumpMode(tester);
    await tester.tap(find.byKey(const Key('mode-twoPlayers')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('win-fullCard')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start-game')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start-game')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(LotoSessionPage), findsOneWidget);
  });
}
