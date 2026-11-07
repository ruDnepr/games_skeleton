// Полный набор тестов движка го. Покрывает: группы и дыхания, захват, запрет
// самоубийства, правило ко, оба режима (Захват / Классическое го), подсчёт
// территории с коми — то, что в оригинальной «Го для Дианы» лежало в
// `packages/go_engine/test/go_engine_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/go/engine/model.dart';
import 'package:games_for_diana/games/go/engine/rules.dart';
import 'package:games_for_diana/games/go/engine/scoring.dart';

GameSetup captureSetup({
  int size = 9,
  CaptureTarget target = CaptureTarget.one,
}) =>
    GameSetup(
      mode: GoMode.capture,
      boardSize: size,
      captureTarget: target,
      komi: GameSetup.defaultKomi(size),
    );

GameSetup classicSetup({int size = 9, double komi = 6.5}) =>
    GameSetup(mode: GoMode.classic, boardSize: size, komi: komi);

void main() {
  // ----------------------- Группы и дыхания -----------------------

  group('группы и дыхания', () {
    test('одиночный камень в углу — 2 дыхания', () {
      final b = Board(9, {const Point(0, 0): StoneColor.black});
      final g = GoRules.groupAt(b, const Point(0, 0))!;
      expect(g.stones.length, 1);
      expect(g.libertyCount, 2);
    });

    test('одиночный камень на краю — 3 дыхания', () {
      final b = Board(9, {const Point(4, 0): StoneColor.black});
      expect(GoRules.groupAt(b, const Point(4, 0))!.libertyCount, 3);
    });

    test('одиночный камень в центре — 4 дыхания', () {
      final b = Board(9, {const Point(4, 4): StoneColor.black});
      expect(GoRules.groupAt(b, const Point(4, 4))!.libertyCount, 4);
    });

    test('группа из двух камней делит дыхания', () {
      final b = Board(9, {
        const Point(4, 4): StoneColor.black,
        const Point(5, 4): StoneColor.black,
      });
      final g = GoRules.groupAt(b, const Point(4, 4))!;
      expect(g.stones.length, 2);
      expect(g.libertyCount, 6);
    });

    test('группа в атари (одно дыхание)', () {
      final b = Board(9, {
        const Point(0, 0): StoneColor.white,
        const Point(1, 0): StoneColor.black,
      });
      final g = GoRules.groupAt(b, const Point(0, 0))!;
      expect(g.inAtari, isTrue);
      expect(g.libertyCount, 1);
    });
  });

  // ----------------------- Захват -----------------------

  group('захват', () {
    test('белые в углу снимаются последним ходом', () {
      final r = CaptureGoRules(captureSetup());
      var s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      s = r.applyMove(
        s,
        GoMove.place(const Point(0, 1), color: StoneColor.black),
      );
      expect(s.board.occupied(const Point(0, 0)), isFalse);
      expect(s.blackCaptured, 1);
      expect(s.whiteCaptured, 0);
    });

    test('группа из двух камней снимается целиком', () {
      final r = CaptureGoRules(captureSetup());
      var s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(0, 1): StoneColor.white,
          const Point(1, 0): StoneColor.black,
          const Point(1, 1): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      s = r.applyMove(
        s,
        GoMove.place(const Point(0, 2), color: StoneColor.black),
      );
      expect(s.board.occupied(const Point(0, 0)), isFalse);
      expect(s.board.occupied(const Point(0, 1)), isFalse);
      expect(s.blackCaptured, 2);
    });
  });

  // ----------------------- Самоубийство -----------------------

  group('самоубийство', () {
    test('запрещено: нельзя поставить камень без дыханий', () {
      final r = CaptureGoRules(captureSetup());
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(1, 0): StoneColor.black,
          const Point(0, 1): StoneColor.black,
        }),
        turn: StoneColor.white,
      );
      expect(
        r.isValidMove(
          s,
          GoMove.place(const Point(0, 0), color: StoneColor.white),
        ),
        isFalse,
      );
    });

    test('разрешено, если этим ходом захватывается соперник', () {
      final r = CaptureGoRules(captureSetup());
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.black,
          const Point(1, 1): StoneColor.white,
          const Point(1, 0): StoneColor.white,
        }),
        turn: StoneColor.white,
      );
      // Чёрный (0,0) в атари: дыхание (0,1). Белые ставят (0,1) — снимают
      // чёрного.
      final move = GoMove.place(const Point(0, 1), color: StoneColor.white);
      expect(r.isValidMove(s, move), isTrue);
      final next = r.applyMove(s, move);
      expect(next.board.occupied(const Point(0, 0)), isFalse);
      expect(next.whiteCaptured, 1);
    });
  });

  // ----------------------- Правило ко -----------------------

  group('правило ко', () {
    // Классическая форма ко: чёрные окружают белый (4,4) с трёх сторон,
    // единственное дыхание — (5,4). Чёрные играют (5,4), снимают белый,
    // и сами оказываются в атари — тогда (4,4) становится запрещённой
    // точкой.
    final koState = GameState(
      setup: GameSetup(mode: GoMode.capture, boardSize: 9),
      board: Board(9, {
        const Point(3, 4): StoneColor.black,
        const Point(4, 3): StoneColor.black,
        const Point(4, 5): StoneColor.black,
        const Point(4, 4): StoneColor.white,
        const Point(6, 4): StoneColor.white,
        const Point(5, 3): StoneColor.white,
        const Point(5, 5): StoneColor.white,
      }),
      turn: StoneColor.black,
    );

    test('немедленный откат запрещён', () {
      final r = CaptureGoRules(captureSetup());
      final next = r.applyMove(
        koState,
        GoMove.place(const Point(5, 4), color: StoneColor.black),
      );
      expect(
        r.isValidMove(
          next,
          GoMove.place(const Point(4, 4), color: StoneColor.white),
        ),
        isFalse,
      );
    });

    test('ко-точка устанавливается после снятия одного камня', () {
      final r = CaptureGoRules(captureSetup());
      final next = r.applyMove(
        koState,
        GoMove.place(const Point(5, 4), color: StoneColor.black),
      );
      expect(next.board.occupied(const Point(4, 4)), isFalse);
      expect(next.koPoint, const Point(4, 4));
      expect(next.blackCaptured, 1);
      expect(
        r.isValidMove(
          next,
          GoMove.place(const Point(4, 4), color: StoneColor.white),
        ),
        isFalse,
      );
      expect(r.legalPlacements(next).contains(const Point(4, 4)), isFalse);
    });
  });

  // ----------------------- Режим «Захват» -----------------------

  group('режим «Захват»', () {
    test('победа по первому захвату', () {
      final r = CaptureGoRules(captureSetup(target: CaptureTarget.one));
      var s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      expect(r.isOver(s), isFalse);
      s = r.applyMove(
        s,
        GoMove.place(const Point(0, 1), color: StoneColor.black),
      );
      expect(r.isOver(s), isTrue);
      expect(r.winner(s), StoneColor.black);
    });

    test('цель — три камня: партия не заканчивается на первом', () {
      final r = CaptureGoRules(captureSetup(target: CaptureTarget.three));
      var s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      s = r.applyMove(
        s,
        GoMove.place(const Point(0, 1), color: StoneColor.black),
      );
      expect(r.isOver(s), isFalse);
      expect(s.blackCaptured, 1);
    });

    test('пас допустим и не меняет счётчик захватов', () {
      final r = CaptureGoRules(captureSetup());
      var s = GameState.initial(r.setup);
      s = r.applyMove(s, GoMove.pass(color: StoneColor.black));
      expect(s.turn, StoneColor.white);
      expect(s.consecutivePasses, 1);
      expect(s.blackCaptured, 0);
    });
  });

  // ----------------------- Классическое го -----------------------

  group('классическое го', () {
    test('два паса подряд заканчивают партию', () {
      final r = ClassicGoRules(classicSetup());
      var s = GameState.initial(r.setup);
      s = r.applyMove(s, GoMove.pass(color: StoneColor.black));
      expect(r.isOver(s), isFalse);
      s = r.applyMove(s, GoMove.pass(color: StoneColor.white));
      expect(r.isOver(s), isTrue);
    });

    test('подсчёт территории: чёрные окружают угол', () {
      final r = ClassicGoRules(classicSetup(komi: 6.5));
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(1, 0): StoneColor.black,
          const Point(0, 1): StoneColor.black,
          const Point(1, 1): StoneColor.black,
        }),
        turn: StoneColor.white,
        consecutivePasses: 2,
      );
      expect(r.isOver(s), isTrue);
      final score = r.score(s)!;
      expect(score.blackTerritory, greaterThanOrEqualTo(1));
      expect(score.komi, 6.5);
    });

    test('коми добавляется белым', () {
      final r = ClassicGoRules(classicSetup(komi: 7.5));
      final s = GameState(
        setup: r.setup,
        board: Board.empty(9),
        turn: StoneColor.black,
        consecutivePasses: 2,
      );
      final score = r.score(s)!;
      expect(score.whiteScore, 7.5);
      expect(score.blackScore, 0);
      expect(score.leader, StoneColor.white);
    });

    test('дамэ (нейтральная область) не считается ничьей территорией', () {
      final r = ClassicGoRules(classicSetup());
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.black,
          const Point(0, 2): StoneColor.white,
        }),
        turn: StoneColor.black,
        consecutivePasses: 2,
      );
      final score = r.score(s)!;
      expect(score.blackTerritory + score.whiteTerritory, 0);
    });
  });

  // ----------------------- Сериализация -----------------------

  group('сериализация', () {
    test('GoMove пасс сериализуется', () {
      final m = GoMove.pass(color: StoneColor.white);
      final back = GoMove.fromJson(m.toJson());
      expect(back.isPass, isTrue);
      expect(back.color, StoneColor.white);
    });

    test('GoMove постановки сериализуется', () {
      final m = GoMove.place(const Point(4, 4), color: StoneColor.black);
      final back = GoMove.fromJson(m.toJson());
      expect(back.point, const Point(4, 4));
      expect(back.color, StoneColor.black);
    });

    test('Point сериализуется парой целых', () {
      const p = Point(3, 7);
      expect(p.toJson(), [3, 7]);
      expect(Point.fromJson([3, 7]), p);
    });
  });
}
