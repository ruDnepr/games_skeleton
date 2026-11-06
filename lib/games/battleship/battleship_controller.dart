import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/history.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режим партии.
enum BattleshipMode { local, ai, network }

/// Фаза партии: расстановка, бой, окончание.
enum BattleshipPhase { setup, playing, over }

/// Кого сейчас ждём на выстрел — для подписи «чей ход».
enum BattleshipActiveSide { me, computer, friend, nobody }

/// Контроллер партии морского боя. Содержит состояние, историю, звук и сеть;
/// интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
///
/// **Приватность флота**: в сетевой игре корабли соперника никогда не
/// пересылаются — только координаты выстрелов и их результаты. Контроллер
/// хранит свой флот локально, а чужой остаётся неизвестным (`_enemyFleet`
/// пустой); результат вычисляет тот, по кому стреляли.
class BattleshipController extends ChangeNotifier {
  BattleshipController({
    required this.settings,
    required this.sounds,
    this.network,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = BattleshipMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
  }

  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  late final bool isHost;

  BattleshipMode mode = BattleshipMode.local;
  Difficulty difficulty = Difficulty.medium;
  BattleshipPhase phase = BattleshipPhase.setup;

  /// Чей сейчас выстрел (с точки зрения этого устройства: «me» = моя очередь).
  Side _turn = Side.me;
  Side? _winner;

  /// Мой флот — всегда видим этому устройству. В расстановке это флот того,
  /// кто сейчас расставляет; в игре — мой флот.
  Fleet _myFleet = emptyFleet;

  /// Флот соперника. В режиме ИИ и вдвоём на одном устройстве — известен
  /// (туман войны только в UI). В сети — пустой: мы его не знаем.
  Fleet _enemyFleet = emptyFleet;

  /// Для локального режима 2 на 1: после расстановки первого игрока его флот
  /// прячем сюда, чтобы второй игрок не видел чужие корабли во время своей
  /// расстановки. Когда второй готов — перекладываем в `_myFleet`/`_enemyFleet`.
  Fleet _stashedFleet = emptyFleet;

  /// В локальном режиме 2 на 1: чья сейчас расстановка (0 — первый игрок,
  /// 1 — второй). В других режимах всегда 0.
  int _setupTurn = 0;

  /// Готовность к бою. В сети — оба игрока должны послать `fleetReady`, чтобы
  /// началась партия.
  bool _myReady = false;
  bool _enemyReady = false;

  /// Мои выстрелы по сопернику: клетка → выстрел с результатом.
  final Map<Square, Shot> _myShots = {};

  /// Выстрелы соперника по мне: клетка → выстрел с результатом.
  final Map<Square, Shot> _enemyShots = {};

  /// История выстрелов для отмены хода (офлайн). По сети отмены нет — правила
  /// морского боя необратимы после результата.
  final ShotHistory _history = ShotHistory();
  final List<BoardSnapshot> _snapshots = [];

  /// Подсказка: клетка, куда стоит стрелять (показывается, пока игрок не
  /// выстрелит или не нажмёт «Скрыть»).
  Square? _hint;
  String? _status;
  bool _busy = false;
  bool _disposed = false;
  Timer? _aiTimer;
  StreamSubscription<NetworkMessage>? _networkSub;

  final Random _rng = Random();
  static const BattleshipRules _rules = BattleshipRules();

  // ---- Доступ к состоянию ---------------------------------------------------

  Fleet get myFleet => _myFleet;
  Fleet get enemyFleet => _enemyFleet;
  Side get turn => _turn;
  Side? get winner => _winner;
  bool get isOver => phase == BattleshipPhase.over || _winner != null;
  bool get myReady => _myReady;
  bool get enemyReady => _enemyReady;
  bool get busy => _busy;
  String? get status => _status;
  Square? get hint => _hint;

  /// Мои выстрелы по сопернику (для отрисовки верхнего поля).
  Map<Square, Shot> get myShots => Map.unmodifiable(_myShots);

  /// Выстрелы соперника по мне (для отрисовки нижнего поля).
  Map<Square, Shot> get enemyShots => Map.unmodifiable(_enemyShots);

  /// Подсказки включены в настройках.
  bool get hintsEnabled => settings.flag(battleshipGameId, 'hints');

  /// Расстановка завершена и можно стрелять.
  bool get setupComplete => phase == BattleshipPhase.playing;

  /// Чья сейчас расстановка в локальном режиме 2 на 1: 0 — первый игрок,
  /// 1 — второй. В других режимах всегда 0.
  int get setupTurn => _setupTurn;

  /// Все ли 10 кораблей расставлены у того, кто сейчас расставляет.
  bool get myFleetComplete => _myFleet.isComplete;

  /// Активная сторона — для подписи «чей ход».
  BattleshipActiveSide get activeSide {
    if (isOver) return BattleshipActiveSide.nobody;
    if (phase == BattleshipPhase.setup) {
      if (mode == BattleshipMode.network) {
        // В сети ждём, пока оба расставят флот.
        return _myReady && !_enemyReady
            ? BattleshipActiveSide.friend
            : BattleshipActiveSide.me;
      }
      return BattleshipActiveSide.me;
    }
    if (mode == BattleshipMode.ai) {
      return _turn == Side.me
          ? BattleshipActiveSide.me
          : BattleshipActiveSide.computer;
    }
    if (mode == BattleshipMode.network) {
      return _turn == Side.me
          ? BattleshipActiveSide.me
          : BattleshipActiveSide.friend;
    }
    return BattleshipActiveSide.me; // вдвоём на одном устройстве — всегда человек
  }

  /// Можно ли тапать по полю соперника прямо сейчас.
  bool get canInteract {
    if (isOver) return false;
    if (phase != BattleshipPhase.playing) return false;
    if (_busy) return false;
    if (mode == BattleshipMode.ai) return _turn == Side.me;
    if (mode == BattleshipMode.network) return _turn == Side.me;
    return true; // local: оба игрока — люди, тапать может текущий
  }

  /// Можно ли отменить последний ход. По сети отмены нет.
  bool get canUndo {
    if (isOver) return false;
    if (phase != BattleshipPhase.playing) return false;
    if (mode == BattleshipMode.network) return false;
    return _snapshots.isNotEmpty;
  }

  /// Можно ли сдаться.
  bool get canResign =>
      phase == BattleshipPhase.playing && mode != BattleshipMode.local;

  /// Подпись «чей ход» в строку состояния.
  String get turnLabel {
    if (phase == BattleshipPhase.setup) {
      if (mode == BattleshipMode.network) {
        if (!_myReady) return 'Расставь корабли';
        if (!_enemyReady) return 'Ждём, когда друг расставит корабли…';
      }
      return 'Расставь корабли';
    }
    if (mode == BattleshipMode.local) {
      if (isOver) return 'Партия окончена';
      return _turn == Side.me
          ? 'Ход игрока 1 — стреляй по полю игрока 2!'
          : 'Ход игрока 2 — стреляй по полю игрока 1!';
    }
    switch (activeSide) {
      case BattleshipActiveSide.me:
        return 'Твой ход — стреляй по полю соперника!';
      case BattleshipActiveSide.computer:
        return 'Компьютер думает…';
      case BattleshipActiveSide.friend:
        return 'Ходит друг…';
      case BattleshipActiveSide.nobody:
        return isOver ? 'Партия окончена' : '';
    }
  }

  /// Имя игрока для верхней/нижней панели.
  String playerName(Side side) {
    if (mode == BattleshipMode.local) {
      return side == Side.me ? 'Игрок 1' : 'Игрок 2';
    }
    if (mode == BattleshipMode.ai) {
      return side == Side.me ? settings.nickname : 'Компьютер';
    }
    // Сеть: хост = me, клиент = enemy.
    final mine = isHost ? Side.me : Side.enemy;
    if (side == mine) return settings.nickname;
    return network?.peerName ?? 'Друг';
  }

  /// Чья очередь с точки зрения этого устройства. В сети у хоста `me`, у
  /// клиента `enemy`.
  Side get _mySide => mode == BattleshipMode.network
      ? (isHost ? Side.me : Side.enemy)
      : Side.me;

  // ---- Расстановка ---------------------------------------------------------

  /// Можно ли поставить корабль [type] в [origin] с ориентацией [orientation].
  /// Не меняет состояние — нужно для подсветки в UI.
  bool canPlaceShip(
    ShipType type,
    Square origin,
    Orientation orientation,
  ) {
    final ship = Ship(type: type, origin: origin, orientation: orientation);
    return _rules.canPlace(_myFleet, ship);
  }

  /// Сколько ещё кораблей типа [type] можно поставить.
  int remainingToPlace(ShipType type) =>
      type.count - _myFleet.countOf(type);

  /// Ставит корабль [type] в [origin] с ориентацией [orientation]. Если нельзя
  /// (не помещается, касается других или лимит исчерпан) — ничего не делает.
  /// Возвращает true, если корабль поставлен.
  bool placeShip(
    ShipType type,
    Square origin,
    Orientation orientation,
  ) {
    if (phase != BattleshipPhase.setup) return false;
    if (_myReady) return false;
    if (remainingToPlace(type) <= 0) return false;
    final ship = Ship(type: type, origin: origin, orientation: orientation);
    if (!_rules.canPlace(_myFleet, ship)) return false;
    _myFleet = _rules.withShip(_myFleet, ship);
    _status = null;
    notifyListeners();
    return true;
  }

  /// Убирает корабль, стоящий в клетке [cell]. Если в клетке корабля нет —
  /// ничего не делает.
  void removeShipAt(Square cell) {
    if (phase != BattleshipPhase.setup) return;
    if (_myReady) return;
    final next = _rules.withoutShipAt(_myFleet, cell);
    if (next == _myFleet) return;
    _myFleet = next;
    _status = null;
    notifyListeners();
  }

  /// Случайная корректная расстановка полного флота. Удобно, когда не хочется
  /// расставлять вручную.
  void autoArrange() {
    if (phase != BattleshipPhase.setup) return;
    if (_myReady) return;
    _myFleet = _rules.autoFleet(_rng);
    _status = null;
    notifyListeners();
  }

  /// Очищает расстановку — например, чтобы начать заново.
  void clearFleet() {
    if (phase != BattleshipPhase.setup) return;
    if (_myReady) return;
    _myFleet = emptyFleet;
    _status = null;
    notifyListeners();
  }

  /// Поворачивает корабль в клетке [cell]: убирает его и... возвращает с другой
  /// ориентацией, если это возможно. Удобно для кнопки «Повернуть».
  void rotateShipAt(Square cell) {
    if (phase != BattleshipPhase.setup) return;
    if (_myReady) return;
    final ship = _myFleet.shipAt(cell);
    if (ship == null) return;
    final without = _rules.withoutShipAt(_myFleet, cell);
    final rotated = Ship(
      type: ship.type,
      origin: ship.origin,
      orientation: ship.orientation.flipped,
    );
    if (_rules.canPlace(without, rotated)) {
      _myFleet = _rules.withShip(without, rotated);
      notifyListeners();
      return;
    }
    // Не помещается повёрнутым — попробуем сдвинуть, чтобы влез.
    for (final origin in allSquares()) {
      final candidate = Ship(
        type: ship.type,
        origin: origin,
        orientation: ship.orientation.flipped,
      );
      if (_rules.canPlace(without, candidate)) {
        _myFleet = _rules.withShip(without, candidate);
        notifyListeners();
        return;
      }
    }
  }

  /// Игрок закончил расстановку. В сети — отправляет `fleetReady` и ждёт
  /// соперника. В ИИ — автоматически расставляет флот компьютера и начинает
  /// бой. В локальном режиме 2 на 1 — прячет флот первого игрока и переходит
  /// ко второму; когда второй готов — начинает бой.
  void fleetReady() {
    if (phase != BattleshipPhase.setup) return;
    if (_myReady) return;
    if (!_myFleet.isComplete) return;

    switch (mode) {
      case BattleshipMode.ai:
        _enemyFleet = _rules.autoFleet(_rng);
        _myReady = true;
        _enemyReady = true;
        _beginPlay();
        break;
      case BattleshipMode.local:
        if (_setupTurn == 0) {
          // Первый игрок готов — прячем его флот, расставляет второй.
          _stashedFleet = _myFleet;
          _myFleet = emptyFleet;
          _myReady = false;
          _setupTurn = 1;
          _status = 'Игрок 2 расставляет флот';
          notifyListeners();
        } else {
          // Второй игрок готов — оба флота на месте, начинаем.
          _enemyFleet = _myFleet;
          _myFleet = _stashedFleet;
          _stashedFleet = emptyFleet;
          _myReady = true;
          _enemyReady = true;
          _beginPlay();
        }
        break;
      case BattleshipMode.network:
        _myReady = true;
        network!.service.send(NetworkMessage('event', fleetReadyToJson()));
        _status = _enemyReady ? null : 'Ждём, когда друг расставит корабли…';
        notifyListeners();
        _maybeBeginNetworkPlay();
        break;
    }
  }

  /// Возвращает расстановку к началу (для экрана расстановки, если игрок
  /// хочет переиграть расстановку). В сети после `fleetReady` уже поздно.
  void restartSetup() {
    if (phase != BattleshipPhase.setup) return;
    if (mode == BattleshipMode.network && _myReady) return;
    _myFleet = emptyFleet;
    _stashedFleet = emptyFleet;
    _myReady = false;
    _setupTurn = 0;
    _status = null;
    notifyListeners();
  }

  // ---- Старт партий --------------------------------------------------------

  /// Начало партии против компьютера. Вызывается до расстановки.
  void startAi(Difficulty level, {bool meFirst = true}) {
    mode = BattleshipMode.ai;
    difficulty = level;
    _resetForSetup();
    _turn = meFirst ? Side.me : Side.enemy;
    notifyListeners();
    // Если человек не ходит первым, ИИ расставит флот и сразу откроет огонь
    // после расстановки человека — это произойдёт в `fleetReady`.
  }

  /// Начало партии вдвоём на одном устройстве.
  void startLocal() {
    mode = BattleshipMode.local;
    _resetForSetup();
    _turn = Side.me;
    notifyListeners();
  }

  /// Начало партии по сети. Хост стреляет первым.
  void startNetwork() {
    mode = BattleshipMode.network;
    _resetForSetup();
    _turn = Side.me; // условно; по сети настоящий ход определит хост
    notifyListeners();
  }

  void _resetForSetup() {
    phase = BattleshipPhase.setup;
    _myFleet = emptyFleet;
    _enemyFleet = emptyFleet;
    _stashedFleet = emptyFleet;
    _myReady = false;
    _enemyReady = false;
    _setupTurn = 0;
    _myShots.clear();
    _enemyShots.clear();
    _history.clear();
    _snapshots.clear();
    _hint = null;
    _status = null;
    _busy = false;
    _winner = null;
  }

  /// Переход из расстановки в бой.
  void _beginPlay() {
    phase = BattleshipPhase.playing;
    _status = null;
    notifyListeners();
    // Если первый ход не мой — стреляет ИИ (по сети в этой ветке не оказываемся:
    // там бой начинается в `_maybeBeginNetworkPlay`).
    if (mode == BattleshipMode.ai && _turn != Side.me) {
      _scheduleAiTurn();
    }
  }

  void _maybeBeginNetworkPlay() {
    if (_myReady && _enemyReady && phase == BattleshipPhase.setup) {
      // Хост стреляет первым. У хоста `me`, у клиента `enemy`.
      _turn = isHost ? Side.me : Side.enemy;
      _beginPlay();
    }
  }

  // ---- Выстрелы ------------------------------------------------------------

  /// Текущий игрок стреляет в [target]. В локальном режиме работает для обоих
  /// игроков; в ИИ — только для человека; в сети — только в свой ход.
  void shoot(Square target) {
    if (!canInteract) return;
    if (mode == BattleshipMode.local && _turn == Side.enemy) {
      _applyEnemyShot(target, remote: false);
      return;
    }
    if (_turn != Side.me) return;
    _applyMyShot(target, remote: false);
  }

  /// Я стреляю в [target]. В сети — отправляет выстрел сопернику и ждёт
  /// результат; офлайн — считает результат сам (мы знаем флот соперника).
  void _applyMyShot(Square target, {required bool remote}) {
    if (_myShots.containsKey(target)) return; // повторный выстрел запрещён
    // Снимок для отмены (офлайн).
    _pushSnapshot();

    if (mode == BattleshipMode.network) {
      // Отправляем выстрел; результат придёт сообщением `event` shotResult.
      final ply = _myShots.length + _enemyShots.length + 1;
      network!.service.send(
        NetworkMessage('move', shotToJson(target, ply)),
      );
      sounds.play(GameSound.guess);
      _busy = true;
      _hint = null;
      _status = 'Выстрел по клетке $target…';
      notifyListeners();
      return;
    }

    // Офлайн: мы знаем флот соперника, считаем сами.
    final shot = _rules.shootResult(_enemyFleet, _myShots, target);
    _myShots[target] = shot;
    _history.push(ShotRecord(
      shooter: Side.me,
      shot: shot,
      sunkBefore: _rules.sunkCount(_enemyFleet, _myShots),
      allSunkBefore: false,
    ));
    _busy = false;
    _hint = null;
    _afterMyShot(shot, remote: remote);
  }

  /// Действия после моего выстрела (звук, переход хода, победа).
  void _afterMyShot(Shot shot, {required bool remote}) {
    sounds.play(GameSound.guess);
    switch (shot.result) {
      case ShotResult.miss:
        sounds.play(GameSound.miss);
        _status = 'Мимо! Ход переходит к сопернику.';
        _turn = Side.enemy;
        notifyListeners();
        _maybeAiTurn();
        break;
      case ShotResult.hit:
        sounds.play(GameSound.capture);
        _status = 'Попадание! Стреляй ещё раз.';
        notifyListeners();
        break;
      case ShotResult.sunk:
        sounds.play(GameSound.capture);
        sounds.play(GameSound.crown);
        _status = 'Потоплен ${shot.sunkType?.russianLabel ?? 'корабль'}! '
            'Стреляй ещё раз.';
        notifyListeners();
        break;
    }
    if (_rules.fleetSunk(_enemyFleet, _myShots)) {
      _onWin(Side.me);
    }
  }

  /// Соперник стреляет в [target]. В сети — это вызывается при получении `move`
  /// от соперника: мы знаем свой флот, считаем результат, отправляем обратно
  /// `event` shotResult. Офлайн — в локальном режиме 2 на 1 человек стреляет
  /// за соперника; в ИИ — стреляет компьютер.
  void _applyEnemyShot(Square target, {required bool remote}) {
    if (_enemyShots.containsKey(target)) return;
    _pushSnapshot();

    // Свой флот всегда знаем — даже в сети (это наш флот).
    final shot = _rules.shootResult(_myFleet, _enemyShots, target);
    _enemyShots[target] = shot;
    _history.push(ShotRecord(
      shooter: Side.enemy,
      shot: shot,
      sunkBefore: _rules.sunkCount(_myFleet, _enemyShots),
      allSunkBefore: false,
    ));
    sounds.play(GameSound.guess);

    if (mode == BattleshipMode.network) {
      // Отправляем результат обратно сопернику.
      final nextTurn = shot.result == ShotResult.miss ? 'me' : 'enemy';
      final ply = _myShots.length + _enemyShots.length;
      network!.service.send(
        NetworkMessage('event', shotResultToJson(
          ply: ply,
          square: target,
          result: shot.result,
          sunkType: shot.sunkType,
          nextTurn: nextTurn,
        )),
      );
    }

    switch (shot.result) {
      case ShotResult.miss:
        sounds.play(GameSound.miss);
        _status = 'Соперник промахнулся в $target. Твой ход!';
        _turn = Side.me;
        _busy = false;
        notifyListeners();
        break;
      case ShotResult.hit:
        sounds.play(GameSound.capture);
        _status = 'Соперник попал в $target! Стреляет ещё раз.';
        notifyListeners();
        // В ИИ — ходит ИИ снова; в сети — ждём следующий выстрел; в локальном —
        // текущий игрок (теперь это соперник) стреляет снова.
        _maybeAiTurn();
        break;
      case ShotResult.sunk:
        sounds.play(GameSound.capture);
        sounds.play(GameSound.crown);
        _status = 'Соперник потопил ваш ${shot.sunkType?.russianLabel ?? 'корабль'}. '
            'Стреляет ещё раз.';
        notifyListeners();
        _maybeAiTurn();
        break;
    }
    if (_rules.fleetSunk(_myFleet, _enemyShots)) {
      _onWin(Side.enemy);
    }
  }

  /// Применяет результат моего выстрела, пришедший по сети. Обновляет `_myShots`
  /// и решает, чей теперь ход.
  void applyShotResult(Square square, ShotResult result, {ShipType? sunkType}) {
    if (!_myShots.containsKey(square) || _myShots[square]!.result != result) {
      _myShots[square] = Shot(
        square: square,
        result: result,
        sunkType: sunkType,
      );
    }
    _busy = false;
    switch (result) {
      case ShotResult.miss:
        sounds.play(GameSound.miss);
        _status = 'Мимо! Ход переходит к другу.';
        _turn = Side.enemy;
        notifyListeners();
        break;
      case ShotResult.hit:
        sounds.play(GameSound.capture);
        _status = 'Попадание! Стреляй ещё раз.';
        notifyListeners();
        break;
      case ShotResult.sunk:
        sounds.play(GameSound.capture);
        sounds.play(GameSound.crown);
        _status = 'Потоплен ${sunkType?.russianLabel ?? 'корабль'}! '
            'Стреляй ещё раз.';
        notifyListeners();
        break;
    }
    // В сети мы не знаем флот соперника, но если пришло «sunk» 10-го корабля —
    // мы победили. Проще: считаем число «sunk» в `_myShots`.
    final sunkCount = _myShots.values
        .where((s) => s.result == ShotResult.sunk)
        .length;
    if (sunkCount >= totalShips) {
      _onWin(Side.me);
    }
  }

  // ---- Подсказка ------------------------------------------------------------

  /// Предлагает клетку для выстрела — на уровне сложности выше среднего. Сам
  /// выстрел не делает: ребёнок стреляет сам.
  void showHint() {
    if (!canInteract) return;
    if (!hintsEnabled) return;
    final enemy = EnemyBoard(_myShots);
    final ai = const BattleshipAI(Difficulty.medium);
    _hint = ai.chooseShot(enemy, _rng);
    _status = 'Попробуй выстрелить в $_hint';
    notifyListeners();
  }

  /// Скрывает подсказку.
  void clearHint() {
    if (_hint != null) {
      _hint = null;
      _status = null;
      notifyListeners();
    }
  }

  // ---- Отмена хода ---------------------------------------------------------

  void undo() {
    if (!canUndo) return;
    if (_snapshots.isEmpty) return;
    // Снимки делаются перед каждым выстрелом. В локальном режиме 2 на 1,
    // когда ход переходит к другому игроку, снимок «до чужого выстрела»
    // имеет чужой ход — откатывать его бессмысленно (друг сразу выстрелит
    // заново). Поэтому в локальном режиме откатываем сразу несколько
    // снимков, пока не вернёмся к своему ходу.
    var snap = _snapshots.removeLast();
    while (mode == BattleshipMode.local &&
        _snapshots.isNotEmpty &&
        snap.turn != _turn) {
      snap = _snapshots.removeLast();
    }
    _turn = snap.turn;
    _myShots
      ..clear()
      ..addAll(snap.myShots);
    _enemyShots
      ..clear()
      ..addAll({
        for (final e in snap.myIncoming.entries)
          e.key: Shot(square: e.key, result: e.value),
      });
    if (_history.records.isNotEmpty) _history.pop();
    _busy = false;
    _hint = null;
    _status = 'Ход отменён';
    notifyListeners();
  }

  void _pushSnapshot() {
    if (mode == BattleshipMode.network) return; // по сети отмены нет
    // В режиме ИИ снимки делаем только перед выстрелом человека: отменять
    // ход компьютера бессмысленно — он сразу выстрелит заново. Так кнопка
    // «Отменить» возвращает игрока к его последнему решению.
    if (mode == BattleshipMode.ai && _turn != Side.me) return;
    _snapshots.add(BoardSnapshot(
      turn: _turn,
      myIncoming: {
        for (final e in _enemyShots.entries) e.key: e.value.result,
      },
      myShots: Map.of(_myShots),
    ));
  }

  // ---- Сдача ---------------------------------------------------------------

  void resign() {
    if (phase != BattleshipPhase.playing) return;
    if (mode == BattleshipMode.network) {
      network!.service.send(const NetworkMessage('resign'));
    }
    _onWin(_turn == Side.me ? Side.enemy : Side.me, byResign: true);
  }

  // ---- Победа ---------------------------------------------------------------

  void _onWin(Side winner, {bool byResign = false}) {
    if (isOver) return;
    phase = BattleshipPhase.over;
    _winner = winner;
    _busy = false;
    final iWon = mode == BattleshipMode.network
        ? winner == _mySide
        : (mode == BattleshipMode.ai
            ? winner == Side.me
            : true); // local: кто-то на этом устройстве всегда выиграл
    sounds.play(
      resultSoundName(
        draw: false,
        local: mode != BattleshipMode.network,
        iWon: iWon,
      ),
    );
    settings.recordGame(won: iWon || mode == BattleshipMode.local);
    notifyListeners();
  }

  // ---- Перезапуск ----------------------------------------------------------

  /// Перезапуск той же партии. Используется кнопкой «Играть снова» офлайн.
  void playAgain() {
    _aiTimer?.cancel();
    _resetForSetup();
    notifyListeners();
  }

  // ---- ИИ -------------------------------------------------------------------

  void _maybeAiTurn() {
    if (mode != BattleshipMode.ai) return;
    if (phase != BattleshipPhase.playing) return;
    if (_turn != Side.enemy) return;
    _scheduleAiTurn();
  }

  void _scheduleAiTurn() {
    _busy = true;
    notifyListeners();
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 450), _runAiTurn);
  }

  void _runAiTurn() {
    if (_disposed || phase != BattleshipPhase.playing) return;
    if (mode != BattleshipMode.ai) return;
    if (_turn != Side.enemy) {
      _busy = false;
      notifyListeners();
      return;
    }
    // ИИ видит свои выстрелы по мне — это его «поле соперника».
    final enemy = EnemyBoard(_enemyShots);
    final ai = BattleshipAI(difficulty);
    final target = ai.chooseShot(enemy, _rng);
    _busy = false;
    _applyEnemyShot(target, remote: false);
  }

  // ---- Сеть -----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    switch (event.type) {
      case 'move':
        // Соперник стреляет по мне — считаем результат и отправляем обратно.
        _receiveShot(event.data);
        break;
      case 'event':
        final kind = event.data['kind'];
        if (kind == 'shotResult') {
          _receiveShotResult(event.data);
        } else if (kind == 'fleetReady') {
          _enemyReady = true;
          _status = null;
          notifyListeners();
          _maybeBeginNetworkPlay();
        }
        break;
      case 'resign':
        if (isOver) return;
        _onWin(_mySide, byResign: true);
        break;
      case 'disconnected':
        _status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        phase = BattleshipPhase.over;
        notifyListeners();
        break;
      case 'desync':
        _desync('Партия рассинхронизировалась');
        break;
      case 'error':
        final msg = event.data['message'];
        _status = msg is String ? msg : 'Связь потеряна';
        phase = BattleshipPhase.over;
        notifyListeners();
        break;
    }
  }

  void _receiveShot(Map<String, Object?> data) {
    if (phase != BattleshipPhase.playing) return;
    try {
      final parsed = parseShot(data);
      if (_turn != Side.enemy) {
        // Соперник стреляет не в свой ход — это рассинхронизация.
        _desync('Соперник стреляет не в свой ход');
        return;
      }
      if (_enemyShots.containsKey(parsed.square)) {
        _desync('Соперник стреляет в обстрелянную клетку');
        return;
      }
      _applyEnemyShot(parsed.square, remote: true);
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Ход не распознан' : e.message);
    }
  }

  void _receiveShotResult(Map<String, Object?> data) {
    if (phase != BattleshipPhase.playing) return;
    try {
      final parsed = parseShotResult(data);
      // Результат должен прийти по нашему выстрелу.
      if (_turn != Side.me) {
        _desync('Соперник прислал результат не в свой ход');
        return;
      }
      // Если клетка не в `_myShots`, это странно — мы должны были стрелять.
      // На всякий случай добавим.
      applyShotResult(
        parsed.square,
        parsed.result,
        sunkType: parsed.sunkType,
      );
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Результат не распознан' : e.message);
    }
  }

  void _desync(String reason) {
    _status = reason;
    phase = BattleshipPhase.over;
    notifyListeners();
    // Транспорт уже разорвёт связь; закрывать сервис здесь не нужно — лобби
    // владеет им и закроет при выходе.
  }

  @override
  void dispose() {
    _disposed = true;
    _aiTimer?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}
