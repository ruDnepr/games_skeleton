import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/ui/dice_widget.dart';

/// Кубики рисуют выпавшие значения и затемняют использованные.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('две разные кости рисуются без дубля', (tester) async {
    tester.view.physicalSize = const Size(320, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DiceWidget(rolled: const [3, 5], available: const [3, 5]),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DiceWidget), findsOneWidget);
    expect(find.text('дубль!'), findsNothing);
  });

  testWidgets('дубль рисует четыре кубика и подпись «дубль!»', (tester) async {
    tester.view.physicalSize = const Size(360, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DiceWidget(
              rolled: const [4, 4],
              available: const [4, 4, 4, 4],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('дубль!'), findsOneWidget);
    expect(find.byType(DiceWidget), findsOneWidget);
  });
}
