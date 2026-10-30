import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/games/example/network.dart';
import 'package:games_for_diana/network/network_game_service.dart';
import 'package:games_for_diana/network/protocol.dart';

import '../support/async_wait.dart';

/// Two real services on the loopback address: no mDNS, no emulator, just the
/// same transport the phones use — server, WebSocket, handshake, messages.
void main() {
  const lobby = LobbyConfig(
    gameId: exampleGameId,
    hostSide: 'host',
    code: 'ABC234',
    hostName: 'Диана',
    options: {'reminder': true, 'markers': false},
  );
  const patience = Duration(seconds: 5);

  // The one thing a game gives the transport: its own check of a move.
  final game = GameCatalog.byId(exampleGameId)!;

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

  /// Connects a client by `IP:port` and waits until the lobby arrives.
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

  /// Waits for the next message of [type] on [service].
  ///
  /// Messages wake up the stream, not the listeners of the service, so the test
  /// waits for the event itself and only uses [waitUntil] for the state.
  Future<NetworkMessage> nextMessage(
    NetworkGameService service,
    String type,
  ) => service.events
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

    // The lobby travels as an envelope; the game itself reads its options.
    final received = client.config!;
    expect(received.version, protocolVersion);
    expect(received.gameId, exampleGameId);
    expect(received.hostSide, 'host');
    expect(received.code, lobby.code);
    expect(GameCatalog.byId(received.gameId), isNotNull);
    final options = exampleParseOptions(received.options);
    expect(options.reminder, isTrue);
    expect(options.markers, isFalse);
  });

  test('ходы идут через send/events в обе стороны, отмена подтверждается', () async {
    final host = await startHost();
    final client = await connectClient(host);
    closeBoth(host, client);

    // Client → host: the transport asked the game about this move and the game
    // let it through, so the session sees it.
    final atHost = nextMessage(host, 'move');
    client.send(const NetworkMessage('move', {'from': 'a1', 'to': 'a3'}));
    final move = await atHost;
    expect(move.data['from'], 'a1');
    expect(move.data['to'], 'a3');

    // Host → client: the other direction works the same way.
    final atClient = nextMessage(client, 'move');
    host.send(const NetworkMessage('move', {'from': 'b2', 'to': 'b4'}));
    expect((await atClient).data['to'], 'b4');

    // Undo is a request and an answer, both sides see the exchange.
    final request = nextMessage(host, 'undoRequest');
    client.send(const NetworkMessage('undoRequest', {'ply': 1}));
    expect((await request).data['ply'], 1);

    final answer = nextMessage(client, 'undoResponse');
    host.send(const NetworkMessage('undoResponse', {'accepted': true}));
    expect((await answer).data['accepted'], isTrue);
  });

  test('невозможный ход не доходит до партии: связь рвётся с причиной', () async {
    final host = await startHost();
    final client = await connectClient(host);
    closeBoth(host, client);

    final seenByHost = <NetworkMessage>[];
    final subscription = host.events.listen(seenByHost.add);
    addTearDown(subscription.cancel);

    // «z9» лежит вне доски, поэтому игра такой ход не принимает.
    final refusal = nextMessage(client, 'error');
    client.send(const NetworkMessage('move', {'from': 'a1', 'to': 'z9'}));

    final error = await refusal.timeout(patience);
    expect(error.data['message'], 'Ход не распознан');

    await waitUntil(() => host.status == NetworkStatus.disconnected);
    await waitUntil(() => client.status == NetworkStatus.disconnected);

    // The session never saw the move: it was stopped before the game applied it.
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

    // A peer that pretends to speak another protocol version.
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
