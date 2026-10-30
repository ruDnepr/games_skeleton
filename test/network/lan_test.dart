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

  Future<NetworkGameService> startHost() async {
    final host = NetworkGameService();
    await host.host(
      lobby,
      advertise: false,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    expect(host.status, NetworkStatus.hosting);
    expect(host.port, isNotNull);
    return host;
  }

  test('хост и клиент соединяются по адресу, лобби разбирается игрой', () async {
    final host = await startHost();
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });

    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect(
      '127.0.0.1',
      host.port!,
      code: lobby.code,
      playerName: 'Маша',
    );
    await configured.timeout(const Duration(seconds: 5));

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
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      await host.close();
      client.dispose();
      host.dispose();
    });
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    await client.connect('127.0.0.1', host.port!, code: lobby.code);
    await configured.timeout(const Duration(seconds: 5));

    final game = GameCatalog.byId(exampleGameId)!;
    final atHost = <NetworkMessage>[];
    final atClient = <NetworkMessage>[];
    final hostSub = host.events.listen(atHost.add);
    final clientSub = client.events.listen(atClient.add);
    addTearDown(() {
      unawaited(hostSub.cancel());
      unawaited(clientSub.cancel());
    });

    // Client → host: the move is checked by the game before it is applied.
    client.send(const NetworkMessage('move', {'from': 'a1', 'to': 'a3'}));
    await waitUntil(
      host,
      () => atHost.any((message) => message.type == 'move'),
      timeout: const Duration(seconds: 5),
    );
    final move = atHost.firstWhere((message) => message.type == 'move');
    expect(move.data['from'], 'a1');
    game.validateMove(move.data);
    // A move that does not pass the game's own check is refused.
    expect(
      () => game.validateMove({'from': 'a1', 'to': 'z9'}),
      throwsFormatException,
    );

    // Host → client: the other direction works the same way.
    host.send(const NetworkMessage('move', {'from': 'b2', 'to': 'b4'}));
    await waitUntil(
      client,
      () => atClient.any((message) => message.type == 'move'),
      timeout: const Duration(seconds: 5),
    );
    game.validateMove(
      atClient.firstWhere((message) => message.type == 'move').data,
    );

    // Undo is a request and an answer, both sides see the exchange.
    client.send(const NetworkMessage('undoRequest', {'ply': 1}));
    await waitUntil(
      host,
      () => atHost.any((message) => message.type == 'undoRequest'),
      timeout: const Duration(seconds: 5),
    );
    host.send(const NetworkMessage('undoResponse', {'accepted': true}));
    await waitUntil(
      client,
      () => atClient.any((message) => message.type == 'undoResponse'),
      timeout: const Duration(seconds: 5),
    );
    expect(
      atClient
          .firstWhere((message) => message.type == 'undoResponse')
          .data['accepted'],
      isTrue,
    );
  });

  test('после close обе стороны считают связь потерянной', () async {
    final host = await startHost();
    final client = NetworkGameService();
    addTearDown(() async {
      await client.close();
      client.dispose();
      host.dispose();
    });
    final configured = client.events.firstWhere(
      (event) => event.type == 'gameConfig',
    );
    final lost = client.events.firstWhere(
      (event) => event.type == 'disconnected',
    );
    await client.connect('127.0.0.1', host.port!, code: lobby.code);
    await configured.timeout(const Duration(seconds: 5));
    expect(client.status, NetworkStatus.connected);

    await host.close();
    await lost.timeout(const Duration(seconds: 5));
    expect(client.status, NetworkStatus.disconnected);
    expect(host.status, isNot(NetworkStatus.connected));
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
      const NetworkMessage('hello', {
        'version': protocolVersion + 1,
        'code': lobby.code,
        'name': 'Гость',
      }).encode(),
    );

    final refusal = await answer.future.timeout(const Duration(seconds: 5));
    expect(refusal.type, 'error');
    expect(refusal.data['message'], contains('разные версии'));
    expect(host.status, NetworkStatus.disconnected);
    expect(host.refusal, contains('разные версии'));
  });
}
