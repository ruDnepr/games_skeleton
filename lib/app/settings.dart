import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// Settings that belong to the whole app rather than to one game.
///
/// A game keeps its own switches here as well: every [GameSetting] the game
/// declares is stored under `game.<id>.<key>`, so two games can use the same
/// switch name and never see each other's value. The default value of such a
/// switch is the one declared by the game, never a hardcoded one.
class SettingsController extends ChangeNotifier {
  SharedPreferences? _preferences;
  bool sound = true;
  String nickname = 'Диана';
  int gamesPlayed = 0;
  int gamesWon = 0;

  /// Known values, keyed by the full storage key. A switch that was never
  /// touched is not in the map and falls back to the game's default.
  final Map<String, bool> _flags = {};

  /// Storage key of one switch of one game. Public, because the tests and the
  /// README use the same shape to talk about stored values.
  static String flagKey(String gameId, String key) => 'game.$gameId.$key';

  Future<void> load() async {
    _preferences = await SharedPreferences.getInstance();
    sound = _preferences!.getBool('sound') ?? true;
    nickname = _preferences!.getString('nickname') ?? 'Диана';
    gamesPlayed = _preferences!.getInt('gamesPlayed') ?? 0;
    gamesWon = _preferences!.getInt('gamesWon') ?? 0;
    for (final game in GameCatalog.games) {
      for (final setting in game.settings) {
        final key = flagKey(game.id, setting.key);
        _flags[key] = _preferences!.getBool(key) ?? setting.defaultValue;
      }
    }
    notifyListeners();
  }

  /// Value of one switch of one game, or the default the game declared.
  bool flag(String gameId, String key) {
    final stored = _flags[flagKey(gameId, key)];
    if (stored != null) return stored;
    return GameCatalog.defaultFlag(gameId, key);
  }

  /// Stores one switch of one game. Writing the same value again is silent, so
  /// a switch that reports its own state cannot rebuild the page for nothing.
  Future<void> setFlag(String gameId, String key, bool value) async {
    if (flag(gameId, key) == value) return;
    final storageKey = flagKey(gameId, key);
    _flags[storageKey] = value;
    notifyListeners();
    await _preferences?.setBool(storageKey, value);
  }

  Future<void> setSound(bool value) async {
    if (sound == value) return;
    sound = value;
    notifyListeners();
    await _preferences?.setBool('sound', value);
  }

  /// Stores the name. The trimmed text is kept to 20 characters; an empty name
  /// falls back to «Диана». Nothing is announced when the name did not change,
  /// so the field that is being typed into is never rebuilt for nothing.
  Future<void> setNickname(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty
        ? 'Диана'
        : String.fromCharCodes(trimmed.runes.take(20));
    if (next == nickname) return;
    nickname = next;
    notifyListeners();
    await _preferences?.setString('nickname', next);
  }

  Future<void> recordGame({required bool won}) async {
    gamesPlayed++;
    if (won) gamesWon++;
    notifyListeners();
    await _preferences?.setInt('gamesPlayed', gamesPlayed);
    await _preferences?.setInt('gamesWon', gamesWon);
  }

  Future<void> resetProgress() async {
    gamesPlayed = 0;
    gamesWon = 0;
    notifyListeners();
    await _preferences?.setInt('gamesPlayed', 0);
    await _preferences?.setInt('gamesWon', 0);
  }
}
