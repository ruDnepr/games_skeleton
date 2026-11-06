import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режим партии.
enum GameMode { ai, local, network }

/// Фаза партии: идёт или окончена.
enum GamePhase { playing, over }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно интерфейсу для правильной подписи.
enum ActiveSide { me, computer, friend, nobody }

/// Исход партии. `null` — ещё идёт.
enum GameResult { white, black, draw }

/// Контроллер партии шашек. Содержит состояние, историю, звук и сеть; интерфейс
/// только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
class CheckersController extends ChangeNotifier {
  CheckersController({
    required this.settings,
    required this.sounds,
    required this.variant,
    this.network,
  }) : isHost = network?.isHost ?? false,
       rules = GameRules.forVariant(variant) as StandardRules {
    if (network != null) {
      mode = GameMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    state = GameState.initial(variant);
    _recordPosition(state);
  }

  final SettingsController settings;
  final GameSounds sounds;
  final GameVariant variant;
  final StandardRules rules;
  final NetworkSession? network;
  late final bool isHost;

  GameMode mode = GameMode.local;
  Difficulty difficulty = Difficulty.medium;

  /// Цвет человека на этом устройстве. В режиме ИИ — цвет ребёнка; в сети у
  /// хоста white, у клиента black; вдвоём на одном устройстве оба «человеческие».
  Side humanColor = Side.white;

  GameState state = GameState.initial(GameVariant.russian);
  GamePhase phase = GamePhase.playing;

  /// Снимки на начало каждого хода — для отмены. По сети оба устройства кладут
  /// сюда по одному снимку на ход, поэтому они симметричны и отмена работает
  /// одинаково с обеих сторон.
  final List<GameState> _history = [];

  /// Счётчик повторов позиции для правила ничьей. Ключ — `positionKey`
  /// (доска + сторона хода, без номера полухода).
  final Map<String, int> _positionCounts = {};

  Square? _selected;
  List<Move> _legalForSelected = const [];
  Move? _suggested;
  String? _hintText;

  bool busy = false;
  String? status;

  StreamSubscription<NetworkMessage>? _networkSub;
  bool _disposed = false;
  bool _undoPending = false;

  /// Колбэк, который выставляет интерфейс, чтобы спросить ребёнка о согласии
  /// на отмену хода по сети. Сетевой контроллер не показывает диалог сам.
  void Function()? onUndoRequested;

  // ---- Настройки ------------------------------------------------------------

  bool get hintsEnabled => settings.flag(checkersGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(checkersGameId, 'hintButton');

  // ---- Выбор и подсветка ----------------------------------------------------

  Square? get selected => _selected;
  List<Move> get legalForSelected => _legalForSelected;
  Move? get suggestedMove => _suggested;
  String? get hintText => _hintText;

  /// Шашки, которыми можно начать ход (для лёгкой подсветки, когда ничего не
  /// выбрано). Пусто, если подсказки выключены или ход не наш.
  Set<Square> get movablePieces {
    if (!hintsEnabled || !canInteract) return const {};
    if (_selected != null) return const {};
    final points = <Square>{};
    for (final move in rules.legalMoves(state)) {
      points.add(move.from);
    }
    return points;
  }

  /// Клетки-адресаты для выбранной шашки. Пусто, если ничего не выбрано или
  /// подсказки выключены.
  Set<Square> get destinations {
    if (_selected == null) return const {};
    final dests = <Square>{};
    for (final m in _legalForSelected) {
      dests.add(m.to);
    }
    return dests;
  }

  /// Активная сторона — для подписи «чей ход».
  ActiveSide get activeSide {
    if (phase == GamePhase.over) return ActiveSide.nobody;
    if (mode == GameMode.ai) {
      return state.turn == humanColor ? ActiveSide.me : ActiveSide.computer;
    }
    if (mode == GameMode.network) {
      // В сети хост играет white, клиент black.
      final mine = isHost ? Side.white : Side.black;
      return state.turn == mine ? ActiveSide.me : ActiveSide.friend;
    }
    return ActiveSide.me; // вдвоём на одном устройстве — всегда человек
  }

  /// Чей сейчас ход.
  Side get currentTurn => state.turn;

  /// Можно ли принимать тапы. Грубо: партия идёт, не думает ИИ, и сейчас ход
  /// человека на этом устройстве.
  bool get canInteract {
    if (phase != GamePhase.playing) return false;
    if (busy) return false;
    if (mode == GameMode.ai && state.turn != humanColor) return false;
    if (mode == GameMode.network &&
        state.turn != (isHost ? Side.white : Side.black)) {
      return false;
    }
    return true;
  }

  bool get isOver => phase == GamePhase.over;
  bool get isDraw => phase == GamePhase.over && result == GameResult.draw;
  GameResult? result;

  Side? get winner {
    if (phase != GamePhase.over) return null;
    if (result == GameResult.white) return Side.white;
    if (result == GameResult.black) return Side.black;
    return null;
  }

  bool get canUndo {
    if (phase == GamePhase.over) return false;
    if (busy) return false;
    if (_history.isEmpty) return false;
    if (mode == GameMode.network) {
      // По сети отмена — только по согласию, пока ждём своего хода.
      return !_undoPending && canInteract;
    }
    if (mode == GameMode.ai) {
      // Отменяем свою пару «мой ход + ответ ИИ», когда снова наша очередь.
      return canInteract && _history.length >= 2;
    }
    return true;
  }

  /// Имя игрока для панели.
  String playerName(Side side) {
    if (mode == GameMode.local) {
      return side == Side.white ? 'Игрок 1 (белые)' : 'Игрок 2 (чёрные)';
    }
    if (mode == GameMode.ai) {
      return side == humanColor ? settings.nickname : 'Компьютер';
    }
    // Сеть: хост — white, клиент — black.
    final mine = isHost ? Side.white : Side.black;
    if (side == mine) return settings.nickname;
    return network?.peerName ?? 'Друг';
  }

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

  // ---- Старт партий --------------------------------------------------------

  void startLocal() {
    mode = GameMode.local;
    humanColor = Side.white;
    _reset();
  }

  void startAi(Difficulty level, Side human) {
    mode = GameMode.ai;
    difficulty = level;
    humanColor = human;
    _reset();
    // Кто ходит первым зависит от варианта: в классических — чёрные, в
    // остальных — белые. Если первый ход не наш — зовём ИИ.
    if (state.turn != humanColor) {
      _scheduleAiTurn();
    }
  }

  void startNetwork() {
    mode = GameMode.network;
    humanColor = isHost ? Side.white : Side.black;
    _reset();
  }

  void _reset() {
    state = GameState.initial(variant);
    _history.clear();
    _positionCounts.clear();
    _recordPosition(state);
    _selected = null;
    _legalForSelected = const [];
    _suggested = null;
    _hintText = null;
    status = null;
    busy = false;
    result = null;
    phase = GamePhase.playing;
    notifyListeners();
  }

  /// Перезапуск той же партии того же режима на свежей доске.
  void playAgain() {
    switch (mode) {
      case GameMode.local:
        startLocal();
      case GameMode.ai:
        startAi(difficulty, humanColor);
      case GameMode.network:
        // Сетевой рематч требует новой комнаты — просто возвращаем в лобби.
        phase = GamePhase.over;
        notifyListeners();
    }
  }

  // ---- Тапы ----------------------------------------------------------------

  /// Тап по клетке. Выбирает свою шашку или завершает ход на адресат.
  void tap(Square square) {
    if (!canInteract) return;
    _suggested = null;
    _hintText = null;
    final legal = rules.legalMoves(state);
    if (legal.isEmpty) return;

    if (_selected != null) {
      if (square == _selected) {
        _resetSelection();
        notifyListeners();
        return;
      }
      final matches =
          _legalForSelected.where((m) => m.to == square).toList();
      if (matches.isNotEmpty) {
        // Если подходят несколько (серия с возможной остановкой) — берём самое
        // длинное взятие: ребёнок обычно хочет побить больше.
        matches.sort((a, b) => b.captures.length.compareTo(a.captures.length));
        applyMove(matches.first);
        return;
      }
      // Перевыбор другой своей шашки.
      final piece = state.board.at(square);
      if (piece != null && piece.side == state.turn &&
          legal.any((m) => m.from == square)) {
        _select(square, legal);
        notifyListeners();
        return;
      }
      // Тап мимо адресатов — снимаем выбор.
      _resetSelection();
      notifyListeners();
      return;
    }

    final piece = state.board.at(square);
    if (piece == null || piece.side != state.turn) return;
    if (!legal.any((m) => m.from == square)) {
      // Шашкой нельзя ходить — например, обязано взятие другой шашкой.
      status = 'Этой шашкой нельзя ходить — нужно бить';
      notifyListeners();
      return;
    }
    _select(square, legal);
    notifyListeners();
  }

  void _select(Square square, List<Move> legal) {
    _selected = square;
    _legalForSelected =
        legal.where((m) => m.from == square).toList(growable: false);
    status = null;
  }

  void _resetSelection() {
    _selected = null;
    _legalForSelected = const [];
  }

  void clearSelection() {
    if (_selected != null) {
      _resetSelection();
      notifyListeners();
    }
  }

  // ---- Применение хода -----------------------------------------------------

  /// Применяет ход. Если [remote] — ход пришёл по сети и его не надо
  /// отправлять обратно.
  void applyMove(Move move, {bool remote = false}) {
    if (phase != GamePhase.playing) return;
    // Снимок на начало хода — для отмены. Оба устройства кладут по снимку на
    // каждый ход: своё — по тапу, чужое — по сети. Так история симметрична и
    // отмена работает одинаково с обеих сторон.
    _history.add(state);
    final wasCapture = move.isCapture;
    final wasKingBefore = state.board.at(move.from)?.king ?? false;
    state = rules.applyKnownLegal(state, move);
    final isKingNow = state.board.at(move.to)?.king ?? false;
    final promoted = !wasKingBefore && isKingNow;
    _recordPosition(state);
    _resetSelection();
    _suggested = null;
    _hintText = null;
    // Звуки: ход, взятие, превращение в дамку.
    if (wasCapture) {
      sounds.play(GameSound.capture);
    } else {
      sounds.play(GameSound.move);
    }
    if (promoted) sounds.play(GameSound.crown);

    // Отправляем ход другу по сети.
    if (mode == GameMode.network && !remote) {
      network!.service.send(NetworkMessage('move', moveToJson(move)));
    }

    // Проверка исхода.
    final winnerSide = rules.winner(state);
    if (winnerSide != null) {
      _onWin(winnerSide);
      return;
    }
    if (_isDraw) {
      _onDraw();
      return;
    }
    notifyListeners();

    // Дальше — либо ИИ, либо ждём друга.
    if (mode == GameMode.ai && state.turn != humanColor && !remote) {
      _scheduleAiTurn();
    }
  }

  void _recordPosition(GameState s) {
    final key = s.positionKey;
    _positionCounts[key] = (_positionCounts[key] ?? 0) + 1;
  }

  bool get _isDraw {
    // Три повтора позиции с правом хода — ничья.
    if ((_positionCounts[state.positionKey] ?? 0) >= drawRepetitions) {
      return true;
    }
    // Порог тихих полуходов зависит от того, остались ли на доске только
    // дамки: в дамочном окончании партия может тянуться долго.
    final onlyKings = state.board.pieces.values.every((p) => p.king);
    final threshold = onlyKings ? drawQuietPliesKings : drawQuietPlies;
    return state.quietPlies >= threshold;
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Предлагает хороший ход: выбирает шашку и подсвечивает адресат, не делая
  /// ход за ребёнка.
  void showHint() {
    if (!canInteract) return;
    final ai = CheckersAI();
    final move = ai.findBestMove(
      state,
      Difficulty.medium.depth,
      materialOnly: false,
    );
    if (move == null) {
      _hintText = 'Ходов нет';
      notifyListeners();
      return;
    }
    _suggested = move;
    _hintText = _describeHint(move);
    // Заодно подсветим шашку и адресат — как при обычном выборе.
    final legal = rules.legalMoves(state);
    _select(move.from, legal);
    notifyListeners();
  }

  String _describeHint(Move move) {
    final fromStr = 'с ${move.from}';
    final toStr = move.isCapture
        ? 'и побей на ${move.to}'
        : 'и пойди на ${move.to}';
    if (move.captures.length > 1) {
      return 'Возьми шашку $fromStr $toStr '
          'и побей ещё ${move.captures.length - 1}';
    }
    return 'Возьми шашку $fromStr $toStr';
  }

  // ---- Отмена --------------------------------------------------------------

  /// Отменить последний ход.
  ///
  /// Офлайн и в сети во время своего хода — отменяет последний ход. В сети
  /// между ходами — просит друга согласия отменить последний ход.
  void undo() {
    if (phase == GamePhase.over) return;
    if (mode == GameMode.network) {
      if (_undoPending || _history.isEmpty || !canInteract) return;
      _undoPending = true;
      network!.service.send(const NetworkMessage('undoRequest', {'ply': 1}));
      status = 'Ждём ответа друга на отмену хода…';
      notifyListeners();
      return;
    }
    if (mode == GameMode.ai) {
      if (!canInteract) return;
      if (_history.length < 2) return;
      // Откатываем свою пару «мой ход + ответ ИИ».
      _history.removeLast(); // ответ ИИ
      final prev = _history.removeLast(); // мой ход
      _restore(prev);
      return;
    }
    // Локально: откатываем один ход.
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _restore(prev);
  }

  void _restore(GameState prev) {
    state = prev;
    _positionCounts.clear();
    // Пересчитываем счётчик повторов по сохранившейся истории.
    _positionCounts[state.positionKey] = 1;
    for (final s in _history) {
      final k = s.positionKey;
      _positionCounts[k] = (_positionCounts[k] ?? 0) + 1;
    }
    _resetSelection();
    _suggested = null;
    _hintText = null;
    status = 'Ход отменён';
    notifyListeners();
  }

  /// Ответ на просьбу друга об отмене хода по сети.
  void respondUndo(bool accepted) {
    if (mode != GameMode.network) return;
    network!.service.send(
      NetworkMessage('undoResponse', {'accepted': accepted}),
    );
    if (accepted) {
      _doNetworkUndo();
    }
  }

  void _doNetworkUndo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _undoPending = false;
    _restore(prev);
  }

  // ---- Сдача ---------------------------------------------------------------

  void resign() {
    if (phase != GamePhase.playing) return;
    final winnerSide = state.turn.opponent;
    if (mode == GameMode.network) {
      network!.service.send(const NetworkMessage('resign'));
    }
    _onWin(winnerSide, byResign: true);
  }

  // ---- Победа / ничья ------------------------------------------------------

  void _onWin(Side winnerSide, {bool byResign = false}) {
    phase = GamePhase.over;
    result = winnerSide == Side.white ? GameResult.white : GameResult.black;
    final iWon = mode == GameMode.network
        ? winnerSide == (isHost ? Side.white : Side.black)
        : (mode == GameMode.ai ? winnerSide == humanColor : true);
    sounds.play(
      resultSoundName(draw: false, local: mode != GameMode.network, iWon: iWon),
    );
    settings.recordGame(won: iWon || mode == GameMode.local);
    status = byResign
        ? 'Соперник сдался'
        : 'Победили ${winnerSide.label.toLowerCase()}';
    notifyListeners();
  }

  void _onDraw() {
    phase = GamePhase.over;
    result = GameResult.draw;
    sounds.play(
      resultSoundName(draw: true, local: mode != GameMode.network, iWon: false),
    );
    settings.recordGame(won: false);
    status = 'Ничья — позиция повторяется';
    notifyListeners();
  }

  // ---- ИИ -------------------------------------------------------------------

  void _scheduleAiTurn() {
    busy = true;
    status = 'Ход компьютера…';
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
    final ai = CheckersAI();
    final move = ai.findBestMove(
      state,
      difficulty.depth,
      easyNoise: difficulty == Difficulty.easy,
      materialOnly: difficulty.materialOnly,
    );
    busy = false;
    if (move == null) {
      // Ходов нет — соперник (то есть мы) победил.
      final winnerSide = variant.reverseGoal ? state.turn : state.turn.opponent;
      _onWin(winnerSide);
      return;
    }
    applyMove(move);
  }

  // ---- Сеть -----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    switch (event.type) {
      case 'move':
        _receiveMove(event.data);
      case 'undoRequest':
        onUndoRequested?.call();
      case 'undoResponse':
        final accepted = event.data['accepted'] == true;
        _undoPending = false;
        if (accepted) {
          _doNetworkUndo();
        } else {
          status = 'Друг не разрешил отменить ход';
          notifyListeners();
        }
      case 'resign':
        // Друг сдался — победа наша.
        final mine = isHost ? Side.white : Side.black;
        _onWin(mine, byResign: true);
      case 'disconnected':
        status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        phase = GamePhase.over;
        notifyListeners();
      case 'desync':
        _desync('Партия рассинхронизировалась');
      case 'error':
        final msg = event.data['message'];
        status = msg is String ? msg : 'Связь потеряна';
        phase = GamePhase.over;
        notifyListeners();
    }
  }

  void _receiveMove(Map<String, Object?> data) {
    if (phase != GamePhase.playing) return;
    try {
      final move = parseMove(data);
      // Проверим, что ход действительно легален в текущей позиции. Иначе
      // устройство друга разошлось с нашим, и продолжать нельзя.
      if (!rules.legalMoves(state).contains(move)) {
        _desync('Ход друга не подходит к нашей позиции');
        return;
      }
      applyMove(move, remote: true);
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Ход не распознан' : e.message);
    }
  }

  void _desync(String reason) {
    status = reason;
    phase = GamePhase.over;
    notifyListeners();
    // Транспорт уже разорвёт связь; закрывать сервис здесь не нужно — лобби
    // владеет им и закроет при выходе.
  }

  @override
  void dispose() {
    _disposed = true;
    _networkSub?.cancel();
    super.dispose();
  }
}
