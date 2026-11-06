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
enum GameMode { ai, local, network }

/// Фаза партии: сначала определяем первого ходом (упрощённо — белые начинают,
/// но фаза нужна, чтобы различать «партия идёт» и «партия кончилась»).
enum GamePhase { playing, over }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно, чтобы интерфейс показывал правильную подсказку.
enum ActiveSide { me, computer, friend, nobody }

/// Контроллер партии нард. Содержит состояние, историю, звук и сеть; интерфейс
/// только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
class BackgammonController extends ChangeNotifier {
  BackgammonController({
    required this.settings,
    required this.sounds,
    this.network,
    this.variant = BackgammonVariant.short,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = GameMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    state = GameState(
      board: Board.initial(variant: variant),
      turn: Player.white,
      variant: variant,
    );
  }

  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  final BackgammonVariant variant;

  /// Один генератор случайных чисел на всю партию. Создавать `Random()` заново
  /// на каждый бросок — и расточительно, и чревато корреляцией семян при
  /// частых вызовах. Одно поле — честные независимые броски.
  final Random _rng = Random();
  late final bool isHost;

  GameMode mode = GameMode.local;
  Difficulty difficulty = Difficulty.medium;

  /// Цвет человека на этом устройстве. В режиме ИИ — цвет ребёнка; в сети у
  /// хоста white, у клиента black; вдвоём на одном устройстве оба «человеческие»,
  /// тут хранится цвет, чья очередь (для подсветки активного игрока).
  Player humanColor = Player.white;

  GameState state = GameState(board: Board.initial(), turn: Player.white);
  GamePhase phase = GamePhase.playing;

  /// Снимки на начало каждого хода — для отмены целого хода (офлайн и по сети
  /// по согласию). По сети оба устройства кладут сюда по одному снимку на ход
  /// в момент броска костей, поэтому снимки симметричны и отмена работает
  /// одинаково с обеих сторон.
  final GameHistory history = GameHistory();

  /// Снимки перед каждым шагом текущего хода — для пошаговой отмены прямо во
  /// время своего хода. По сети эти шаги друг ещё не видел, поэтому отменять их
  /// можно локально, без запроса. Очищаются в конце хода.
  final List<GameState> _localSteps = [];

  // Выбор шашки для хода.
  int? _selectedPoint;
  bool _selectedBar = false;
  List<Move> _legalForSelected = const [];

  bool busy = false;
  String? status;

  StreamSubscription<NetworkMessage>? _networkSub;
  bool _disposed = false;
  Timer? _autoEndTimer;

  // Ожидание подтверждения отмены по сети.
  bool _undoPending = false;

  // ---- Подсказки и номера пунктов -------------------------------------------

  /// gameId, под которым читаются флаги настроек: у коротких и длинных нард
  /// ключи раздельные, поэтому выбираем по варианту.
  String get _flagGameId =>
      variant == BackgammonVariant.long ? 'long_backgammon' : 'backgammon';

  bool get hintsEnabled => settings.flag(_flagGameId, 'hints');
  bool get numbersEnabled => settings.flag(_flagGameId, 'numbers');
  bool get autoRollEnabled => settings.flag(_flagGameId, 'autoRoll');

  /// Если включён авто-бросок и сейчас ход человека (не сети — там кости
  /// бросает хост), бросает кости автоматически. Вызывается в начале хода
  /// человека: после старта партии и после завершения чужого хода.
  void _maybeAutoRoll() {
    if (!autoRollEnabled) return;
    if (phase != GamePhase.playing) return;
    if (mode == GameMode.network) return; // в сети бросает хост
    if (state.available.isNotEmpty) return; // уже брошены
    if (mode == GameMode.ai && state.turn != humanColor) return; // не наш ход
    _rollAndAnnounce();
  }

  // ---- Выбор ---------------------------------------------------------------

  int? get selectedPoint => _selectedPoint;
  bool get selectedBar => _selectedBar;
  List<Move> get legalForSelected => _legalForSelected;

  /// Активная сторона — для подписи «чей ход».
  ActiveSide get activeSide {
    if (phase == GamePhase.over) return ActiveSide.nobody;
    if (mode == GameMode.ai) {
      return state.turn == humanColor ? ActiveSide.me : ActiveSide.computer;
    }
    if (mode == GameMode.network) {
      // В сети хост играет white, клиент black.
      final mine = isHost ? Player.white : Player.black;
      return state.turn == mine ? ActiveSide.me : ActiveSide.friend;
    }
    return ActiveSide.me; // вдвоём на одном устройстве — всегда человек
  }

  /// Имя игрока для панели (как в шашках): локально — «Игрок 1»/«Игрок 2»,
  /// против компьютера — ник + «Компьютер», по сети — ник + имя друга.
  String playerName(Player side) {
    if (mode == GameMode.local) {
      return side == Player.white ? 'Игрок 1 (белые)' : 'Игрок 2 (чёрные)';
    }
    if (mode == GameMode.ai) {
      return side == humanColor ? settings.nickname : 'Компьютер';
    }
    // Сеть: хост — white, клиент — black.
    final mine = isHost ? Player.white : Player.black;
    if (side == mine) return settings.nickname;
    return network?.peerName ?? 'Друг';
  }

  /// Чей сейчас ход — для бейджа «ХОД» на панели.
  Player get currentTurn => state.turn;

  /// Доступные пункты-адресаты для выбранной шашки (для подсветки).
  Set<int> get highlightedDestinations {
    if (!hintsEnabled) return const {};
    if (_selectedPoint == null && !_selectedBar) {
      // Ничего не выбрано — подсветим шашки, которыми вообще можно ходить.
      return const {};
    }
    final dests = <int>{};
    for (final m in _legalForSelected) {
      if (m.to != null) dests.add(m.to!);
    }
    return dests;
  }

  /// Шашки, которыми можно начать ход (для лёгкой подсветки, когда ничего не
  /// выбрано).
  Set<int> get movablePoints {
    if (!hintsEnabled) return const {};
    if (_selectedPoint != null || _selectedBar) return const {};
    final points = <int>{};
    for (final move in BackgammonRules.allMoves(state)) {
      if (move.from != null) points.add(move.from!);
    }
    return points;
  }

  bool get canSelectBar =>
      state.board.hasBar(state.turn) && state.turn == _myTurn();

  /// Чей ход «моего» устройства — для разрешения тапов.
  Player? _myTurn() {
    if (mode == GameMode.ai) return humanColor;
    if (mode == GameMode.network) return isHost ? Player.white : Player.black;
    return state.turn; // local: оба хода человека
  }

  bool get _isMyTurn {
    if (phase != GamePhase.playing) return false;
    if (mode == GameMode.ai && state.turn != humanColor) return false;
    if (mode == GameMode.network &&
        state.turn != (isHost ? Player.white : Player.black)) {
      return false;
    }
    return true;
  }

  // ---- Старт партий --------------------------------------------------------

  void startLocal() {
    mode = GameMode.local;
    humanColor = Player.white;
    state = GameState(
      board: Board.initial(variant: variant),
      turn: Player.white,
      variant: variant,
    );
    phase = GamePhase.playing;
    history.clear();
    _resetSelection();
    status = null;
    busy = false;
    notifyListeners();
    _maybeAutoRoll();
  }

  void startAi(Difficulty level, Player human) {
    mode = GameMode.ai;
    difficulty = level;
    humanColor = human;
    state = GameState(
      board: Board.initial(variant: variant),
      turn: Player.white,
      variant: variant,
    );
    phase = GamePhase.playing;
    history.clear();
    _resetSelection();
    status = null;
    busy = false;
    notifyListeners();
    // Белые ходят первыми. Если компьютер — белые, он ходит сам.
    if (state.turn != humanColor) {
      _scheduleAiTurn();
    } else {
      _maybeAutoRoll();
    }
  }

  void startNetwork() {
    mode = GameMode.network;
    humanColor = isHost ? Player.white : Player.black;
    state = GameState(
      board: Board.initial(variant: variant),
      turn: Player.white,
      variant: variant,
    );
    phase = GamePhase.playing;
    history.clear();
    _resetSelection();
    status = null;
    busy = false;
    notifyListeners();
    // Хост бросает кости для первого хода (белые = хост) и сообщает клиенту.
    // Небольшая задержка нужна, чтобы клиент успел открыть экран партии и
    // подписаться на события: иначе первое сообщение `dice` может прийти
    // раньше и потеряться.
    if (isHost) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (_disposed || phase != GamePhase.playing) return;
        if (state.available.isEmpty) {
          _rollAndAnnounce();
        }
      });
    }
  }

  // ---- Бросок костей -------------------------------------------------------

  /// Бросает кости за текущего игрока (локально). В сети это делает только хост,
  /// клиент получает кости сообщением `dice`.
  void rollDice() {
    if (phase != GamePhase.playing) return;
    if (state.available.isNotEmpty) return; // уже брошены
    if (mode == GameMode.network && !isHost) return; // клиент не бросает
    if (mode == GameMode.ai && state.turn != humanColor) return; // ИИ бросит сам
    if (!_isMyTurn && mode != GameMode.ai) return;
    _rollAndAnnounce();
  }

  void _rollAndAnnounce() {
    final dice = [_rng.nextInt(6) + 1, _rng.nextInt(6) + 1];
    _playedThisTurn.clear();
    _localSteps.clear();
    // Снимок на начало хода — для отмены целого хода.
    history.push(state.copyWith(rolled: const [], available: const []));
    state = state.withRoll(dice);
    sounds.play(GameSound.guess); // звук броска
    _resetSelection();
    status = null;
    notifyListeners();
    if (mode == GameMode.network) {
      // Сообщаем клиенту бросок — он показывает те же кости.
      network!.service.send(
        NetworkMessage('dice', diceMessage(state.turn, dice)),
      );
    }
    _afterRoll();
  }

  /// Принять брошенные хостом кости (для клиента по сети).
  void _receiveDice(Player player, List<int> dice) {
    _playedThisTurn.clear();
    _localSteps.clear();
    history.push(state.copyWith(rolled: const [], available: const []));
    if (state.turn != player) {
      state = state.copyWith(turn: player);
    }
    state = state.withRoll(dice);
    _resetSelection();
    notifyListeners();
    _afterRoll();
  }

  void _afterRoll() {
    // Если ходить некуда — ход пропускается автоматически. Но в сети только та
    // сторона, чей сейчас ход, может завершить его: клиент не завершает ход
    // хоста и наоборот.
    if (!BackgammonRules.canPlayAny(state, state.available)) {
      status = 'Ходить некуда — ход переходит другу';
      notifyListeners();
      if (mode == GameMode.network && !_isMyTurn) return;
      _autoEndTimer?.cancel();
      _autoEndTimer = Timer(const Duration(milliseconds: 900), _endTurn);
      return;
    }
    if (mode == GameMode.ai && state.turn != humanColor) {
      _scheduleAiTurn();
    }
  }

  // ---- Выбор и ход ---------------------------------------------------------

  void selectPoint(int point) {
    if (!_isMyTurn || phase != GamePhase.playing) return;
    if (state.available.isEmpty) return; // кости ещё не брошены
    // Если уже выбран источник и тап по адресу — пробуем ходить.
    if ((_selectedPoint != null || _selectedBar) &&
        _tryMoveTo(point)) {
      return;
    }
    // Иначе выбираем шашку на этом пункте.
    if (state.board.hasBar(state.turn)) {
      // С бара ходят только входом — выбор пункта-источника запрещён.
      _resetSelection();
      notifyListeners();
      return;
    }
    if (state.board.at(point, state.turn) == 0) {
      _resetSelection();
      notifyListeners();
      return;
    }
    _selectSource(point: point);
  }

  void selectBar() {
    if (!_isMyTurn || phase != GamePhase.playing) return;
    if (state.available.isEmpty) return;
    if (!state.board.hasBar(state.turn)) return;
    _selectSource(bar: true);
  }

  /// Тап по зоне выноса: вынести выбранную шашку, если это разрешено правилами.
  void selectOff() {
    if (!_isMyTurn || phase != GamePhase.playing) return;
    if (_selectedPoint == null && !_selectedBar) return;
    // Ищем шаг-вынос среди легальных для выбранной шашки.
    final bearOff =
        _legalForSelected.where((m) => m.bearOff).toList(growable: false);
    if (bearOff.isEmpty) return;
    bearOff.sort((a, b) => a.die.compareTo(b.die));
    _applyMove(bearOff.first);
  }

  void _selectSource({int? point, bool bar = false}) {
    _selectedPoint = point;
    _selectedBar = bar;
    final moves = <Move>[];
    for (final die in state.available) {
      for (final m in BackgammonRules.movesForDie(state, die)) {
        if (bar && m.fromBar) {
          moves.add(m);
        } else if (!bar && m.from == point) {
          moves.add(m);
        }
      }
    }
    // Дедупликация по to.
    final seen = <int?>{};
    _legalForSelected =
        moves.where((m) => seen.add(m.to)).toList(growable: false);
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedPoint != null || _selectedBar) {
      _resetSelection();
      notifyListeners();
    }
  }

  void _resetSelection() {
    _selectedPoint = null;
    _selectedBar = false;
    _legalForSelected = const [];
  }

  /// Пытается походить выбранной шашкой на пункт [to] (или вынести, если
  /// [to] == null). Возвращает true, если ход сделан.
  bool _tryMoveTo(int? to) {
    final moves =
        _legalForSelected.where((m) => m.to == to).toList(growable: false);
    if (moves.isEmpty) return false;
    // Берём первый подходящий шаг. Если подходят две разные кости на тот же
    // пункт — берём меньшую, чтобы оставить больше возможностей.
    moves.sort((a, b) => a.die.compareTo(b.die));
    _applyMove(moves.first);
    return true;
  }

  void _applyMove(Move move) {
    final wasHit = !move.bearOff &&
        !move.fromBar &&
        state.board.opponentAt(move.to!, state.turn) == 1;
    final wasBearOff = move.bearOff;
    // Снимок перед шагом — для пошаговой отмены во время своего хода.
    if (mode != GameMode.ai || state.turn == humanColor) {
      _localSteps.add(state);
    }
    state = BackgammonRules.applyMove(state, move);
    _playedThisTurn.add(move);
    _resetSelection();
    sounds.play(GameSound.move);
    if (wasHit) sounds.play(GameSound.capture);
    if (wasBearOff) sounds.play(GameSound.crown);
    notifyListeners();
    if (state.winner != null) {
      // В сети выигрышный ход надо отправить сопернику: иначе он не узнает о
      // победе. Обычная отправка — в _endTurn, но при победе ход не
      // завершается, поэтому шлём здесь.
      if (mode == GameMode.network) {
        network!.service.send(
          NetworkMessage(
            'move',
            moveMessage(Turn(
              player: state.turn,
              dice: state.rolled,
              moves: List<Move>.of(_playedThisTurn),
            )),
          ),
        );
      }
      _onWin(state.winner!);
      return;
    }
    // Авто-завершение хода, когда кости кончились или ходить больше некуда.
    if (state.available.isEmpty ||
        !BackgammonRules.canPlayAny(state, state.available)) {
      _autoEndTimer?.cancel();
      _autoEndTimer = Timer(const Duration(milliseconds: 600), _endTurn);
    }
  }

  /// Ручное завершение хода раньше, чем кости кончатся (упрощение для ребёнка:
  /// не обязательно использовать обе кости). Доступно, когда сделан хоть один
  /// шаг и ещё есть невыбранные кости.
  void endTurn() {
    if (!_canEndTurnManually) return;
    _autoEndTimer?.cancel();
    _endTurn();
  }

  bool get _canEndTurnManually {
    if (phase != GamePhase.playing) return false;
    if (state.available.isEmpty) return false;
    if (!_isMyTurn) return false;
    // Нельзя завершить, не сделав ни одного шага, если ход возможен.
    return _playedThisTurn.isNotEmpty;
  }

  bool get canEndTurn => _canEndTurnManually;

  void _endTurn() {
    // Отменяем отложенное авто-завершение: иначе после прямого вызова
    // _endTurn (из цикла ИИ или по кнопке) сработавший таймер вызовет
    // _endTurn ещё раз — ход вернётся к компьютеру, и ИИ заиграет сам
    // себя без конца.
    _autoEndTimer?.cancel();
    _autoEndTimer = null;
    if (phase != GamePhase.playing) return;
    // Защита от повторного вызова: если кости уже стёрты (ход завершён),
    // повторное завершение перевернуло бы ход обратно сопернику.
    if (state.rolled.isEmpty && state.available.isEmpty) return;
    final endedTurn = state.turn;
    final playedDice = state.rolled;
    final playedMoves = List<Move>.of(_playedThisTurn);
    _playedThisTurn.clear();
    _localSteps.clear();
    final ended = BackgammonRules.endTurn(state);
    state = ended;
    _resetSelection();
    status = null;
    notifyListeners();

    if (mode == GameMode.network) {
      // Отправляем завершённый ход другу.
      network!.service.send(
        NetworkMessage(
          'move',
          moveMessage(Turn(player: endedTurn, dice: playedDice, moves: playedMoves)),
        ),
      );
      // Хост бросает кости следующего игрока и сообщает их.
      if (isHost) {
        _rollAndAnnounce();
      }
    } else if (mode == GameMode.ai && state.turn != humanColor) {
      _scheduleAiTurn();
    } else {
      // Ход перешёл к человеку — если включён авто-бросок, бросаем сразу.
      _maybeAutoRoll();
    }
  }

  /// Шаги, сделанные в текущем ходе (для отправки по сети и для отмены).
  final List<Move> _playedThisTurn = [];

  // ---- Подсказка ------------------------------------------------------------

  /// Предлагает хороший ход: выбирает шашку и подсвечивает адресат, не делая
  /// ход за ребёнка. На лёгком уровне тоже работает по просьбе.
  void hint() {
    if (!_isMyTurn || phase != GamePhase.playing) return;
    if (state.available.isEmpty) return;
    final sequences = BackgammonRules.allTurnSequences(state, state.available);
    if (sequences.isEmpty) {
      status = 'Ходов нет — нажми «Завершить»';
      notifyListeners();
      return;
    }
    final best = BackgammonAI.findBestTurn(
      state,
      level: Difficulty.medium,
      random: _rng,
    );
    if (best.moves.isEmpty) {
      status = 'Ходов нет — нажми «Завершить»';
      notifyListeners();
      return;
    }
    final first = best.moves.first;
    if (first.fromBar) {
      _selectSource(bar: true);
    } else {
      _selectSource(point: first.from);
    }
    status = _describeHint(best.moves);
    notifyListeners();
  }

  /// Человекочитательное описание подсказанного хода: «Возьми шашку с 13-го
  /// пункта и пойди на 9-й». Так ребёнку понятнее, чем «попробуй этот ход».
  String _describeHint(List<Move> moves) {
    if (moves.isEmpty) return 'Ходов нет';
    final m = moves.first;
    final fromStr = m.fromBar ? 'с бара' : 'с ${m.from! + 1}-го пункта';
    final toStr = m.bearOff
        ? 'и вынеси её'
        : 'и пойди на ${m.to! + 1}-й пункт';
    var text = 'Возьми шашку $fromStr $toStr';
    if (moves.length > 1) {
      text += ' (и ещё ${moves.length - 1} ход${moves.length == 2 ? '' : 'а'})';
    }
    return text;
  }

  // ---- Отмена хода ---------------------------------------------------------

  /// Отменить последний ход или шаг.
  ///
  /// Офлайн и в сети во время своего хода — отменяет последний шаг локально
  /// (друг этих шагов ещё не видел). В сети между ходами — просит друга
  /// согласия отменить последний завершённый ход.
  void undo() {
    if (phase == GamePhase.over) return;
    // Пошаговая отмена прямо во время своего хода.
    if (_localSteps.isNotEmpty) {
      state = _localSteps.removeLast();
      if (_playedThisTurn.isNotEmpty) _playedThisTurn.removeLast();
      _resetSelection();
      status = 'Шаг отменён';
      notifyListeners();
      return;
    }
    if (mode == GameMode.network) {
      // Между ходами — отмена целого хода по согласию.
      if (_undoPending || !history.canUndo) return;
      _undoPending = true;
      network!.service.send(const NetworkMessage('undoRequest', {'ply': 1}));
      status = 'Ждём ответа друга на отмену хода…';
      notifyListeners();
      return;
    }
    // Офлайн: отмена последнего хода целиком (включая бросок).
    if (!history.canUndo) return;
    // В режиме ИИ отменяем только свой ход, когда наша очередь.
    if (mode == GameMode.ai && !_isMyTurn) return;
    _doUndoTurn();
  }

  /// Откатывает один ход целиком до снимка его начала. Используется офлайн и
  /// по сети после согласия друга.
  void _doUndoTurn() {
    if (!history.canUndo) return;
    final prev = history.pop();
    state = prev;
    phase = GamePhase.playing;
    _playedThisTurn.clear();
    _localSteps.clear();
    _resetSelection();
    status = 'Ход отменён';
    notifyListeners();
    // В сети хост перевыбрасывает кости отменённого хода и сообщает их.
    if (mode == GameMode.network && isHost && state.available.isEmpty) {
      _rollAndAnnounce();
    }
  }

  bool get canUndo {
    if (phase == GamePhase.over) return false;
    if (_localSteps.isNotEmpty) return true;
    if (mode == GameMode.network) {
      return phase == GamePhase.playing && !_undoPending && history.canUndo;
    }
    if (mode == GameMode.ai) return _isMyTurn && history.canUndo;
    return history.canUndo;
  }

  // ---- Сдача ---------------------------------------------------------------

  void resign() {
    if (phase != GamePhase.playing) return;
    final winner = state.turn.other;
    if (mode == GameMode.network) {
      network!.service.send(const NetworkMessage('resign'));
    }
    _onWin(winner, byResign: true);
  }

  // ---- Победа ---------------------------------------------------------------

  void _onWin(Player winner, {bool byResign = false}) {
    phase = GamePhase.over;
    state = state.copyWith(winner: winner);
    status = null;
    final iWon = mode == GameMode.network
        ? winner == (isHost ? Player.white : Player.black)
        : (mode == GameMode.ai ? winner == humanColor : true);
    sounds.play(
      resultSoundName(draw: false, local: mode != GameMode.network, iWon: iWon),
    );
    settings.recordGame(won: iWon || mode == GameMode.local);
    notifyListeners();
  }

  // ---- ИИ -------------------------------------------------------------------

  void _scheduleAiTurn() {
    busy = true;
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 350), _runAiTurn);
  }

  Future<void> _runAiTurn() async {
    if (_disposed || phase != GamePhase.playing) return;
    if (state.turn == humanColor) {
      busy = false;
      notifyListeners();
      return;
    }
    // Бросаем кости за компьютер, если ещё не брошены.
    if (state.available.isEmpty) {
      final dice = [_rng.nextInt(6) + 1, _rng.nextInt(6) + 1];
      _playedThisTurn.clear();
      _localSteps.clear();
      history.push(state.copyWith(rolled: const [], available: const []));
      state = state.withRoll(dice);
      sounds.play(GameSound.guess);
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    if (!BackgammonRules.canPlayAny(state, state.available)) {
      busy = false;
      _endTurn();
      return;
    }
    final turn = BackgammonAI.findBestTurn(state, level: difficulty, random: _rng);
    for (final move in turn.moves) {
      if (_disposed || phase != GamePhase.playing) return;
      _applyMove(move);
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
    if (_disposed || phase != GamePhase.playing) return;
    busy = false;
    if (state.winner == null) {
      _endTurn();
    }
  }

  // ---- Сеть -----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    switch (event.type) {
      case 'dice':
        try {
          final parsed = parseDiceMessage(event.data);
          _receiveDice(parsed.player, parsed.dice);
        } on FormatException catch (e) {
          _desync(e.message);
        }
        break;
      case 'move':
        _receiveMove(event.data);
        break;
      case 'undoRequest':
        // Просьба об отмене от друга — покажем диалог через колбэк.
        onUndoRequested?.call();
        break;
      case 'undoResponse':
        final accepted = event.data['accepted'] == true;
        _undoPending = false;
        if (accepted) {
          _doUndoTurn();
        } else {
          status = 'Друг не разрешил отменить ход';
          notifyListeners();
        }
        break;
      case 'resign':
        _onWin(_myTurn() ?? state.turn, byResign: true);
        break;
      case 'disconnected':
        status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        phase = GamePhase.over;
        notifyListeners();
        break;
      case 'desync':
        _desync('Партия рассинхронизировалась');
        break;
      case 'error':
        final msg = event.data['message'];
        status = msg is String ? msg : 'Связь потеряна';
        phase = GamePhase.over;
        notifyListeners();
        break;
    }
  }

  void _receiveMove(Map<String, Object?> data) {
    try {
      final turn = parseTurn(data);
      state = BackgammonRules.applyTurn(state, turn);
      _resetSelection();
      notifyListeners();
      if (state.winner != null) {
        _onWin(state.winner!);
        return;
      }
      // Хост — авторитет бросков: после чужого хода он бросает кости следующего
      // игрока и сообщает их. Клиент кости не бросает.
      if (mode == GameMode.network && isHost) {
        _rollAndAnnounce();
      }
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Партия рассинхронизировалась' : e.message);
    }
  }

  void _desync(String reason) {
    status = reason;
    phase = GamePhase.over;
    notifyListeners();
    // Транспорт уже разорвёт связь; закрывать сервис здесь не нужно — лобби
    // владеет им и закроет при выходе.
  }

  /// Ответ на просьбу друга об отмене хода по сети.
  void respondUndo(bool accepted) {
    if (mode != GameMode.network) return;
    network!.service.send(
      NetworkMessage('undoResponse', {'accepted': accepted}),
    );
    if (accepted) {
      _doUndoTurn();
    }
  }

  /// Колбэк, который выставляет интерфейс, чтобы спросить ребёнка о согласии
  /// на отмену хода по сети. Сетевой контроллер не показывает диалог сам.
  void Function()? onUndoRequested;

  // ---- Утилиты -------------------------------------------------------------

  String get turnLabel {
    switch (activeSide) {
      case ActiveSide.me:
        return 'Твой ход';
      case ActiveSide.computer:
        return 'Ход компьютера…';
      case ActiveSide.friend:
        return 'Ходит друг…';
      case ActiveSide.nobody:
        return phase == GamePhase.over ? 'Партия окончена' : '';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _autoEndTimer?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}
