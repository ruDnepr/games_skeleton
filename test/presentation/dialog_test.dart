import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/presentation/theme.dart';

/// Material lays dialog actions out in a row, where three Russian labels shrink
/// to a size a child cannot hit. `showDianaDialog` puts them in a column
/// instead: full width, 56 px high, the safe choice first and filled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(
    WidgetTester tester,
    void Function(bool? value) onResult,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: dianaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final result = await showDianaDialog<bool>(
                    context: context,
                    title: 'Сбросить прогресс?',
                    content: const Text(
                      'Счётчик партий и побед станет равен нулю.',
                      textAlign: TextAlign.center,
                      style: dialogTextStyle,
                    ),
                    actions: const [
                      DianaDialogButton<bool>(
                        label: 'Не сейчас',
                        value: false,
                        primary: true,
                      ),
                      DianaDialogButton<bool>(label: 'Сбросить', value: true),
                    ],
                  );
                  onResult(result);
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('кнопки диалога высокие, во всю ширину и в столбик', (
    tester,
  ) async {
    await openDialog(tester, (_) {});

    final buttons = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(buttons, findsNWidgets(2));

    final first = tester.getRect(buttons.at(0));
    final second = tester.getRect(buttons.at(1));
    for (final rect in [first, second]) {
      expect(rect.height, 56);
      expect(rect.width, greaterThanOrEqualTo(200));
    }
    // One under another, and both as wide as the dialog allows.
    expect(second.top, greaterThanOrEqualTo(first.bottom));
    expect(first.width, second.width);

    // The safe choice is the first one and it is the filled one.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Не сейчас'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.text('Сбросить'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('первая кнопка возвращает безопасный выбор', (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('вторая кнопка возвращает подтверждение', (tester) async {
    bool? result;
    await openDialog(tester, (value) => result = value);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
