import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/battleship/engine/model.dart';
import 'package:games_for_diana/games/battleship/network.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Сетевые сообщения морского боя: round-trip выстрела, результата и
/// готовности флота. Приватность: флот по сети не передаётся.
void main() {
  group('Приватность: флот не передаётся по сети', () {
    test('сообщение move (выстрел) содержит только ply и квадрат — без флота',
        () {
      final msg = NetworkMessage(
        'move',
        shotToJson(const Square(3, 3), 1),
      ).encode();
      expect(msg.contains('ships'), isFalse);
      expect(msg.contains('fleet'), isFalse);
    });

    test('shotResult содержит только результат — без расположения корабля', () {
      final msg = NetworkMessage(
        'event',
        shotResultToJson(
          ply: 1,
          square: const Square(3, 3),
          result: ShotResult.sunk,
          sunkType: ShipType.destroyer,
          nextTurn: 'me',
        ),
      ).encode();
      // Тип потопленного корабля передаётся (это разрешено), но не его клетки.
      expect(msg.contains('"row"'), isFalse);
      expect(msg.contains('"col"'), isFalse);
      expect(msg.contains('"ships"'), isFalse);
    });

    test('fleetReady не содержит кораблей', () {
      final msg =
          NetworkMessage('event', fleetReadyToJson()).encode();
      // «ships» не должно быть в сообщении — флот по сети не передаётся.
      // «fleet» является частью слова «fleetReady» (kind события), поэтому
      // проверяем именно отсутствие «ships» и «row»/«col» (координат кораблей).
      expect(msg.contains('ships'), isFalse);
      expect(msg.contains('"row"'), isFalse);
      expect(msg.contains('"col"'), isFalse);
    });
  });

  group('Round-trip сообщений', () {
    test('shotToJson → parseShot сохраняет ply и квадрат', () {
      final data = shotToJson(const Square(2, 4), 3);
      final parsed = parseShot(data);
      expect(parsed.ply, 3);
      expect(parsed.square, const Square(2, 4));
    });

    test('shotResultToJson → parseShotResult сохраняет результат и nextTurn',
        () {
      final data = shotResultToJson(
        ply: 1,
        square: const Square(3, 3),
        result: ShotResult.sunk,
        sunkType: ShipType.destroyer,
        nextTurn: 'me',
      );
      final parsed = parseShotResult(data);
      expect(parsed.result, ShotResult.sunk);
      expect(parsed.sunkType, ShipType.destroyer);
      expect(parsed.nextTurn, 'me');
      expect(parsed.square, const Square(3, 3));
    });

    test('fleetReadyToJson распознаётся как событие готовности', () {
      final data = fleetReadyToJson();
      expect(isFleetReadyEvent(data), isTrue);
    });

    test('move-сообщение проходит через общий транспорт', () {
      final msg =
          NetworkMessage('move', shotToJson(const Square(5, 5), 7));
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'move');
      final parsed = parseShot(decoded.data);
      expect(parsed.square, const Square(5, 5));
      expect(parsed.ply, 7);
    });

    test('event-сообщение shotResult проходит через общий транспорт', () {
      final msg = NetworkMessage(
        'event',
        shotResultToJson(
          ply: 1,
          square: const Square(0, 0),
          result: ShotResult.miss,
          nextTurn: 'enemy',
        ),
      );
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'event');
      expect(decoded.data['kind'], 'shotResult');
      final parsed = parseShotResult(decoded.data);
      expect(parsed.result, ShotResult.miss);
      expect(parsed.nextTurn, 'enemy');
    });

    test('event-сообщение fleetReady проходит через общий транспорт', () {
      final msg = NetworkMessage('event', fleetReadyToJson());
      final decoded = NetworkMessage.decode(msg.encode());
      expect(decoded.type, 'event');
      expect(isFleetReadyEvent(decoded.data), isTrue);
    });
  });

  group('Чужая форма отвергается', () {
    test('parseShot бросает на чужую клетку', () {
      expect(
        () => parseShot({'ply': 1, 'square': [0, 10]}),
        throwsFormatException,
      );
      expect(
        () => parseShot({'ply': 1, 'square': 'A1'}),
        throwsFormatException,
      );
    });

    test('parseShotResult бросает на чужой kind', () {
      expect(
        () => parseShotResult({
          'kind': 'wrongKind',
          'ply': 1,
          'square': [0, 0],
          'result': 'miss',
          'nextTurn': 'me',
        }),
        throwsFormatException,
      );
    });

    test('parseShotResult бросает на чужой результат', () {
      expect(
        () => parseShotResult({
          'kind': 'shotResult',
          'ply': 1,
          'square': [0, 0],
          'result': 'wrong',
          'nextTurn': 'me',
        }),
        throwsFormatException,
      );
    });

    test('battleshipValidateMove пропускает правильный ход', () {
      expect(
        () => battleshipValidateMove({
          'ply': 1,
          'square': [3, 4],
        }),
        returnsNormally,
      );
    });

    test('battleshipValidateMove бросает на чужой ход', () {
      expect(
        () => battleshipValidateMove({'square': 'A1'}),
        throwsFormatException,
      );
      expect(
        () => battleshipValidateMove({
          'square': [0, 10],
        }),
        throwsFormatException,
      );
      expect(
        () => battleshipValidateMove({
          'square': [-1, 0],
        }),
        throwsFormatException,
      );
    });
  });
}
