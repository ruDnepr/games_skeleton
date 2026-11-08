import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/loto/engine/model.dart';
import 'package:games_for_diana/games/loto/session_page.dart';
import 'package:games_for_diana/presentation/theme.dart';

/// Виджеты лото в изоляции: бочонок, история, панель игрока и салют.
/// Повторяет оригинальный `test/presentation/widgets_test.dart`.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: dianaTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('бочонок подписан числом с торца', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(wrap(const BarrelView(number: 11)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(BarrelView), findsOneWidget);
    expect(find.bySemanticsLabel('Бочонок 11'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('торец бочонка без корпуса подписан числом', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(wrap(const BarrelCap(number: 42, size: 40)));
    await tester.pump();
    expect(find.byType(BarrelCap), findsOneWidget);
    expect(find.bySemanticsLabel('Бочонок 42'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('история показывает вытянутые бочонки по порядку', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const HistoryPanel(drawn: [])));
    await tester.pump();
    expect(find.text('пока пусто'), findsOneWidget);
    expect(find.byType(BarrelCap), findsNothing);

    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 420,
          child: HistoryPanel(drawn: [11, 42, 7]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('вытянуто 3'), findsOneWidget);
    expect(find.byType(BarrelCap), findsNWidgets(3));
    // Свежий бочонок — первым в списке.
    final first = tester.widget<BarrelCap>(find.byType(BarrelCap).first);
    expect(first.number, 7);
  });

  testWidgets('панель игрока называет игрока и режим победы', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 340,
          child: PlayerPanel(
            player: LotoPlayer(
              id: 'rival',
              name: 'Друг',
              card: LotoCard.fromJson(const {
                'rows': [
                  [5, null, null, 31, null, 50, null, 71, 80],
                  [null, 15, 25, null, 44, null, 65, null, 85],
                  [9, 19, null, 39, null, null, null, 79, 90],
                ],
              }),
              isComputer: true,
            ),
            winMode: WinMode.row,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Друг'), findsOneWidget);
  });

  testWidgets('салют предлагает сыграть ещё и выйти', (tester) async {
    var again = 0;
    var exit = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: dianaTheme(),
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              CelebrationOverlay(
                title: 'Победа!',
                subtitle: 'Диана закрыла строку',
                onAgain: () => again++,
                onExit: () => exit++,
                againLabel: 'Ещё партия',
                exitLabel: 'К лобби',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Победа!'), findsOneWidget);
    expect(find.text('Диана закрыла строку'), findsOneWidget);
    await tester.tap(find.byKey(const Key('celebration-again')));
    expect(again, 1);
    await tester.tap(find.byKey(const Key('celebration-exit')));
    expect(exit, 1);
  });

  testWidgets('сцена ведущего объявляет число и остаток в мешке', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 400,
          child: BarrelStage(
            barrel: Barrel(11),
            barrelsLeft: 79,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('11 — барабанные палочки'), findsOneWidget);
    expect(find.text('В мешке: 79'), findsOneWidget);
  });

  testWidgets('сцена ведущего показывает, кого ждём', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 400,
          child: BarrelStage(
            barrel: Barrel(42),
            barrelsLeft: 50,
            waitingFor: ['Диана'],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Бочонок 42'), findsOneWidget);
    expect(find.text('Ждём: Диана'), findsOneWidget);
  });
}
