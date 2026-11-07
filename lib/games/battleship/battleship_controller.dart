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

/// Режим партии: против компьютера, по сети или вдвоём на одном устройстве.
enum GameMode { computer, network, local }

/// Параметры создаваемой партии. Передаются как данные из расстановки
/// в экран игры — сам контроллер живёт на экране игры, а не на расстановке,
/// чтобы при смене экрана не «умирать» вместе с расстановкой.
class GameSetup {
  const GameSetup({
    required this.mode,
    required this.myFleet,
    required this.iShootFirst,
    this.difficulty = Difficulty.easy,
    this.enemyFleet,
    this.network,
  });

  final GameMode mode;

  /// Мой флот — всегда видим этому устройству.
  final Fleet myFleet;

  /// true, если первый выстрел за этим игроком. Против компьютера — всегда
  /// true (ребёнок ходит первым). В сети — true для хоста. Вдвоём на одном
  /// устройстве — true (игрок 1 начинает).
  final bool iShootFirst;

  final Difficulty difficulty;

  /// Флот соперника. В игре с компьютером и вдвоём на одном устройстве —
  /// известен (туман войны только в UI). В сети — null: флот соперника
  /// неизвестен, результаты выстрелов считает сторона, по которой стреляют.
  final Fleet? enemyFleet;

  final NetworkSession? network;

  /// Копия с подменённой сетевой сессией — на случай, если расстановка
  /// создавала её, а экран игры хочет переиспользовать ту же.
  GameSetup copyWithNetwork(NetworkSession? network) => GameSetup(
        mode: mode,
        myFleet: myFleet,
        iShootFirst: iShootFirst,
        difficulty: difficulty,
        enemyFleet: enemyFleet,
        network: network ?? this.network,
      );
}

/// Снимок состояния партии перед выстрелом — для отмены хода (офлайн).
class _StateSnapshot {
  const _StateSnapshot({
    required this.turn,
    required this.shotsAtMe,
    required this.myShotsOnEnemy,
    required this.winner,
    required this.ply,
  });
  final Side turn;
  final Map<Square, Shot> shotsAtMe;
  final Map<Square, Shot> myShotsOnEnemy;
  final Side? winner;
  final int ply;
}

/// Анимация выстрела для UI: кто стрелял, сам выстрел, потопленный корабль
/// (для обводки) и длительность. Живёт рядом с контроллером, чтобы виджет
/// поля мог рендерить оверлей, зная свой размер клетки.
class ShotAnimation {
  const ShotAnimation({
    required this.shooter,
    required this.shot,
    required this.sunkShip,
    required this.duration,
  });
  final Side shooter;
  final Shot shot;
  final Ship? sunkShip;
  final Duration duration;
}

/// Контроллер партии морского боя.
///
/// Одна копия на партию, живёт на экране игры (а не на расстановке). Знает
/// всё про текущее состояние и историю, сам играет за компьютер и обменивается
/// сообщениями с сетевым соперником. UI только слушает [notifyListeners] и
/// рисует.
class BattleshipController extends ChangeNotifier {
  BattleshipController(
    this.setup,
    this.settings, {
    GameSounds? sounds,
    this.thinkingDelay = const Duration(milliseconds: 650),
  })  : sounds = sounds ?? GameSounds(settings),
        rules = battleshipRules,
        _ai = BattleshipAI(setup.difficulty) {
    if (setup.mode == GameMode.network && setup.network == null) {
      throw ArgumentError('Для сетевой игры необходимо соединение');
    }
    _turn = setup.iShootFirst ? Side.me : Side.enemy;
    _myFleet = setup.myFleet;
    _enemyFleet = setup.enemyFleet;
    // В сетевой игре расстановка завершается раньше, чем открывается экран
    // партии: SetupPage ждёт готовности обеих сторон и только потом ведёт
    // сюда. Значит к моменту создания контроллера соперник уже готов. Событие
    // `fleetReady` могло прийти до подписки — мы его пропустим, но это не
    // страшно: доверяем гарантии расстановки.
    peerFleetReady = true;
    _networkSubscription = setup.network?.service.events.listen(_onNetworkMessage);
    settings.addListener(_settingsChanged);
    if (_turn == Side.enemy && setup.mode == GameMode.computer) {
      _startComputer();
    }
  }

  final GameSetup setup;
  final SettingsController settings;
  final GameSounds sounds;
  final BattleshipRules rules;
  final Duration thinkingDelay;
  final BattleshipAI _ai;

  late Fleet _myFleet;
  Fleet? _enemyFleet;
  Side _turn = Side.me;
  Side? _winner;
  int _ply = 0;
  final Map<Square, Shot> _shotsAtMe = {};
  final Map<Square, Shot> _myShotsOnEnemy = {};
  final List<_StateSnapshot> _history = [];
  final ShotHistory _records = ShotHistory();

  ShotAnimation? animation;
  bool computerThinking = false;
  bool hintThinking = false;
  bool waitingForUndo = false;
  bool awaitingShotResult = false;
  Square? _pendingShotSquare;
  int? incomingUndoPly;
  bool peerFleetReady = false;
  bool myFleetReady = true;
  String? notice;
  String? fatalMessage;
  Square? suggestedShot;
  String? hintText;
  Side? _resignedWinner;

  StreamSubscription<NetworkMessage>? _networkSubscription;
  Timer? _noticeTimer;
  bool _disposed = false;
  int _generation = 0;

  /// Сколько заметка висит перед автозакрытием.
  static const noticeDuration = Duration(milliseconds: 1400);

  /// Текущее состояние для UI.
  GameState get state => GameState(
        turn: _turn,
        myBoard: MyBoard(fleet: _myFleet, incoming: _resultsOf(_shotsAtMe)),
        enemyBoard: EnemyBoard(Map.unmodifiable(_myShotsOnEnemy)),
        winner: _winner,
      );

  static Map<Square, ShotResult> _resultsOf(Map<Square, Shot> shots) =>
      shots.map((k, v) => MapEntry(k, v.result));

  Side? get winner => _winner ?? _resignedWinner;
  bool get isOver => winner != null;
  bool get waitingForPeer =>
      setup.mode == GameMode.network && !peerFleetReady;
  bool get isMyTurn =>
      !isOver &&
      fatalMessage == null &&
      !waitingForPeer &&
      _turn == Side.me;

  bool get isAnimating => animation != null;

  /// Можно ли принимать тапы по полю соперника прямо сейчас.
  bool get canInteract =>
      !isOver &&
      fatalMessage == null &&
      !isAnimating &&
      !computerThinking &&
      !waitingForUndo &&
      !awaitingShotResult &&
      incomingUndoPly == null &&
      !waitingForPeer &&
      isMyTurn;

  bool get canUndo {
    if (_history.isEmpty ||
        _resignedWinner != null ||
        isAnimating ||
        waitingForUndo ||
        incomingUndoPly != null ||
        fatalMessage != null ||
        waitingForPeer) {
      return false;
    }
    if (setup.mode == GameMode.network) {
      return setup.network != null &&
          _records.last?.shooter == Side.enemy &&
          _turn == Side.me;
    }
    if (setup.mode == GameMode.computer) {
      final last = _records.last;
      if (last == null) return false;
      if (last.shooter == Side.enemy) {
        // Последним стрелял компьютер — отменяем пару «мой ход + ответ ИИ».
        return _history.length >= 2;
      }
      // Последним стрелял игрок (попадание, дополнительный ход) — отменяем один.
      return true;
    }
    // Вдвоём на одном устройстве — отменяем один выстрел.
    return _history.isNotEmpty;
  }

  /// Можно ли сдаться. В расстановке и в уже окончившейся партии — нельзя.
  bool get canResign =>
      !isOver && fatalMessage == null;

  /// Последний выстрел — для UI.
  Shot? get lastShot => _records.last?.shot;

  /// История выстрелов для экрана «история».
  List<ShotRecord> get history => _records.records;

  /// Подсказки включены в настройках каркаса.
  bool get hintsEnabled => settings.flag(battleshipGameId, 'hints');

  void _settingsChanged() {
    if (!hintsEnabled) {
      suggestedShot = null;
      hintText = null;
    }
    _notify();
  }

  /// Показывает временную заметку, которая сама скроется через [noticeDuration].
  void _showNotice(String text) {
    notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeDuration, () {
      if (_disposed) return;
      if (notice != null) {
        notice = null;
        _notify();
      }
    });
    _notify();
  }

  /// Выстрел игрока по клетке поля соперника.
  Future<void> shoot(Square square) async {
    if (!canInteract) return;
    if (_myShotsOnEnemy.containsKey(square)) {
      _showNotice('Сюда уже стреляли — выбери другую клетку.');
      return;
    }
    clearHint();
    if (setup.mode == GameMode.network) {
      _sendShot(square);
      awaitingShotResult = true;
      _pendingShotSquare = square;
      _notify();
      // Результат придёт сообщением shotResult — до тех пор ход «подвешен».
      return;
    }
    // Против компьютера и вдвоём: результат считает контроллер.
    final enemy = _enemyFleet;
    if (enemy == null) return;
    final shot = rules.shootResult(enemy, _myShotsOnEnemy, square);
    await _applyMyShot(shot, remote: false);
  }

  /// Применяет мой выстрел с известным результатом (локально или из сети).
  Future<void> _applyMyShot(Shot shot, {required bool remote}) async {
    if (_disposed || fatalMessage != null) return;
    _pushSnapshot();
    _records.push(ShotRecord(
      shooter: Side.me,
      shot: shot,
      sunkBefore:
          rules.sunkCount(_enemyFleet ?? const Fleet([]), _myShotsOnEnemy),
      allSunkBefore: _winner != null,
    ));
    _myShotsOnEnemy[shot.square] = shot;
    _ply++;
    _playShotSound(shot, Side.me);
    final sunkShip = _sunkShipOf(shot, _enemyFleet);
    // Ход переключаем СРАЗУ (до анимации) — иначе ложный desync из-за
    // рассинхрона анимаций на двух устройствах.
    final passTurn = shot.result == ShotResult.miss;
    if (passTurn) _turn = Side.enemy;
    animation = ShotAnimation(
      shooter: Side.me,
      shot: shot,
      sunkShip: sunkShip,
      duration: _durationFor(shot),
    );
    final gen = ++_generation;
    _notify();
    await Future<void>.delayed(animation!.duration);
    if (_disposed || gen != _generation) return;
    final pause = _pauseAfter(shot);
    if (pause > Duration.zero) {
      await Future<void>.delayed(pause);
      if (_disposed || gen != _generation) return;
    }
    animation = null;
    _afterShot(shot, shooter: Side.me, remote: remote);
    _notify();
    if (isOver || fatalMessage != null) return;
    // В игре с компьютером ИИ ходит после анимации (после моего промаха —
    // его ход). Вдвоём на одном устройстве ход переходит к другому игроку.
    if (passTurn && setup.mode == GameMode.computer) _startComputer();
    // При попадании/потоплении тот же игрок стреляет снова — ход не меняется.
  }

  /// Применяет входящий выстрел соперника по моему полю.
  Future<void> _applyIncomingShot(Square square,
      {required bool remote}) async {
    if (_disposed || fatalMessage != null) return;
    // Результат считает та сторона, по которой стреляют (она знает свой флот).
    final shot = rules.shootResult(_myFleet, _shotsAtMe, square);
    _pushSnapshot();
    _records.push(ShotRecord(
      shooter: Side.enemy,
      shot: shot,
      sunkBefore: rules.sunkCount(_myFleet, _shotsAtMe),
      allSunkBefore: _winner != null,
    ));
    _shotsAtMe[square] = shot;
    _ply++;
    _playShotSound(shot, Side.enemy);
    final sunkShip = _sunkShipOf(shot, _myFleet);
    final passTurn = shot.result == ShotResult.miss;
    if (passTurn) _turn = Side.me;
    animation = ShotAnimation(
      shooter: Side.enemy,
      shot: shot,
      sunkShip: sunkShip,
      duration: _durationFor(shot),
    );
    final gen = ++_generation;
    _notify();
    await Future<void>.delayed(animation!.duration);
    if (_disposed || gen != _generation) return;
    final pause = _pauseAfter(shot);
    if (pause > Duration.zero) {
      await Future<void>.delayed(pause);
      if (_disposed || gen != _generation) return;
    }
    animation = null;
    _afterShot(shot, shooter: Side.enemy, remote: remote);
    _notify();
    if (isOver || fatalMessage != null) return;
    // В игре с компьютером после попадания ИИ стреляет снова (после анимации).
    if (!passTurn && setup.mode == GameMode.computer) _startComputer();
    // В сетевой игре после попадания соперник продолжит сам — его контроллер
    // пришлёт следующий 'shot'; здесь ничего запускать не нужно. Вдвоём на
    // одном устройстве ход остаётся за соперником (тем же игроком).
  }

  Ship? _sunkShipOf(Shot shot, Fleet? fleet) {
    if (shot.result != ShotResult.sunk || fleet == null) return null;
    return fleet.shipAt(shot.square);
  }

  /// Длительность анимации выстрела. Чуть длиннее на попадании и потоплении —
  /// чтобы ребёнок успел увидеть, что случилось, прежде чем ход пойдёт дальше.
  Duration _durationFor(Shot shot) => switch (shot.result) {
        ShotResult.miss => const Duration(milliseconds: 700),
        ShotResult.hit => const Duration(milliseconds: 1050),
        ShotResult.sunk => const Duration(milliseconds: 1500),
      };

  /// Пауза после анимации (до смены хода / следующего выстрела).
  Duration _pauseAfter(Shot shot) => switch (shot.result) {
        ShotResult.miss => Duration.zero,
        ShotResult.hit => const Duration(milliseconds: 350),
        ShotResult.sunk => const Duration(milliseconds: 600),
      };

  /// Звук выстрела. Стрелок-человек слышит «запуск» (guess), затем результат.
  /// ИИ стреляет тихо: только результат (miss/capture/crown).
  void _playShotSound(Shot shot, Side shooter) {
    switch (shot.result) {
      case ShotResult.miss:
        sounds.play(GameSound.miss);
      case ShotResult.hit:
        sounds.play(GameSound.capture);
      case ShotResult.sunk:
        sounds.play(GameSound.crown);
    }
    if (shooter == Side.me) sounds.play(GameSound.guess);
  }

  void _afterShot(Shot shot, {required Side shooter, required bool remote}) {
    // В сетевой игре победу объявляет каждая сторона сама по своему состоянию
    // (счёт 10 sunk у стрелка-победителя; флот-проигравший видит потопленным
    // свой флот). В игре с компьютером и вдвоём контроллер знает оба флота.
    final sunkFleet = shooter == Side.me ? _enemyFleet : _myFleet;
    final myShots = shooter == Side.me ? _myShotsOnEnemy : _shotsAtMe;
    // В сети мы не знаем флот соперника, но можем посчитать «sunk» в своих
    // выстрелах: 10 sunk = победа.
    final wonByCount = setup.mode == GameMode.network &&
        shooter == Side.me &&
        myShots.values.where((s) => s.result == ShotResult.sunk).length >=
            totalShips;
    final sunk = (sunkFleet != null && rules.fleetSunk(sunkFleet, myShots)) ||
        wonByCount;
    if (!sunk) return;
    _winner = shooter;
    // Side.me на этом устройстве — всегда «я». В сети это так же: каждое
    // устройство считает себя «me», а соперника — «enemy».
    final iWon = setup.mode == GameMode.local || shooter == Side.me;
    sounds.play(iWon ? GameSound.win : GameSound.lose);
    settings.recordGame(won: iWon);
  }

  /// Ход компьютера: ИИ выбирает клетку и стреляет по моему полю.
  void _startComputer() {
    if (_disposed || computerThinking || isOver || fatalMessage != null) {
      return;
    }
    computerThinking = true;
    final gen = _generation;
    final snapshot = EnemyBoard(Map.unmodifiable(_shotsAtMe));
    _notify();
    Future<void>(() async {
      if (_disposed || gen != _generation) return;
      await Future<void>.delayed(thinkingDelay);
      if (_disposed || gen != _generation || isOver) {
        computerThinking = false;
        _notify();
        return;
      }
      final target = _ai.chooseShot(snapshot, _rng);
      if (_disposed || gen != _generation) return;
      computerThinking = false;
      await _applyIncomingShot(target, remote: false);
    });
  }

  /// Подсказка: подсвечивает клетку, куда стоит стрелять.
  Future<void> showHint() async {
    if (!hintsEnabled || !canInteract || hintThinking) return;
    hintThinking = true;
    notice = null;
    _notify();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_disposed || !hintsEnabled) return;
      final board = EnemyBoard(Map.unmodifiable(_myShotsOnEnemy));
      Square? pick;
      if (setup.mode == GameMode.computer &&
          setup.difficulty != Difficulty.easy) {
        pick = _ai.chooseShot(board, _rng);
      } else {
        final unfired = board.unfired;
        if (unfired.isEmpty) {
          pick = null;
        } else {
          final list = unfired.toList();
          pick = list[_rng.nextInt(list.length)];
        }
      }
      if (pick != null) {
        suggestedShot = pick;
        hintText = setup.mode == GameMode.computer &&
                setup.difficulty != Difficulty.easy
            ? 'Подсказка: ИИ советует стрелять в $pick.'
            : 'Подсказка: попробуй клетку $pick.';
      }
    } finally {
      if (!_disposed) {
        hintThinking = false;
        _notify();
      }
    }
  }

  void clearHint() {
    if (suggestedShot == null && hintText == null) return;
    suggestedShot = null;
    hintText = null;
    _notify();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    _notify();
  }

  /// Отмена последнего хода.
  void undo() {
    if (!canUndo) return;
    if (setup.mode == GameMode.network) {
      waitingForUndo = true;
      try {
        setup.network!.service
            .send(NetworkMessage('undoRequest', {'ply': _ply}));
      } catch (_) {
        waitingForUndo = false;
        fatalMessage = 'Связь потеряна.';
      }
      _notify();
      return;
    }
    var count = 1;
    if (setup.mode == GameMode.computer &&
        _records.last?.shooter == Side.enemy) {
      count = 2;
    }
    _restore(count);
  }

  void _restore(int count) {
    _generation++;
    computerThinking = false;
    hintThinking = false;
    animation = null;
    for (var i = 0; i < count && _history.isNotEmpty; i++) {
      final snap = _history.removeLast();
      _turn = snap.turn;
      _shotsAtMe
        ..clear()
        ..addAll(snap.shotsAtMe);
      _myShotsOnEnemy
        ..clear()
        ..addAll(snap.myShotsOnEnemy);
      _winner = snap.winner;
      _ply = snap.ply;
      _records.pop();
    }
    _resignedWinner = null;
    waitingForUndo = false;
    incomingUndoPly = null;
    suggestedShot = null;
    hintText = null;
    notice = null;
    _notify();
  }

  void respondToUndo(bool accepted) {
    final ply = incomingUndoPly;
    if (ply == null) return;
    try {
      setup.network!.service.send(
        NetworkMessage('undoResponse', {'ply': ply, 'accepted': accepted}),
      );
      incomingUndoPly = null;
      if (accepted && _history.isNotEmpty) {
        _restore(1);
      } else {
        _notify();
      }
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      _notify();
    }
  }

  void resign() {
    if (isOver || fatalMessage != null) return;
    if (setup.mode == GameMode.network) {
      try {
        setup.network!.service.send(const NetworkMessage('resign'));
      } catch (_) {}
    }
    // Я сдаюсь — победил соперник (Side.enemy с точки зрения этого устройства).
    _resignedWinner = Side.enemy;
    _generation++;
    computerThinking = false;
    animation = null;
    settings.recordGame(won: false);
    sounds.play(GameSound.lose);
    _notify();
  }

  void _pushSnapshot() {
    if (setup.mode == GameMode.network) return;
    // В режиме ИИ снимки делаем только перед выстрелом человека: отменять
    // ход компьютера бессмысленно — он сразу выстрелит заново.
    if (setup.mode == GameMode.computer && _turn != Side.me) return;
    _history.add(_StateSnapshot(
      turn: _turn,
      shotsAtMe: Map.of(_shotsAtMe),
      myShotsOnEnemy: Map.of(_myShotsOnEnemy),
      winner: _winner,
      ply: _ply,
    ));
  }

  // ---- Сетевые сообщения -------------------------------------------------

  void _sendShot(Square square) {
    try {
      final ply = _myShotsOnEnemy.length + _shotsAtMe.length + 1;
      setup.network!.service
          .send(NetworkMessage('move', shotToJson(square, ply)));
    } catch (_) {
      fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
      _notify();
    }
  }

  void _sendRaw(NetworkMessage message) {
    try {
      setup.network!.service.send(message);
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      _notify();
    }
  }

  void _onNetworkMessage(NetworkMessage message) {
    if (_disposed || fatalMessage != null) return;
    switch (message.type) {
      case 'event':
        final kind = message.data['kind'];
        if (kind == 'fleetReady') {
          peerFleetReady = true;
          _notify();
        } else if (kind == 'shotResult') {
          _onShotResult(message);
        }
      case 'move':
        _onPeerShot(message);
      case 'undoRequest':
        final valid = message.data['ply'] == _ply &&
            _history.isNotEmpty &&
            _records.last?.shooter == Side.me &&
            _turn == Side.me &&
            incomingUndoPly == null;
        if (valid) {
          incomingUndoPly = _ply;
          _notify();
        } else {
          _sendRaw(NetworkMessage(
            'undoResponse',
            {'ply': message.data['ply'], 'accepted': false},
          ));
        }
      case 'undoResponse':
        if (waitingForUndo &&
            message.data['ply'] == _ply &&
            message.data['accepted'] is bool) {
          waitingForUndo = false;
          if (message.data['accepted'] == true && _history.isNotEmpty) {
            _restore(1);
          } else {
            _showNotice('Друг решил продолжить без отмены хода.');
          }
        }
      case 'resign':
        // Соперник сдался — я победил (Side.me с точки зрения этого устройства).
        _resignedWinner = Side.me;
        settings.recordGame(won: true);
        sounds.play(GameSound.win);
        _generation++;
        animation = null;
        _notify();
      case 'disconnected':
        if (!isOver) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
          _notify();
        }
      case 'desync':
        fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
        _notify();
      default:
        break;
    }
  }

  /// Соперник стреляет по моему полю: я считаю результат и отвечаю.
  void _onPeerShot(NetworkMessage message) {
    try {
      final parsed = parseShot(message.data);
      if (_turn != Side.enemy) {
        throw const FormatException('Разные позиции');
      }
      final square = parsed.square;
      if (_shotsAtMe.containsKey(square)) {
        throw const FormatException('Повторный выстрел');
      }
      unawaited(_applyIncomingShot(square, remote: true).then((_) {
        if (_disposed || fatalMessage != null) return;
        final shot = _shotsAtMe[square]!;
        final nextTurn = shot.result == ShotResult.miss ? 'me' : 'enemy';
        _sendRaw(NetworkMessage(
          'event',
          shotResultToJson(
            ply: _ply,
            square: square,
            result: shot.result,
            sunkType: shot.sunkType,
            nextTurn: nextTurn,
          ),
        ));
        // Если мой флот потоплен — я проиграл. Соперник поймёт это по счёту
        // 10 sunk в своих выстрелах.
        if (rules.fleetSunk(_myFleet, _shotsAtMe)) {
          _winner = Side.enemy;
          sounds.play(GameSound.lose);
          settings.recordGame(won: false);
          _notify();
        }
      }));
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Ход не распознан' : e.message);
    } catch (_) {
      _desync('Ход не распознан');
    }
  }

  /// Приходит результат моего выстрела — применяю его к своему обзору.
  void _onShotResult(NetworkMessage message) {
    try {
      final parsed = parseShotResult(message.data);
      if (_turn != Side.me || !awaitingShotResult) {
        throw const FormatException('Разные позиции');
      }
      if (_pendingShotSquare != parsed.square) {
        throw const FormatException('Не та клетка');
      }
      final shot = Shot(
        square: parsed.square,
        result: parsed.result,
        sunkType: parsed.sunkType,
      );
      awaitingShotResult = false;
      _pendingShotSquare = null;
      unawaited(_applyMyShot(shot, remote: true));
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Результат не распознан' : e.message);
    } catch (_) {
      _desync('Результат не распознан');
    }
  }

  void _desync(String reason) {
    _sendRaw(const NetworkMessage('desync'));
    fatalMessage = reason.isEmpty
        ? 'Партии перестали совпадать. Начните новую игру.'
        : 'Партия рассинхронизировалась: $reason';
    _generation++;
    animation = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Источник случайности для подсказок и ИИ.
  final Random _rng = Random();

  /// Применяет входящий выстрел — для тестов.
  @visibleForTesting
  Future<void> applyIncomingForTest(Square square) =>
      _applyIncomingShot(square, remote: true);

  /// Применяет результат своего выстрела — для тестов.
  @visibleForTesting
  Future<void> applyMyShotForTest(Shot shot) =>
      _applyMyShot(shot, remote: false);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _noticeTimer?.cancel();
    settings.removeListener(_settingsChanged);
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }
}
