import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/loto/loto_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Логика контроллера без виджетов: авто-вытягивание, ожидание ребёнка,
/// подсказки, отмена, победа и режим двух игроков. Повторяет оригинальный
/// `test/application/game_controller_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;
  late RecordingBackend backend;
  late GameSounds sounds;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
    backend = RecordingBackend();
    sounds = GameSounds(settings, backend: backend);
  });

  tearDown(() => settings.dispose());

  const fast = Duration(milliseconds: 5);

  GameSetup setupFor(LotoMode mode, {int seed = 3}) => GameSetup(
    mode: mode,
    seed: seed,
    opponentName: mode == LotoMode.computerHost ? 'Компьютер' : 'Друг',
    firstDrawDelay: fast,
    drawDelay: fast,
    rivalReaction: fast,
  );

  /// Ждёт, пока условие станет верным, давая настоящим таймерам идти.
  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Условие не наступило за $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
  }

  test('компьютер-ведущий тянет бочонки и играет за соперника', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    settings.sound = true;
    controller.start(setupFor(LotoMode.computerHost));
    expect(controller.game.players, hasLength(2));
    expect(controller.others.single.isComputer, isTrue);
    await waitUntil(() => controller.game.drawn.isNotEmpty);
    expect(backend.played, contains(GameSound.guess));
  });

  test('ведущий ждёт, пока ребёнок закроет свой бочонок', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    // Ищем удачную раздачу: первый бочонок должен лежать на моей карточке.
    var seed = 1;
    while (true) {
      controller.start(setupFor(LotoMode.computerHost, seed: seed));
      if (controller.me!.card.contains(controller.game.bag.next!)) break;
      seed++;
      expect(seed, lessThan(500), reason: 'не нашли подходящую раздачу');
    }
    await waitUntil(() => controller.game.drawn.length == 1);
    final barrel = controller.lastBarrel!.number;
    expect(controller.myPendingBarrel, barrel);
    // Пока число не закрыто, следующий бочонок не появляется.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.game.drawn, hasLength(1));
    controller.closeMine(barrel);
    await waitUntil(() => controller.game.drawn.length > 1);
  });

  test('ведущий-человек тянет бочонки только по кнопке', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.humanHost));
    expect(controller.canDrawManually, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller.game.drawn, isEmpty);
    controller.drawBarrel();
    expect(controller.game.drawn, hasLength(1));
  });

  test('подсказка подсвечивает числа и снимается повторным нажатием', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.humanHost));
    var guard = 0;
    while (controller.myClosable.isEmpty) {
      controller.drawBarrel();
      if (++guard > 40) fail('на карточку так и не пришёл бочонок');
    }
    final closable = controller.myClosable;
    controller.toggleHint();
    expect(controller.hintHighlight, closable.toSet());
    expect(controller.notice, contains('Можно закрыть'));
    controller.toggleHint();
    expect(controller.hintHighlight, isEmpty);
  });

  test('отмена хода возвращает бочонок в мешок', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.humanHost));
    controller.drawBarrel();
    final first = controller.game.drawn.first;
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.game.drawn, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(controller.notice, contains('Ход отменён'));
    // Следующий бочонок — тот же: мешок вернулся вместе с ним.
    controller.drawBarrel();
    expect(controller.game.drawn, [first]);
  });

  test('закрыть невытянутое число нельзя, и об этом есть подсказка', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.humanHost));
    final card = controller.me!.card;
    controller.closeMine(card.numbers.first);
    expect(controller.me!.closed, isEmpty);
    expect(controller.notice, 'Этот бочонок ещё в мешке');
    expect(controller.noticeWarning, isTrue);
  });

  test('победа по строке записывается в статистику', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    expect(settings.gamesPlayed, 0);
    controller.start(setupFor(LotoMode.twoPlayers, seed: 4));
    var guard = 0;
    while (!controller.isOver) {
      final barrel = controller.lastBarrel;
      if (barrel != null) {
        for (final player in controller.game.pendingClosers.toList()) {
          controller.close(playerId: player.id, number: barrel.number);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 4));
      if (++guard > 400) fail('партия не закончилась');
    }
    expect(controller.winner, isNotNull);
    expect(controller.game.winningRow, isNotNull);
    await waitUntil(() => settings.gamesPlayed == 1);
    expect(settings.gamesPlayed, 1);
  });

  test('два игрока на одном устройстве видят обе карточки', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.twoPlayers));
    expect(controller.game.players, hasLength(2));
    expect(controller.others, hasLength(1));
    expect(controller.others.single.name, 'Друг');
    expect(
      controller.game.players.every((player) => player.isHuman),
      isTrue,
    );
  });

  test('сдача в режиме против компьютера отдаёт победу сопернику', () async {
    final controller = LotoController(settings: settings, sounds: sounds);
    addTearDown(controller.dispose);
    controller.start(setupFor(LotoMode.computerHost));
    expect(controller.canResign, isTrue);
    controller.resign();
    expect(controller.isOver, isTrue);
    expect(controller.winner?.id, 'rival');
    expect(controller.iWon, isFalse);
  });
}
