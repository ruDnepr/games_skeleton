import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/games/domino/engine/model.dart';
import 'package:games_for_diana/games/domino/network.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Сериализация хода и снимка домино: round-trip и отказ на чужой форме.
/// Протокол игры: `move` (кость + сторона), `event` (snapshot/draw/pass),
/// `undoRequest`/`undoResponse`, `resign`.
void main() {
  group('ход камнем', () {
    test('сообщение move проходит туда-обратно', () {
      const move = DominoMove(tile: DominoTile(3, 5), side: ChainSide.right);
      final json = moveToJson(move);
      expect(json['tile'], '3:5');
      expect(json['side'], 'right');
      final parsed = parseMove(json);
      expect(parsed.tile.label, '3:5');
      expect(parsed.side, ChainSide.right);
    });

    test('левая сторона тоже сериализуется', () {
      const move = DominoMove(tile: DominoTile(0, 6), side: ChainSide.left);
      final parsed = parseMove(moveToJson(move));
      expect(parsed.tile.label, '0:6');
      expect(parsed.side, ChainSide.left);
    });

    test('dominoValidateMove принимает каноническую запись', () {
      dominoValidateMove({'tile': '3:5', 'side': 'left'});
      dominoValidateMove({'tile': '0:6', 'side': 'right'});
    });

    test('dominoValidateMove отвергает чужой формат', () {
      expect(
        () => dominoValidateMove({'tile': '5:3', 'side': 'left'}),
        throwsFormatException,
      );
      expect(
        () => dominoValidateMove({'tile': '3:8', 'side': 'left'}),
        throwsFormatException,
      );
      expect(
        () => dominoValidateMove({'tile': '3:5', 'side': 'up'}),
        throwsFormatException,
      );
      expect(
        () => dominoValidateMove({'tile': 35, 'side': 'left'}),
        throwsFormatException,
      );
      expect(
        () => dominoValidateMove({'side': 'left'}),
        throwsFormatException,
      );
      expect(
        () => dominoValidateMove({'tile': '3:5'}),
        throwsFormatException,
      );
    });
  });

  group('сетевые сообщения', () {
    test('NetworkMessage кодируется и читается обратно', () {
      const message = NetworkMessage('move', {'tile': '3:5', 'side': 'right'});
      final restored = NetworkMessage.decode(message.encode());
      expect(restored.type, 'move');
      expect(restored.data['tile'], '3:5');
      expect(restored.data['side'], 'right');
    });

    test('event-snapshot — допустимый тип', () {
      const message = NetworkMessage('event', {'kind': 'snapshot'});
      expect(NetworkMessage.types, contains('event'));
      final restored = NetworkMessage.decode(message.encode());
      expect(restored.data['kind'], 'snapshot');
    });

    test('event-draw и event-pass — допустимые события', () {
      const draw = NetworkMessage('event', {'kind': 'draw'});
      const pass = NetworkMessage('event', {'kind': 'pass'});
      expect(NetworkMessage.decode(draw.encode()).data['kind'], 'draw');
      expect(NetworkMessage.decode(pass.encode()).data['kind'], 'pass');
    });

    test('undoRequest и undoResponse — допустимые типы', () {
      const req = NetworkMessage('undoRequest', {'ply': 3});
      const res = NetworkMessage('undoResponse', {'ply': 3, 'accepted': true});
      expect(NetworkMessage.decode(req.encode()).data['ply'], 3);
      final decoded = NetworkMessage.decode(res.encode());
      expect(decoded.data['ply'], 3);
      expect(decoded.data['accepted'], true);
    });

    test('resign — допустимый тип без данных', () {
      const msg = NetworkMessage('resign', {});
      expect(NetworkMessage.decode(msg.encode()).type, 'resign');
    });

    test('мусор и неизвестный тип не принимаются', () {
      expect(() => NetworkMessage.decode('не json'), throwsFormatException);
      expect(() => NetworkMessage.decode('[]'), throwsFormatException);
      expect(
        () => NetworkMessage.decode('{"type":"hack","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => NetworkMessage.decode('{"type":"move","data":[]}'),
        throwsFormatException,
      );
    });
  });

  group('снимок стола', () {
    GameState sampleState() {
      var chain = const Board.empty();
      chain = chain.place(const DominoTile(2, 5), ChainSide.right);
      return GameState(
        playerCount: 2,
        hands: [
          [const DominoTile(0, 0), const DominoTile(3, 3)],
          const [],
        ],
        sizes: [2, 5],
        bazaar: const [DominoTile(1, 4), DominoTile(0, 6)],
        board: chain,
        turn: 1,
        ply: 4,
      );
    }

    test('в снимок попадает только своя рука', () {
      final state = sampleState();
      final forHost = snapshotToJson(state, 0);
      final forClient = snapshotToJson(state, 1);
      expect(forHost['hand'], isA<List>());
      expect((forHost['hand'] as List).length, 2);
      expect(forClient['hand'], isA<List>());
      expect((forClient['hand'] as List).length, 0);
      expect(forHost['opponentHandSize'], 5);
      expect(forClient['opponentHandSize'], 2);
    });

    test('снимок восстанавливается без потерь', () {
      final state = sampleState();
      final json = snapshotToJson(state, 1);
      final restored = parseSnapshot(json);
      expect(restored.playerCount, 2);
      expect(restored.turn, 1);
      expect(restored.ply, 4);
      expect(restored.bazaarCount, 2);
      expect(restored.board.fingerprint, state.board.fingerprint);
      expect(restored.handSizes, [2, 0]);
      expect(restored.handOf(1), isEmpty); // чужая рука не видна
    });

    test('чужой формат снимка отвергается', () {
      expect(
        () => parseSnapshot({'board': 'не список'}),
        throwsFormatException,
      );
      expect(
        () => parseSnapshot({
          'board': [],
          'bazaarCount': -1,
          'hand': [],
          'opponentHandSize': 5,
          'turn': 0,
          'ply': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => parseSnapshot({
          'board': [],
          'bazaarCount': 0,
          'hand': ['9:9'],
          'opponentHandSize': 5,
          'turn': 0,
          'ply': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('опции игры', () {
    test('свои опции проходят', () {
      final parsed = dominoParseOptions({'hints': true, 'hintButton': false});
      expect(parsed.hints, isTrue);
      expect(parsed.hintButton, isFalse);
    });

    test('чужие опции отвергаются', () {
      expect(
        () => dominoParseOptions({'hints': 'да', 'hintButton': false}),
        throwsFormatException,
      );
      expect(
        () => dominoParseOptions({'hints': true}),
        throwsFormatException,
      );
      expect(
        () => dominoParseOptions({
          'hints': true,
          'hintButton': true,
          'extra': 1,
        }),
        throwsFormatException,
      );
    });
  });
}
