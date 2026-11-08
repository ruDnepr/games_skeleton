import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/rendzu/engine/model.dart';
import 'package:games_for_diana/games/rendzu/rendzu_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Логика контроллера без виджетов: ход, запрещённый ход, отмена, подсказка,
/// сдача — как в оригинальном game_state_test, но через контроллер каркаса.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;
  late RecordingBackend backend;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
    backend = RecordingBackend();
  });

  tearDown(() => settings.dispose());

  /// Создаёт контроллер для локальной партии (два игрока на одном устройстве).
  RendzuController localController({
    Ruleset ruleset = Ruleset.gomoku,
    BoardSize boardSize = BoardSize.small9,
  }) {
    final controller = RendzuController(
      settings: settings,
      sounds: GameSounds(settings, backend: backend),
      ruleset: ruleset,
      boardSize: boardSize,
    );
    controller.startLocal();
    return controller;
  }

  group('RendzuController — базовое', () {
    test('начальное состояние: чёрные ходят, доска пуста', () {
      final c = localController();
      addTearDown(c.dispose);
      expect(c.currentColor, StoneColor.black);
      expect(c.board.isEmpty, isTrue);
      expect(c.isOver, isFalse);
      expect(c.moveNumber, 0);
    });

    test('ход ставит камень и передаёт очередь', () {
      final c = localController();
      addTearDown(c.dispose);
      c.tap(const Point(4, 4));
      expect(c.board.at(const Point(4, 4)), StoneColor.black);
      expect(c.currentColor, StoneColor.white);
      expect(c.moveNumber, 1);
      expect(c.lastMove, const Point(4, 4));
    });

    test('ход в занятую клетку отклоняется молча', () {
      final c = localController();
      addTearDown(c.dispose);
      c.tap(const Point(4, 4));
      // повторный ход в ту же точку — ничего не происходит
      c.tap(const Point(4, 4));
      expect(c.moveNumber, 1);
      expect(c.currentColor, StoneColor.white);
    });
  });

  group('RendzuController — победа', () {
    test('гомоку: пять в ряд → победа', () {
      final c = localController(ruleset: Ruleset.gomoku);
      addTearDown(c.dispose);
      c.tap(const Point(0, 0)); // ч
      c.tap(const Point(8, 8)); // б
      c.tap(const Point(1, 0)); // ч
      c.tap(const Point(7, 7)); // б
      c.tap(const Point(2, 0)); // ч
      c.tap(const Point(6, 6)); // б
      c.tap(const Point(3, 0)); // ч
      c.tap(const Point(5, 5)); // б
      c.tap(const Point(4, 0)); // ч — пять!
      expect(c.isOver, isTrue);
      expect(c.winnerColor, StoneColor.black);
      expect(c.winningLine.length, 5);
    });
  });

  group('RendzuController — запрещённый ход отклоняется (рэндзю)', () {
    test('3-3 отклоняется, доска не меняется', () {
      final c = localController(
        ruleset: Ruleset.renju,
        boardSize: BoardSize.standard15,
      );
      addTearDown(c.dispose);
      // чёрные ставят камни для подготовки 3-3 в (7,7)
      c.tap(const Point(5, 7)); // ч
      c.tap(const Point(0, 0)); // б
      c.tap(const Point(6, 7)); // ч
      c.tap(const Point(0, 1)); // б
      c.tap(const Point(7, 5)); // ч
      c.tap(const Point(0, 2)); // б
      c.tap(const Point(7, 6)); // ч
      c.tap(const Point(0, 3)); // б
      // теперь ход чёрных, и (7,7) — запрещённый (3-3)
      c.tap(const Point(7, 7));
      expect(c.board.at(const Point(7, 7)), isNull,
          reason: 'Запрещённый ход не должен ставиться на доску');
      expect(c.warning, isNotNull);
      expect(c.moveNumber, 8, reason: 'Запрещённый ход не увеличивает историю');
    });
  });

  group('RendzuController — отмена хода', () {
    test('undo убирает последний камень', () {
      final c = localController();
      addTearDown(c.dispose);
      c.tap(const Point(4, 4));
      expect(c.board.at(const Point(4, 4)), StoneColor.black);
      c.undo();
      expect(c.board.at(const Point(4, 4)), isNull);
      expect(c.moveNumber, 0);
    });

    test('undo на пустой доске — ничего не делает', () {
      final c = localController();
      addTearDown(c.dispose);
      c.undo();
      expect(c.moveNumber, 0);
    });
  });

  group('RendzuController — подсказка', () {
    test('showHint возвращает центр на пустой доске', () {
      final c = localController();
      addTearDown(c.dispose);
      c.showHint();
      expect(c.hintPoint, const Point(4, 4));
    });

    test('showHint возвращает точку рядом с камнями', () {
      final c = localController();
      addTearDown(c.dispose);
      c.tap(const Point(4, 4));
      c.showHint();
      // после хода белых подсказка для белых — рядом с (4,4)
      expect(c.hintPoint, isNotNull);
      final h = c.hintPoint!;
      expect((h.x - 4).abs() + (h.y - 4).abs(), lessThanOrEqualTo(2));
    });
  });

  group('RendzuController — сдача', () {
    test('resign отдаёт победу сопернику', () {
      final c = localController();
      addTearDown(c.dispose);
      c.tap(const Point(4, 4)); // чёрные сходили
      // теперь белые, сдадутся
      c.resign();
      expect(c.isOver, isTrue);
      expect(c.winnerColor, StoneColor.black,
          reason: 'Сдаются белые — побеждают чёрные');
    });
  });

  group('RendzuController — canInteract', () {
    test('в локальном режиме можно ходить, пока партия не окончена', () {
      final c = localController();
      addTearDown(c.dispose);
      expect(c.canInteract, isTrue);
      c.resign();
      expect(c.canInteract, isFalse);
    });
  });
}
