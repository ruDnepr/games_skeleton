import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/network/protocol.dart';

/// The envelope both devices agree on before a game starts.
void main() {
  const lobby = LobbyConfig(
    gameId: 'example',
    hostSide: 'host',
    code: 'ABC234',
    hostName: 'Диана',
    options: {'reminder': true, 'markers': false},
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
    expect(isGameId('example'), isTrue);
    expect(isGameId('two_words2'), isTrue);
    expect(isGameId('Example'), isFalse);
    expect(isGameId('2example'), isFalse);
    expect(isGameId('игра'), isFalse);
    expect(isGameId(''), isFalse);
  });

  test('сообщение кодируется и декодируется', () {
    final decoded = NetworkMessage.decode(
      const NetworkMessage('move', {
        'from': 'a1',
        'to': 'a3',
      }).encode(),
    );
    expect(decoded.type, 'move');
    expect(decoded.data['to'], 'a3');

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
    expect(received.gameId, 'example');
    expect(received.hostSide, 'host');
    expect(received.code, 'ABC234');
    expect(received.hostName, 'Диана');
    expect(received.options['reminder'], isTrue);

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
      () => LobbyConfig.fromJson(lobby.toJson()..['gameId'] = 'Игра'),
      throwsFormatException,
    );
    // Игра разбирает свои опции сама: чужой тип и лишний ключ — отказ.
    expect(
      () => LobbyConfig.fromJson(
        lobby.toJson()..['options'] = {'reminder': 'да', 'markers': false},
      ),
      throwsFormatException,
    );
    expect(
      () => LobbyConfig.fromJson(
        lobby.toJson()
          ..['options'] = {'reminder': true, 'markers': false, 'extra': 1},
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
