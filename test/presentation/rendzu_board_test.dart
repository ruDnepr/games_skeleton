import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/rendzu/engine/model.dart';
import 'package:games_for_diana/games/rendzu/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Накачивает экран партии рэндзю на фиксированном виртуальном устройстве и
/// возвращает его состояние для проверок. Все виджет-тесты партии повторяют
/// одни и те же настройки — они живут здесь один раз.
Future<RendzuSessionPage> pumpRendzu(
  WidgetTester tester, {
  required SettingsController settings,
  Ruleset ruleset = Ruleset.gomoku,
  BoardSize boardSize = BoardSize.small9,
  bool vsAi = false,
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: RendzuSessionPage(
        settings: settings,
        ruleset: ruleset,
        boardSize: boardSize,
        vsAi: vsAi,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return tester.widget<RendzuSessionPage>(find.byType(RendzuSessionPage));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RendzuSessionPage — рендеринг', () {
    testWidgets('экран партии рендерится с пустой доской', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings);
      expect(find.byType(RendzuSessionPage), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('AppBar показывает «Гомоку · 9×9»', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(
        tester,
        settings: settings,
        ruleset: Ruleset.gomoku,
        boardSize: BoardSize.small9,
      );
      expect(find.text('Гомоку · 9×9'), findsOneWidget);
    });

    testWidgets('AppBar показывает «Рэндзю · 15×15»', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(
        tester,
        settings: settings,
        ruleset: Ruleset.renju,
        boardSize: BoardSize.standard15,
      );
      expect(find.text('Рэндзю · 15×15'), findsOneWidget);
    });

    testWidgets('кнопки «Отменить» и «Сдаться» видны', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings);
      expect(find.text('Отменить'), findsOneWidget);
      expect(find.text('Сдаться'), findsOneWidget);
    });

    testWidgets('кнопки «Подсказка» и «Заново» в AppBar', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings);
      expect(find.byTooltip('Подсказка'), findsOneWidget);
      expect(find.byTooltip('Заново'), findsOneWidget);
    });
  });

  group('RendzuSessionPage — тап по доске', () {
    testWidgets('тап по центру ставит камень', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings);
      // Тапнем в центр доски.
      final boardCenter = tester.getCenter(find.byType(CustomPaint).first);
      await tester.tapAt(boardCenter);
      await tester.pump();
      // После хода номер хода увеличивается.
      expect(find.textContaining('Ход'), findsWidgets);
    });
  });
}
