import 'package:flutter/widgets.dart';

import '../app/settings.dart';
import '../network/network_game_service.dart';
import '../network/protocol.dart';

/// One card of the rules screen: the number in the circle, a title and the
/// explanation under it. The shared rules screen draws the cards in the order
/// the game lists them.
class RuleCard {
  const RuleCard({
    required this.number,
    required this.title,
    required this.text,
  });

  /// Shown as is inside the circle. The framework does not renumber cards, so
  /// the game stays in charge of how its rules are counted.
  final int number;
  final String title;
  final String text;
}

/// A switch that the game declares itself.
///
/// The shared settings screen renders every declared switch with the same row
/// as the sound switch, and stores it under `game.<id>.<key>`.
class GameSetting {
  const GameSetting({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.defaultValue = true,
  });

  /// Latin key, unique inside one game. Together with the game id it becomes
  /// the storage key.
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;

  /// What the switch shows until the child touches it.
  final bool defaultValue;
}

/// A live session between two devices, handed to the game's own session screen.
///
/// The transport is created, negotiated and kept alive by the lobby page; the
/// game only reads the lobby it was opened with and sends its own moves.
class NetworkSession {
  const NetworkSession({
    required this.service,
    required this.lobby,
    required this.isHost,
  });

  final NetworkGameService service;

  /// What the two devices agreed on before the session started.
  final LobbyConfig lobby;

  /// Whether this device created the game.
  final bool isHost;

  /// Name the other device sent during the handshake.
  String get peerName => service.peerName;
}

/// Where the «Играть» button of a game card leads.
///
/// [network] is null for a game on one device and is filled by [NetworkPage]
/// after a friend connected. The game itself decides which screen to open.
typedef GameStart =
    Future<void> Function(
      BuildContext context,
      SettingsController settings, {
      NetworkSession? network,
    });

/// The options a game shows to its opponent, as a JSON-ready map.
typedef GameOptions = Map<String, Object?> Function(
  SettingsController settings,
);

/// The reverse of [GameOptions]: reads the opponent's map and throws
/// [FormatException] on data this game does not understand. The framework only
/// checks that the call did not throw; the game keeps its own parsed object.
typedef GameOptionsParser = Object? Function(Map<String, Object?> options);

/// Checks one move received over the network against the rules of the game.
/// Throws [FormatException] when the move cannot be played.
typedef GameMoveCheck = void Function(Map<String, Object?> move);

/// Which side the host gets. The scaffold keeps it as an opaque label: a game
/// with sides returns its real one, a game without sides returns whatever it
/// wants to call the host's place.
typedef GameHostSide = String Function(SettingsController settings);

/// Everything the shared screens need to know about one game.
///
/// A new game is one object of this type listed in `GameCatalog.games`; the
/// menu, the game list, the rules screen, the settings screen and the network
/// lobby never mention a particular game.
class GameDefinition {
  GameDefinition({
    required this.id,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.rules,
    required this.settings,
    required this.start,
    required this.options,
    required this.parseOptions,
    required this.validateMove,
    required this.hostSide,
  }) : assert(id != '', 'У игры должен быть id'),
       assert(rules.isNotEmpty, 'У игры должны быть правила: $id'),
       assert(
         settings.every((setting) => setting.key != ''),
         'У переключателя должен быть ключ: $id',
       );

  /// Latin identifier. It goes into storage keys and into the network
  /// handshake, so it must never change once the game is published.
  final String id;

  /// Big line of the card and title of the session screen.
  final String title;

  /// Small line under the title.
  final String tagline;
  final IconData icon;

  /// Colour of the game card, taken from the palette.
  final Color accent;
  final List<RuleCard> rules;
  final List<GameSetting> settings;
  final GameStart start;

  /// What this game tells the opponent about itself.
  final GameOptions options;

  /// Reads the opponent's options and rejects foreign data.
  final GameOptionsParser parseOptions;

  /// Checks a move that arrived over the network.
  ///
  /// The lobby hands this function to the shared transport, which calls it for
  /// every incoming move before the session sees it. Throwing [FormatException]
  /// refuses the move and closes the connection, so the two devices never
  /// disagree about the position.
  final GameMoveCheck validateMove;

  /// The host's place in the game, sent in the lobby.
  final GameHostSide hostSide;
}
