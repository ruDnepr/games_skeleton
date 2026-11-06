import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/backgammon/game.dart';
import 'package:games_for_diana/games/backgammon/network.dart';
import 'package:games_for_diana/network/protocol.dart';

/// Контракт игры «Нарды»: каталог, карточки правил, ключи переключателей,
/// опции через общий конверт и проверка формата хода.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('каталог: id латиницей и без повторов', () {
    expect(GameCatalog.games, isNotEmpty);
    final ids = GameCatalog.games.map((game) => game.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(isGameId(id), isTrue, reason: id);
    }
    expect(GameCatalog.byId(backgammonGameId), isNotNull);
    expect(GameCatalog.byId('darts'), isNull);
    expect(GameCatalog.first.id, ids.first);
    expect(backgammonGame.id, 'backgammon');
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

  test('у каждой игры свои ключи переключателей и дефолты', () {
    for (final game in GameCatalog.games) {
      final keys = game.settings.map((setting) => setting.key).toList();
      expect(keys.toSet().length, keys.length, reason: game.id);
      for (final setting in game.settings) {
        // Латиница, цифры и подчёркивание, со строчной буквы; camelCase
        // (например, autoRoll) тоже допустим.
        expect(setting.key, matches(RegExp(r'^[a-z][a-zA-Z0-9_]*$')));
        expect(
          GameCatalog.defaultFlag(game.id, setting.key),
          setting.defaultValue,
        );
      }
    }
    // У нард три переключателя: hints, numbers и autoRoll.
    expect(backgammonGame.settings.map((s) => s.key).toSet(),
        {'hints', 'numbers', 'autoRoll'});
  });

  test('опции игры проходят через общий конверт', () {
    final settings = SettingsController();
    addTearDown(settings.dispose);

    final lobby = LobbyConfig(
      gameId: backgammonGameId,
      hostSide: backgammonGame.hostSide(settings),
      code: 'ABC234',
      hostName: settings.nickname,
      options: backgammonGame.options(settings),
    );
    expect(lobby.hostSide, 'white');

    final received = LobbyConfig.fromJson(lobby.toJson());
    final options = backgammonParseOptions(received.options);
    expect(options.hints, isTrue); // по умолчанию
    expect(options.numbers, isFalse);
  });

  test('опции другой игры отвергаются', () {
    expect(
      () => backgammonParseOptions({'something': 1}),
      throwsFormatException,
    );
    // Недостающий ключ — отказ.
    expect(
      () => backgammonParseOptions({'hints': true}),
      throwsFormatException,
    );
    expect(
      () => backgammonParseOptions({'hints': 1, 'numbers': false}),
      throwsFormatException,
    );
    // Полный набор проходит.
    expect(
      backgammonParseOptions({
        'hints': false,
        'numbers': true,
        'autoRoll': true,
      }).autoRoll,
      isTrue,
    );
  });

  test('проверка хода смотрит формат: цвет, кости, шаги', () {
    // Корректный ход проходит.
    backgammonValidateMove({
      'player': 'white',
      'dice': [3, 5],
      'moves': [
        {'player': 'white', 'die': 3, 'from': 23, 'to': 20},
      ],
    });
    // Вынос (to = null) и вход с бара (from = null) тоже допустимы формально.
    backgammonValidateMove({
      'player': 'black',
      'dice': [6, 1],
      'moves': [
        {'player': 'black', 'die': 6, 'from': 18, 'to': null},
        {'player': 'black', 'die': 1, 'from': null, 'to': 0},
      ],
    });

    // Чужой цвет.
    expect(
      () => backgammonValidateMove({
        'player': 'red',
        'dice': [3, 5],
        'moves': [],
      }),
      throwsFormatException,
    );
    // Не те кости.
    expect(
      () => backgammonValidateMove({
        'player': 'white',
        'dice': [7, 1],
        'moves': [],
      }),
      throwsFormatException,
    );
    // Кости не из броска.
    expect(
      () => backgammonValidateMove({
        'player': 'white',
        'dice': [3, 5],
        'moves': [
          {'player': 'white', 'die': 4, 'from': 23, 'to': 19},
        ],
      }),
      throwsFormatException,
    );
    // Слишком много шагов.
    expect(
      () => backgammonValidateMove({
        'player': 'white',
        'dice': [3, 5],
        'moves': List.filled(5, {'player': 'white', 'die': 3, 'from': 23, 'to': 20}),
      }),
      throwsFormatException,
    );
  });
}
