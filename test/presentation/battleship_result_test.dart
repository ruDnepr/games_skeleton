import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/battleship/battleship_controller.dart';
import 'package:games_for_diana/games/battleship/engine/ai.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/engine/rules.dart';
import 'package:games_for_diana/games/battleship/session_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Виджет-тест экрана результата: победа/поражение, кнопки «Ещё раз»/«В меню».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SettingsController> makeSettings() async {
    final settings = SettingsController();
    await settings.load();
    settings.sound = false;
    return settings;
  }

  testWidgets('экран победы показывает трофей и кнопку «Ещё раз»',
      (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = battleshipRules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: Difficulty.easy,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipResultPage(
          winner: Side.me,
          setup: setup,
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Победа!'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    expect(find.text('Ещё раз'), findsOneWidget);
    expect(find.text('В меню'), findsOneWidget);
  });

  testWidgets('экран поражения поддерживает ребёнка', (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final myFleet = battleshipRules.autoFleet();
    final enemyFleet = battleshipRules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: myFleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: Difficulty.easy,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipResultPage(
          winner: Side.enemy,
          setup: setup,
          settings: settings,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('В этот раз не вышло'), findsOneWidget);
    expect(find.byIcon(Icons.sentiment_dissatisfied_rounded), findsOneWidget);
  });

  testWidgets('фатальная ошибка показывает значок связи', (tester) async {
    final settings = await makeSettings();
    addTearDown(settings.dispose);
    final myFleet = battleshipRules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.network,
      myFleet: myFleet,
      iShootFirst: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BattleshipResultPage(
          winner: Side.enemy,
          setup: setup,
          settings: settings,
          fatalMessage: 'Связь потеряна. Вернись в меню.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Связь прервалась'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });
}
