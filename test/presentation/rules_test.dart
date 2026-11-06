import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/game.dart';
import 'package:games_for_diana/presentation/rules_page.dart';
import 'package:games_for_diana/presentation/theme.dart';

/// Экран правил рисует карточки игры и ничего лишнего.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('экран правил рисует все карточки игры по порядку', (tester) async {
    // Высокая поверхность, чтобы все карточки строились и измерялись сразу.
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: dianaTheme(), home: RulesPage(game: backgammonGame)),
    );
    await tester.pump();

    expect(find.text('Это просто!'), findsOneWidget);
    expect(find.text(backgammonGame.tagline), findsOneWidget);

    final tops = <double>[];
    for (final card in backgammonGame.rules) {
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

    // Карточки идут вниз ровно в том порядке, в котором их объявила игра.
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet().length, backgammonGame.rules.length);

    // Прокручиваем к концу, чтобы закрывающая строка гарантированно
    // построилась — карточек нард десять, и они длиннее, чем у заготовки.
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(
      find.text('Ошибаться и пробовать снова — это нормально! ✨'),
      findsOneWidget,
    );
  });

  testWidgets('на экране правил только данные игры и слоганы каркаса', (
    tester,
  ) async {
    // Десять карточек нард длиннее, чем у заготовки: берём высоту с запасом,
    // чтобы построилась и закрывающая строка.
    tester.view.physicalSize = const Size(420, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: dianaTheme(), home: RulesPage(game: backgammonGame)),
    );
    await tester.pump();

    // Всё на экране — либо от игры, либо от общего каркаса.
    final expected = <String>{
      'Правила',
      'УЧИМСЯ ИГРАЯ',
      'Это просто!',
      backgammonGame.tagline,
      for (final card in backgammonGame.rules) ...<String>[
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

    expect(
      find.text('Ошибаться и пробовать снова — это нормально! ✨'),
      findsOneWidget,
    );
  });
}
