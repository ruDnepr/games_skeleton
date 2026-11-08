import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/loto/engine/model.dart';

/// Карточка лото: генерация, восстановление из сети и поиск чисел.
void main() {
  test('карточка всегда: три строки, по пять чисел, все столбцы заняты', () {
    final random = Random(2026);
    for (var attempt = 0; attempt < 300; attempt++) {
      final card = LotoCard.generate(random: random);
      expect(card.rows, hasLength(LotoCard.rowCount));
      expect(
        card.rows.every((row) => row.length == LotoCard.columnCount),
        isTrue,
      );
      expect(card.numberSet, hasLength(LotoCard.totalNumbers));
      for (var row = 0; row < LotoCard.rowCount; row++) {
        expect(card.numbersOfRow(row), hasLength(LotoCard.numbersPerRow));
      }
      for (var column = 0; column < LotoCard.columnCount; column++) {
        final values = [
          for (var row = 0; row < LotoCard.rowCount; row++)
            card.rows[row][column],
        ].whereType<int>().toList();
        expect(values, isNotEmpty, reason: 'столбец $column пуст');
        expect(values.length, lessThanOrEqualTo(3));
        for (final value in values) {
          expect(
            LotoCard.columnContains(column, value),
            isTrue,
            reason: 'число $value не из столбца $column',
          );
        }
        // Числа в столбце растут сверху вниз.
        expect(values, orderedEquals([...values]..sort()));
      }
      for (final number in card.numbers) {
        expect(number, inInclusiveRange(1, 90));
      }
    }
  });

  test('все числа в диапазоне своего столбца', () {
    final r0 = LotoCard.columnRange(0);
    expect(r0.start, 1);
    expect(r0.end, 9);
    final r1 = LotoCard.columnRange(1);
    expect(r1.start, 10);
    expect(r1.end, 19);
    final r8 = LotoCard.columnRange(8);
    expect(r8.start, 80);
    expect(r8.end, 90);
    expect(LotoCard.columnContains(0, 9), isTrue);
    expect(LotoCard.columnContains(0, 10), isFalse);
    expect(LotoCard.columnContains(8, 90), isTrue);
    expect(LotoCard.columnContains(7, 80), isFalse);
  });

  test('карточка переживает отправку по сети', () {
    final card = LotoCard.generate(random: Random(7));
    final restored = LotoCard.fromJson(card.toJson());
    expect(restored.rows, card.rows);
    expect(restored.numberSet, card.numberSet);
  });

  test('битая карточка из сети не принимается', () {
    expect(() => LotoCard.fromJson(null), throwsA(isA<FormatException>()));
    expect(
      () => LotoCard.fromJson({
        'rows': const [
          [1, null, null, null, null, null, null, null, null],
          [null, null, null, null, null, null, null, null, null],
        ],
      }),
      throwsA(isA<FormatException>()),
    );
    // Число не из своего столбца.
    expect(
      () => LotoCard.fromJson({
        'rows': const [
          [1, 11, 21, 31, 41, null, null, null, null],
          [null, null, null, null, null, null, null, null, null],
          [null, null, null, null, null, null, null, null, null],
        ],
      }),
      throwsA(isA<FormatException>()),
    );
    // Повтор числа.
    expect(
      () => LotoCard.fromJson({
        'rows': const [
          [3, 12, 21, 34, 45, null, null, null, null],
          [3, null, null, null, null, null, null, null, null],
          [null, null, null, null, null, null, null, null, null],
        ],
      }),
      throwsA(isA<FormatException>()),
    );
    // Четыре числа в строке вместо пяти.
    expect(
      () => LotoCard.fromJson({
        'rows': const [
          [3, 12, 21, 34, null, null, null, null, null],
          [null, null, null, null, 47, 52, 61, 78, 88],
          [7, null, null, 38, null, 56, 66, null, 89],
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('число находят по строке и столбцу', () {
    final card = LotoCard.fromJson(const {
      'rows': [
        [3, 12, 21, 34, 45, null, null, null, null],
        [null, null, null, null, 47, 52, 61, 78, 88],
        [7, null, null, 38, null, 56, 66, null, 89],
      ],
    });
    expect(card.rowOf(45), 0);
    expect(card.rowOf(47), 1);
    expect(card.rowOf(89), 2);
    expect(card.columnOf(45), 4);
    expect(card.columnOf(88), 8);
    expect(card.rowOf(90), isNull);
    expect(card.contains(52), isTrue);
    expect(card.contains(99), isFalse);
  });
}
