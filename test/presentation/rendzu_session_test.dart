import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/rendzu/engine/model.dart';
import 'package:games_for_diana/games/rendzu/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Накачивает экран партии рэндзю на фиксированном виртуальном устройстве.
Future<void> pumpRendzu(
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RendzuSessionPage — поток партии', () {
    testWidgets('пять в ряд показывает диалог победы', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings, ruleset: Ruleset.gomoku);

      // Чёрные собирают пять по горизонтали в верхней строке, белые ходят
      // далеко в углу, чтобы не мешать.
      final boardRect = tester.getRect(find.byType(CustomPaint).first);
      final cell = boardRect.width / 9;

      // Помощник: тап по пересечению (x, y).
      Future<void> tapAt(int x, int y) async {
        final dx = boardRect.left + cell * (x + 0.5);
        final dy = boardRect.top + cell * (y + 0.5);
        await tester.tapAt(Offset(dx, dy));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // ч: (0,0), б: (8,8), ч: (1,0), б: (7,7), ч: (2,0), б: (6,6),
      // ч: (3,0), б: (5,5), ч: (4,0) — пять!
      await tapAt(0, 0);
      await tapAt(8, 8);
      await tapAt(1, 0);
      await tapAt(7, 7);
      await tapAt(2, 0);
      await tapAt(6, 6);
      await tapAt(3, 0);
      await tapAt(5, 5);
      await tapAt(4, 0);

      await tester.pump(const Duration(milliseconds: 300));
      // Диалог победы с кнопками «Играть снова» и «В меню».
      expect(find.text('Играть снова'), findsOneWidget);
      expect(find.text('В меню'), findsOneWidget);
      // Кнопка «Отменить ход» доступна в офлайн после победы.
      expect(find.text('Отменить ход'), findsOneWidget);
    });

    testWidgets('кнопка «Заново» открывает подтверждение', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(tester, settings: settings);

      await tester.tap(find.byTooltip('Заново'));
      await tester.pump();
      expect(find.text('Начать заново?'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Заново'), findsOneWidget);
    });

    testWidgets('запрещённый ход в рэндзю показывает снэкбар', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await pumpRendzu(
        tester,
        settings: settings,
        ruleset: Ruleset.renju,
        boardSize: BoardSize.standard15,
      );

      final boardRect = tester.getRect(find.byType(CustomPaint).first);
      final cell = boardRect.width / 15;

      Future<void> tapAt(int x, int y) async {
        final dx = boardRect.left + cell * (x + 0.5);
        final dy = boardRect.top + cell * (y + 0.5);
        await tester.tapAt(Offset(dx, dy));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Подготавливаем 3-3 в точке (7,7):
      // ч: (5,7), б: (0,0), ч: (6,7), б: (0,1), ч: (7,5), б: (0,2),
      // ч: (7,6), б: (0,3), затем ч: (7,7) — запрещено.
      await tapAt(5, 7);
      await tapAt(0, 0);
      await tapAt(6, 7);
      await tapAt(0, 1);
      await tapAt(7, 5);
      await tapAt(0, 2);
      await tapAt(7, 6);
      await tapAt(0, 3);
      await tapAt(7, 7); // запрещено

      await tester.pump(const Duration(milliseconds: 300));
      // Снэкбар с предупреждением появляется.
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
