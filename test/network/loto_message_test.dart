import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/loto/engine/model.dart';
import 'package:games_for_diana/games/loto/network.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Сетевые сообщения лото: round-trip бочонка, закрытия и снимка, проверка
/// формы хода и опций. Приватность: карточка по сети передаётся только в
/// снимке партии, отдельно — никогда.
void main() {
  group('Round-trip сообщений', () {
    test('barrelMessageToJson → parseBarrelMessage сохраняет число и остаток',
        () {
      final data = barrelMessageToJson(42, 87);
      final parsed = parseBarrelMessage(data);
      expect(parsed.number, 42);
      expect(parsed.left, 87);
    });

    test('closeNumberToJson → parseCloseNumber сохраняет игрока и число', () {
      final data = closeNumberToJson('host', 17);
      final parsed = parseCloseNumber(data);
      expect(parsed.playerId, 'host');
      expect(parsed.number, 17);
    });

    test('closeEventToJson → parseCloseEvent сохраняет результат и причину', () {
      final accepted = closeEventToJson(
        playerId: 'client',
        number: 5,
        accepted: true,
      );
      final parsedAccepted = parseCloseEvent(accepted);
      expect(parsedAccepted.accepted, isTrue);
      expect(parsedAccepted.reason, isNull);

      final rejected = closeEventToJson(
        playerId: 'client',
        number: 5,
        accepted: false,
        reason: 'Этот бочонок ещё в мешке',
      );
      final parsedRejected = parseCloseEvent(rejected);
      expect(parsedRejected.accepted, isFalse);
      expect(parsedRejected.reason, 'Этот бочонок ещё в мешке');
    });

    test('snapshot проходит через общий транспорт', () {
      final game = LotoGame.start(
        players: [
          LotoPlayer(
            id: 'host',
            name: 'Диана',
            card: LotoCard.generate(),
            isHost: true,
          ),
          LotoPlayer(
            id: 'client',
            name: 'Друг',
            card: LotoCard.generate(),
          ),
        ],
        winMode: WinMode.row,
      );
      final drawn = game.draw();
      final closed = drawn.close(playerId: 'host', number: drawn.lastBarrel!.number).game;
      final data = snapshotToJson(
        game: closed,
        hostPlayerId: 'host',
        clientPlayerId: 'client',
      );
      final msg = NetworkMessage('event', data);
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'event');
      final parsed = parseSnapshot(decoded.data);
      expect(parsed.game.drawn, closed.drawn);
      expect(parsed.game.winMode, WinMode.row);
      expect(parsed.hostPlayerId, 'host');
      expect(parsed.clientPlayerId, 'client');
      expect(
        parsed.game.playerById('host')!.closed,
        closed.playerById('host')!.closed,
      );
    });

    test('closeNumber-сообщение проходит через общий транспорт', () {
      final msg = NetworkMessage('move', closeNumberToJson('host', 33));
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'move');
      final parsed = parseCloseNumber(decoded.data);
      expect(parsed.playerId, 'host');
      expect(parsed.number, 33);
    });

    test('barrel-событие проходит через общий транспорт', () {
      final msg = NetworkMessage('event', barrelMessageToJson(11, 79));
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'event');
      expect(decoded.data['kind'], 'barrel');
      final parsed = parseBarrelMessage(decoded.data);
      expect(parsed.number, 11);
      expect(parsed.left, 79);
    });
  });

  group('Чужая форма отвергается', () {
    test('parseBarrelMessage бросает на чужой kind', () {
      expect(
        () => parseBarrelMessage({'kind': 'wrong', 'number': 1, 'left': 1}),
        throwsFormatException,
      );
    });

    test('parseBarrelMessage бросает на чужое число', () {
      expect(
        () => parseBarrelMessage({'kind': 'barrel', 'number': 0, 'left': 1}),
        throwsFormatException,
      );
      expect(
        () => parseBarrelMessage({'kind': 'barrel', 'number': 91, 'left': 1}),
        throwsFormatException,
      );
      expect(
        () => parseBarrelMessage({'kind': 'barrel', 'number': '11', 'left': 1}),
        throwsFormatException,
      );
    });

    test('parseCloseNumber бросает на чужого игрока', () {
      expect(
        () => parseCloseNumber({'playerId': '', 'number': 1}),
        throwsFormatException,
      );
      expect(
        () => parseCloseNumber({'playerId': 'host', 'number': '1'}),
        throwsFormatException,
      );
      expect(
        () => parseCloseNumber({'playerId': 'host', 'number': 0}),
        throwsFormatException,
      );
    });

    test('parseCloseEvent бросает на чужой kind и результат', () {
      expect(
        () => parseCloseEvent({
          'kind': 'wrong',
          'playerId': 'host',
          'number': 1,
          'accepted': true,
        }),
        throwsFormatException,
      );
      expect(
        () => parseCloseEvent({
          'kind': 'closeNumber',
          'playerId': 'host',
          'number': 1,
          'accepted': 'да',
        }),
        throwsFormatException,
      );
    });

    test('parseSnapshot бросает на чужие данные', () {
      expect(
        () => parseSnapshot({'kind': 'snapshot'}),
        throwsFormatException,
      );
      expect(
        () => parseSnapshot({
          'kind': 'snapshot',
          'winMode': 'row',
          'drawn': ['не число'],
          'players': [],
          'hostPlayerId': 'host',
          'clientPlayerId': 'client',
        }),
        throwsFormatException,
      );
    });
  });

  group('Проверка хода и опций', () {
    test('lotoValidateMove пропускает правильный ход', () {
      expect(() => lotoValidateMove({'number': 42}), returnsNormally);
      expect(() => lotoValidateMove({'number': 1}), returnsNormally);
      expect(() => lotoValidateMove({'number': 90}), returnsNormally);
    });

    test('lotoValidateMove бросает на чужой ход', () {
      expect(() => lotoValidateMove({'number': 0}), throwsFormatException);
      expect(() => lotoValidateMove({'number': 91}), throwsFormatException);
      expect(() => lotoValidateMove({'number': '42'}), throwsFormatException);
      expect(() => lotoValidateMove({}), throwsFormatException);
      expect(() => lotoValidateMove({'move': 42}), throwsFormatException);
    });

    test('lotoParseOptions принимает родные опции', () {
      expect(
        () => lotoParseOptions({
          'hints': true,
          'hintButton': false,
          'voice': true,
          'winMode': 'row',
        }),
        returnsNormally,
      );
      final parsed = lotoParseOptions({
        'hints': true,
        'hintButton': false,
        'voice': true,
        'winMode': 'fullCard',
      });
      expect(parsed.hints, isTrue);
      expect(parsed.hintButton, isFalse);
      expect(parsed.voice, isTrue);
      expect(
        LotoOptions.winModeFromOptions({'winMode': 'fullCard'}),
        WinMode.fullCard,
      );
    });

    test('lotoParseOptions бросает на чужие опции', () {
      expect(
        () => lotoParseOptions({'hints': 'да', 'hintButton': false, 'voice': true}),
        throwsFormatException,
      );
      expect(
        () => lotoParseOptions({
          'hints': true,
          'hintButton': false,
          'voice': true,
          'foreign': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => lotoParseOptions({'hints': true, 'voice': true}),
        throwsFormatException,
      );
      expect(
        () => lotoParseOptions({
          'hints': true,
          'hintButton': false,
          'voice': true,
          'winMode': 5,
        }),
        throwsFormatException,
      );
    });

    test('winMode факультативен в опциях', () {
      final parsed = lotoParseOptions({
        'hints': true,
        'hintButton': false,
        'voice': true,
      });
      expect(parsed.hints, isTrue);
    });
  });
}
