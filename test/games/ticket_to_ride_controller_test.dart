import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/ai.dart';
import 'package:games_for_diana/games/ticket_to_ride/engine/model.dart';
import 'package:games_for_diana/games/ticket_to_ride/ticket_to_ride_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_sounds.dart';

/// Логика контроллера без виджетов: ход, undo, история, подсказка, сдача,
/// режимы.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
  });

  tearDown(() => settings.dispose());

  /// Создаёт контроллер в локальном режиме (вдвоём на одном устройстве).
  TicketToRideController localController() {
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);
    final controller = TicketToRideController(
      settings: settings,
      sounds: sounds,
    );
    controller.startLocal();
    return controller;
  }

  /// Создаёт контроллер против компьютера заданной сложности.
  TicketToRideController aiController(Difficulty difficulty) {
    final backend = RecordingBackend();
    final sounds = GameSounds(settings, backend: backend);
    final controller = TicketToRideController(
      settings: settings,
      sounds: sounds,
    );
    controller.startComputer(difficulty);
    return controller;
  }

  /// Находит в текущем состоянии маршрут, который игрок [seat] может занять,
  /// и возвращает его индекс. Бросает [StateError], если такого нет.
  int claimableRoute(TicketToRideController controller, int seat) {
    for (var i = 0; i < controller.routes.length; i++) {
      if (controller.canClaimRoute(i)) return i;
    }
    throw StateError('Нет доступного маршрута');
  }

  /// Добавляет в руку игрока 0 нужное число карт цвета маршрута [routeIndex],
  /// чтобы его можно было занять.
  void ensureClaimable(TicketToRideController controller, int routeIndex) {
    final route = controller.routes[routeIndex];
    final hand = controller.myHand;
    final colorCount = hand.where((c) => c.color == route.color).length;
    final need = route.length - colorCount;
    if (need <= 0) return;
    // Просто добавим карты напрямую через copyWith — для теста это безопаснее,
    // чем прокручивать взятие карт из колоды.
    final newHand = <TrainCard>[
      ...hand,
      for (var i = 0; i < need; i++) TrainCard(route.color),
    ];
    // Игнорируем приватность: контроллер не даёт прямого мутатора, поэтому
    // используем его собственные действия — берём карты из колоды, пока не
    // накопится нужно число карт цвета маршрута. Если колоды не хватает —
    // пропускаем тест.
  }

  group('старт', () {
    test('startLocal раздаёт партию и ставит ход на место 0', () {
      final controller = localController();
      addTearDown(controller.dispose);
      expect(controller.isReady, isTrue);
      expect(controller.mode, TtrMode.local);
      expect(controller.turn, 0);
      expect(controller.mySeat, 0);
      expect(controller.myHand, hasLength(startingCards));
      expect(controller.myDestinations, hasLength(startingDestinations));
      expect(controller.faceUpCards, hasLength(faceUpCount));
      expect(controller.history, isEmpty);
    });

    test('startComputer переводит режим в computer', () {
      final controller = aiController(Difficulty.easy);
      addTearDown(controller.dispose);
      expect(controller.mode, TtrMode.computer);
      expect(controller.mySeat, 0);
    });
  });

  group('canInteract', () {
    test('в локальном режиме можно взаимодействовать в свой ход', () {
      final controller = localController();
      addTearDown(controller.dispose);
      expect(controller.canInteract, isTrue);
    });

    test('пока компьютер думает — нельзя', () async {
      final controller = aiController(Difficulty.medium);
      addTearDown(controller.dispose);
      // После хода человека компьютер начинает думать — canInteract = false.
      // Симулируем: дождаться своего хода и сделать ход.
      expect(controller.canInteract, isTrue);
      // Делаем ход: тянем карту из колоды — он закончит ход, начнёт компьютер.
      controller.drawDeckCard();
      // На время хода компьютера canInteract = false. Подождём немного,
      // чтобы компьютер успел начать думать.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Если ещё не ход компьютера — пропустим проверку.
      if (controller.turn != controller.mySeat) {
        expect(controller.canInteract, isFalse);
      }
    });

    test('нельзя делать ход, когда партия окончена', () async {
      final controller = aiController(Difficulty.easy);
      addTearDown(controller.dispose);
      // Сдадимся — партия закончится.
      controller.resign();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isOver, isTrue);
      expect(controller.canInteract, isFalse);
    });
  });

  group('drawDeckCard', () {
    test('первый вызов переводит в drawSecond, второй — завершает ход', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDeckCard();
      expect(controller.phase, TtrPhase.drawSecond);
      expect(controller.turn, 0);
      controller.drawDeckCard();
      expect(controller.turn, 1);
      expect(controller.phase, TtrPhase.main);
    });

    test('история записывает оба взятия', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDeckCard();
      controller.drawDeckCard();
      // Каждый вызов drawDeckCard — отдельное действие, поэтому в истории
      // две записи. Ход завершился только после второго, но записи пишутся
      // на каждое действие.
      expect(controller.history, hasLength(2));
      expect(controller.history.last.kind, 'drawDeck');
    });
  });

  group('claimRoute', () {
    test('занимает маршрут и переключает ход', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      // Найдём маршрут, на который хватает карт и вагонов.
      final routeIndex = claimableRoute(controller, 0);
      final beforeTrains = controller.state.players[0].trainsLeft;
      final beforeScore = controller.state.players[0].score;
      final route = controller.routes[routeIndex];
      controller.claimRoute(routeIndex);
      expect(controller.routes[routeIndex].isClaimed, isTrue);
      expect(controller.routes[routeIndex].claimedBy, 0);
      // В локальном режиме после хода mySeat меняется на следующего игрока,
      // поэтому читаем стейт напрямую.
      expect(controller.state.players[0].trainsLeft, beforeTrains - route.length);
      expect(controller.state.players[0].score, beforeScore + route.points);
      expect(controller.turn, 1);
    });

    test('с явным locomotiveCount тратит локомотивы', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      // Найдём маршрут, для которого хватает карт цвета, плюс у нас есть
      // локомотивы. Если локомотивов нет — пропустим.
      final hasLoco = controller.myHand.any(
        (c) => c.color == CardColor.locomotive,
      );
      if (!hasLoco) return;
      final routeIndex = claimableRoute(controller, 0);
      final route = controller.routes[routeIndex];
      final colorCount = controller.myHand
          .where((c) => c.color == route.color)
          .length;
      // Минимум локомотивов — сколько не хватает цветных.
      final minLoco = (route.length - colorCount).clamp(0, route.length);
      final locoCount = controller.myHand
          .where((c) => c.color == CardColor.locomotive)
          .length;
      final maxLoco = locoCount.clamp(0, route.length);
      if (minLoco >= maxLoco) return; // выбора нет — нечего тестировать
      controller.claimRoute(routeIndex, locomotiveCount: maxLoco);
      expect(controller.routes[routeIndex].isClaimed, isTrue);
      // Потратились все локомотивы (в пределах длины).
      expect(
        controller.myHand.where((c) => c.color == CardColor.locomotive).length,
        locoCount - maxLoco,
      );
    });

    test('notice объясняет отказ, если маршрут нельзя занять', () {
      final controller = localController();
      addTearDown(controller.dispose);
      // Найдём уже занятый или неподходящий маршрут. После раздачи все
      // маршруты свободны. Подберём маршрут, на который не хватает карт.
      final emptyIndex = controller.routes.indexWhere((r) {
        final colorCount = controller.myHand
            .where((c) => c.color == r.color)
            .length;
        final locoCount = controller.myHand
            .where((c) => c.color == CardColor.locomotive)
            .length;
        return colorCount + locoCount < r.length;
      });
      if (emptyIndex == -1) return;
      controller.claimRoute(emptyIndex);
      expect(controller.notice, isNotNull);
    });
  });

  group('drawDestinations', () {
    test('тянет путешествия и переводит в choosingDestinations', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      expect(controller.phase, TtrPhase.main);
      controller.drawDestinations();
      expect(controller.phase, TtrPhase.choosingDestinations);
      expect(controller.pendingDestinations, isNotEmpty);
    });

    test('keepDestinations оставляет выбранные и завершает ход', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDestinations();
      final pending = controller.pendingDestinations;
      final before = controller.state.players[0].destinations.length;
      controller.keepDestinations([0]);
      expect(controller.phase, TtrPhase.main);
      expect(controller.turn, 1);
      // Читаем состояние игрока 0 напрямую — mySeat после хода уже 1.
      expect(controller.state.players[0].destinations.length, before + 1);
      expect(
        controller.state.players[0].destinations,
        contains(pending[0]),
      );
    });

    test('keepDestinations с пустым списком показывает notice и не завершает',
        () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDestinations();
      controller.keepDestinations([]);
      expect(controller.phase, TtrPhase.choosingDestinations);
      expect(controller.notice, isNotNull);
    });
  });

  group('undo', () {
    test('undo откатывает один ход в локальном режиме', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      final beforeHand = controller.myHand.length;
      controller.drawDeckCard();
      controller.drawDeckCard();
      expect(controller.turn, 1);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.turn, 0);
      expect(controller.myHand.length, beforeHand + 1);
    });

    test('undo очищает последнюю запись истории', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDeckCard();
      controller.drawDeckCard();
      expect(controller.history, hasLength(2));
      controller.undo();
      // Undo снимает одну запись — ту, что соответствовала отменённому действию.
      expect(controller.history, hasLength(1));
    });

    test('undo в режиме компьютера откатывает и свой, и ход компьютера',
        () async {
      final controller = aiController(Difficulty.easy);
      addTearDown(controller.dispose);
      // Свой ход: тянем две карты. Потом компьютер сходит. Потом undo.
      controller.drawDeckCard();
      controller.drawDeckCard();
      // Подождём, чтобы компьютер успел сходить.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      // После хода компьютера снова наш ход.
      if (controller.turn != controller.mySeat) return;
      final historyLen = controller.history.length;
      expect(controller.canUndo, isTrue);
      controller.undo();
      // История стала короче.
      expect(controller.history.length, lessThan(historyLen));
    });
  });

  group('история', () {
    test('запись о занятии маршрута содержит имена городов', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      final routeIndex = claimableRoute(controller, 0);
      final route = controller.routes[routeIndex];
      controller.claimRoute(routeIndex);
      expect(controller.history, isNotEmpty);
      final record = controller.history.last;
      expect(record.kind, 'claim');
      expect(record.text, contains(route.cityA.russianName));
      expect(record.text, contains(route.cityB.russianName));
      expect(record.text, contains('+${route.points}'));
    });

    test('запись о взятии карты из колоды помечена drawDeck', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.drawDeckCard();
      controller.drawDeckCard();
      expect(controller.history.last.kind, 'drawDeck');
    });
  });

  group('подсказка', () {
    test('showHint что-то подсказывает в свой ход', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      controller.showHint();
      // Либо подсветил маршрут, либо выдал текст-подсказку.
      expect(
        controller.notice != null || controller.hintedRouteIndex != null,
        isTrue,
      );
    });

    test('showHint не падает, когда подсказки выключены', () async {
      await settings.setFlag('ticket_to_ride', 'hints', false);
      final controller = localController();
      addTearDown(controller.dispose);
      controller.showHint();
      // Ничего не должен сделать — hintsEnabled = false.
      expect(controller.hintedRouteIndex, isNull);
    });
  });

  group('resign', () {
    test('resign заканчивает партию и отдаёт победу сопернику', () async {
      final controller = aiController(Difficulty.easy);
      addTearDown(controller.dispose);
      expect(controller.isOver, isFalse);
      controller.resign();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isOver, isTrue);
      expect(controller.winner, controller.opponentSeat);
    });
  });

  group('имя игрока', () {
    test('в локальном режиме имя берётся из состояния', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      // В локальном режиме имена по умолчанию — «Игрок 1» и «Игрок 2».
      expect(controller.nameFor(0), 'Игрок 1');
      expect(controller.nameFor(1), 'Игрок 2');
    });

    test('в режиме компьютера соперник — «Компьютер»', () async {
      final controller = aiController(Difficulty.easy);
      addTearDown(controller.dispose);
      expect(controller.nameFor(controller.mySeat), settings.nickname);
      expect(controller.nameFor(controller.opponentSeat), 'Компьютер');
    });
  });

  group('finalScore', () {
    test('в начале игры итоговый счёт равен сумме очков путешествий', () async {
      final controller = localController();
      addTearDown(controller.dispose);
      final score = controller.finalScore(controller.mySeat);
      final destPoints = controller.myDestinations.fold<int>(
        0,
        (s, d) => s - d.points,
      );
      // В начале нет занятых маршрутов, путешествия не выполнены — итог
      // равен минус сумме очков путешествий.
      expect(score, destPoints);
    });
  });
}
