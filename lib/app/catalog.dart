import '../games/backgammon/game.dart';
import '../games/battleship/game.dart';
import '../games/checkers/game.dart';
import '../games/definition.dart';
import '../games/domino/game.dart';
import '../games/go/game.dart';
import '../games/loto/game.dart';
import '../games/rendzu/game.dart';
import '../games/ticket_to_ride/game.dart';

/// Единственное место со списком игр приложения.
///
/// Главное окно, список игр, лобби, экраны правил и настроек читают этот
/// список. Добавить игру — значит добавить одну строку сюда и больше нигде.
/// Порядок карточек в меню — это порядок списка.
class GameCatalog {
  const GameCatalog._();

  static final List<GameDefinition> games = List.unmodifiable([
    checkersGame,
    rendzuGame,
    goGame,
    backgammonGame,
    battleshipGame,
    dominoGame,
    lotoGame,
    ticketToRideGame,
  ]);

  /// Игра, правила которой показывает пункт «Правила» главного меню.
  static GameDefinition get first => games.first;

  static GameDefinition? byId(String id) {
    for (final game in games) {
      if (game.id == id) return game;
    }
    return null;
  }

  /// Значение переключателя по умолчанию, как его объявила игра. Используется,
  /// пока ребёнок не тронул переключатель.
  static bool defaultFlag(String gameId, String key) {
    final game = byId(gameId);
    if (game == null) return false;
    for (final setting in game.settings) {
      if (setting.key == key) return setting.defaultValue;
    }
    return false;
  }
}
