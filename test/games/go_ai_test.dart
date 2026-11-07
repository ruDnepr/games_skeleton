// Тесты ИИ го: три уровня сложности делают осмысленные и легальные ходы.
// Лёгкий иногда «не замечает» простой захват, средний хватает и спасает,
// сложный думает за разумное время. Адаптировано из оригинального
// `packages/go_engine/test/go_engine_test.dart`.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/go/engine/ai.dart';
import 'package:games_for_diana/games/go/engine/model.dart';
import 'package:games_for_diana/games/go/engine/rules.dart';

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

void main() {
  group('лёгкий ИИ', () {
    test('не делает запрещённых ходов', () {
      final r = CaptureGoRules(captureSetup());
      final ai = GoAI(random: _FixedRandom());
      for (var i = 0; i < 20; i++) {
        var s = GameState.initial(r.setup);
        var guard = 0;
        while (!r.isOver(s) && guard < 40) {
          final p = ai.findBestMove(s, r, Difficulty.easy);
          if (p == null) break;
          expect(r.isValidMove(s, GoMove.place(p, color: s.turn)), isTrue);
          s = r.applyMove(s, GoMove.place(p, color: s.turn));
          guard++;
        }
      }
    });

    test('в «Захвате» даёт ребёнку шанс (не всегда хватает камень)', () {
      final r = CaptureGoRules(captureSetup(target: CaptureTarget.one));
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      // У чёрных есть выигрывающий ход — (0,1) снимает белого. Лёгкий ИИ
      // иногда его «не замечает».
      var missedCapture = false;
      final ai = GoAI(); // случайный
      for (var i = 0; i < 60; i++) {
        final p = ai.findBestMove(s, r, Difficulty.easy);
        if (p != const Point(0, 1)) {
          missedCapture = true;
          break;
        }
      }
      expect(
        missedCapture,
        isTrue,
        reason: 'Лёгкий ИИ должен иногда пропускать простой захват',
      );
    });
  });

  group('средний ИИ', () {
    test('захватывает, когда может', () {
      final r = CaptureGoRules(captureSetup());
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.white,
          const Point(1, 0): StoneColor.black,
        }),
        turn: StoneColor.black,
      );
      final ai = GoAI(random: _FixedRandom());
      final p = ai.findBestMove(s, r, Difficulty.medium);
      expect(p, const Point(0, 1));
    });

    test('спасает группу в атари', () {
      final r = CaptureGoRules(captureSetup());
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(2, 2): StoneColor.black,
          const Point(1, 2): StoneColor.white,
          const Point(2, 1): StoneColor.white,
          const Point(2, 3): StoneColor.white,
        }),
        turn: StoneColor.black,
      );
      final g = GoRules.groupAt(s.board, const Point(2, 2))!;
      expect(g.inAtari, isTrue);
      final ai = GoAI(random: _FixedRandom());
      final p = ai.findBestMove(s, r, Difficulty.medium);
      expect(p, const Point(3, 2));
    });
  });

  group('сложный ИИ', () {
    test('делает осмысленный и легальный ход за разумное время', () {
      final r = CaptureGoRules(captureSetup());
      final s = GameState.initial(r.setup);
      final ai = GoAI(random: _FixedRandom());
      final sw = Stopwatch()..start();
      final p = ai.findBestMove(
        s,
        r,
        Difficulty.hard,
        timeLimit: const Duration(milliseconds: 800),
      );
      sw.stop();
      expect(p, isNotNull);
      expect(r.isValidMove(s, GoMove.place(p!, color: s.turn)), isTrue);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('защищается и не проигрывает мгновенно в «Захвате 1»', () {
      final r = CaptureGoRules(captureSetup(target: CaptureTarget.one));
      final s = GameState(
        setup: r.setup,
        board: Board(9, {
          const Point(0, 0): StoneColor.black,
          const Point(1, 0): StoneColor.white,
          const Point(0, 1): StoneColor.white,
        }),
        turn: StoneColor.black,
      );
      final ai = GoAI(random: _FixedRandom());
      final p = ai.findBestMove(
        s,
        r,
        Difficulty.hard,
        timeLimit: const Duration(milliseconds: 700),
      );
      expect(p, isNotNull);
      final next = r.applyMove(s, GoMove.place(p!, color: StoneColor.black));
      // После хода ИИ чёрные не должны быть сняты (партия не проиграна).
      expect(
        next.board.occupied(const Point(0, 0)) || next.whiteCaptured == 0,
        isTrue,
      );
    });
  });
}

/// Детерминированный Random для воспроизводимых тестов ИИ.
class _FixedRandom implements Random {
  int _seed = 12345;
  @override
  int nextInt(int max) {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed % max;
  }

  @override
  double nextDouble() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return (_seed % 100000) / 100000;
  }

  @override
  bool nextBool() => nextDouble() > 0.5;
}
