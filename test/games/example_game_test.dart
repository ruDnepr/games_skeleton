import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/example/game.dart';
import 'package:games_for_diana/games/example/network.dart';
import 'package:games_for_diana/network/protocol.dart';

/// The contract a game has to keep, checked on the example game.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('каталог: id латиницей и без повторов', () {
    expect(GameCatalog.games, isNotEmpty);
    final ids = GameCatalog.games.map((game) => game.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(isGameId(id), isTrue, reason: id);
    }
    expect(GameCatalog.byId(ids.first), isNotNull);
    expect(GameCatalog.byId('darts'), isNull);
    expect(GameCatalog.first.id, ids.first);
  });

  test('правила: карточки идут по порядку и заполнены', () {
    for (final game in GameCatalog.games) {
      expect(game.rules, isNotEmpty, reason: game.id);
      final numbers = game.rules.map((card) => card.number).toList();
      expect(numbers.toSet().length, numbers.length, reason: game.id);
      expect(numbers, orderedEquals([...numbers]..sort()), reason: game.id);
      for (final card in game.rules) {
        expect(card.title.trim(), isNotEmpty, reason: game.id);
        expect(card.text.trim(), isNotEmpty, reason: game.id);
      }
      expect(game.title.trim(), isNotEmpty);
      expect(game.tagline.trim(), isNotEmpty);
    }
  });

  test('у каждой игры свои ключи переключателей', () {
    for (final game in GameCatalog.games) {
      final keys = game.settings.map((setting) => setting.key).toList();
      expect(keys.toSet().length, keys.length, reason: game.id);
      for (final setting in game.settings) {
        expect(setting.key, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        expect(
          GameCatalog.defaultFlag(game.id, setting.key),
          setting.defaultValue,
        );
      }
    }
  });

  test('опции игры проходят через общий конверт', () {
    final settings = SettingsController();
    addTearDown(settings.dispose);

    final lobby = LobbyConfig(
      gameId: exampleGameId,
      hostSide: exampleGame.hostSide(settings),
      code: 'ABC234',
      hostName: settings.nickname,
      options: exampleGame.options(settings),
    );
    expect(lobby.hostSide, isNotEmpty);

    final received = LobbyConfig.fromJson(lobby.toJson());
    final options = exampleParseOptions(received.options);
    // Значения по умолчанию объявлены самой игрой.
    expect(options.reminder, isTrue);
    expect(options.markers, isFalse);
  });

  test('опции другой игры отвергаются', () {
    expect(
      () => exampleParseOptions({'something': 1}),
      throwsFormatException,
    );
    expect(
      () => exampleParseOptions({'reminder': true}),
      throwsFormatException,
    );
    expect(
      () => exampleParseOptions({'reminder': 1, 'markers': false}),
      throwsFormatException,
    );
    expect(exampleParseOptions({'reminder': false, 'markers': true}).markers,
        isTrue);
  });

  test('проверка хода смотрит только формат', () {
    exampleGame.validateMove({'from': 'a1', 'to': 'a3'});
    expect(
      () => exampleGame.validateMove({'from': 'a1', 'to': 'a1'}),
      throwsFormatException,
    );
    expect(
      () => exampleGame.validateMove({'from': 'z9', 'to': 'a3'}),
      throwsFormatException,
    );
    expect(
      () => exampleGame.validateMove({'from': 'a1'}),
      throwsFormatException,
    );
    expect(
      () => exampleGame.validateMove({}),
      throwsFormatException,
    );
  });
}
