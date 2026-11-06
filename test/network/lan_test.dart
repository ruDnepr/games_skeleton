import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/games/backgammon/network.dart';
import 'package:games_for_diana/network/network_game_service.dart';
import 'package:games_for_diana/network/protocol.dart';

import '../support/async_wait.dart';

/// Два настоящих сервиса на loopback: без mDNS и эмулятора — тот же транспорт,
/// что и на телефонах (сервер, WebSocket, рукопожатие, сообщения).
void main() {
  const lobby = LobbyConfig(
    gameId: backgammonGameId,
    hostSide: 'white',
    code: 'ABC234',
    hostName: 'Диана',
    options: {'hints': true, 'numbers': false, 'autoRoll': false},
  );
  const patience = Duration(seconds: 5);

  // Единственное, что игра даёт транспорту: свою проверку хода.
  final game = GameCatalog.byId(backgammonGameId)!;

  Future<NetworkGameService> startHost() async {
    final host = NetworkGameService();
    host.attachGame(gameId: game.id, checkMove: game.validateMove);
    await host.host(
      lobby,
      advertise: false,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    expect(host.status, NetworkStatus.hosting);
    expect(host.port, isNotNull);
    return host;
  }

  /// Подключает клиента по IP:порт и ждёт прибытия лобби.
  Future<NetworkGameService> connectClient(NetworkGameService host) async {
    final client = NetworkGameService();
    client.attachGame(gameId: game.id, checkMove: game.validateMove);
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect(
      '127.0.0.1',
      host.port!,
      code: lobby.code,
      playerName: 'Маша',
    );
    await configured.timeout(patience);
    return client;
  }

  Future<NetworkMessage> nextMessage(
    NetworkGameService service,
    String type,
  ) =>
      service.events
          .firstWhere((message) => message.type == type)
          .timeout(patience);

  void closeBoth(NetworkGameService host, NetworkGameService client) {
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });
  }

  test('хост и клиент соединяются по адресу, лобби разбирается игрой', () async {
    final host = await startHost();
    final client = NetworkGameService();
    closeBoth(host, client);

    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect(
      '127.0.0.1',
      host.port!,
      code: lobby.code,
      playerName: 'Маша',
    );
    await configured.timeout(patience);

    expect(host.status, NetworkStatus.connected);
    expect(client.status, NetworkStatus.connected);
    expect(host.peerName, 'Маша');
    expect(host.isHost, isTrue);
    expect(client.isHost, isFalse);

    // Лобби едет конвертом; опции разбирает сама игра.
    final received = client.config!;
    expect(received.version, protocolVersion);
    expect(received.gameId, backgammonGameId);
    expect(received.hostSide, 'white');
    expect(received.code, lobby.code);
    expect(GameCatalog.byId(received.gameId), isNotNull);
    final options = backgammonParseOptions(received.options);
    expect(options.hints, isTrue);
    expect(options.numbers, isFalse);
  });

  test('ходы и кости идут через send/events в обе стороны, отмена подтверждается',
      () async {
    final host = await startHost();
    final client = await connectClient(host);
    closeBoth(host, client);

    // Клиент → хост: ход белых (хост бросил кости и прислал их, затем ход).
    final atHost = nextMessage(host, 'move');
    client.send(const NetworkMessage('move', {
      'player': 'white',
      'dice': [3, 5],
      'moves': [
        {'player': 'white', 'die': 3, 'from': 23, 'to': 20},
      ],
    }));
    final move = await atHost;
    expect(move.data['player'], 'white');
    expect((move.data['dice'] as List)[0], 3);

    // Хост → клиент: в обратную сторону работает так же.
    final atClient = nextMessage(client, 'move');
    host.send(const NetworkMessage('move', {
      'player': 'black',
      'dice': [6, 1],
      'moves': [
        {'player': 'black', 'die': 6, 'from': 18, 'to': null},
      ],
    }));
    expect((await atClient).data['player'], 'black');

    // Бросок костей (тип dice) тоже доходит.
    final diceAtClient = nextMessage(client, 'dice');
    host.send(const NetworkMessage('dice', {
      'player': 'white',
      'dice': [4, 2],
    }));
    final dice = await diceAtClient;
    expect(dice.data['player'], 'white');

    // Отмена — запрос и ответ, обе стороны видят обмен.
    final request = nextMessage(host, 'undoRequest');
    client.send(const NetworkMessage('undoRequest', {'ply': 1}));
    expect((await request).data['ply'], 1);

    final answer = nextMessage(client, 'undoResponse');
    host.send(const NetworkMessage('undoResponse', {'accepted': true}));
    expect((await answer).data['accepted'], isTrue);
  });

  test('негодный ход не доходит до партии: связь рвётся с причиной', () async {
    final host = await startHost();
    final client = await connectClient(host);
    closeBoth(host, client);

    final seenByHost = <NetworkMessage>[];
    final subscription = host.events.listen(seenByHost.add);
    addTearDown(subscription.cancel);

    // Кость 7 не бывает — игра такой ход не принимает (проверка формата).
    final refusal = nextMessage(client, 'error');
    client.send(const NetworkMessage('move', {
      'player': 'white',
      'dice': [7, 1],
      'moves': [],
    }));

    final error = await refusal.timeout(patience);
    expect(error.data['message'], 'Ход не распознан: кости');

    await waitUntil(host, () => host.status == NetworkStatus.disconnected);
    await waitUntil(
      client,
      () => client.status == NetworkStatus.disconnected,
    );

    // Партия этот ход не увидела: его остановили до применения.
    expect(seenByHost.where((event) => event.type == 'move'), isEmpty);
  });

  test('после close обе стороны считают связь потерянной', () async {
    final host = await startHost();
    final client = await connectClient(host);
    closeBoth(host, client);
    expect(client.status, NetworkStatus.connected);

    final lost = nextMessage(client, 'disconnected');
    await host.close();
    await lost;
    await waitUntil(client, () => client.status == NetworkStatus.disconnected);
    expect(client.status, NetworkStatus.disconnected);
  });

  test('чужая версия протокола получает вежливый отказ', () async {
    final host = await startHost();
    addTearDown(() async {
      await host.close();
      host.dispose();
    });

    // Узел, который прикидывается другой версией протокола.
    final socket = await WebSocket.connect('ws://127.0.0.1:${host.port}');
    addTearDown(() => socket.close());
    final answer = Completer<NetworkMessage>();
    socket.listen((raw) {
      if (answer.isCompleted) return;
      answer.complete(NetworkMessage.decode(raw));
    });
    socket.add(
      NetworkMessage('hello', {
        'version': protocolVersion + 1,
        'code': lobby.code,
        'name': 'Гость',
      }).encode(),
    );

    final refusal = await answer.future.timeout(patience);
    expect(refusal.type, 'error');
    expect(refusal.data['message'], contains('разные версии'));
    await waitUntil(host, () => host.status == NetworkStatus.disconnected);
    expect(host.refusal, contains('разные версии'));
  });
}
