// Контракт игры «Го»: каталог, карточки правил, ключи переключателей,
// опции через общий конверт и проверка формата хода. По образцу
// `test/games/backgammon_game_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/catalog.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/go/engine/model.dart';
import 'package:games_for_diana/games/go/game.dart';
import 'package:games_for_diana/games/go/network.dart';
import 'package:games_for_diana/network/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('каталог: id латиницей, го в списке', () {
    expect(GameCatalog.games, isNotEmpty);
    final ids = GameCatalog.games.map((game) => game.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, contains(goGameId));
    expect(GameCatalog.byId(goGameId), isNotNull);
    expect(GameCatalog.byId('go'), goGame);
    expect(goGame.id, 'go');
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
    // У го пять правил: постановка, захват, самоубийство, ко, два режима.
    expect(goGame.rules, hasLength(5));
    expect(goGame.rules.first.title, 'Ставь камни на пересечения');
    expect(goGame.rules.last.title, 'Два режима');
  });

  test('у го свои ключи переключателей и дефолты', () {
    final keys = goGame.settings.map((s) => s.key).toSet();
    expect(keys, {'hints', 'hintButton'});
    for (final setting in goGame.settings) {
      expect(setting.key, matches(RegExp(r'^[a-z][a-zA-Z0-9_]*$')));
      expect(
        GameCatalog.defaultFlag(goGame.id, setting.key),
        setting.defaultValue,
      );
    }
  });

  group('опции', () {
    late SettingsController settings;

    setUp(() async {
      settings = SettingsController();
      await settings.load();
      settings.sound = false;
    });

    tearDown(() => settings.dispose);

    test('проходят через общий конверт', () async {
      // Сначала сохраняем выбор хоста — он входит в опции.
      await saveGoHostSetup(
        settings,
        mode: GoMode.classic,
        boardSize: 13,
        target: CaptureTarget.three,
        side: StoneColor.white,
      );

      final lobby = LobbyConfig(
        gameId: goGameId,
        hostSide: goGame.hostSide(settings),
        code: 'ABC234',
        hostName: settings.nickname,
        options: goOptions(settings),
      );
      expect(lobby.hostSide, 'white');

      final received = LobbyConfig.fromJson(lobby.toJson());
      final options = goParseOptions(received.options);
      expect(options.hints, isTrue); // по умолчанию
      expect(options.hintButton, isTrue);
      expect(options.mode, GoMode.classic);
      expect(options.boardSize, 13);
      expect(options.captureTarget, CaptureTarget.three);
      expect(options.hostSide, StoneColor.white);
    });

    test('опции другой игры отвергаются', () {
      expect(
        () => goParseOptions({'something': 1}),
        throwsFormatException,
      );
      // Недостающий ключ — отказ.
      expect(
        () => goParseOptions({'hints': true}),
        throwsFormatException,
      );
      // Чужой тип — отказ.
      expect(
        () => goParseOptions({
          'hints': 1,
          'hintButton': true,
          'mode': 'capture',
          'boardSize': 9,
          'captureTarget': 1,
          'hostSide': 'black',
        }),
        throwsFormatException,
      );
      // Чужой размер — отказ.
      expect(
        () => goParseOptions({
          'hints': true,
          'hintButton': true,
          'mode': 'capture',
          'boardSize': 7,
          'captureTarget': 1,
          'hostSide': 'black',
        }),
        throwsFormatException,
      );
      // Чужая цель — отказ.
      expect(
        () => goParseOptions({
          'hints': true,
          'hintButton': true,
          'mode': 'capture',
          'boardSize': 9,
          'captureTarget': 2,
          'hostSide': 'black',
        }),
        throwsFormatException,
      );
      // Полный набор проходит — захват и классика.
      expect(
        goParseOptions({
          'hints': false,
          'hintButton': true,
          'mode': 'capture',
          'boardSize': 9,
          'captureTarget': 1,
          'hostSide': 'black',
        }).mode,
        GoMode.capture,
      );
      expect(
        goParseOptions({
          'hints': false,
          'hintButton': true,
          'mode': 'classic',
          'boardSize': 19,
          'captureTarget': 3,
          'hostSide': 'white',
        }).mode,
        GoMode.classic,
      );
    });
  });

  group('проверка хода', () {
    test('принимает корректный ход-постановку', () {
      goValidateMove({
        'color': 'black',
        'pass': false,
        'point': [4, 4],
      });
    });

    test('принимает пас', () {
      goValidateMove({
        'color': 'white',
        'pass': true,
      });
      // Пас без явного `pass: true` не считается пасом — нужна точка.
      // Но `pass: null` (отсутствие ключа) трактуется как постановка, что
      // требует точку.
    });

    test('принимает ход-постановку без явного pass', () {
      goValidateMove({
        'color': 'black',
        'point': [0, 0],
      });
    });

    test('отвергает чужой цвет', () {
      expect(
        () => goValidateMove({
          'color': 'red',
          'pass': true,
        }),
        throwsFormatException,
      );
    });

    test('отвергает чужой pass', () {
      expect(
        () => goValidateMove({
          'color': 'black',
          'pass': 'yes',
          'point': [0, 0],
        }),
        throwsFormatException,
      );
    });

    test('отвергает чужую точку', () {
      expect(
        () => goValidateMove({
          'color': 'black',
          'point': [4],
        }),
        throwsFormatException,
      );
      expect(
        () => goValidateMove({
          'color': 'black',
          'point': [4, 'a'],
        }),
        throwsFormatException,
      );
      expect(
        () => goValidateMove({
          'color': 'black',
          'point': [-1, 0],
        }),
        throwsFormatException,
      );
      expect(
        () => goValidateMove({
          'color': 'black',
          'point': [0, 19],
        }),
        throwsFormatException,
      );
    });

    test('формат хода совпадает с моделью', () {
      final move = GoMove.place(const Point(4, 4), color: StoneColor.black);
      expect(moveToJson(move), move.toJson());
      expect(parseMove(move.toJson()), move);
      final pass = GoMove.pass(color: StoneColor.white);
      expect(parseMove(pass.toJson()), pass);
    });
  });
}
