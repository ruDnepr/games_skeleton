import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Общий конверт, код и лобби — то, о чём устройства договариваются до партии.
void main() {
  const lobby = LobbyConfig(
    gameId: 'backgammon',
    hostSide: 'white',
    code: 'ABC234',
    hostName: 'Диана',
    options: {'hints': true, 'numbers': false, 'autoRoll': false},
  );

  test('код из шести символов принимается только из своего алфавита', () {
    expect(isGameCode('ABC234'), isTrue);
    expect(isGameCode('A2B3C4'), isTrue);
    expect(isGameCode(codeAlphabet.substring(0, 6)), isTrue);

    // Длина не та.
    expect(isGameCode('ABC23'), isFalse);
    expect(isGameCode('ABC2345'), isFalse);
    expect(isGameCode(''), isFalse);
    // Строчные буквы не годятся: код диктуют заглавными.
    expect(isGameCode('abc234'), isFalse);
    // Похожие символы исключены из алфавита.
    expect(isGameCode('OBC234'), isFalse);
    expect(isGameCode('IBC234'), isFalse);
    expect(isGameCode('ABC23O'), isFalse);
    expect(isGameCode('ABC231'), isFalse);
    expect(isGameCode('ABC230'), isFalse);
    expect(codeAlphabet.contains('O'), isFalse);
    expect(codeAlphabet.contains('0'), isFalse);
    expect(codeAlphabet.contains('1'), isFalse);
    expect(codeAlphabet.contains('I'), isFalse);
  });

  test('идентификатор игры — латиница без пробелов', () {
    expect(isGameId('backgammon'), isTrue);
    expect(isGameId('two_words2'), isTrue);
    expect(isGameId('Backgammon'), isFalse);
    expect(isGameId('2backgammon'), isFalse);
    expect(isGameId('нарды'), isFalse);
    expect(isGameId(''), isFalse);
  });

  test('сообщение кодируется и декодируется, включая тип dice', () {
    final move = NetworkMessage.decode(
      const NetworkMessage('move', {
        'player': 'white',
        'dice': [3, 5],
        'moves': [
          {'player': 'white', 'die': 3, 'from': 23, 'to': 20},
        ],
      }).encode(),
    );
    expect(move.type, 'move');
    expect(move.data['player'], 'white');

    final dice = NetworkMessage.decode(
      const NetworkMessage('dice', {
        'player': 'black',
        'dice': [6, 6],
      }).encode(),
    );
    expect(dice.type, 'dice');
    expect(dice.data['player'], 'black');

    final undo = NetworkMessage.decode(
      const NetworkMessage('undoRequest', {'ply': 2}).encode(),
    );
    expect(undo.type, 'undoRequest');
    expect(undo.data['ply'], 2);
  });

  test('неизвестный тип и слишком большое сообщение отвергаются', () {
    expect(
      () => NetworkMessage.decode('{"type":"bad","data":{}}'),
      throwsFormatException,
    );
    expect(
      () => NetworkMessage.decode('{"type":"move","data":[]}'),
      throwsFormatException,
    );
    expect(() => NetworkMessage.decode(42), throwsFormatException);

    final huge = NetworkMessage('move', {
      'blob': 'x' * NetworkMessage.maxLength,
    });
    expect(huge.encode().length, greaterThan(NetworkMessage.maxLength));
    expect(() => NetworkMessage.decode(huge.encode()), throwsFormatException);
  });

  test('лобби проходит, если версия, игра и опции свои', () {
    final received = LobbyConfig.fromJson(
      NetworkMessage.decode(
        NetworkMessage('gameConfig', lobby.toJson()).encode(),
      ).data,
    );
    expect(received.version, protocolVersion);
    expect(received.gameId, 'backgammon');
    expect(received.hostSide, 'white');
    expect(received.code, 'ABC234');
    expect(received.hostName, 'Диана');
    expect(received.options['hints'], isTrue);

    // Данные переживают дорогу через JSON как есть.
    expect(
      LobbyConfig.fromJson(lobby.toJson()).options,
      equals(lobby.options),
    );
  });

  test('лобби отвергается при чужой версии, чужой игре и негодных опциях', () {
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['version'] = 99),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['gameId'] = 'darts'),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['gameId'] = 'Нарды'),
      throwsFormatException,
    );
    // Игра разбирает свои опции сама: чужой тип и лишний ключ — отказ.
    expect(
      () => LobbyConfig.fromJson(
        lobby.toJson()..['options'] = {'hints': 'да', 'numbers': false},
      ),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(
        lobby.toJson()
          ..['options'] = {'hints': true, 'numbers': false, 'extra': 1},
      ),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['options'] = 'нет'),
      throwsFormatException,
    );
    // Битый код, пустая сторона и слишком длинное имя тоже не проходят.
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['code'] = 'ABC23O'),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['hostSide'] = '  '),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(lobby.toJson()..['hostName'] = 'a' * 41),
      throwsFormatException,
    );
  });
}
