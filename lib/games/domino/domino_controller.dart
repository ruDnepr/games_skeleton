import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режим партии домино.
enum DominoMode { local, computer, network }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно, чтобы интерфейс показывал правильную подсказку.
enum DominoActive { me, computer, friend, nobody }

/// Контроллер партии домино. Содержит состояние, историю, звук и сеть;
/// интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила
/// общие. По сети хост авторитарный: у него обе руки, он проверяет ходы и
/// рассылает снимки; клиент только показывает снимок и шлёт свои действия.
class DominoController extends ChangeNotifier {
  DominoController({
    required this.settings,
    required this.sounds,
    this.network,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = DominoMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
  }

  final bool isHost;

  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  bool get _isNetwork => mode == DominoMode.network;

  /// Один генератор случайных чисел на всю партию: раздача, ИИ и подсказки.
  final Random _rng = Random();
  static const _rules = DominoRules();

  DominoMode mode = DominoMode.local;
  Difficulty difficulty = Difficulty.medium;

  /// Игрок-человек на этом устройстве. В режиме ИИ — место 0, в сети у хоста 0,
  /// у клиента 1, вдвоём на одном устройстве — текущее состояние, чья очередь
  /// (рука внизу совпадает с этим местом).
  int get mySeat {
    switch (mode) {
      case DominoMode.local:
        return state.turn;
      case DominoMode.computer:
        return 0;
      case DominoMode.network:
        return isHost ? 0 : 1;
    }
  }

  int get opponentSeat => 1 - mySeat;

  GameState? _state;
  GameState get state => _state!;
  GameState? get stateOrNull => _state;
  bool get isReady => _state != null;

  bool get isOver =>
      (_state?.isOver ?? false) || _resignedWinner != null;
  GameResult? get result => _state?.result;
  int? get winner => _resignedWinner ?? _state?.result?.winner;
  bool get isDraw =>
      _resignedWinner == null && (_state?.result?.isDraw ?? false);
  bool get isFish => _state?.result?.isFish ?? false;

  int get playerCount => _state?.playerCount ?? 2;

  /// Чья рука показана внизу: в игре вдвоём за одним устройством — того, чья
  /// очередь, у компьютера и в сети — моя.
  int get handSeat {
    switch (mode) {
      case DominoMode.local:
        return state.turn;
      case DominoMode.computer:
      case DominoMode.network:
        return mySeat;
    }
  }

  List<DominoTile> get myHand =>
      isReady ? state.handOf(handSeat) : const [];
  int get opponentHandSize =>
      isReady ? state.handSizes[opponentSeat] : 0;

  Board get board => _state?.board ?? const Board.empty();
  int get bazaarCount => _state?.bazaarCount ?? 0;
  int? get leftEnd => board.leftEnd;
  int? get rightEnd => board.rightEnd;
  int get turn => _state?.turn ?? 0;
  int get ply => _state?.ply ?? 0;

  DominoTile? selectedTile;
  DominoMove? suggestedMove;
  String? notice;
  String? fatalMessage;
  bool computerThinking = false;

  /// Снимки состояний перед каждым действием — для отмены (офлайн и против
  /// компьютера). По сети отмена не работает: у клиента нет чужой руки, чтобы
  /// восстановить позицию, а у хоста нет согласия клиента.
  final List<GameState> _undo = <GameState>[];

  StreamSubscription<NetworkMessage>? _networkSub;
  bool _advancing = false;
  bool _disposed = false;
  int? _resignedWinner;

  static const _passDelay = Duration(milliseconds: 500);
  static const _computerPause = Duration(milliseconds: 600);

  // ---- Настройки ------------------------------------------------------------

  bool get hintsEnabled => settings.flag(dominoGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(dominoGameId, 'hintButton');

  // ---- Подсказки и интерактивность ------------------------------------------

  /// Кости в моей руке, которые подходят к столу. Подсветка включается, когда
  /// включены подсказки в настройках.
  Set<DominoTile> get playableTiles {
    if (!isReady) return const {};
    final set = <DominoTile>{};
    for (final tile in state.handOf(handSeat)) {
      if (state.board.canPlace(tile)) set.add(tile);
    }
    return set;
  }

  /// Чей сейчас ход — для подписи «Твой ход / Ход соперника / Компьютер думает».
  DominoActive get activeSide {
    if (isOver || !isReady) return DominoActive.nobody;
    switch (mode) {
      case DominoMode.local:
        return DominoActive.me; // оба места за одним устройством
      case DominoMode.computer:
        return state.turn == mySeat
            ? DominoActive.me
            : DominoActive.computer;
      case DominoMode.network:
        return state.turn == mySeat
            ? DominoActive.me
            : DominoActive.friend;
    }
  }

  String get turnLabel {
    if (fatalMessage != null) return 'Связь потеряна';
    if (isOver) {
      if (isDraw) return 'Ничья';
      if (winner == mySeat) return 'Ты выиграл!';
      return mode == DominoMode.local ? 'Партия окончена' : 'Партия окончена';
    }
    switch (activeSide) {
      case DominoActive.me:
        return 'Твой ход';
      case DominoActive.computer:
        return 'Компьютер думает…';
      case DominoActive.friend:
        return 'Ходит друг…';
      case DominoActive.nobody:
        return '';
    }
  }

  /// Можно ли взаимодействовать с рукой и столом.
  bool get canInteract {
    if (!isReady || isOver || fatalMessage != null) return false;
    if (computerThinking) return false;
    if (mode == DominoMode.network && state.turn != mySeat) return false;
    if (mode == DominoMode.computer && state.turn != mySeat) return false;
    return true;
  }

  /// Можно ли брать кость из базара: ход мой, ходов нет, базар не пуст.
  bool get canDraw {
    if (!canInteract) return false;
    if (_rules.getValidMoves(state).isNotEmpty) return false;
    return state.bazaarCount > 0;
  }

  /// Можно ли пропустить ход: ход мой, ходов нет, базар пуст.
  bool get canPass {
    if (!canInteract) return false;
    if (_rules.getValidMoves(state).isNotEmpty) return false;
    return state.bazaarCount == 0;
  }

  /// Отмена доступна только офлайн и против компьютера.
  bool get canUndo {
    if (isOver) return false;
    if (_isNetwork) return false;
    if (!isReady) return false;
    if (_undo.isEmpty) return false;
    if (mode == DominoMode.computer && state.turn != mySeat) return false;
    return true;
  }

  bool get canShowHint {
    if (!canInteract) return false;
    if (!hintButtonEnabled) return false;
    return _rules.getValidMoves(state).isNotEmpty;
  }

  String nameFor(int seat) {
    switch (mode) {
      case DominoMode.local:
        return seat == 0 ? 'Игрок 1' : 'Игрок 2';
      case DominoMode.computer:
        return seat == mySeat ? settings.nickname : 'Компьютер';
      case DominoMode.network:
        if (seat == mySeat) return settings.nickname;
        return network?.peerName ?? 'Друг';
    }
  }

  // ---- Старт партий --------------------------------------------------------

  /// Раздаёт кости и выкладывает стартовую кость. Локально и против компьютера.
  void _dealAndAutoStart() {
    _state = _rules.initial(players: 2, random: _rng);
    _undo.clear();
    selectedTile = null;
    suggestedMove = null;
    notice = null;
    _resignedWinner = null;
    fatalMessage = null;
    computerThinking = false;
    _autoPlaceStarting();
  }

  /// Выкладывает стартовую кость: у кого дубль 1:1 (или старшая кость), тот
  /// «открывает» партию, после чего ход переходит дальше.
  void _autoPlaceStarting() {
    if (!isReady) return;
    if (state.board.isNotEmpty) return;
    final starting = _rules.firstTile(state);
    final before = state.copyWith(turn: starting.seat);
    _state = _rules.applyMove(before, starting.move);
    sounds.play(GameSound.move);
  }

  void startLocal() {
    mode = DominoMode.local;
    _dealAndAutoStart();
    notifyListeners();
    unawaited(_advance());
  }

  void startComputer(Difficulty level) {
    mode = DominoMode.computer;
    difficulty = level;
    _dealAndAutoStart();
    notifyListeners();
    unawaited(_advance());
  }

  /// Сеть: хост раздаёт и выкладывает стартовую кость, потом шлёт снимок.
  /// Клиент ждёт первого снимка.
  void startNetwork() {
    mode = DominoMode.network;
    if (isHost) {
      _dealAndAutoStart();
      notifyListeners();
      // Небольшая задержка, чтобы клиент успел открыть экран партии и
      // подписаться на события: иначе первый снимок может прийти раньше и
      // потеряться.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (_disposed || !_isNetwork || !isHost) return;
        _broadcastSnapshot();
      });
    } else {
      // Клиент: положение пришлёт хост первым снимком. Пока покажем заглушку.
      _state = GameState(
        playerCount: 2,
        hands: const [[], []],
        bazaar: const [],
        bazaarTotal: deckSize - 2 * tilesPerPlayer,
        turn: 0,
      );
      notifyListeners();
    }
  }

  // ---- Выбор и ход --------------------------------------------------------

  /// Игрок нажал кость в руке. Если кость подходит только к одному концу —
  /// ставим её сразу; если к двум — подсвечиваем концы и ждём выбора.
  void tapTile(DominoTile tile) {
    if (!canInteract) return;
    notice = null;
    final sides = state.board.sidesFor(tile);
    if (sides.isEmpty) {
      // Не подходит ни к одному концу — объясним, что делать.
      notice = _explainNoMatch();
      suggestedMove = null;
      notifyListeners();
      return;
    }
    if (sides.length == 1) {
      unawaited(_play(DominoMove(tile: tile, side: sides.first)));
      return;
    }
    // Подходит к обоим концам — попросим, куда ставить.
    if (selectedTile == tile) {
      selectedTile = null;
      notice = null;
      notifyListeners();
      return;
    }
    selectedTile = tile;
    notice = 'Куда поставить ${tile.label}? Нажми на подсвеченный конец.';
    notifyListeners();
  }

  /// Игрок нажал на открытый конец цепочки.
  void placeTile(DominoTile tile, ChainSide side) {
    if (!canInteract) return;
    if (!state.board.sidesFor(tile).contains(side)) {
      notice = 'Кость ${tile.label} не подходит к этому концу.';
      notifyListeners();
      return;
    }
    unawaited(_play(DominoMove(tile: tile, side: side)));
  }

  /// Тап по концу цепочки: ставит выбранную кость.
  void selectSide(ChainSide side) {
    if (!canInteract) return;
    final tile = selectedTile ?? suggestedMove?.tile;
    if (tile == null) {
      notice = 'Сначала выбери кость в руке.';
      notifyListeners();
      return;
    }
    placeTile(tile, side);
  }

  void clearSelection() {
    if (selectedTile != null) {
      selectedTile = null;
      notice = null;
      notifyListeners();
    }
  }

  String _explainNoMatch() {
    final left = state.board.leftEnd;
    final right = state.board.rightEnd;
    if (left == null || right == null) {
      return 'Начни цепочку с любой кости.';
    }
    final ends = left == right ? '$left' : '$left и $right';
    if (state.bazaarCount > 0) {
      return 'Нет подходящей кости к концам $ends. Возьми из базара.';
    }
    return 'Нет подходящей кости к концам $ends, а базар пуст — придётся пасовать.';
  }

  // ---- Действия ------------------------------------------------------------

  Future<void> _play(DominoMove move) async {
    if (!isReady || isOver) return;
    final before = state;
    if (!before.handOf(before.turn).contains(move.tile)) return;
    if (!before.board.sidesFor(move.tile).contains(move.side)) return;
    if (_isNetwork && !isHost) {
      // Клиент: отправляем ход хосту, ждём снимок. Хост применяет ход сам.
      try {
        network!.service.send(NetworkMessage('move', moveToJson(move)));
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
        notifyListeners();
        return;
      }
      selectedTile = null;
      suggestedMove = null;
      notice = null;
      notifyListeners();
      return;
    }
    _undo.add(before);
    _state = _rules.applyMove(before, move);
    selectedTile = null;
    suggestedMove = null;
    notice = null;
    sounds.play(GameSound.move);
    notifyListeners();
    if (isOver) {
      unawaited(_onWin());
    }
    if (_isNetwork && isHost) {
      _broadcastSnapshot();
    } else if (!isOver) {
      unawaited(_advance());
    }
  }

  /// Взять кость из базара. Очередь хода не меняется: взяв кость, игрок
  /// продолжает искать, чем походить.
  Future<void> drawFromBazaar() async {
    if (!canInteract) return;
    if (_rules.getValidMoves(state).isNotEmpty) {
      notice = 'У тебя есть подходящая кость — поставь её на стол.';
      notifyListeners();
      return;
    }
    if (state.bazaarCount == 0) {
      notice = 'Базар пуст — придётся пропустить ход.';
      notifyListeners();
      return;
    }
    if (_isNetwork && !isHost) {
      try {
        network!.service.send(
          const NetworkMessage('event', {'kind': 'draw'}),
        );
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
        notifyListeners();
        return;
      }
      notice = 'Берём кость из базара…';
      notifyListeners();
      return;
    }
    final before = state;
    final seat = before.turn;
    _undo.add(before);
    _state = _rules.drawFromBazaar(before);
    final drawn = _state!.handOf(seat).last;
    sounds.play(GameSound.guess);
    if (_rules.getValidMoves(state).isNotEmpty) {
      notice = 'Кость ${drawn.label} подошла! Поставь её на стол.';
    } else if (state.bazaarCount > 0) {
      notice = 'Кость ${drawn.label} не подходит. Возьми ещё из базара.';
    } else {
      notice = 'Кость ${drawn.label} не подходит, а базар пуст — пропускаем ход.';
    }
    notifyListeners();
    if (isOver) {
      unawaited(_onWin());
    }
    if (_isNetwork && isHost) {
      _broadcastSnapshot();
    } else if (!isOver) {
      unawaited(_advance());
    }
  }

  /// Пропустить ход: подходящих костей нет, базар пуст.
  Future<void> pass() async {
    if (!canInteract) return;
    if (_rules.getValidMoves(state).isNotEmpty) {
      notice = 'У тебя есть подходящая кость — поставь её.';
      notifyListeners();
      return;
    }
    if (state.bazaarCount > 0) {
      notice = 'Базар ещё не пуст — возьми кость.';
      notifyListeners();
      return;
    }
    if (_isNetwork && !isHost) {
      try {
        network!.service.send(
          const NetworkMessage('event', {'kind': 'pass'}),
        );
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
        notifyListeners();
        return;
      }
      notice = 'Пропускаем ход…';
      notifyListeners();
      return;
    }
    _applyLocalPass();
    if (_isNetwork && isHost && isReady) {
      _broadcastSnapshot();
    }
  }

  void _applyLocalPass() {
    if (!isReady || isOver) return;
    final before = state;
    _undo.add(before);
    _state = _rules.pass(before);
    notice = '${nameFor(before.turn)} пропускает ход.';
    notifyListeners();
    if (isOver) {
      unawaited(_onWin());
      return;
    }
    unawaited(_advance());
  }

  // ---- Продвижение партии: ИИ, авто-пропуски -------------------------------

  /// Следующий шаг: пропуск ходов, ответ компьютера, подсказка про базар.
  Future<void> _advance() async {
    if (_disposed || !isReady || isOver || _isNetwork) return;
    if (_advancing) return;
    _advancing = true;
    try {
      var guard = 0;
      while (!_disposed && isReady && !isOver && guard++ < 24) {
        final moves = _rules.getValidMoves(state);
        if (moves.isEmpty) {
          if (state.bazaarCount > 0) {
            // Живой игрок берёт кость сам; компьютер — ниже.
            if (mode == DominoMode.computer && state.turn != mySeat) {
              await _computerDraw();
              continue;
            }
            notice = 'Подходящих костей нет — возьми кость из базара.';
            notifyListeners();
            return;
          }
          // Базар пуст — пропускаем ход автоматически.
          _applyLocalPass();
          await Future<void>.delayed(_passDelay);
          continue;
        }
        if (mode == DominoMode.computer && state.turn != mySeat) {
          await _computerTurn();
          continue;
        }
        notifyListeners();
        return;
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> _computerDraw() async {
    if (!isReady || isOver) return;
    final before = state;
    _undo.add(before);
    _state = _rules.drawFromBazaar(before);
    sounds.play(GameSound.guess);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _computerTurn() async {
    if (_disposed || isOver) return;
    if (state.turn == mySeat) return;
    computerThinking = true;
    notifyListeners();
    await Future<void>.delayed(_computerPause);
    if (_disposed || isOver) {
      computerThinking = false;
      notifyListeners();
      return;
    }
    final move = DominoAI.findBestMove(state, state.turn, difficulty, _rng);
    if (move == null) {
      // Ходов нет — _advance сам разберётся (возьмёт из базара или пропустит).
      computerThinking = false;
      notifyListeners();
      return;
    }
    final before = state;
    _undo.add(before);
    _state = _rules.applyMove(before, move);
    computerThinking = false;
    sounds.play(GameSound.move);
    notifyListeners();
    if (isOver) {
      unawaited(_onWin());
    }
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Предлагает хороший ход: подсвечивает кость и конец, не делая ход за
  /// ребёнка.
  void showHint() {
    if (!canInteract || !hintButtonEnabled) return;
    final move = DominoAI.findBestMove(
      state,
      state.turn,
      Difficulty.medium,
      _rng,
    );
    if (move == null) {
      notice = state.bazaarCount > 0
          ? 'Подходящих костей нет — возьми из базара.'
          : 'Ходов нет — придётся пропустить.';
      suggestedMove = null;
      notifyListeners();
      return;
    }
    suggestedMove = move;
    selectedTile = move.tile;
    notice = 'Попробуй поставить ${move.tile.label} ${move.side.label}.';
    notifyListeners();
  }

  // ---- Отмена --------------------------------------------------------------

  void undo() {
    if (!canUndo) return;
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    _state = prev;
    selectedTile = null;
    suggestedMove = null;
    notice = 'Ход отменён';
    notifyListeners();
  }

  // ---- Сдача ---------------------------------------------------------------

  /// Сдаться. Доступно только против компьютера и по сети — вдвоём на одном
  /// устройстве сдаваться незачем, можно просто выйти в меню.
  void resign() {
    if (isOver) return;
    if (mode == DominoMode.local) return;
    final winnerSeat = opponentSeat;
    _resignedWinner = winnerSeat;
    if (_isNetwork) {
      try {
        network!.service.send(const NetworkMessage('resign'));
      } catch (_) {
        // Связь уже могла пропасть — всё равно фиксируем итог.
      }
    }
    unawaited(_onWin());
  }

  // ---- Победа --------------------------------------------------------------

  Future<void> _onWin() async {
    if (!isOver) return;
    final draw = isDraw;
    // В локальном режиме оба места за одним устройством, так что «человек
    // выиграл» — всегда. В сети и против компьютера — только если победил
    // мой seat.
    final iWon = mode == DominoMode.local ? true : winner == mySeat;
    sounds.play(resultSoundName(draw: draw, local: mode == DominoMode.local, iWon: iWon));
    await settings.recordGame(won: iWon);
    notifyListeners();
  }

  // ---- Сеть: хост ----------------------------------------------------------

  void _broadcastSnapshot() {
    if (!_isNetwork || !isHost) return;
    if (!isReady) return;
    try {
      network!.service.send(
        NetworkMessage(
          'event',
          {'kind': 'snapshot', ...snapshotToJson(state, 1)},
        ),
      );
    } catch (_) {
      fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
      notifyListeners();
    }
  }

  /// Хост получил ход от клиента. Применяет, проверяя правила, и рассылает
  /// снимок. Нелегальный ход — это рассинхрон: обрываем связь.
  void _hostReceiveMove(Map<String, Object?> data) {
    if (!_isNetwork || !isHost || !isReady) return;
    if (state.turn != 1) return; // не клиентский ход
    try {
      final move = parseMove(data);
      _undo.add(state);
      _state = _rules.applyMove(state, move);
      sounds.play(GameSound.move);
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
      _broadcastSnapshot();
    } on Object catch (e) {
      _desync(e.toString());
    }
  }

  void _hostReceiveDraw() {
    if (!_isNetwork || !isHost || !isReady) return;
    if (state.turn != 1) return;
    if (state.bazaar.isEmpty) {
      // Клиент просит взять из пустого базара — это противоречие.
      _desync('Нельзя взять из пустого базара');
      return;
    }
    try {
      _undo.add(state);
      _state = _rules.drawFromBazaar(state);
      sounds.play(GameSound.guess);
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
      _broadcastSnapshot();
    } on Object catch (e) {
      _desync(e.toString());
    }
  }

  void _hostReceivePass() {
    if (!_isNetwork || !isHost || !isReady) return;
    if (state.turn != 1) return;
    try {
      _undo.add(state);
      _state = _rules.pass(state);
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
      _broadcastSnapshot();
    } on Object catch (e) {
      _desync(e.toString());
    }
  }

  // ---- Сеть: клиент --------------------------------------------------------

  /// Клиент получил снимок от хоста: просто заменяем состояние.
  void _clientApplySnapshot(Map<String, Object?> data) {
    if (!_isNetwork || isHost) return;
    try {
      _state = parseSnapshot(data);
      selectedTile = null;
      suggestedMove = null;
      notice = null;
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Снимок не распознан' : e.message);
    }
  }

  // ---- Сеть: общее ---------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    switch (event.type) {
      case 'move':
        if (isHost) {
          _hostReceiveMove(event.data);
        }
        // Клиент не получает ходы напрямую: только снимки.
        break;
      case 'event':
        final kind = event.data['kind'];
        if (kind == 'snapshot') {
          _clientApplySnapshot(event.data);
        } else if (kind == 'draw' && isHost) {
          _hostReceiveDraw();
        } else if (kind == 'pass' && isHost) {
          _hostReceivePass();
        }
        break;
      case 'resign':
        // Соперник сдался — победа за этим устройством.
        _resignedWinner = mySeat;
        unawaited(_onWin());
        break;
      case 'disconnected':
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
        notifyListeners();
        break;
      case 'desync':
        _desync('Партия рассинхронизировалась');
        break;
      case 'error':
        final msg = event.data['message'];
        fatalMessage = msg is String ? msg : 'Связь потеряна';
        notifyListeners();
        break;
    }
  }

  void _desync(String reason) {
    fatalMessage = reason.isEmpty ? 'Партия рассинхронизировалась' : reason;
    notifyListeners();
  }

  // ---- Утилиты -------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _networkSub?.cancel();
    super.dispose();
  }
}
