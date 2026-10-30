import '../games/definition.dart';
import '../games/example/game.dart';

/// The one place where the games of the app are listed.
///
/// Everything else — the «Играть» list, the network lobby, the rules screen,
/// the settings screen — reads this list. Adding a game means adding one entry
/// here and nothing else.
class GameCatalog {
  const GameCatalog._();

  static final List<GameDefinition> games = List.unmodifiable([exampleGame]);

  /// The game the «Правила» item of the main menu shows.
  static GameDefinition get first => games.first;

  static GameDefinition? byId(String id) {
    for (final game in games) {
      if (game.id == id) return game;
    }
    return null;
  }

  /// Default value of one switch, as the game declared it. Used until the child
  /// touches the switch for the first time.
  static bool defaultFlag(String gameId, String key) {
    final game = byId(gameId);
    if (game == null) return false;
    for (final setting in game.settings) {
      if (setting.key == key) return setting.defaultValue;
    }
    return false;
  }
}
