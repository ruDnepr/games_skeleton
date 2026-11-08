import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/push_hour/engine/levels.dart';
import 'package:games_for_diana/games/push_hour/engine/model.dart';
import 'package:games_for_diana/games/push_hour/engine/rules.dart';
import 'package:games_for_diana/games/push_hour/progress.dart';
import 'package:games_for_diana/games/push_hour/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Экран партии «Push Hour»: список уровней, движение машин, победа и отмена.
/// Повторяет оригинальный `test/games/push_hour/session_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// В экране партии идёт таймер, поэтому pumpAndSettle не подходит.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Offset dragOffset(Move move) {
    final dx = move.to.col > move.from.col ? 40.0 : -40.0;
    final dy = move.to.row > move.from.row ? 40.0 : -40.0;
    return move.from.row == move.to.row ? Offset(dx, 0) : Offset(0, dy);
  }

  Future<void> dragCar(
    WidgetTester tester,
    String carId,
    Offset delta,
  ) async {
    await tester.drag(find.byKey(Key('car-tap-$carId')), delta);
    await settle(tester);
  }

  Future<PushHourProgress> pumpSession(
    WidgetTester tester, {
    required SettingsController settings,
    required Level level,
  }) async {
    final progress = PushHourProgress();
    await progress.load();
    await tester.pumpWidget(
      MaterialApp(
        home: PushHourSessionPage(
          settings: settings,
          progress: progress,
          level: level,
        ),
      ),
    );
    await settle(tester);
    return progress;
  }

  testWidgets('выбор уровня открывает поле первого уровня', (tester) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final progress = PushHourProgress();
    await progress.load();

    await tester.pumpWidget(
      MaterialApp(
        home: PushHourEntryPage(
          settings: settings,
          progress: progress,
          level: levelByNumber(1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('100 пробок'), findsOneWidget);
    expect(find.byKey(const Key('level-tile-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('level-tile-1')));
    await settle(tester);

    expect(find.text('Уровень 1'), findsOneWidget);
    expect(find.text('Ходы: 0'), findsOneWidget);
  });

  testWidgets('партия проходится ходами и открывает следующий уровень', (
    tester,
  ) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final level = levelByNumber(1);
    final solution = RushHourSolver.solve(level.grid)!;

    final progress = await pumpSession(
      tester,
      settings: settings,
      level: level,
    );

    expect(find.text('Уровень 1'), findsOneWidget);
    expect(find.text('Ходы: 0'), findsOneWidget);

    for (final move in solution) {
      await dragCar(tester, move.carId, dragOffset(move));
    }

    expect(find.text('Уровень пройден! 🎉'), findsOneWidget);
    expect(progress.bestFor(1), solution.length);
    expect(progress.unlockedLevel, 2);

    await tester.tap(find.byKey(const Key('session-next')));
    await settle(tester);
    expect(find.text('Уровень 2'), findsOneWidget);
  });

  testWidgets('отмена возвращает поле назад', (tester) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final level = levelByNumber(1);
    await pumpSession(tester, settings: settings, level: level);

    final move = RushHourRules.children(level.grid).first.$1;
    await dragCar(tester, move.carId, dragOffset(move));
    expect(find.text('Ходы: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-undo')));
    await settle(tester);
    expect(find.text('Ходы: 0'), findsOneWidget);
  });

  testWidgets('подсказка показывает следующий ход', (tester) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final level = levelByNumber(10);
    await pumpSession(tester, settings: settings, level: level);

    await tester.tap(find.byKey(const Key('session-hint')));
    await settle(tester);

    expect(find.textContaining('Подсказка:'), findsOneWidget);
  });

  testWidgets('подсказка работает, даже если в настройках выключена', (
    tester,
  ) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;
    await settings.setFlag('push_hour', 'hints', false);

    final level = levelByNumber(2);
    await pumpSession(tester, settings: settings, level: level);

    await tester.tap(find.byKey(const Key('session-hint')));
    await settle(tester);

    expect(find.textContaining('Подсказка:'), findsOneWidget);
    // Лампочка включается сама, чтобы кнопка не молчала.
    expect(settings.flag('push_hour', 'hints'), isTrue);
  });

  testWidgets('нажатие на машину сдвигает её на клетку', (tester) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final level = levelByNumber(1);
    await pumpSession(tester, settings: settings, level: level);

    await tester.tap(find.byKey(const Key('car-tap-red')));
    await settle(tester);

    expect(find.text('Ходы: 1'), findsOneWidget);
  });

  testWidgets('«Заново» в верхней панели возвращает поле в начало', (
    tester,
  ) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    final level = levelByNumber(1);
    await pumpSession(tester, settings: settings, level: level);

    await tester.tap(find.byKey(const Key('car-tap-red')));
    await settle(tester);
    expect(find.text('Ходы: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-restart')));
    await settle(tester);
    expect(find.text('Ходы: 0'), findsOneWidget);
  });

  testWidgets('динамик в верхней панели выключает и включает звук', (
    tester,
  ) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    settings.sound = false;

    // Прямо выставляем звук в true — кнопка должна его показывать включённым.
    settings.sound = true;

    final level = levelByNumber(1);
    await pumpSession(tester, settings: settings, level: level);

    expect(settings.sound, isTrue);
    await tester.tap(find.byKey(const Key('session-sound')));
    await settle(tester);
    expect(settings.sound, isFalse);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-sound')));
    await settle(tester);
    expect(settings.sound, isTrue);
  });
}
