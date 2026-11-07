import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/loto/engine/model.dart';
import 'package:games_for_diana/games/loto/engine/rules.dart';

/// Правила лото: проверка закрытия числа, строка/карточка, подсказки и
/// режим победы.
LotoCard myCard() => LotoCard.fromJson(const {
  'rows': [
    [3, 12, 21, 34, 45, null, null, null, null],
    [null, null, null, null, 47, 52, 61, 78, 88],
    [7, null, null, 38, null, 56, 66, null, 89],
  ],
});

void main() {
  final card = myCard();

  test('закрыть можно только вытянутое число со своей карточки', () {
    expect(
      LotoRules.checkCloseFields(
        card: card,
        closed: const {},
        drawn: const [3],
        number: 3,
      ),
      CloseStatus.closed,
    );
    expect(
      LotoRules.checkCloseFields(
        card: card,
        closed: const {},
        drawn: const [12],
        number: 3,
      ),
      CloseStatus.notDrawn,
    );
    expect(
      LotoRules.checkCloseFields(
        card: card,
        closed: const {},
        drawn: const [90],
        number: 90,
      ),
      CloseStatus.notOnCard,
    );
    expect(
      LotoRules.checkCloseFields(
        card: card,
        closed: const {3},
        drawn: const [3],
        number: 3,
      ),
      CloseStatus.alreadyClosed,
    );
    expect(
      LotoRules.canClose(
        card: card,
        closed: const {},
        drawn: const [45],
        number: 45,
      ),
      isTrue,
    );
  });

  test('строка закрывается только целиком', () {
    expect(
      LotoRules.isRowClosed(
        card: card,
        closed: const {3, 12, 21, 34},
        row: 0,
      ),
      isFalse,
    );
    expect(
      LotoRules.closedInRow(
        card: card,
        closed: const {3, 12, 21, 34},
        row: 0,
      ),
      4,
    );
    expect(
      LotoRules.isRowClosed(
        card: card,
        closed: const {3, 12, 21, 34, 45},
        row: 0,
      ),
      isTrue,
    );
    expect(
      LotoRules.rowsClosed(card: card, closed: const {3, 12, 21, 34, 45}),
      [true, false, false],
    );
    expect(
      LotoRules.closedRowIndex(
        card: card,
        closed: const {3, 12, 21, 34, 45},
      ),
      0,
    );
    expect(
      LotoRules.closedRowIndex(card: card, closed: const {3, 12}),
      isNull,
    );
  });

  test('победа по строке и победа по всей карточке', () {
    final row = {3, 12, 21, 34, 45};
    expect(LotoRules.hasWon(card: card, closed: row, mode: WinMode.row), isTrue);
    expect(
      LotoRules.hasWon(card: card, closed: row, mode: WinMode.fullCard),
      isFalse,
    );
    final all = card.numberSet;
    expect(
      LotoRules.hasWon(card: card, closed: all, mode: WinMode.fullCard),
      isTrue,
    );
    expect(
      LotoRules.hasWon(card: card, closed: all, mode: WinMode.row),
      isTrue,
    );
    expect(LotoRules.isCardClosed(card: card, closed: all), isTrue);
    expect(
      LotoRules.isCardClosed(card: card, closed: {...all}..remove(89)),
      isFalse,
    );
  });

  test('подсказка перечисляет числа, которые можно закрыть', () {
    expect(
      LotoRules.closableNumbers(
        card: card,
        closed: const {},
        drawn: const [3, 12, 50, 90],
      ),
      [3, 12],
    );
    expect(
      LotoRules.closableNumbers(
        card: card,
        closed: const {12},
        drawn: const [3, 12],
      ),
      [3],
    );
    expect(
      LotoRules.pendingClose(
        card: card,
        closed: const {},
        drawn: const [3, 45, 89],
      ),
      3,
    );
  });

  test('режим победы восстанавливается из строки настроек', () {
    expect(WinMode.fromName('row'), WinMode.row);
    expect(WinMode.fromName('fullCard'), WinMode.fullCard);
    expect(WinMode.fromName('что-то'), WinMode.row);
    expect(WinMode.fromName(null), WinMode.row);
  });

  test('у отказа есть понятное объяснение для ребёнка', () {
    expect(CloseStatus.notDrawn.hint, 'Этот бочонок ещё в мешке');
    expect(CloseStatus.notOnCard.hint, 'Этого числа нет на карточке');
    expect(CloseStatus.alreadyClosed.hint, 'Это число уже закрыто');
    expect(CloseStatus.closed.hint, isEmpty);
  });
}
