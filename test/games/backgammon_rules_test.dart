import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/engine/model.dart';
import 'package:games_for_diana/games/backgammon/engine/rules.dart';

/// Тесты правил коротких нард: движение, блок, выбивание, бар, вынос, дубль,
/// победа. Правила — общие для человека, ИИ и сети, поэтому проверяются отдельно
/// и тщательно.
void main() {
  GameState state({
    required Board board,
    Player turn = Player.white,
    List<int> rolled = const [],
    List<int> available = const [],
  }) =>
      GameState(
        board: board,
        turn: turn,
        rolled: rolled,
        available: available,
      );

  Board board(List<int> points, {int whiteBar = 0, int blackBar = 0, int whiteOff = 0, int blackOff = 0}) =>
      Board(
        points: points,
        whiteBar: whiteBar,
        blackBar: blackBar,
        whiteOff: whiteOff,
        blackOff: blackOff,
      );

  test('стартовая расстановка: по 15 шашек у каждого', () {
    final b = Board.initial();
    expect(b.onBoard(Player.white), 15);
    expect(b.onBoard(Player.black), 15);
    expect(b.at(23, Player.white), 2);
    expect(b.at(12, Player.white), 5);
    expect(b.at(7, Player.white), 3);
    expect(b.at(5, Player.white), 5);
    expect(b.at(0, Player.black), 2);
    expect(b.at(11, Player.black), 5);
    expect(b.at(16, Player.black), 3);
    expect(b.at(18, Player.black), 5);
  });

  test('белые идут к 0, чёрные к 23: направления и вход с бара', () {
    expect(Player.white.direction, -1);
    expect(Player.black.direction, 1);
    expect(BackgammonRules.barEntry(Player.white, 1), 23);
    expect(BackgammonRules.barEntry(Player.white, 6), 18);
    expect(BackgammonRules.barEntry(Player.black, 1), 0);
    expect(BackgammonRules.barEntry(Player.black, 6), 5);
  });

  test('дубль даёт четыре движения, разные кости — два', () {
    expect(BackgammonRules.expandDice([4, 4]), [4, 4, 4, 4]);
    expect(BackgammonRules.expandDice([3, 5]), [3, 5]);
  });

  group('движение', () {
    test('обычный ход белой шашки к дому', () {
      final s = state(
        board: Board.initial(),
        available: const [3],
      );
      final moves = BackgammonRules.movesForDie(s, 3);
      // С 23 → 20, с 12 → 9, с 7 → 4, с 5 → 2.
      expect(moves.any((m) => m.from == 23 && m.to == 20), isTrue);
      expect(moves.any((m) => m.from == 12 && m.to == 9), isTrue);
      expect(moves.any((m) => m.from == 7 && m.to == 4), isTrue);
      expect(moves.any((m) => m.from == 5 && m.to == 2), isTrue);
    });

    test('нельзя встать на пункт с двумя и более чужими шашками (блок)', () {
      // Чёрные блокируют пункт 9 (две шашки). Белая шашка на 12.
      final b = board(List.filled(24, 0)..[12] = 1..[9] = -2);
      final s = state(board: b, available: const [3]);
      final moves = BackgammonRules.movesForDie(s, 3);
      expect(moves.any((m) => m.from == 12 && m.to == 9), isFalse);
    });

    test('можно встать на пункт с одной чужой шашкой — выбивание', () {
      final b = board(List.filled(24, 0)..[5] = 1..[2] = -1);
      final s = state(board: b, available: const [3]);
      final moves = BackgammonRules.movesForDie(s, 3);
      final hit = moves.firstWhere((m) => m.from == 5 && m.to == 2);
      final after = BackgammonRules.applyMoveToBoard(b, hit);
      expect(after.at(2, Player.white), 1);
      expect(after.at(2, Player.black), 0); // чёрная выбита
      expect(after.bar(Player.black), 1);
    });
  });

  group('бар', () {
    test('с бара ходят только входом, пока шашка на баре', () {
      final b = board(List.filled(24, 0), whiteBar: 1);
      final s = state(board: b, available: const [3]);
      final moves = BackgammonRules.movesForDie(s, 3);
      expect(moves.length, 1);
      expect(moves.single.fromBar, isTrue);
      expect(moves.single.to, 21); // 24 - 3
    });

    test('вход закрыт блоком — хода нет', () {
      // Чёрные блокируют пункт 21 (вход белых костью 3).
      final b = board(List.filled(24, 0)..[21] = -2, whiteBar: 1);
      final s = state(board: b, available: const [3]);
      expect(BackgammonRules.movesForDie(s, 3), isEmpty);
    });

    test('выбитая шашка возвращается с бара в игру', () {
      final b = board(List.filled(24, 0), whiteBar: 1);
      final s = state(board: b, available: const [3]);
      final move = BackgammonRules.movesForDie(s, 3).single;
      final after = BackgammonRules.applyMove(s, move);
      expect(after.board.bar(Player.white), 0);
      expect(after.board.at(21, Player.white), 1);
    });
  });

  group('вынос', () {
    test('нельзя выносить, пока есть шашки вне дома', () {
      final b = board(List.filled(24, 0)..[5] = 5..[7] = 3..[10] = 7);
      expect(BackgammonRules.canBearOff(b, Player.white), isFalse);
    });

    test('можно выносить, когда все шашки дома', () {
      final b = board(List.filled(24, 0)..[5] = 5..[4] = 3..[3] = 4..[0] = 3);
      expect(BackgammonRules.canBearOff(b, Player.white), isTrue);
    });

    test('точный вынос: кость 6 выносит шашку с 6-го пункта (индекс 5)', () {
      final b = board(List.filled(24, 0)..[5] = 1);
      final s = state(board: b, available: const [6]);
      final moves = BackgammonRules.movesForDie(s, 6);
      expect(moves.any((m) => m.from == 5 && m.bearOff), isTrue);
    });

    test('лишняя кость выносит самую дальнюю шашку', () {
      // Шашки на 3 и 1. Кость 5 больше, чем нужно для 3 (4) — выносит с 3,
      // потому что 3 — самая дальняя. С 1 лишней костью выносить нельзя.
      final b = board(List.filled(24, 0)..[3] = 1..[1] = 1);
      final s = state(board: b, available: const [5]);
      final moves = BackgammonRules.movesForDie(s, 5);
      expect(moves.any((m) => m.from == 3 && m.bearOff), isTrue);
      expect(moves.any((m) => m.from == 1 && m.bearOff), isFalse);
    });

    test('меньшая кость не выносит, а ходит внутри дома', () {
      final b = board(List.filled(24, 0)..[3] = 1);
      final s = state(board: b, available: const [2]);
      final moves = BackgammonRules.movesForDie(s, 2);
      expect(moves.any((m) => m.bearOff), isFalse);
      expect(moves.any((m) => m.from == 3 && m.to == 1), isTrue);
    });
  });

  group('победа и конец хода', () {
    test('вынос последней шашки — победа', () {
      final b = board(List.filled(24, 0)..[0] = 1, whiteOff: 14);
      final s = state(board: b, available: const [1]);
      final move = BackgammonRules.movesForDie(s, 1).firstWhere((m) => m.bearOff);
      final after = BackgammonRules.applyMove(s, move);
      expect(after.winner, Player.white);
      expect(after.board.whiteOff, 15);
    });

    test('endTurn передаёт очередь сопернику', () {
      final s = state(board: Board.initial(), turn: Player.white);
      final after = BackgammonRules.endTurn(s);
      expect(after.turn, Player.black);
      expect(after.available, isEmpty);
    });
  });

  group('последовательности хода', () {
    test('две разные кости можно использовать обе', () {
      final s = state(board: Board.initial(), available: const [3, 1]);
      final seqs = BackgammonRules.allTurnSequences(s, const [3, 1]);
      expect(seqs, isNotEmpty);
      // Хотя бы одна последовательность использует обе кости.
      expect(seqs.any((seq) => seq.length == 2), isTrue);
    });

    test('дубль даёт до четырёх шагов', () {
      final s = state(board: Board.initial(), available: const [4, 4, 4, 4]);
      final seqs = BackgammonRules.allTurnSequences(s, const [4, 4, 4, 4]);
      expect(seqs, isNotEmpty);
      expect(seqs.any((seq) => seq.length == 4), isTrue);
    });

    test('expandDice: дубль расширяется до четырёх, не до двух', () {
      // Регрессия: withRoll раньше клал в available ровно [a, a] (2) для
      // дубля, и можно было сыграть только 2 хода вместо 4. withRoll теперь
      // расширяет сам — проверим, что after withRoll available длиной 4.
      final s = GameState(board: Board.initial(), turn: Player.white)
          .withRoll(const [4, 4]);
      expect(s.rolled, [4, 4]);
      expect(s.available.length, 4);
      expect(s.available, [4, 4, 4, 4]);
      // Не-дубль — две кости.
      final s2 = GameState(board: Board.initial(), turn: Player.white)
          .withRoll(const [3, 5]);
      expect(s2.available.length, 2);
    });

    test('canPlayAny ложен, когда хода нет', () {
      // Белая шашка на баре, все входы заблокированы чёрными.
      final b = board(
        List.filled(24, 0)..[23] = -2..[22] = -2..[21] = -2
          ..[20] = -2..[19] = -2..[18] = -2,
        whiteBar: 1,
      );
      final s = state(board: b, available: const [1, 2, 3, 4, 5, 6]);
      expect(BackgammonRules.canPlayAny(s, const [1, 2, 3, 4, 5, 6]), isFalse);
    });
  });

  group('applyTurn', () {
    test('применяет ход и передаёт очередь', () {
      final s = state(
        board: Board.initial(),
        turn: Player.white,
        rolled: const [3, 1],
      );
      final turn = Turn(
        player: Player.white,
        dice: const [3, 1],
        moves: [
          const Move(player: Player.white, die: 3, from: 23, to: 20),
          const Move(player: Player.white, die: 1, from: 20, to: 19),
        ],
      );
      final after = BackgammonRules.applyTurn(s, turn);
      expect(after.turn, Player.black);
      expect(after.board.at(23, Player.white), 1); // было 2, одну увели
      expect(after.board.at(19, Player.white), 1);
    });

    test('бросает FormatException на чужие кости', () {
      final s = state(
        board: Board.initial(),
        turn: Player.white,
        rolled: const [3, 1],
      );
      final turn = Turn(
        player: Player.white,
        dice: const [5, 6],
        moves: const [],
      );
      expect(() => BackgammonRules.applyTurn(s, turn), throwsFormatException);
    });

    test('бросает FormatException на чужой цвет', () {
      final s = state(
        board: Board.initial(),
        turn: Player.white,
        rolled: const [3, 1],
      );
      final turn = Turn(
        player: Player.black,
        dice: const [3, 1],
        moves: const [],
      );
      expect(() => BackgammonRules.applyTurn(s, turn), throwsFormatException);
    });
  });

  group('длинные нарды', () {
    GameState longState({
      required Board board,
      Player turn = Player.white,
      List<int> available = const [],
    }) =>
        GameState(
          board: board,
          turn: turn,
          available: available,
          variant: BackgammonVariant.long,
        );

    test('стартовая расстановка: все 15 шашек на голове', () {
      final b = Board.initial(variant: BackgammonVariant.long);
      expect(b.at(23, Player.white), 15); // белые на 24-м
      expect(b.at(0, Player.black), 15); // чёрные на 1-м
      // Остальные пункты пусты.
      expect(b.onBoard(Player.white), 15);
      expect(b.onBoard(Player.black), 15);
    });

    test('нельзя встать на пункт с одной чужой шашкой — выбивания нет', () {
      // Белая шашка на 12, кость 3 → пункт 9. Там одна чёрная.
      final b = Board(points: List.filled(24, 0)..[12] = 1..[9] = -1);
      final s = longState(board: b, available: const [3]);
      final moves = BackgammonRules.movesForDie(s, 3);
      // Хода на 9 нет — чужая шашка блокирует (в коротких можно было бы выбить).
      expect(moves.any((m) => m.from == 12 && m.to == 9), isFalse);
    });

    test('можно встать на свободный пункт', () {
      final b = Board(points: List.filled(24, 0)..[12] = 1);
      final s = longState(board: b, available: const [3]);
      final moves = BackgammonRules.movesForDie(s, 3);
      expect(moves.any((m) => m.from == 12 && m.to == 9), isTrue);
    });
  });
}
