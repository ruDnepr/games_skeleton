import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/loto/engine/model.dart';

LotoCard myCard() => LotoCard.fromJson(const {
  'rows': [
    [3, 12, 21, 34, 45, null, null, null, null],
    [null, null, null, null, 47, 52, 61, 78, 88],
    [7, null, null, 38, null, 56, 66, null, 89],
  ],
});

LotoCard rivalCard() => LotoCard.fromJson(const {
  'rows': [
    [5, null, null, 31, null, 50, null, 71, 80],
    [null, 15, 25, null, 44, null, 65, null, 85],
    [9, 19, null, 39, null, null, null, 79, 90],
  ],
});

LotoPlayer player(String id, {bool computer = false, LotoCard? card}) =>
    LotoPlayer(
      id: id,
      name: id,
      card: card ?? myCard(),
      isComputer: computer,
    );

/// Порядок мешка, в котором сначала идут числа карточки: так тест сам решает,
/// какой бочонок вытянут следующим.
List<int> bagOrderFor(LotoCard card) => [
  ...card.numbers,
  for (var number = 1; number <= 90; number++)
    if (!card.contains(number)) number,
];

/// Мешок, бочонки, партия и победа — неизменяемое состояние и его копии.
void main() {
  test('в мешке ровно девяносто разных бочонков', () {
    var bag = BarrelBag.shuffled();
    expect(bag.remaining, 90);
    final drawn = <int>[];
    while (!bag.isEmpty) {
      drawn.add(bag.next!);
      bag = bag.take();
    }
    expect(drawn, hasLength(90));
    expect(drawn.toSet(), hasLength(90));
    expect(drawn.reduce((a, b) => a < b ? a : b), 1);
    expect(drawn.reduce((a, b) => a > b ? a : b), 90);
    expect(bag.next, isNull);
  });

  test('порядок мешка можно задать — это нужно тестам и отмене хода', () {
    final bag = BarrelBag.fromOrder([7, 42, 90]);
    expect(bag.left, [7, 42, 90]);
    expect(bag.take().left, [42, 90]);
    expect(bag.take().take().take().isEmpty, isTrue);
    expect(() => BarrelBag.fromOrder([0]), throwsArgumentError);
    expect(() => BarrelBag.fromOrder([91]), throwsArgumentError);
    expect(() => BarrelBag.fromOrder([5, 5]), throwsArgumentError);
  });

  test('бочонок знает своё число и прибаутку', () {
    expect(const Barrel(11).announcement, '11 — барабанные палочки');
    expect(const Barrel(11).nickname, 'барабанные палочки');
    expect(const Barrel(15).announcement, 'Бочонок 15');
    expect(const Barrel(7).announcement, '7 — кочерга');
    expect(const Barrel(1).isValid, isTrue);
    expect(const Barrel(90).isValid, isTrue);
    expect(const Barrel(91).isValid, isFalse);
    expect(const Barrel(11), const Barrel(11));
    expect(const Barrel(11).hashCode, const Barrel(11).hashCode);
  });

  test('все прозвища — для настоящих бочонков и не пустые', () {
    for (final entry in barrelNicknames.entries) {
      expect(entry.key, inInclusiveRange(Barrel.min, Barrel.max));
      expect(entry.value.trim(), isNotEmpty);
      expect(entry.value, isNot(contains('  ')));
    }
    expect(barrelNicknames, hasLength(greaterThan(30)));
    for (var number = 1; number <= 90; number++) {
      expect(() => Barrel(number).announcement, returnsNormally);
    }
  });

  test('девяносто вытянутых бочонков не повторяются', () {
    var game = LotoGame.start(
      players: [player('you'), player('rival', computer: true)],
      winMode: WinMode.fullCard,
    );
    for (var index = 0; index < BarrelBag.total; index++) {
      game = game.draw();
    }
    expect(game.drawn, hasLength(90));
    expect(game.drawn.toSet(), hasLength(90));
    expect(game.bag.isEmpty, isTrue);
    expect(game.isBagEmpty, isTrue);
    expect(game.barrelsLeft, 0);
    // Девяносто первый бочонок не появится: состояние не меняется.
    expect(identical(game.draw(), game), isTrue);
  });

  test('партия помнит последний бочонок и ждёт, кто его закроет', () {
    var game = LotoGame.start(
      players: [
        player('you'),
        player('rival', computer: true, card: rivalCard()),
      ],
      winMode: WinMode.row,
      bag: BarrelBag.fromOrder(bagOrderFor(myCard())),
    );
    game = game.draw();
    expect(game.lastBarrel?.number, 3);
    expect(game.pendingClosers.map((player) => player.id), ['you']);
    expect(game.waitsForPlayers, isTrue);
  });

  test('закрытие числа проверяется правилами', () {
    var game = LotoGame.start(
      players: [player('you'), player('rival', card: rivalCard())],
      winMode: WinMode.row,
      bag: BarrelBag.fromOrder(bagOrderFor(myCard())),
    );
    // Число ещё в мешке.
    expect(
      game.close(playerId: 'you', number: 3).status,
      CloseStatus.notDrawn,
    );
    game = game.draw();
    // Чужое число.
    expect(
      game.close(playerId: 'you', number: 5).status,
      CloseStatus.notOnCard,
    );
    // Такого игрока нет.
    expect(
      game.close(playerId: 'nobody', number: 3).status,
      CloseStatus.unknownPlayer,
    );
    final open = game.close(playerId: 'you', number: 3);
    expect(open.status, CloseStatus.closed);
    expect(open.game.playerById('you')!.closed, {3});
    expect(
      open.game.close(playerId: 'you', number: 3).status,
      CloseStatus.alreadyClosed,
    );
  });

  test('победа по строке объявляется сразу после пятого числа', () {
    var game = LotoGame.start(
      players: [player('you'), player('rival', card: rivalCard())],
      winMode: WinMode.row,
      bag: BarrelBag.fromOrder(bagOrderFor(myCard())),
    );
    for (final number in [3, 12, 21, 34]) {
      while (game.lastBarrel?.number != number) {
        game = game.draw();
      }
      game = game.close(playerId: 'you', number: number).game;
      expect(game.isOver, isFalse);
    }
    while (game.lastBarrel?.number != 45) {
      game = game.draw();
    }
    final outcome = game.close(playerId: 'you', number: 45);
    expect(outcome.accepted, isTrue);
    expect(outcome.game.isOver, isTrue);
    expect(outcome.game.winner?.id, 'you');
    expect(outcome.game.winningRow, 0);
    // В закрытой партии больше ничего не закрыть.
    expect(
      outcome.game.close(playerId: 'you', number: 47).status,
      CloseStatus.gameOver,
    );
  });

  test('победа по всей карточке требует все пятнадцать чисел', () {
    var game = LotoGame.start(
      players: [player('you')],
      winMode: WinMode.fullCard,
      bag: BarrelBag.fromOrder(bagOrderFor(myCard())),
    );
    final numbers = myCard().numbers.toList();
    for (var index = 0; index < numbers.length; index++) {
      final number = numbers[index];
      while (game.lastBarrel?.number != number) {
        game = game.draw();
      }
      game = game.close(playerId: 'you', number: number).game;
      if (index < numbers.length - 1) expect(game.isOver, isFalse);
    }
    expect(game.isOver, isTrue);
  });

  test('состояние партии неизменяемое: отмена — это возврат копии', () {
    final before = LotoGame.start(
      players: [player('you')],
      winMode: WinMode.row,
      bag: BarrelBag.fromOrder(bagOrderFor(myCard())),
    );
    final after = before.draw();
    expect(before.drawn, isEmpty);
    expect(after.drawn, [3]);
    expect(after.bag.remaining, before.bag.remaining - 1);
    final closed = after.close(playerId: 'you', number: 3).game;
    expect(closed.playerById('you')!.closed, {3});
    // Возврат к состоянию до хода возвращает и мешок, и жетоны.
    expect(after.playerById('you')!.closed, isEmpty);
    expect(after.lastBarrel?.number, 3);
  });

  test('копия партии на другом устройстве знает историю и победителя', () {
    final replica = LotoGame.replica(
      players: [player('you'), player('rival', card: rivalCard())],
      winMode: WinMode.row,
      drawn: const [3, 12, 21, 34, 45],
      winnerId: 'you',
      winningRow: 0,
    );
    expect(replica.drawn, hasLength(5));
    expect(replica.barrelsLeft, 85);
    expect(replica.isOver, isTrue);
    expect(replica.winner?.id, 'you');
    expect(replica.winningRow, 0);
    expect(replica.indexOf('rival'), 1);
    expect(replica.indexOf('nobody'), -1);
    expect(replica.playerById('nobody'), isNull);
  });

  test('объявленный бочонок попадает в историю и на карточку', () {
    final game = LotoGame.replica(
      players: [player('you')],
      winMode: WinMode.row,
      drawn: const [3],
    );
    final announced = game.announce(12);
    expect(announced.drawn, [3, 12]);
    expect(announced.lastBarrel?.number, 12);
    expect(announced.close(playerId: 'you', number: 12).accepted, isTrue);
  });

  test('игрок сериализуется и восстанавливается', () {
    final original = player('you');
    final restored = LotoPlayer.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.card.numberSet, original.card.numberSet);
    expect(restored.isComputer, original.isComputer);
    expect(restored.isHost, original.isHost);
    expect(restored.closed, original.closed);
  });
}
