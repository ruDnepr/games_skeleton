import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/backgammon/engine/model.dart';
import 'package:games_for_diana/games/backgammon/network.dart';

/// Сериализация хода и броска нард: round-trip и отказ на чужой форме.
void main() {
  test('ход проходит туда-обратно через moveMessage/parseTurn', () {
    final turn = Turn(
      player: Player.white,
      dice: const [3, 5],
      moves: const [
        Move(player: Player.white, die: 3, from: 23, to: 20),
        Move(player: Player.white, die: 5, from: 20, to: 15),
      ],
    );
    final parsed = parseTurn(moveMessage(turn));
    expect(parsed.player, Player.white);
    expect(parsed.dice, [3, 5]);
    expect(parsed.moves.length, 2);
    expect(parsed.moves.first.from, 23);
    expect(parsed.moves.first.to, 20);
    expect(parsed.moves.first.die, 3);
  });

  test('ход с выносом и входом с бара сериализуется', () {
    final turn = Turn(
      player: Player.black,
      dice: const [6, 1],
      moves: const [
        Move(player: Player.black, die: 6, from: 18, to: null),
        Move(player: Player.black, die: 1, from: null, to: 0),
      ],
    );
    final parsed = parseTurn(moveMessage(turn));
    expect(parsed.moves.first.bearOff, isTrue);
    expect(parsed.moves.first.to, isNull);
    expect(parsed.moves[1].fromBar, isTrue);
    expect(parsed.moves[1].to, 0);
  });

  test('parseTurn отвергает чужой формат', () {
    expect(
      () => parseTurn({'player': 'red', 'dice': [1, 2], 'moves': []}),
      throwsFormatException,
    );
    expect(
      () => parseTurn({'player': 'white', 'dice': [1], 'moves': []}),
      throwsFormatException,
    );
    expect(
      () => parseTurn({
        'player': 'white',
        'dice': [1, 2],
        'moves': [
          {'player': 'white', 'die': 9, 'from': 0, 'to': 1},
        ],
      }),
      throwsFormatException,
    );
  });

  test('сообщение dice проходит туда-обратно', () {
    final msg = diceMessage(Player.black, const [6, 6]);
    final parsed = parseDiceMessage(msg);
    expect(parsed.player, Player.black);
    expect(parsed.dice, [6, 6]);
  });

  test('parseDiceMessage отвергает чужую форму', () {
    expect(
      () => parseDiceMessage({'player': 'red', 'dice': [1, 2]}),
      throwsFormatException,
    );
    expect(
      () => parseDiceMessage({'player': 'white', 'dice': [7, 2]}),
      throwsFormatException,
    );
    expect(
      () => parseDiceMessage({'player': 'white', 'dice': [1]}),
      throwsFormatException,
    );
  });
}
