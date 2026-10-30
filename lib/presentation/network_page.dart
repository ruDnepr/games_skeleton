import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../games/definition.dart';
import '../network/network_game_service.dart';
import '../network/protocol.dart';
import 'theme.dart';

enum _LobbyView { choose, host, find }

/// The network lobby of one game.
///
/// The whole transport lives in [NetworkGameService]: mDNS discovery, the
/// WebSocket server and client, the six-character code, the `IP:port` fallback,
/// the handshake with the version check and ping/pong. The page only shows it
/// and, once a friend is connected, asks the game to open its own session
/// screen with a [NetworkSession] in hand.
class NetworkPage extends StatefulWidget {
  const NetworkPage({
    super.key,
    required this.settings,
    required this.game,
    this.service,
  });
  final SettingsController settings;
  final GameDefinition game;

  /// Allows discovery/transport to be substituted in widget tests.
  final NetworkGameService? service;
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late final NetworkGameService service =
      widget.service ?? NetworkGameService();
  StreamSubscription<NetworkMessage>? _subscription;
  final codeController = TextEditingController();
  final addressController = TextEditingController();
  _LobbyView view = _LobbyView.choose;
  bool busy = false;
  bool _inSession = false;
  String? message;

  @override
  void initState() {
    super.initState();
    // The game plugs in exactly one thing: the check of its own moves. The
    // rest of the transport — discovery, sockets, handshake, heartbeats — is
    // shared and knows nothing about rules.
    service.attachGame(
      gameId: widget.game.id,
      checkMove: widget.game.validateMove,
    );
    _subscription = service.events.listen(_onEvent);
  }

  void _onEvent(NetworkMessage event) {
    if (!mounted || _inSession) return;
    if (event.type == 'connected' || event.type == 'gameConfig') {
      final lobby = service.config;
      if (lobby == null) return;
      unawaited(_openSession(lobby));
    } else if (event.type == 'disconnected') {
      // The refusal says «у вас разные версии игры» when that is the reason.
      setState(() {
        busy = false;
        message =
            service.refusal ?? 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
      });
    }
  }

  /// Hands the live connection to the game and lets it open its session screen.
  /// When the game is finished, the lobby is closed as well.
  Future<void> _openSession(LobbyConfig lobby) async {
    _inSession = true;
    await widget.game.start(
      context,
      widget.settings,
      network: NetworkSession(
        service: service,
        lobby: lobby,
        isHost: service.isHost,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _create() async {
    setState(() {
      view = _LobbyView.host;
      busy = true;
      message = null;
    });
    final lobby = LobbyConfig(
      gameId: widget.game.id,
      hostSide: widget.game.hostSide(widget.settings),
      code: NetworkGameService.newCode(),
      hostName: widget.settings.nickname,
      options: widget.game.options(widget.settings),
    );
    try {
      await service.host(lobby);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Не получилось создать игру. Проверь подключение к Wi-Fi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _find() async {
    setState(() {
      view = _LobbyView.find;
      busy = true;
      message = null;
    });
    await service.discover();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _connect(String host, int port, {String? code}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await service.connect(
        host,
        port,
        code: code,
        playerName: widget.settings.nickname,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              service.refusal ?? 'Не получилось подключиться. Проверь адрес и Wi-Fi.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _connectCode() {
    final code = codeController.text.trim().toUpperCase();
    if (!isGameCode(code)) {
      setState(() => message = 'Введи шесть символов кода друга.');
      return;
    }
    final game = service.games.where((game) => game.code == code).firstOrNull;
    if (game == null) {
      setState(
        () => message =
            'Пока не нашли игру с этим кодом. Убедись, что вы в одной сети.',
      );
      return;
    }
    unawaited(_connect(game.host, game.port, code: game.code));
  }

  void _connectAddress() {
    final text = addressController.text.trim();
    final uri = Uri.tryParse('ws://$text');
    if (uri == null ||
        !uri.hasPort ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      setState(() => message = 'Проверь адрес. Пример: 192.168.1.10:12345');
      return;
    }
    unawaited(_connect(uri.host, uri.port));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    codeController.dispose();
    addressController.dispose();
    // The lobby owns the connection: closing the page closes the session.
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Сетевая игра',
    child: ListenableBuilder(
      listenable: service,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          ...switch (view) {
            _LobbyView.choose => _chooseContent(),
            _LobbyView.host => _hostContent(),
            _LobbyView.find => _findContent(),
          },
          if (message != null) ...[
            const SizedBox(height: 18),
            _NetworkInfo(text: message!),
          ],
        ],
      ),
    ),
  );

  List<Widget> _chooseContent() => [
    const Intro(
      eyebrow: 'ВМЕСТЕ ВЕСЕЛЕЕ',
      title: 'Играй с другом',
      subtitle:
          'Подключите оба устройства к одной сети Wi-Fi или точке доступа.',
    ),
    const SizedBox(height: 20),
    _GameLine(game: widget.game),
    const SizedBox(height: 24),
    BigButton(
      title: 'Создать игру',
      subtitle: 'Ты приглашаешь друга',
      icon: Icons.add_rounded,
      onPressed: _create,
    ),
    const SizedBox(height: 16),
    BigButton(
      title: 'Найти игру / ввести код',
      subtitle: 'Подключись к другу',
      icon: Icons.search_rounded,
      color: const Color(0xFFF4CB67),
      foreground: ink,
      onPressed: _find,
    ),
    const SizedBox(height: 30),
    const _NetworkInfo(
      text:
          'Интернет и аккаунты не нужны. Игра работает только в одной локальной сети.',
    ),
  ];

  List<Widget> _hostContent() => [
    const Intro(
      eyebrow: 'ТЫ СОЗДАЁШЬ ИГРУ',
      title: 'Пригласи друга!',
      subtitle: 'Скажи другу этот код. Он найдёт твою игру в той же сети.',
    ),
    const SizedBox(height: 26),
    Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFEDE4F0)),
        boxShadow: [
          BoxShadow(
            color: purple.withValues(alpha: .07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'КОД ИГРЫ',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            service.config?.code ?? '······',
            style: const TextStyle(
              fontSize: 37,
              letterSpacing: 7,
              color: deepPurple,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.game.title,
            style: const TextStyle(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.game.tagline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 12),
        Text(
          busy ? 'Создаём игру…' : 'Ждём друга…',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ],
    ),
    if (service.localAddress != null && service.port != null) ...[
      const SizedBox(height: 26),
      _NetworkInfo(
        text:
            'Если поиск не работает, взрослый может ввести адрес: '
            '${service.localAddress}:${service.port}',
      ),
    ],
    if (service.discoveryError != null) ...[
      const SizedBox(height: 12),
      _NetworkInfo(text: service.discoveryError!),
    ],
  ];

  List<Widget> _findContent() => [
    const Intro(
      eyebrow: 'ПОИСК ДРУГА',
      title: 'Найди игру',
      subtitle: 'Выбери игру из списка или введи код, который сказал друг.',
    ),
    const SizedBox(height: 20),
    const _NetworkInfo(
      text: 'Оба устройства должны быть в одной сети Wi-Fi.',
    ),
    const SizedBox(height: 20),
    Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('network-code'),
            controller: codeController,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z2-9]')),
            ],
            decoration: InputDecoration(
              counterText: '',
              hintText: 'КОД ИГРЫ',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.tag_rounded, color: purple),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: busy ? null : _connectCode,
          style: FilledButton.styleFrom(minimumSize: const Size(92, 58)),
          child: const Text('Найти'),
        ),
      ],
    ),
    const SizedBox(height: 24),
    Row(
      children: [
        const Text(
          'Игры рядом',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        if (busy || service.status == NetworkStatus.discovering)
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    ),
    const SizedBox(height: 12),
    if (service.games.isEmpty)
      const _NetworkInfo(text: 'Пока никого не видно. Поиск продолжается…'),
    for (final game in service.games)
      ChoiceTile(
        title: game.name,
        subtitle: 'Код: ${game.code}',
        icon: Icons.wifi_rounded,
        color: const Color(0xFFDDF1DF),
        onTap: () {
          if (!busy) unawaited(_connect(game.host, game.port, code: game.code));
        },
      ),
    if (service.discoveryError != null) ...[
      const SizedBox(height: 10),
      _NetworkInfo(text: service.discoveryError!),
    ],
    const SizedBox(height: 20),
    ExpansionTile(
      title: const Text(
        'Подключение по адресу',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
      subtitle: const Text(
        'Если поиск не работает, попроси взрослого помочь',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      children: [
        TextField(
          key: const Key('network-address'),
          controller: addressController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: '192.168.1.10:12345',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: busy ? null : _connectAddress,
          child: const Text('Подключиться'),
        ),
        const SizedBox(height: 10),
      ],
    ),
    if (service.status == NetworkStatus.connecting)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: Text(
            'Подключаемся…',
            style: TextStyle(color: purple, fontWeight: FontWeight.w900),
          ),
        ),
      ),
  ];
}

/// Which game the lobby belongs to, so nobody has to guess what is being set up.
class _GameLine extends StatelessWidget {
  const _GameLine({required this.game});
  final GameDefinition game;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF2EAE3)),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: game.accent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(game.icon, color: ink.withValues(alpha: .8)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                game.tagline,
                style: const TextStyle(
                  fontSize: 12,
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NetworkInfo extends StatelessWidget {
  const _NetworkInfo({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0E9FC),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: purple, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: ink,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
