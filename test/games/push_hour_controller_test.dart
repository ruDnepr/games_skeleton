import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/push_hour/engine/levels.dart';
import 'package:games_for_diana/games/push_hour/engine/model.dart';
import 'package:games_for_diana/games/push_hour/engine/rules.dart';
import 'package:games_for_diana/games/push_hour/network.dart';
import 'package:games_for_diana/games/push_hour/progress.dart';
import 'package:games_for_diana/games/push_hour/push_hour_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Контроллер «Push Hour»: ходы, отмена, победа, подсказка и запись прогресса.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;
  late RecordingBackend backend;
  late GameSounds sounds;
  late PushHourProgress progress;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
    backend = RecordingBackend();
    sounds = GameSounds(settings, backend: backend);
    progress = PushHourProgress();
    await progress.load();
  });

  tearDown(() => settings.dispose());

  /// Решает уровень, применяя ходы солвера, и возвращает число ходов.
  int playSolution(PushHourController controller) {
    final solution = RushHourSolver.solve(controller.grid)!;
    // Включаем звук, чтобы backend записал звуки хода и победы.
    settings.sound = true;
    for (final move in solution) {
      final car = controller.grid.carById(move.carId)!;
      final step = move.from.row != move.to.row
          ? (move.to.row > move.from.row ? 1 : -1)
          : (move.to.col > move.from.col ? 1 : -1);
      expect(controller.tryMove(car, step), isTrue);
    }
    return solution.length;
  }

  test('уровень проходится и победа записывается в прогресс', () async {
    final level = levelByNumber(1);
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: level,
    );
    addTearDown(controller.dispose);

    final moves = playSolution(controller);
    expect(controller.solved, isTrue);
    expect(controller.moves, moves);
    expect(backend.played, contains(GameSound.win));
    expect(backend.played, contains(GameSound.move));

    // Прогресс должен сохраниться асинхронно — подождём пару микротасков.
    await Future<void>.delayed(Duration.zero);
    expect(progress.bestFor(1), moves);
    expect(progress.unlockedLevel, 2);
  });

  test('отмена возвращает поле на шаг назад и снимает флаг решения', () {
    final level = levelByNumber(1);
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: level,
    );
    addTearDown(controller.dispose);

    final move = RushHourRules.children(controller.grid).first.$1;
    final car = controller.grid.carById(move.carId)!;
    final step = move.from.row != move.to.row
        ? (move.to.row > move.from.row ? 1 : -1)
        : (move.to.col > move.from.col ? 1 : -1);

    expect(controller.tryMove(car, step), isTrue);
    expect(controller.moves, 1);

    controller.undo();
    expect(controller.moves, 0);
    // Grid не переопределяет ==, поэтому сравниваем машины: после отмены
    // расстановка должна совпадать с исходным уровнем.
    expect(controller.grid.cars, level.grid.cars);
  });

  test('undo на пустой истории не падает и не двигает счётчик', () {
    settings.sound = true;
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: levelByNumber(1),
    );
    addTearDown(controller.dispose);

    controller.undo();
    expect(controller.moves, 0);
    expect(backend.played, contains(GameSound.miss));
  });

  test('restart сбрасывает ходы и историю', () {
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: levelByNumber(1),
    );
    addTearDown(controller.dispose);

    final move = RushHourRules.children(controller.grid).first.$1;
    final car = controller.grid.carById(move.carId)!;
    final step = move.from.row != move.to.row
        ? (move.to.row > move.from.row ? 1 : -1)
        : (move.to.col > move.from.col ? 1 : -1);

    controller.tryMove(car, step);
    controller.tryMove(car, -step);
    expect(controller.moves, 2);

    controller.restart();
    expect(controller.moves, 0);
    expect(controller.history, isEmpty);
    expect(controller.grid.cars, levelByNumber(1).grid.cars);
  });

  test('запрет хода сквозь другую машину', () {
    settings.sound = true;
    const grid = Grid(
      cars: [
        Car(
          id: 'red',
          color: Color(0xFFFF4B4B),
          axis: CarAxis.horizontal,
          length: 2,
          position: Position(2, 0),
        ),
        Car(
          id: 'c1',
          color: Color(0xFF8266D5),
          axis: CarAxis.vertical,
          length: 3,
          position: Position(1, 2),
        ),
        Car(
          id: 'c2',
          color: Color(0xFFFFD66D),
          axis: CarAxis.vertical,
          length: 2,
          position: Position(4, 2),
        ),
      ],
    );

    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: Level(number: 0, grid: grid, minMoves: 0),
    );
    addTearDown(controller.dispose);

    final red = controller.grid.redCar!;
    expect(controller.tryMove(red, 1), isFalse);
    expect(controller.tryMove(red, -1), isFalse);
    expect(controller.moves, 0);
    expect(backend.played, contains(GameSound.miss));
  });

  test('подсказка показывает следующий ход', () {
    settings.sound = true;
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: levelByNumber(10),
    );
    addTearDown(controller.dispose);

    final result = controller.requestHint();
    expect(result, isTrue);
    expect(controller.hint, isNotNull);
    // Первый ход подсказки совпадает с первым ходом солвера.
    expect(controller.hint, RushHourSolver.hint(controller.grid));
    expect(backend.played, contains(GameSound.guess));
  });

  test('запрет хода после победы', () {
    final level = levelByNumber(1);
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: level,
    );
    addTearDown(controller.dispose);

    playSolution(controller);
    expect(controller.solved, isTrue);

    final red = controller.grid.redCar!;
    expect(controller.tryMove(red, -1), isFalse);
    controller.undo();
    expect(controller.solved, isTrue);
  });

  test('goToNextLevel переключает на следующий уровень', () {
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: levelByNumber(1),
    );
    addTearDown(controller.dispose);

    expect(controller.goToNextLevel(), isTrue);
    expect(controller.level.number, 2);
    expect(controller.moves, 0);
    expect(controller.solved, isFalse);
  });

  test('последний уровень не открывает следующий', () {
    final controller = PushHourController(
      settings: settings,
      sounds: sounds,
      progress: progress,
      level: levelByNumber(campaignSize),
    );
    addTearDown(controller.dispose);

    expect(controller.hasNextLevel, isFalse);
    expect(controller.goToNextLevel(), isFalse);
  });

  test('звёзды: 3 — за минимум, 2 — за небольшой перебор, 1 — за проход', () {
    final level = levelByNumber(1);
    final minMoves = level.minMoves;
    expect(progress.stars(1, minMoves), 3);
    expect(progress.stars(1, minMoves + 2), 2);
    expect(progress.stars(1, minMoves + 10), 1);
  });

  test('опции лобби прижимают номер уровня к границам', () {
    expect(pushHourParseOptions({'level': 999}), campaignSize);
    expect(pushHourParseOptions({'level': 0}), 1);
    expect(pushHourParseOptions({'level': 7}), 7);
    expect(pushHourParseOptions(const {}), 1);
    expect(
      () => pushHourParseOptions({'level': 'x'}),
      throwsFormatException,
    );
    expect(
      () => pushHourParseOptions({'level': 1, 'extra': 0}),
      throwsFormatException,
    );
  });

  test('проверка хода Push Hour', () {
    pushHourValidateMove({'from': 0, 'to': 1});
    pushHourValidateMove({'from': 7, 'to': 13});
    expect(
      () => pushHourValidateMove({'from': -1, 'to': 1}),
      throwsFormatException,
    );
    expect(
      () => pushHourValidateMove({'from': 0, 'to': 40}),
      throwsFormatException,
    );
    expect(
      () => pushHourValidateMove({'from': 0, 'to': 8}),
      throwsFormatException,
    );
    expect(
      () => pushHourValidateMove({'from': 'a', 'to': 1}),
      throwsFormatException,
    );
  });
}
