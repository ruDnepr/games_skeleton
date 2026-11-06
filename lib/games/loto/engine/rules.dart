/// Правила лото, отделённые от интерфейса.
///
/// Класс без состояния: каждый метод принимает состояние и возвращает новое.
/// Так один и тот же код проверяет закрытие числа у живого игрока, у
/// компьютерного соперника и у игрока, пришедшего по сети, — расхождения быть
/// не может. Подробные правила — в `rules.dart` экрана правил; здесь — точная
/// механика.
library;

import 'model.dart';

/// Правила лото: только проверки, без хранения состояния.
///
/// Ими пользуются и одиночная игра, и хост сетевой партии, поэтому правила
/// невозможно «обойти» на одном из устройств.
class LotoRules {
  const LotoRules._();

  /// Можно ли игроку [playerId] закрыть число [number] в партии [game].
  ///
  /// Удобный метод для контроллера и хоста сети: вся проверка в одном месте,
  /// от извлечения карточки игрока до финального решения. Использует
  /// [checkCloseFields] для самих правил.
  static CloseStatus checkClose(
    LotoGame game,
    String playerId,
    int number,
  ) {
    if (game.isOver) return CloseStatus.gameOver;
    final player = game.playerById(playerId);
    if (player == null) return CloseStatus.unknownPlayer;
    return checkCloseFields(
      card: player.card,
      closed: player.closed,
      drawn: game.drawn,
      number: number,
    );
  }

  /// Можно ли закрыть число: оно есть на карточке, его уже вытянули и оно
  /// ещё не закрыто.
  static CloseStatus checkCloseFields({
    required LotoCard card,
    required Set<int> closed,
    required Iterable<int> drawn,
    required int number,
  }) {
    if (!card.contains(number)) return CloseStatus.notOnCard;
    if (!drawn.contains(number)) return CloseStatus.notDrawn;
    if (closed.contains(number)) return CloseStatus.alreadyClosed;
    return CloseStatus.closed;
  }

  /// Можно ли закрыть число: то же, что [checkCloseFields], но в виде bool.
  static bool canClose({
    required LotoCard card,
    required Set<int> closed,
    required Iterable<int> drawn,
    required int number,
  }) =>
      checkCloseFields(
        card: card,
        closed: closed,
        drawn: drawn,
        number: number,
      ) ==
      CloseStatus.closed;

  /// Сколько чисел строки уже закрыто.
  static int closedInRow({
    required LotoCard card,
    required Set<int> closed,
    required int row,
  }) =>
      card.numbersOfRow(row).where(closed.contains).length;

  /// Закрыта ли строка целиком.
  static bool isRowClosed({
    required LotoCard card,
    required Set<int> closed,
    required int row,
  }) =>
      closedInRow(card: card, closed: closed, row: row) ==
      LotoCard.numbersPerRow;

  /// Для каждой строки — закрыта она или нет. Победа по строке срабатывает,
  /// как только хотя бы одна строка закрыта целиком.
  static List<bool> rowsClosed({
    required LotoCard card,
    required Set<int> closed,
  }) =>
      List<bool>.generate(
        LotoCard.rowCount,
        (row) => isRowClosed(card: card, closed: closed, row: row),
        growable: false,
      );

  /// Сколько строк закрыто.
  static int closedRows({
    required LotoCard card,
    required Set<int> closed,
  }) =>
      rowsClosed(card: card, closed: closed)
          .where((closedRow) => closedRow)
          .length;

  /// Номер первой полностью закрытой строки или `null`.
  static int? closedRowIndex({
    required LotoCard card,
    required Set<int> closed,
  }) {
    for (var row = 0; row < LotoCard.rowCount; row++) {
      if (isRowClosed(card: card, closed: closed, row: row)) return row;
    }
    return null;
  }

  /// Закрыта ли вся карточка (все пятнадцать чисел).
  static bool isCardClosed({
    required LotoCard card,
    required Set<int> closed,
  }) =>
      card.numbers.every(closed.contains);

  /// Победил ли игрок при выбранном [mode].
  static bool hasWon({
    required LotoCard card,
    required Set<int> closed,
    required WinMode mode,
  }) => switch (mode) {
    WinMode.row => closedRowIndex(card: card, closed: closed) != null,
    WinMode.fullCard => isCardClosed(card: card, closed: closed),
  };

  /// Какие числа карточки уже можно закрыть — это и есть подсказка.
  static List<int> closableNumbers({
    required LotoCard card,
    required Set<int> closed,
    required Iterable<int> drawn,
  }) {
    final drawnSet = drawn is Set<int> ? drawn : drawn.toSet();
    return card.numbers
        .where(
          (number) => drawnSet.contains(number) && !closed.contains(number),
        )
        .toList();
  }

  /// Сколько чисел карточки ещё открыто и при этом уже вытянуто.
  static int pendingClose({
    required LotoCard card,
    required Set<int> closed,
    required Iterable<int> drawn,
  }) =>
      closableNumbers(card: card, closed: closed, drawn: drawn).length;
}
