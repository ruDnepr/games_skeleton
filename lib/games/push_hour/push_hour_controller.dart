import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/levels.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';
import 'progress.dart';

/// Состояние партии «Push Hour»: поле, история, ходы, подсказка и прогресс.
///
/// Контроллер один ведёт партию — и на одном устройстве, и по сети. Сеть не
/// синхронизирует поле пошагово: устройства соревнуются «кто раньше выедет»,
/// сообщая друг другу прогресс (число ходов) и победу. Так расхождения не
/// бывает, а ходить можно в своём темпе.
class PushHourController extends ChangeNotifier {
  PushHourController({
    required this.settings,
    required this.sounds,
    required this.progress,
    required Level level,
    this.network,
  }) : isHost = network?.isHost ?? false {
    _level = level;
    _grid = level.grid.copy();
    if (network != null) {
      _remoteName = network!.peerName.isEmpty ? 'Друг' : network!.peerName;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    _startTimer();
  }

  final SettingsController settings;
  final GameSounds sounds;
  final PushHourProgress progress;
  final NetworkSession? network;
  final bool isHost;

  late Level _level;
  Level get level => _level;

  late Grid _grid;
  Grid get grid => _grid;

  final List<Grid> _history = <Grid>[];
  List<Grid> get history => List<Grid>.unmodifiable(_history);

  int _moves = 0;
  int get moves => _moves;

  int _seconds = 0;
  int get seconds => _seconds;

  bool _solved = false;
  bool get solved => _solved;

  Move? _hint;
  Move? get hint => _hint;

  int _remoteMoves = 0;
  int get remoteMoves => _remoteMoves;

  String _remoteName = 'Друг';
  String get remoteName => _remoteName;

  bool _remoteSolved = false;
  bool get remoteSolved => _remoteSolved;

  /// Игра идёт по сети — показываем прогресс друга.
  bool get hasNetwork => network != null;

  bool get hintsEnabled => settings.flag(pushHourGameId, 'hints');

  StreamSubscription<NetworkMessage>? _networkSub;
  Timer? _timer;
  bool _disposed = false;

  // ---- Жизненный цикл ------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_solved || _disposed) return;
      _seconds++;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_networkSub?.cancel());
    super.dispose();
  }

  // ---- Ходы ----------------------------------------------------------------

  /// Пытается сдвинуть машину [car] на одну клетку вдоль её оси в сторону
  /// [step] (-1 или +1). Возвращает true, если ход удался.
  ///
  /// [quiet] — не пищать при упоре в соседнюю машину: при свайпе палец
  /// проходит порог несколько раз, и звук «мимо» только раздражает.
  bool tryMove(Car car, int step, {bool quiet = false}) {
    if (_solved) return false;
    final next = RushHourRules.move(_grid, car.id, step);
    if (next == null) {
      if (!quiet) sounds.play(GameSound.miss);
      return false;
    }
    _history.add(_grid);
    _grid = next;
    _moves++;
    _hint = null;
    notifyListeners();
    sounds.play(GameSound.move);
    _sendProgress();
    if (RushHourRules.isSolved(next)) _finishLevel();
    return true;
  }

  /// Куда сдвинуть машину по нажатию: туда, где есть свободное место.
  /// Возвращает null, если машина заблокирована с обеих сторон.
  int? preferredStep(Car car) {
    if (RushHourRules.canMove(_grid, car.id, 1)) return 1;
    if (RushHourRules.canMove(_grid, car.id, -1)) return -1;
    return null;
  }

  /// Нажатие на машину — сдвигает в любую доступную сторону.
  bool tapCar(Car car) {
    final step = preferredStep(car);
    if (step == null) {
      sounds.play(GameSound.miss);
      return false;
    }
    return tryMove(car, step);
  }

  /// Отменяет последний ход. Тихо, если истории нет или уровень уже пройден.
  void undo() {
    if (_history.isEmpty || _solved) {
      sounds.play(GameSound.miss);
      return;
    }
    _grid = _history.removeLast();
    if (_moves > 0) _moves--;
    _hint = null;
    notifyListeners();
    sounds.play(GameSound.move);
    _sendProgress();
  }

  /// Начинает уровень заново.
  void restart() {
    _grid = _level.grid.copy();
    _moves = 0;
    _seconds = 0;
    _solved = false;
    _hint = null;
    _history.clear();
    _startTimer();
    notifyListeners();
    _sendProgress();
  }

  /// Запрашивает подсказку у солвера. Возвращает:
  /// * true — подсказка показана;
  /// * false — подсказку здесь не найти (например, позиция тупиковая);
  /// * null — уровень уже пройден.
  bool? requestHint() {
    if (_solved) return null;
    final hint = RushHourSolver.hint(_grid);
    if (hint == null) return false;
    // Лампочка работает всегда: если подсказки были выключены в настройках,
    // просто включаем их здесь, чтобы кнопка не отвечала молчанием.
    if (!hintsEnabled) {
      unawaited(settings.setFlag(pushHourGameId, 'hints', true));
    }
    sounds.play(GameSound.guess);
    _hint = hint;
    notifyListeners();
    return true;
  }

  /// Загружает следующий уровень кампании. Возвращает false, если следующего
  /// уровня нет.
  bool goToNextLevel() {
    final next = _level.number + 1;
    if (next > campaignLevels.length) return false;
    loadLevel(levelByNumber(next));
    return true;
  }

  /// Есть ли следующий уровень в кампании.
  bool get hasNextLevel => _level.number < campaignLevels.length;

  /// Загружает произвольный уровень.
  void loadLevel(Level level) {
    _level = level;
    _grid = level.grid.copy();
    _moves = 0;
    _seconds = 0;
    _solved = false;
    _hint = null;
    _history.clear();
    _startTimer();
    notifyListeners();
    _sendProgress();
  }

  void _finishLevel() {
    _solved = true;
    _timer?.cancel();
    sounds.play(GameSound.win);
    unawaited(settings.recordGame(won: true));
    unawaited(progress.recordWin(_level.number, _moves));
    _sendSolved();
    notifyListeners();
  }

  // ---- Сеть ----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    if (event.type == 'event') {
      final kind = event.data['kind'];
      if (kind == 'progress') {
        final moves = event.data['moves'];
        final name = event.data['name'];
        if (moves is int) _remoteMoves = moves;
        if (name is String && name.trim().isNotEmpty) _remoteName = name;
        notifyListeners();
      } else if (kind == 'solved') {
        final moves = event.data['moves'];
        final name = event.data['name'];
        _remoteSolved = true;
        if (moves is int) _remoteMoves = moves;
        if (name is String && name.trim().isNotEmpty) _remoteName = name;
        notifyListeners();
      }
    } else if (event.type == 'disconnected') {
      // Связь потеряна: играем дальше одного. Просто перестаём слушать друга.
      _remoteName = 'Друг';
      notifyListeners();
    }
  }

  void _sendProgress() {
    final session = network;
    if (session == null) return;
    try {
      session.service.send(
        NetworkMessage('event', {
          'kind': 'progress',
          'moves': _moves,
          'name': settings.nickname,
        }),
      );
    } catch (_) {
      // Связь могла оборваться — ничего не поделаешь, играем дальше.
    }
  }

  void _sendSolved() {
    final session = network;
    if (session == null) return;
    try {
      session.service.send(
        NetworkMessage('event', {
          'kind': 'solved',
          'moves': _moves,
          'name': settings.nickname,
        }),
      );
    } catch (_) {
      // Связь оборвалась, но победа уже зафиксирована локально.
    }
  }
}
