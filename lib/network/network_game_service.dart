import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

enum NetworkStatus {
  idle,
  hosting,
  discovering,
  connecting,
  connected,
  disconnected,
}

class DiscoveredGame {
  const DiscoveredGame({
    required this.code,
    required this.name,
    required this.host,
    required this.port,
  });
  final String code;
  final String name;
  final String host;
  final int port;
}

/// Owns exactly one LAN session. mDNS is for discovery, not authentication or
/// internet rendezvous. The WebSocket carries only configuration and actions.
class NetworkGameService extends ChangeNotifier {
  NetworkStatus status = NetworkStatus.idle;
  LobbyConfig? config;
  bool isHost = false;
  int? port;
  String? localAddress;
  String? discoveryError;

  /// Why the other device refused the game, in words the child can read. Kept
  /// so the lobby can say «разные версии игры» instead of a silent drop.
  String? refusal;

  /// The game this connection is for and the check its own rules give. The
  /// transport knows no rules: it only asks the game about every move that
  /// arrives, so two devices never drift apart in the middle of a session.
  String? _expectedGameId;
  void Function(Map<String, Object?> move)? _checkMove;

  /// What the lobby of a game hands to the shared transport.
  void attachGame({
    required String gameId,
    required void Function(Map<String, Object?> move) checkMove,
  }) {
    _expectedGameId = gameId;
    _checkMove = checkMove;
  }
  String peerName = 'Друг';

  HttpServer? _server;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  Timer? _heartbeat;
  Timer? _handshakeTimer;
  DateTime _lastHeard = DateTime.now();
  bool _handshake = false;
  bool _closed = false;
  bool _disposed = false;
  final _events = StreamController<NetworkMessage>.broadcast();
  Stream<NetworkMessage> get events => _events.stream;

  static String newCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      6,
      (_) => codeAlphabet[rng.nextInt(codeAlphabet.length)],
    ).join();
  }

  List<DiscoveredGame> get games {
    final result = <DiscoveredGame>[];
    final pattern = RegExp(r'^Diana-([A-HJ-NP-Z2-9]{6})(?: \(\d+\))?$');
    for (final service in _discovery?.services ?? <nsd.Service>[]) {
      final match = pattern.firstMatch(service.name ?? '');
      if (match == null || service.port == null) continue;
      final addresses = service.addresses ?? [];
      final host =
          addresses
              .where((a) => a.type == InternetAddressType.IPv4)
              .firstOrNull
              ?.address ??
          addresses.firstOrNull?.address ??
          service.host;
      if (host == null || host.isEmpty) continue;
      var name = 'Игра друга';
      final nameBytes = service.txt?['name'];
      if (nameBytes != null) {
        final decoded = utf8.decode(nameBytes, allowMalformed: true).trim();
        if (decoded.isNotEmpty) {
          name = decoded.length > 40 ? decoded.substring(0, 40) : decoded;
        }
      }
      result.add(
        DiscoveredGame(
          code: match.group(1)!,
          name: name,
          host: host,
          port: service.port!,
        ),
      );
    }
    return result;
  }

  Future<void> host(
    LobbyConfig game, {
    bool advertise = true,
    InternetAddress? bindAddress,
  }) async {
    if (status != NetworkStatus.idle || !isGameCode(game.code)) {
      throw StateError('Нельзя создать игру');
    }
    isHost = true;
    config = game;
    refusal = null;
    final server = await shelf_io.serve(
      webSocketHandler((socket, _) => _accept(socket)),
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    port = server.port;
    status = NetworkStatus.hosting;
    _notify();
    if (advertise) {
      try {
        final registration = await nsd.register(
          nsd.Service(
            name: 'Diana-${game.code}',
            type: serviceType,
            port: port,
            txt: {'name': Uint8List.fromList(utf8.encode(game.hostName))},
          ),
        );
        if (_closed || status == NetworkStatus.connected) {
          await nsd.unregister(registration);
        } else {
          _registration = registration;
        }
      } catch (_) {
        // The server remains available through the explicit IP:port fallback.
        discoveryError =
            'Не получилось объявить игру в сети. Можно подключиться по адресу.';
      }
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      localAddress = interfaces
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .firstOrNull
          ?.address;
    } catch (_) {
      /* The advanced address is optional. */
    }
    _notify();
  }

  Future<void> discover() async {
    if (status != NetworkStatus.idle && status != NetworkStatus.discovering) {
      throw StateError('Поиск уже недоступен');
    }
    if (_discovery != null) return;
    status = NetworkStatus.discovering;
    discoveryError = null;
    _notify();
    try {
      final discovery = await nsd.startDiscovery(
        serviceType,
        ipLookupType: nsd.IpLookupType.any,
      );
      if (_closed || status == NetworkStatus.connected) {
        await nsd.stopDiscovery(discovery);
      } else {
        _discovery = discovery;
        discovery.addListener(_notify);
      }
    } catch (_) {
      discoveryError =
          'Поиск в сети недоступен. Попробуй подключение по адресу.';
    }
    _notify();
  }

  Future<void> connect(
    String host,
    int serverPort, {
    String? code,
    String playerName = 'Друг',
  }) async {
    if (status != NetworkStatus.idle &&
        status != NetworkStatus.discovering &&
        status != NetworkStatus.disconnected) {
      throw StateError('Подключение уже выполняется');
    }
    if (serverPort < 1 ||
        serverPort > 65535 ||
        host.trim().isEmpty ||
        (code != null && !isGameCode(code))) {
      throw const FormatException('Проверь адрес или код');
    }
    status = NetworkStatus.connecting;
    refusal = null;
    _notify();
    try {
      final channel = WebSocketChannel.connect(
        Uri(scheme: 'ws', host: host, port: serverPort, path: '/'),
      );
      _attach(channel);
      await channel.ready.timeout(const Duration(seconds: 8));
      _sendRaw(
        NetworkMessage('hello', {
          'version': protocolVersion,
          'code': code ?? '',
          'name': playerName.length > 40
              ? playerName.substring(0, 40)
              : playerName,
        }),
      );
    } catch (_) {
      await _socketSubscription?.cancel();
      await _channel?.sink.close();
      _channel = null;
      status = NetworkStatus.disconnected;
      _notify();
      rethrow;
    }
  }

  void _accept(WebSocketChannel channel) {
    if (_closed || _channel != null || status != NetworkStatus.hosting) {
      channel.sink.close();
      return;
    }
    _attach(channel);
  }

  void _attach(WebSocketChannel channel) {
    _channel = channel;
    _lastHeard = DateTime.now();
    _handshake = false;
    _socketSubscription = channel.stream.listen(
      _receive,
      onError: (_) => _lost(),
      onDone: _lost,
    );
    _handshakeTimer = Timer(const Duration(seconds: 10), () {
      if (!_handshake) _lost();
    });
  }

  void _receive(dynamic raw) {
    if (_closed) return;
    try {
      final message = NetworkMessage.decode(raw);
      _lastHeard = DateTime.now();
      if (!_handshake) {
        if (isHost && message.type == 'hello') {
          // Another version or another game would disagree about the rules in
          // the middle of the game, so the peer is refused before it starts.
          final sameVersion = message.data['version'] == protocolVersion;
          final sameCode =
              message.data['code'] == '' || message.data['code'] == config!.code;
          if (!sameVersion || !sameCode) {
            refusal = sameVersion
                ? 'Это приглашение для другой игры'
                : 'У вас разные версии игры';
            _sendRaw(NetworkMessage('error', {'message': refusal!}));
            _lost();
            return;
          }
          final name = message.data['name'];
          if (name is String && name.trim().isNotEmpty) {
            peerName = name.length > 40 ? name.substring(0, 40) : name;
          }
          _handshake = true;
          _sendRaw(NetworkMessage('gameConfig', config!.toJson()));
          _connected();
          _events.add(const NetworkMessage('connected'));
        } else if (!isHost && message.type == 'gameConfig') {
          try {
            // The game itself checks its own options: a foreign game id or
            // data this game does not understand is refused here.
            config = LobbyConfig.fromJson(message.data);
          } on FormatException catch (error) {
            refusal = error.message;
            _sendRaw(NetworkMessage('error', {'message': error.message}));
            _lost();
            return;
          }
          if (_expectedGameId != null && config!.gameId != _expectedGameId) {
            // The friend invited us to another game: the session would speak
            // about rules this screen does not know.
            unawaited(_refuse('Это приглашение для другой игры'));
            return;
          }
          _handshake = true;
          _connected();
          _events.add(message);
        } else if (message.type == 'error') {
          // The other device refused us and already said why.
          final text = message.data['message'];
          if (text is String && text.trim().isNotEmpty) refusal = text;
          _lost();
        } else {
          refusal ??= 'Не удалось подключиться к этой игре';
          _sendRaw(NetworkMessage('error', {'message': refusal!}));
          _lost();
        }
        return;
      }
      if (message.type == 'move') {
        final check = _checkMove;
        if (check != null) {
          try {
            check(message.data);
          } on FormatException catch (error) {
            // The game does not accept the move, so the two sides would
            // disagree: the session ends here instead of drifting apart.
            final reason = error.message;
            unawaited(_refuse(reason.isEmpty ? 'Ход не распознан' : reason));
            return;
          }
        }
      }
      switch (message.type) {
        case 'ping':
          _sendRaw(const NetworkMessage('pong'));
          return;
        case 'pong':
          return;
        case 'hello':
        case 'gameConfig':
        case 'connected':
        case 'disconnected':
          throw const FormatException('Неожиданное служебное сообщение');
        default:
          _events.add(message);
      }
    } catch (_) {
      _events.add(const NetworkMessage('desync'));
      _lost();
    }
  }

  void _connected() {
    _handshakeTimer?.cancel();
    status = NetworkStatus.connected;
    // A full game is no longer discoverable; release the expensive discovery
    // and registration resources as soon as a peer has joined.
    unawaited(_stopDiscovery());
    unawaited(_stopAdvertising());
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      if (DateTime.now().difference(_lastHeard) > const Duration(seconds: 30)) {
        _lost();
      } else {
        _sendRaw(const NetworkMessage('ping'));
      }
    });
    _notify();
  }

  void send(NetworkMessage message) {
    if (status != NetworkStatus.connected || !_handshake) {
      throw StateError('Связь потеряна');
    }
    _sendRaw(message);
  }

  void _sendRaw(NetworkMessage message) => _channel?.sink.add(message.encode());

  /// Says why the session cannot go on and closes the connection.
  Future<void> _refuse(String reason) async {
    refusal = reason;
    _sendRaw(NetworkMessage('error', {'message': reason}));
    _lost();
  }

  void _lost() {
    if (_closed || status == NetworkStatus.disconnected) return;
    _heartbeat?.cancel();
    _handshakeTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    status = NetworkStatus.disconnected;
    _events.add(const NetworkMessage('disconnected'));
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery == null) return;
    discovery.removeListener(_notify);
    try {
      await nsd.stopDiscovery(discovery);
    } catch (_) {}
  }

  Future<void> _stopAdvertising() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await nsd.unregister(registration);
    } catch (_) {}
  }

  /// Cancels discovery, advertising, timers, socket and server. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _handshakeTimer?.cancel();
    await _stopDiscovery();
    await _stopAdvertising();
    await _socketSubscription?.cancel();
    await _channel?.sink.close();
    await _server?.close(force: true);
    await _events.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
