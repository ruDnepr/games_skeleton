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

/// Что происходит на столе прямо сейчас — по этому экран рисует анимацию.
enum TableAnimationKind { place, draw }

class TableAnimation {
  const TableAnimation({
    required this.kind,
    required this.seat,
    required this.duration,
    this.move,
    this.tile,
  });

  final TableAnimationKind kind;
  final int seat;
  final DominoMove? move;
  final DominoTile? tile;
  final Duration duration;
}

/// Строчка истории.
class MoveRecord {
  const MoveRecord({required this.seat, required this.text});

  final int seat;
  final String text;

  @override
  String toString() => '#$seat $text';
}

class _UndoEntry {
  const _UndoEntry({
    required this.state,
    required this.seat,
    required this.records,
  });

  final GameState state;
  final int seat;
  final int records;
}

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
    this.animationDuration = const Duration(milliseconds: 420),
    this.initialState,
    GameState Function()? initialStateFactory,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = DominoMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    if (initialState != null) {
      _state = initialState;
    } else if (initialStateFactory != null) {
      _state = initialStateFactory();
    }
    settings.addListener(_settingsChanged);
  }

  final bool isHost;

  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  bool get _isNetwork => mode == DominoMode.network;

  /// Длительность выкладывания кости. В тестах её уменьшают.
  final Duration animationDuration;

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

  /// Стартовая позиция для тестов; в игре всегда раздаётся новая.
  final GameState? initialState;

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

  /// Подходящие ходы в текущей позиции.
  List<DominoMove> get legalMoves =>
      isReady ? _rules.getValidMoves(state) : const <DominoMove>[];

  DominoTile? selectedTile;
  DominoMove? suggestedMove;
  String? hintText;
  String? notice;
  String? fatalMessage;
  TableAnimation? animation;
  bool computerThinking = false;
  bool waitingForUndo = false;
  int? incomingUndoPly;
  int? incomingUndoSeat;
  int? _deferredUndoPly;

  /// История ходов партии — для показа в одноимённом диалоге.
  final List<MoveRecord> _records = <MoveRecord>[];
  List<MoveRecord> get history => List<MoveRecord>.unmodifiable(_records);

  /// Снимки состояний перед каждым действием — для отмены (офлайн и против
  /// компьютера). По сети отмена работает по согласию: запрашиваем у друга.
  final List<_UndoEntry> _undo = <_UndoEntry>[];

  StreamSubscription<NetworkMessage>? _networkSub;
  Timer? _echoTimer;
  bool _awaitingEcho = false;
  bool _advancing = false;
  bool _disposed = false;
  int? _resignedWinner;
  int _animationToken = 0;

  /// Колбэк, который выставляет интерфейс, чтобы спросить ребёнка о согласии
  /// на отмену хода по сети. Сетевой контроллер не показывает диалог сам.
  void Function()? onUndoRequested;

  static const _passDelay = Duration(milliseconds: 450);
  static const _computerPause = Duration(milliseconds: 550);

  // ---- Настройки -----------------------------------------------------------

  bool get hintsEnabled => settings.flag(dominoGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(dominoGameId, 'hintButton');

  void _settingsChanged() {
    if (!hintsEnabled) {
      suggestedMove = null;
      hintText = null;
      if (notice != null && !waitingForUndo) notice = null;
    }
    notifyListeners();
  }

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
      return 'Партия окончена';
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

  bool get isAnimating => animation != null;

  /// Можно ли взаимодействовать с рукой и столом.
  bool get canInteract {
    if (!isReady || isOver || fatalMessage != null) return false;
    if (computerThinking) return false;
    if (isAnimating) return false;
    if (waitingForUndo || incomingUndoPly != null) return false;
    if (_awaitingEcho) return false;
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

  /// Отмена доступна офлайн и против компьютера, а по сети — по согласию.
  /// Доступна и после окончания партии: кнопка «Отменить ход» в диалоге
  /// итога позволяет откатить последнее действие.
  bool get canUndo {
    if (!isReady || isAnimating || fatalMessage != null) return false;
    if (waitingForUndo || incomingUndoPly != null || _awaitingEcho) return false;
    if (_isNetwork) {
      // По сети отмена работает только запросом к другу.
      return network != null && _undo.isNotEmpty && _undo.last.seat == mySeat;
    }
    if (_undo.isEmpty) return false;
    if (mode == DominoMode.computer && state.turn != mySeat && !isOver) {
      return false;
    }
    return true;
  }

  bool get canShowHint {
    if (!canInteract) return false;
    if (!hintsEnabled) return false;
    if (!hintButtonEnabled) return false;
    return _rules.getValidMoves(state).isNotEmpty;
  }

  String nameFor(int seat) {
    if (seat < 0) return 'Игрок';
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
    _records.clear();
    selectedTile = null;
    suggestedMove = null;
    hintText = null;
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
    _records.add(
      MoveRecord(
        seat: starting.seat,
        text: 'открывает партию костью ${starting.tile.label}',
      ),
    );
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

  /// Альтернативный старт с готовой позицией — для тестов. Режим остаётся
  /// тем, что выставил вызывающий (локально или против компьютера).
  void startLocalWithState(GameState state) {
    _state = state;
    _undo.clear();
    _records.clear();
    selectedTile = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    _resignedWinner = null;
    fatalMessage = null;
    computerThinking = false;

    notifyListeners();
    unawaited(_advance());
  }

  /// То же, но в режиме против компьютера.
  void startComputerWithState(GameState state, Difficulty level) {
    mode = DominoMode.computer;
    difficulty = level;
    startLocalWithState(state);
  }

  // ---- Анимация ------------------------------------------------------------

  Future<void> _animate(TableAnimation next) async {
    _animationToken++;
    final token = _animationToken;
    animation = next;
    notifyListeners();
    if (next.duration > Duration.zero) {
      await Future<void>.delayed(next.duration);
    }
    if (_disposed || token != _animationToken) return;
    animation = null;
    _promoteDeferredUndo();
    notifyListeners();
  }

  /// Запрос отмены, пришедший во время анимации, показываем сразу после неё.
  void _promoteDeferredUndo() {
    if (_deferredUndoPly == null || isAnimating) return;
    incomingUndoPly = _deferredUndoPly;
    _deferredUndoPly = null;
    onUndoRequested?.call();
    notifyListeners();
  }

  // ---- Выбор и ход --------------------------------------------------------

  /// Игрок нажал кость в руке. Если кость подходит только к одному концу —
  /// ставим её сразу; если к двум — подсвечиваем концы и ждём выбора.
  void tapTile(DominoTile tile) {
    if (!canInteract) return;
    notice = null;
    hintText = null;
    final sides = state.board.sidesFor(tile);
    if (sides.isEmpty) {
      // Не подходит ни к одному концу — объясним, что делать.
      notice = _explainNoMatch(tile);
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

  /// Тап по концу цепочки: ставит выбранную кость.
  void playAt(ChainSide side) => selectSide(side);

  /// Тап по концу цепочки: ставит выбранную кость.
  void selectSide(ChainSide side) {
    if (!canInteract) return;
    final tile = selectedTile ?? suggestedMove?.tile;
    if (tile == null) {
      notice = 'Сначала выбери кость в руке.';
      notifyListeners();
      return;
    }
    if (!state.board.sidesFor(tile).contains(side)) {
      notice = 'Кость ${tile.label} не подходит к этому концу.';
      notifyListeners();
      return;
    }
    unawaited(_play(DominoMove(tile: tile, side: side)));
  }

  /// Поставить кость сразу, без выбора — так играет подсказка и тесты.
  Future<void> playMove(DominoMove move) async {
    if (!canInteract) return;
    if (!state.board.sidesFor(move.tile).contains(move.side)) return;
    if (!state.handOf(state.turn).contains(move.tile)) return;
    await _play(move);
  }

  void placeTile(DominoTile tile, ChainSide side) {
    if (!canInteract) return;
    if (!state.board.sidesFor(tile).contains(side)) {
      notice = 'Кость ${tile.label} не подходит к этому концу.';
      notifyListeners();
      return;
    }
    unawaited(_play(DominoMove(tile: tile, side: side)));
  }

  void clearSelection() {
    if (selectedTile != null) {
      selectedTile = null;
      notice = null;
      notifyListeners();
    }
  }

  String _explainNoMatch(DominoTile tile) {
    final left = state.board.leftEnd;
    final right = state.board.rightEnd;
    if (!hintsEnabled) return 'Так ходить нельзя.';
    if (left == null || right == null) {
      return 'Начни цепочку с любой кости.';
    }
    final ends = left == right ? '$left' : '$left и $right';
    if (state.bazaarCount > 0) {
      return 'Кость ${tile.label} не подходит к концам $ends. '
          'Возьми кость из базара.';
    }
    return 'Кость ${tile.label} не подходит к концам $ends, '
        'а базар уже пуст — ход пропускается.';
  }

  // ---- Действия ------------------------------------------------------------

  Future<void> _play(DominoMove move) async {
    if (!isReady || isOver) return;
    final before = state;
    if (!before.handOf(before.turn).contains(move.tile)) return;
    if (!before.board.sidesFor(move.tile).contains(move.side)) return;
    final seat = before.turn;
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
      hintText = null;
      notice = null;
      _awaitEcho();
      return;
    }
    _remember(before, seat);
    _state = _rules.applyMove(before, move);
    _records.add(
      MoveRecord(
        seat: seat,
        text: 'ставит ${move.tile.label} ${move.side.label}',
      ),
    );
    selectedTile = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    computerThinking = false;
    sounds.play(GameSound.move);
    notifyListeners();
    await _animate(
      TableAnimation(
        kind: TableAnimationKind.place,
        seat: seat,
        move: move,
        duration: animationDuration,
      ),
    );
    if (_disposed) return;
    if (isOver) {
      unawaited(_onWin());
    }
    if (_isNetwork && isHost) {
      _broadcastSnapshot();
    } else if (!isOver) {
      await _advance();
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
      notice = 'Базар пуст — остаётся пропустить ход.';
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
      _awaitEcho();
      return;
    }
    final before = state;
    final seat = before.turn;
    _remember(before, seat);
    _state = _rules.drawFromBazaar(before);
    final drawn = _state!.handOf(seat).last;
    _records.add(MoveRecord(seat: seat, text: 'берёт ${drawn.label} из базара'));
    sounds.play(GameSound.guess);
    notifyListeners();
    await _animate(
      TableAnimation(
        kind: TableAnimationKind.draw,
        seat: seat,
        tile: drawn,
        duration: animationDuration ~/ 2,
      ),
    );
    if (_disposed) return;
    if (isOver) {
      unawaited(_onWin());
    }
    if (_rules.getValidMoves(state).isNotEmpty) {
      notice = 'Кость ${drawn.label} подошла! Поставь её на стол.';
      notifyListeners();
      return;
    }
    if (_isNetwork && isHost) {
      _broadcastSnapshot();
    } else if (!isOver) {
      await _advance();
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
      _awaitEcho();
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
    final seat = before.turn;
    _remember(before, seat);
    _state = _rules.pass(before);
    _records.add(MoveRecord(seat: seat, text: 'пропускает ход'));
    notice = 'Ходов нет — пропускаем ход.';
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
    final seat = before.turn;
    _remember(before, seat);
    _state = _rules.drawFromBazaar(before);
    final drawn = _state!.handOf(seat).last;
    _records.add(MoveRecord(seat: seat, text: 'берёт ${drawn.label} из базара'));
    sounds.play(GameSound.guess);
    notifyListeners();
    await _animate(
      TableAnimation(
        kind: TableAnimationKind.draw,
        seat: seat,
        tile: drawn,
        duration: animationDuration ~/ 2,
      ),
    );
    if (_disposed) return;
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
    var draws = 0;
    while (!_disposed && !isOver) {
      final moves = _rules.getValidMoves(state);
      if (moves.isNotEmpty) {
        computerThinking = false;
        final move = DominoAI.findBestMove(state, state.turn, difficulty, _rng) ??
            moves.first;
        await _play(move);
        return;
      }
      if (state.bazaarCount == 0 || draws++ > 20) break;
      await _computerDraw();
      if (_disposed) return;
    }
    computerThinking = false;
    notifyListeners();
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Предлагает хороший ход: подсвечивает кость и конец, не делая ход за
  /// ребёнка.
  void showHint() {
    if (!canInteract || !hintsEnabled) return;
    notice = null;
    final move = DominoAI.findBestMove(
      state,
      state.turn,
      Difficulty.medium,
      _rng,
    );
    if (move == null) {
      suggestedMove = null;
      selectedTile = null;
      hintText = state.bazaarCount > 0
          ? 'Подходящей кости нет — возьми кость из базара.'
          : 'Ходов нет — придётся пропустить ход.';
      notifyListeners();
      return;
    }
    suggestedMove = move;
    selectedTile = move.tile;
    hintText = _describeHint(move);
    notifyListeners();
  }

  String _describeHint(DominoMove move) {
    final board = state.board.place(move.tile, move.side);
    final ends = board.leftEnd == board.rightEnd
        ? '${board.leftEnd}'
        : '${board.leftEnd} и ${board.rightEnd}';
    final rest = state.handOf(handSeat).length - 1;
    final left = rest == 0
        ? ' Это последняя кость — и победа!'
        : (rest == 1 ? ' Останется одна кость.' : '');
    if (state.board.isEmpty) {
      return 'Поставь ${move.tile.label} — с неё начнётся цепочка.$left';
    }
    return 'Поставь ${move.tile.label} ${move.side.label}: '
        'после этого открытыми будут $ends.$left';
  }

  void clearHint() {
    if (suggestedMove == null && hintText == null) return;
    suggestedMove = null;
    hintText = null;
    if (selectedTile != null) selectedTile = null;
    notifyListeners();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  // ---- Отмена --------------------------------------------------------------

  void undo() {
    if (!canUndo) return;
    if (_isNetwork) {
      waitingForUndo = true;
      notice = null;
      try {
        network!.service.send(
          NetworkMessage('undoRequest', {'ply': state.ply}),
        );
      } catch (_) {
        waitingForUndo = false;
        fatalMessage = 'Связь потеряна.';
      }
      notifyListeners();
      return;
    }
    final entry = _undo.last;
    _restore(entry);
  }

  void _restore(_UndoEntry entry) {
    _state = entry.state;
    while (_undo.isNotEmpty && _undo.last != entry) {
      _undo.removeLast();
    }
    if (_undo.isNotEmpty) _undo.removeLast();
    final keep = entry.records.clamp(0, _records.length).toInt();
    _records.removeRange(keep, _records.length);
    selectedTile = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    animation = null;
    computerThinking = false;
    waitingForUndo = false;
    incomingUndoPly = null;
    incomingUndoSeat = null;
    _deferredUndoPly = null;
    _awaitingEcho = false;
    _resignedWinner = null;
    notifyListeners();
    unawaited(_advance());
  }

  /// Ответ на просьбу друга об отмене хода по сети.
  void respondUndo(bool accepted) {
    final ply = incomingUndoPly;
    incomingUndoPly = null;
    incomingUndoSeat = null;
    if (ply == null) return;
    if (!_isNetwork) return;
    try {
      network!.service.send(
        NetworkMessage('undoResponse', {'ply': ply, 'accepted': accepted}),
      );
      notice = accepted
          ? 'Возвращаемся на ход назад…'
          : 'Хорошо, продолжаем партию.';
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
    }
    notifyListeners();
  }

  // ---- Сдача ---------------------------------------------------------------

  /// Сдаться. Доступно только против компьютера и по сети — вдвоём на одном
  /// устройстве сдаваться незачем, можно просто выйти в меню.
  void resign() {
    if (!isReady || isOver || fatalMessage != null) return;
    if (mode == DominoMode.local) return;
    if (_isNetwork) {
      try {
        network!.service.send(const NetworkMessage('resign'));
      } catch (_) {
        // Связь уже могла пропасть — всё равно фиксируем итог.
      }
      _resignedWinner = opponentSeat;
      notice = 'Ты сдался. Спасибо за игру!';
      notifyListeners();
      unawaited(_onWin());
      return;
    }
    // Против компьютера: победа достаётся сопернику.
    _resignedWinner = opponentSeat;
    computerThinking = false;
    animation = null;
    notifyListeners();
    unawaited(_onWin());
  }

  void _remember(GameState state, int seat) {
    _undo.add(
      _UndoEntry(state: state, seat: seat, records: _records.length),
    );
    if (_undo.length > 20) _undo.removeAt(0);
  }

  // ---- Победа --------------------------------------------------------------

  Future<void> _onWin() async {
    if (!isOver) return;
    final draw = isDraw;
    // В локальном режиме оба места за одним устройством, так что «человек
    // выиграл» — всегда. В сети и против компьютера — только если победил
    // мой seat.
    final iWon = mode == DominoMode.local ? true : winner == mySeat;
    sounds.play(
      resultSoundName(draw: draw, local: mode == DominoMode.local, iWon: iWon),
    );
    unawaited(settings.recordGame(won: iWon));
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
      _remember(state, 1);
      _state = _rules.applyMove(state, move);
      _records.add(
        MoveRecord(
          seat: 1,
          text: 'ставит ${move.tile.label} ${move.side.label}',
        ),
      );
      sounds.play(GameSound.move);
      notifyListeners();
      unawaited(
        _animate(
          TableAnimation(
            kind: TableAnimationKind.place,
            seat: 1,
            move: move,
            duration: animationDuration,
          ),
        ),
      );
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
      _remember(state, 1);
      _state = _rules.drawFromBazaar(state);
      final drawn = _state!.handOf(1).last;
      _records.add(MoveRecord(seat: 1, text: 'берёт ${drawn.label} из базара'));
      sounds.play(GameSound.guess);
      notifyListeners();
      unawaited(
        _animate(
          TableAnimation(
            kind: TableAnimationKind.draw,
            seat: 1,
            tile: drawn,
            duration: animationDuration ~/ 2,
          ),
        ),
      );
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
      _remember(state, 1);
      _state = _rules.pass(state);
      _records.add(MoveRecord(seat: 1, text: 'пропускает ход'));
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
      _broadcastSnapshot();
    } on Object catch (e) {
      _desync(e.toString());
    }
  }

  void _hostReceiveUndoRequest(Map<String, Object?> data) {
    if (!_isNetwork || !isHost || !isReady) return;
    final ply = data['ply'];
    if (ply is! int) return;
    // Хост хранит свои снимки и снимки клиента; согласие не нужно — отмена
    // локальна к хосту тоже, но по сети мы просто применяем её у себя и шлём
    // снимок. Согласие упрощено: хост разрешает, если ход клиента.
    if (_undo.isEmpty || _undo.last.seat != 1) {
      try {
        network!.service.send(
          NetworkMessage('undoResponse', {'ply': ply, 'accepted': false}),
        );
      } catch (_) {}
      return;
    }
    final entry = _undo.last;
    _restore(entry);
    try {
      network!.service.send(
        NetworkMessage('undoResponse', {'ply': ply, 'accepted': true}),
      );
    } catch (_) {}
    _broadcastSnapshot();
  }

  // ---- Сеть: клиент --------------------------------------------------------

  /// Клиент получил снимок от хоста: просто заменяем состояние.
  void _clientApplySnapshot(Map<String, Object?> data) {
    if (!_isNetwork || isHost) return;
    try {
      final snapshot = parseSnapshot(data);
      _state = snapshot;
      selectedTile = null;
      suggestedMove = null;
      hintText = null;
      notice = null;
      _awaitingEcho = false;
      _echoTimer?.cancel();
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Снимок не распознан' : e.message);
    }
  }

  // ---- Сеть: общее ---------------------------------------------------------

  void _awaitEcho() {
    _awaitingEcho = true;
    _echoTimer?.cancel();
    _echoTimer = Timer(const Duration(seconds: 6), () {
      if (_disposed || !_awaitingEcho) return;
      _awaitingEcho = false;
      notice = 'Хост не отвечает. Проверь Wi-Fi — партия может быть на паузе.';
      notifyListeners();
    });
    notifyListeners();
  }

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
      case 'undoRequest':
        // Запрос от друга об отмене — покажем диалог через колбэк.
        if (isHost) {
          _hostReceiveUndoRequest(event.data);
        } else {
          final ply = event.data['ply'];
          if (ply is! int) return;
          if (isAnimating) {
            _deferredUndoPly = ply;
            return;
          }
          incomingUndoPly = ply;
          incomingUndoSeat = 0;
          onUndoRequested?.call();
          notifyListeners();
        }
        break;
      case 'undoResponse':
        final accepted = event.data['accepted'] == true;
        waitingForUndo = false;
        _awaitingEcho = false;
        _echoTimer?.cancel();
        notice = accepted
            ? 'Ход отменён — возвращаемся назад.'
            : 'Друг решил продолжить без отмены хода.';
        notifyListeners();
        break;
      case 'resign':
        // Соперник сдался — победа за этим устройством.
        _resignedWinner = mySeat;
        unawaited(_onWin());
        break;
      case 'disconnected':
        _awaitingEcho = false;
        _echoTimer?.cancel();
        if (!isOver) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
          animation = null;
          notifyListeners();
        }
        break;
      case 'desync':
        _desync('Партия рассинхронизировалась');
        break;
      case 'error':
        final msg = event.data['message'];
        _awaitingEcho = false;
        _echoTimer?.cancel();
        notice = msg is String ? msg : 'Так ходить нельзя.';
        notifyListeners();
        break;
    }
  }

  void _desync(String reason) {
    fatalMessage = reason.isEmpty ? 'Партия рассинхронизировалась' : reason;
    _awaitingEcho = false;
    _echoTimer?.cancel();
    animation = null;
    notifyListeners();
  }

  // ---- Утилиты -------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;
    _echoTimer?.cancel();
    _animationToken++;
    _networkSub?.cancel();
    settings.removeListener(_settingsChanged);
    super.dispose();
  }
}
