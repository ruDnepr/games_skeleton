import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Контракт, который каждая игра каталога обязана соблюдать.
///
/// Проверка идёт по всем играм из [GameCatalog.games], а не по одной: так
/// добавление новой игры не требует нового теста — достаточно, чтобы она
/// попала в каталог. Те же инварианты, что раньше проверялись на примере
/// одной игры: латинский id, карточки правил по порядку, уникальные ключи
/// переключателей, опции через общий конверт и проверка формы хода.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('каталог: id латиницей и без повторов', () {
    expect(GameCatalog.games, isNotEmpty);
    final ids = GameCatalog.games.map((game) => game.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(isGameId(id), isTrue, reason: id);
    }
    for (final id in ids) {
      expect(GameCatalog.byId(id), isNotNull, reason: id);
    }
    expect(GameCatalog.byId('does_not_exist'), isNull);
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
      expect(game.title.trim(), isNotEmpty, reason: game.id);
      expect(game.tagline.trim(), isNotEmpty, reason: game.id);
    }
  });

  test('у каждой игры свои ключи переключателей', () {
    for (final game in GameCatalog.games) {
      final keys = game.settings.map((setting) => setting.key).toList();
      expect(keys.toSet().length, keys.length, reason: game.id);
      for (final setting in game.settings) {
        // Латиница, цифры и подчёркивание, со строчной буквы; camelCase
        // (например, autoRoll, hintButton) тоже допустим.
        expect(setting.key, matches(RegExp(r'^[a-z][a-zA-Z0-9_]*$')));
        expect(
          GameCatalog.defaultFlag(game.id, setting.key),
          setting.defaultValue,
          reason: '${game.id}.${setting.key}',
        );
      }
    }
  });

  test('опции каждой игры проходят через общий конверт', () {
    final settings = SettingsController();
    addTearDown(settings.dispose);

    for (final game in GameCatalog.games) {
      final lobby = LobbyConfig(
        gameId: game.id,
        hostSide: game.hostSide(settings),
        code: 'ABC234',
        hostName: settings.nickname,
        options: game.options(settings),
      );
      expect(lobby.hostSide, isNotEmpty, reason: game.id);

      // Обратный разбор: лобби приходит как JSON, игра разбирает свои опции.
      final received = LobbyConfig.fromJson(lobby.toJson());
      expect(received.gameId, game.id);
      expect(received.hostSide, lobby.hostSide);
      // Игра не должна бросить на собственных опциях.
      game.parseOptions(received.options);
    }
  });

  test('чужие опции отвергаются каждой игрой', () {
    for (final game in GameCatalog.games) {
      expect(
        () => game.parseOptions({'something_foreign': 1}),
        throwsFormatException,
        reason: game.id,
      );
    }
  });

  test('сторона хоста — непустая строка', () {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    for (final game in GameCatalog.games) {
      final side = game.hostSide(settings);
      expect(side, isNotEmpty, reason: game.id);
      expect(side.length, lessThanOrEqualTo(20), reason: game.id);
    }
  });
}
