import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/example/game.dart';
import 'package:games_for_diana/presentation/rules_page.dart';
import 'package:games_for_diana/presentation/theme.dart';

/// The rules screen draws the cards of the game and nothing else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('экран правил рисует все карточки игры по порядку', (tester) async {
    // A tall surface, so every card is built and can be measured at once.
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: dianaTheme(), home: RulesPage(game: exampleGame)),
    );
    await tester.pump();

    expect(find.text('Это просто!'), findsOneWidget);
    expect(find.text(exampleGame.tagline), findsOneWidget);

    final tops = <double>[];
    for (final card in exampleGame.rules) {
      final finder = find.byKey(Key('rule-card-${card.number}'));
      expect(finder, findsOneWidget, reason: 'карточка ${card.number}');
      expect(
        find.descendant(of: finder, matching: find.text(card.title)),
        findsOneWidget,
        reason: 'заголовок ${card.number}',
      );
      expect(
        find.descendant(of: finder, matching: find.text(card.text)),
        findsOneWidget,
        reason: 'текст ${card.number}',
      );
      expect(
        find.descendant(
          of: finder,
          matching: find.text('${card.number}'),
        ),
        findsOneWidget,
      );
      tops.add(tester.getTopLeft(finder).dy);
    }

    // The cards go down the page exactly in the order the game declared them.
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet().length, exampleGame.rules.length);
  });

  testWidgets('на экране правил только данные игры и слоганы каркаса', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: dianaTheme(), home: RulesPage(game: exampleGame)),
    );
    await tester.pump();

    // Everything the screen shows comes either from the game or from the
    // shared frame: no text of another game is baked into the widget.
    final expected = <String>{
      'Правила',
      'УЧИМСЯ ИГРАЯ',
      'Это просто!',
      exampleGame.tagline,
      for (final card in exampleGame.rules) ...<String>[
        '${card.number}',
        card.title,
        card.text,
      ],
      'Ошибаться и пробовать снова — это нормально! ✨',
    };
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(expected.contains(text), isTrue, reason: text);
    }

    // The closing line of the screen is a slogan of the frame, not of a game.
    expect(
      find.text('Ошибаться и пробовать снова — это нормально! ✨'),
      findsOneWidget,
    );
  });
}
