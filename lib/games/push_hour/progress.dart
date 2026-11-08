import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/levels.dart';

/// Хранилище прогресса по «Push Hour»: открытые уровни и лучшие результаты.
///
/// Каркасный [SettingsController] хранит общие настройки (звук, имя, очки), но
/// не знает про уровни конкретной игры. Поэтому прогресс кампании живёт здесь,
/// прямо в SharedPreferences под собственными ключами. Так каркас остаётся
/// общим, а игра — самодостаточной.
class PushHourProgress extends ChangeNotifier {
  PushHourProgress();

  static const _unlockedKey = 'push_hour.unlocked';
  static const _bestPrefix = 'push_hour.best.';

  SharedPreferences? _preferences;

  /// Сколько уровней кампании открыто (1..campaignSize). Уровень 1 открыт
  /// всегда — с него начинают.
  int _unlockedLevel = 1;
  int get unlockedLevel => _unlockedLevel;

  /// Лучшее число ходов по каждому пройденному уровню. Если уровня нет в карте
  /// — он ещё не пройден.
  final Map<int, int> _bestMoves = <int, int>{};
  Map<int, int> get bestMoves => Map<int, int>.unmodifiable(_bestMoves);

  /// Загружает прогресс из хранилища. Безопасно вызывать один раз при старте.
  Future<void> load() async {
    _preferences = await SharedPreferences.getInstance();
    final stored = _preferences!.getInt(_unlockedKey);
    _unlockedLevel = stored == null ? 1 : stored.clamp(1, campaignLevels.length);
    _bestMoves.clear();
    for (final key in _preferences!.getKeys()) {
      if (!key.startsWith(_bestPrefix)) continue;
      final level = int.tryParse(key.substring(_bestPrefix.length));
      final moves = _preferences!.getInt(key);
      if (level != null && moves != null) _bestMoves[level] = moves;
    }
    notifyListeners();
  }

  /// Лучший результат уровня или null, если ещё не пройден.
  int? bestFor(int level) => _bestMoves[level];

  /// Открыт ли уровень для игры.
  bool isOpen(int level) => level >= 1 && level <= _unlockedLevel;

  /// Записывает победу: запоминает лучший результат и открывает следующий
  /// уровень. Тихо, если результат не побит прежний.
  ///
  /// Сначала обновляет состояние в памяти и зовёт слушателей, а сохранение на
  /// диск делает асинхронно. Так тесты и UI видят новый результат сразу, не
  /// дожидаясь SharedPreferences.
  Future<void> recordWin(int level, int moves) async {
    final best = _bestMoves[level];
    final newBest = best == null || moves < best;
    final next = level + 1;
    final unlocked = next > _unlockedLevel && next <= campaignLevels.length;
    if (newBest) _bestMoves[level] = moves;
    if (unlocked) _unlockedLevel = next;
    if (newBest || unlocked) notifyListeners();
    if (newBest) {
      await _preferences?.setInt('$_bestPrefix$level', moves);
    }
    if (unlocked) {
      await _preferences?.setInt(_unlockedKey, _unlockedLevel);
    }
  }

  /// Сколько звёзд заслужил результат: 3 — минимум или лучше, 2 — небольшой
  /// перебор, 1 — любой проход.
  int stars(int level, int moves) {
    final minimum = levelByNumber(level).minMoves;
    if (moves <= minimum) return 3;
    if (moves <= minimum + 4) return 2;
    return 1;
  }
}
