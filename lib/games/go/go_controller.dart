import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'engine/scoring.dart';
import 'network.dart';

/// Режим партии: против компьютера, вдвоём на одном устройстве или по сети.
enum GoGameMode { ai, local, network }

/// Фаза партии: «идёт» или «окончена». Отдельная фаза нужна, чтобы отличать
/// завершение по правилам от завершения по сдаче или обрыву связи.
enum GoGamePhase { playing, over }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно интерфейсу, чтобы показать правильную подсказку.
enum GoActiveSide { me, computer, friend, nobody }

/// Контроллер партии го. Содержит состояние, историю, звук и сеть; интерфейс
/// только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
class GoController extends ChangeNotifier {
  GoController({
    required this.settings,
    required this.sounds,
    required GameSetup setup,
    this.network,
  })  : setup = setup,
        rules = setup.mode == GoMode.capture
            ? CaptureGoRules(setup)
            : ClassicGoRules(setup),
        isHost = network?.isHost ?? false,
        state = GameState.initial(setup) {
    if (network != null) {
      mode = GoGameMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
  }

  final SettingsController settings;
  final GameSounds sounds;
  final GameSetup setup;
  final GoRules rules;
  final NetworkSession? network;
  final bool isHost;

  GoGameMode mode = GoGameMode.local;
  Difficulty difficulty = Difficulty.easy;

  /// Цвет человека на этом устройстве. В режиме ИИ — цвет ребёнка; в сети у
  /// хоста black (ходит первым), у клиента white; вдвоём на одном устройстве
  /// оба хода человеческие, тут хранится цвет, чья очередь (для подсветки).
  StoneColor humanColor = StoneColor.black;

  GameState state;

  GoGamePhase phase = GoGamePhase.playing;

  /// Снимки на начало каждого хода — для отмены (офлайн и по сети по согласию).
  final List<GameState> _history = [];

  late List<Point> _legalPlacements = rules.legalPlacements(state);

  /// Точка, подсвеченная кнопкой «Подсказка». null — подсказки нет.
  Point? suggestedMove;
  String? hintText;
  String? notice;

  /// Финальный счёт классической партии. Считается на этом устройстве после
  /// двух пасов; по сети хост рассылает его событием `event`, чтобы оба
  /// устройства показали одно и то же.
  ScoreSummary? finalScore;

  /// Победитель с учётом сдачи и обрыва связи. null, пока партия не закончена.
  StoneColor? _resignedWinner;

  String? fatalMessage;

  bool computerThinking = false;
  bool hintThinking = false;

  /// Ждём ответа друга на запрос отмены хода по сети.
  bool waitingForUndo = false;
  int? _incomingUndoPly;

  StreamSubscription<NetworkMessage>? _networkSub;
  Timer? _aiTimer;
  bool _disposed = false;
  int _generation = 0;

  /// ---- Публичные геттеры -------------------------------------------------

  /// Победитель по правилам или по сдаче.
  StoneColor? get winner =>
      _resignedWinner ?? (rules.isOver(state) ? rules.winner(state) : null);

  bool get isOver => phase == GoGamePhase.over;

  bool get isDraw => isOver && winner == null;

  /// Допустимые постановки камня для текущего игрока.
  List<Point> get legalPlacements => _legalPlacements;

  /// Группы под угрозой захвата (в атари) — для подсказки интерфейсу.
  Set<Point> get atariPoints {
    if (!hintsEnabled) return const {};
    final result = <Point>{};
    final seen = <Point>{};
    for (final p in GoRules.allPoints(state.board.size)) {
      if (seen.contains(p) || state.board.at(p) == null) continue;
      final g = GoRules.groupAt(state.board, p)!;
      seen.addAll(g.stones);
      if (g.inAtari) result.addAll(g.stones);
    }
    return result;
  }

  bool get hintsEnabled => settings.flag(goGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(goGameId, 'hintButton');

  /// Чей сейчас ход, по мнению интерфейса.
  StoneColor get currentTurn => state.turn;

  /// Чьего хода ждёт это устройство. В локальном режиме — любой человек.
  GoActiveSide get activeSide {
    if (phase == GoGamePhase.over) return GoActiveSide.nobody;
    if (mode == GoGameMode.ai) {
      return state.turn == humanColor
          ? GoActiveSide.me
          : GoActiveSide.computer;
    }
    if (mode == GoGameMode.network) {
      // В сети хост играет black, клиент white.
      final mine = isHost ? StoneColor.black : StoneColor.white;
      return state.turn == mine ? GoActiveSide.me : GoActiveSide.friend;
    }
    return GoActiveSide.me; // вдвоём на одном устройстве — всегда человек
  }

  /// Имя игрока для панели: локально — «Игрок 1»/«Игрок 2», против
  /// компьютера — ник + «Компьютер», по сети — ник + имя друга.
  String playerName(StoneColor side) {
    if (mode == GoGameMode.local) {
      return side == StoneColor.black
          ? 'Игрок 1 (чёрные)'
          : 'Игрок 2 (белые)';
    }
    if (mode == GoGameMode.ai) {
      return side == humanColor ? settings.nickname : 'Компьютер';
    }
    // Сеть: хост — black, клиент — white.
    final mine = isHost ? StoneColor.black : StoneColor.white;
    if (side == mine) return settings.nickname;
    return network?.peerName ?? 'Друг';
  }

  /// Можно ли тапать по доске прямо сейчас.
  bool get canInteract {
    if (phase != GoGamePhase.playing) return false;
    if (fatalMessage != null) return false;
    if (computerThinking || hintThinking) return false;
    if (waitingForUndo || _incomingUndoPly != null) return false;
    if (mode == GoGameMode.ai && state.turn != humanColor) return false;
    if (mode == GoGameMode.network &&
        state.turn != (isHost ? StoneColor.black : StoneColor.white)) {
      return false;
    }
    return true;
  }

  bool get canPass =>
      canInteract && !rules.isOver(state);

  bool get canUndo {
    if (phase == GoGamePhase.over) return false;
    if (fatalMessage != null) return false;
    if (waitingForUndo || _incomingUndoPly != null) return false;
    if (_history.isEmpty) return false;
    if (mode == GoGameMode.network) return false; // отмена по сети — отдельный
    if (mode == GoGameMode.ai) {
      // В режиме ИИ отменяем только свой ход, когда наша очередь.
      if (state.turn != humanColor) return false;
      return _history.length >= 2;
    }
    return true;
  }

  bool get canResign =>
      phase == GoGamePhase.playing &&
      fatalMessage == null &&
      mode != GoGameMode.local;

  String get turnLabel {
    switch (activeSide) {
      case GoActiveSide.me:
        return 'Твой ход';
      case GoActiveSide.computer:
        return 'Ход компьютера…';
      case GoActiveSide.friend:
        return 'Ходит друг…';
      case GoActiveSide.nobody:
        return phase == GoGamePhase.over ? 'Партия окончена' : '';
    }
  }

  /// ---- Старт партий ------------------------------------------------------

  void startLocal() {
    mode = GoGameMode.local;
    humanColor = StoneColor.black;
    state = GameState.initial(setup);
    phase = GoGamePhase.playing;
    _history.clear();
    _resignedWinner = null;
    finalScore = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    fatalMessage = null;
    _refreshLegal();
    notifyListeners();
  }

  void startAi(Difficulty level, StoneColor human) {
    mode = GoGameMode.ai;
    difficulty = level;
    humanColor = human;
    state = GameState.initial(setup);
    phase = GoGamePhase.playing;
    _history.clear();
    _resignedWinner = null;
    finalScore = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    fatalMessage = null;
    _refreshLegal();
    notifyListeners();
    // Чёрные ходят первыми. Если компьютер — чёрные, он ходит сам.
    if (state.turn != humanColor) {
      _scheduleAiTurn();
    }
  }

  void startNetwork() {
    mode = GoGameMode.network;
    humanColor = isHost ? StoneColor.black : StoneColor.white;
    state = GameState.initial(setup);
    phase = GoGamePhase.playing;
    _history.clear();
    _resignedWinner = null;
    finalScore = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    fatalMessage = null;
    _refreshLegal();
    notifyListeners();
  }

  void _refreshLegal() {
    _legalPlacements = rules.legalPlacements(state);
  }

  /// ---- Действия игрока ---------------------------------------------------

  /// Тап по пересечению. Если ход допустим — ставит камень.
  void tap(Point point) {
    if (!canInteract) return;
    if (state.board.occupied(point)) {
      notice = 'Здесь уже стоит камень.';
      notifyListeners();
      return;
    }
    if (point == state.koPoint) {
      notice = hintsEnabled
          ? 'Это правило ко: нельзя сразу повторять позицию. Походи в другое место.'
          : 'Так ходить нельзя.';
      notifyListeners();
      return;
    }
    if (!_legalPlacements.contains(point)) {
      notice = hintsEnabled
          ? 'Этот ход запретен: камень останется без дыханий (самоубийство).'
          : 'Так ходить нельзя.';
      notifyListeners();
      return;
    }
    notice = null;
    suggestedMove = null;
    hintText = null;
    applyMove(GoMove.place(point, color: state.turn), remote: false);
  }

  /// Пас.
  void pass() {
    if (!canPass) return;
    notice = null;
    suggestedMove = null;
    hintText = null;
    applyMove(GoMove.pass(color: state.turn), remote: false);
  }

  /// Применяет ход (свой или пришедший по сети) и обновляет состояние.
  void applyMove(GoMove move, {required bool remote}) {
    if (_disposed || phase != GoGamePhase.playing || fatalMessage != null) {
      return;
    }
    if (rules.isOver(state)) return;

    final before = state;
    _history.add(before);
    state = rules.applyKnownLegal(before, move);
    _refreshLegal();
    suggestedMove = null;
    hintText = null;
    final captured = state.lastCaptured;
    // Звуки: постановка — move, захват — capture, пас — move (отдельного
    // звука для паса в каркасе нет).
    if (move.isPass) {
      sounds.play(GameSound.move);
    } else if (captured.isNotEmpty) {
      sounds.play(GameSound.move);
      sounds.play(GameSound.capture);
    } else {
      sounds.play(GameSound.move);
    }
    // Позитивное сообщение при захвате. Хвалим человека: в режиме ИИ — только
    // его захваты, вдвоём на одном устройстве — любой захват, по сети хвалить
    // не нужно (счёт виден на панели).
    final isHuman = mode == GoGameMode.local || before.turn == humanColor;
    if (captured.isNotEmpty &&
        mode != GoGameMode.network &&
        isHuman) {
      notice = _praiseForCapture(captured.length);
    }
    notifyListeners();

    // Отправляем ход по сети.
    if (!remote && mode == GoGameMode.network) {
      _sendMove(before, move);
    }

    // В классике после двух пасов хост считает очки и рассылает их событием.
    if (rules.isOver(state) &&
        setup.mode == GoMode.classic &&
        mode == GoGameMode.network &&
        isHost) {
      final s = rules.score(state);
      if (s != null) {
        try {
          network!.service.send(NetworkMessage('event', {
            'kind': 'score',
            'blackTerritory': s.blackTerritory,
            'whiteTerritory': s.whiteTerritory,
            'blackCaptured': s.blackCaptured,
            'whiteCaptured': s.whiteCaptured,
            'komi': s.komi,
            'deadBlack': s.deadBlack,
            'deadWhite': s.deadWhite,
          }));
        } catch (_) {
          // Связь могла пропасть — фатальное сообщение поставит обработчик
          // события `disconnected`.
        }
      }
    }

    if (rules.isOver(state)) {
      _onWin();
      return;
    }
    // Если сейчас ход компьютера — планируем ИИ.
    if (mode == GoGameMode.ai && state.turn != humanColor) {
      _scheduleAiTurn();
    }
  }

  /// Кнопка «Подсказать ход». Запускает ИИ и подсвечивает лучший ход.
  Future<void> showHint() async {
    if (!hintsEnabled || !canInteract || hintThinking) return;
    final snapshot = state;
    final generation = _generation;
    hintThinking = true;
    notice = null;
    notifyListeners();
    try {
      // ИИ для подсказки работает на уровне «средний», чтобы не зависать на
      // MCTS; для hard это всё равно быстрее, чем ход компьютера.
      final level = difficulty == Difficulty.hard
          ? Difficulty.medium
          : difficulty;
      final point = await _runAiSearch(snapshot, level,
          const Duration(milliseconds: 400));
      if (!_disposed &&
          point != null &&
          generation == _generation &&
          snapshot.fingerprint == state.fingerprint &&
          hintsEnabled) {
        suggestedMove = point;
        hintText = _describeHint(point);
      } else if (!_disposed && point == null) {
        notice = 'Подсказка: можно пасовать — хороших ходов не нашлось.';
      }
    } finally {
      if (!_disposed) {
        hintThinking = false;
        notifyListeners();
      }
    }
  }

  String _describeHint(Point point) {
    final buf = StringBuffer('Подсказка: походи в подсвеченную точку');
    final placement = GoRules.place(state.board, point, state.turn);
    if (placement.captured.isNotEmpty) {
      buf.write(
          ', этим ходом ты снимешь ${_countOf(placement.captured.length)} соперника');
    } else {
      buf.write(' — тут камню будет просторно');
    }
    final atari = atariPoints;
    if (atari.isNotEmpty) {
      buf.write('. У тебя на доске есть группа без одного дыхания — спаси её');
    }
    return '${buf.toString()}.';
  }

  static String _countOf(int n) => switch (n) {
        1 => '1 камень',
        2 => '2 камня',
        3 => '3 камня',
        _ => '$n камней',
      };

  /// Отменить последний ход. В режиме ИИ отменяет сразу два (свой и ИИ),
  /// чтобы вернуться к своей очереди.
  void undo() {
    if (!canUndo) return;
    var count = 1;
    if (mode == GoGameMode.ai) {
      // В режиме ИИ отменяем два хода: свой и компьютер.
      count = 2;
    }
    _restore(count);
  }

  void _restore(int count) {
    _generation++;
    computerThinking = false;
    hintThinking = false;
    suggestedMove = null;
    hintText = null;
    notice = null;
    _resignedWinner = null;
    finalScore = null;
    for (var i = 0; i < count; i++) {
      if (_history.isEmpty) break;
      state = _history.removeLast();
    }
    phase = GoGamePhase.playing;
    _refreshLegal();
    notifyListeners();
  }

  /// Сдаться. Победа достаётся сопернику.
  void resign() {
    if (!canResign) return;
    final winnerColor = _mySide().opponent;
    if (mode == GoGameMode.network) {
      try {
        network!.service.send(const NetworkMessage('resign'));
      } catch (_) {
        // Связь пропадёт — фатальное сообщение поставит `disconnected`.
      }
    }
    _resignedWinner = winnerColor;
    _onWin();
  }

  /// Начать ту же партию заново. Используется кнопкой «Играть снова».
  void playAgain() {
    _generation++;
    _aiTimer?.cancel();
    state = GameState.initial(setup);
    phase = GoGamePhase.playing;
    _history.clear();
    _resignedWinner = null;
    finalScore = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    fatalMessage = null;
    computerThinking = false;
    hintThinking = false;
    waitingForUndo = false;
    _incomingUndoPly = null;
    _refreshLegal();
    notifyListeners();
    if (mode == GoGameMode.ai && state.turn != humanColor) {
      _scheduleAiTurn();
    }
  }

  /// Очистить уведомление (вызов из интерфейса).
  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  /// Очистить подсказку (вызов из интерфейса).
  void clearHint() {
    if (suggestedMove == null && hintText == null) return;
    suggestedMove = null;
    hintText = null;
    notifyListeners();
  }

  /// ---- Внутренние: победа ------------------------------------------------

  void _onWin() {
    phase = GoGamePhase.over;
    final w = winner;
    // Записываем счёт, кроме сетевой партии: там каждый сам считает свою
    // статистику, чтобы двойной учёт не получился.
    if (mode != GoGameMode.network && w != null) {
      final won = mode == GoGameMode.local || w == humanColor;
      settings.recordGame(won: won);
      sounds.play(won ? GameSound.win : GameSound.lose);
    } else if (mode == GoGameMode.network) {
      // В сети хост и клиент сами разбираются, кто победил.
      final mine = isHost ? StoneColor.black : StoneColor.white;
      final iWon = w == mine;
      sounds.play(iWon ? GameSound.win : GameSound.lose);
    } else {
      // Ничья в классике.
      sounds.play(GameSound.draw);
    }
    // Снимем финальный счёт классики локально, если ещё не посчитан.
    if (setup.mode == GoMode.classic && finalScore == null && rules.isOver(state)) {
      finalScore = rules.score(state);
    }
    notifyListeners();
  }

  String _praiseForCapture(int n) => switch (n) {
        1 => 'Отличный захват! Снят 1 камень.',
        2 => 'Великолепно! Снято 2 камня.',
        _ => 'Невероятно! Снято $n камней.',
      };

  StoneColor _mySide() {
    if (mode == GoGameMode.ai) return humanColor;
    if (mode == GoGameMode.network) {
      return isHost ? StoneColor.black : StoneColor.white;
    }
    return state.turn; // local: оба хода человека
  }

  /// ---- ИИ ----------------------------------------------------------------

  void _scheduleAiTurn() {
    if (_disposed || phase != GoGamePhase.playing) return;
    computerThinking = true;
    notifyListeners();
    // Небольшая задержка, чтобы UI успел показать «Ход компьютера…».
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 350), _runAiTurn);
  }

  Future<void> _runAiTurn() async {
    if (_disposed ||
        phase != GoGamePhase.playing ||
        state.turn == humanColor) {
      computerThinking = false;
      notifyListeners();
      return;
    }
    final generation = _generation;
    final snapshot = state;
    try {
      final timeLimit = difficulty == Difficulty.hard
          ? const Duration(seconds: 1, milliseconds: 200)
          : Duration.zero;
      final point = await _runAiSearch(snapshot, difficulty, timeLimit);
      if (_disposed ||
          generation != _generation ||
          snapshot.fingerprint != state.fingerprint) {
        return;
      }
      if (point == null) {
        // ИИ пасует, если нет осмысленного хода.
        applyMove(GoMove.pass(color: snapshot.turn), remote: false);
      } else {
        applyMove(GoMove.place(point, color: snapshot.turn), remote: false);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        computerThinking = false;
        fatalMessage = 'Не получилось сделать ход. Попробуй новую партию.';
        notifyListeners();
      }
    }
  }

  /// Поиск хода ИИ. Запускается в изоляте через `compute`, чтобы MCTS не
  /// морозил интерфейс на сложном уровне. На лёгком и среднем уровне ИИ
  /// быстрый, изолят не нужен.
  Future<Point?> _runAiSearch(
    GameState snapshot,
    Difficulty level,
    Duration timeLimit,
  ) async {
    if (level == Difficulty.hard) {
      return compute(
        _searchMoveIsolate,
        _SearchRequest(snapshot, level, timeLimit),
      );
    }
    return _searchMoveIsolate(
      _SearchRequest(snapshot, level, timeLimit),
    );
  }

  /// ---- Сеть --------------------------------------------------------------

  void _sendMove(GameState before, GoMove move) {
    try {
      network!.service.send(
        NetworkMessage('move', {
          'ply': before.ply,
          'before': before.fingerprint,
          'color': before.turn.name,
          'pass': move.isPass,
          if (!move.isPass) 'point': move.point!.toJson(),
        }),
      );
    } catch (_) {
      fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
      notifyListeners();
    }
  }

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed || fatalMessage != null) return;
    switch (event.type) {
      case 'move':
        _receiveMove(event.data);
        break;
      case 'undoRequest':
        _receiveUndoRequest(event.data);
        break;
      case 'undoResponse':
        _receiveUndoResponse(event.data);
        break;
      case 'resign':
        _resignedWinner = _mySide();
        _onWin();
        break;
      case 'event':
        _receiveEvent(event.data);
        break;
      case 'desync':
        fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
        phase = GoGamePhase.over;
        notifyListeners();
        break;
      case 'disconnected':
        if (!isOver) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
          phase = GoGamePhase.over;
          notifyListeners();
        }
        break;
      case 'error':
        final msg = event.data['message'];
        fatalMessage = msg is String ? msg : 'Связь потеряна';
        phase = GoGamePhase.over;
        notifyListeners();
        break;
    }
  }

  void _receiveMove(Map<String, Object?> data) {
    try {
      // Проверяем, что позиция совпадает. Цвет хода — это цвет того, кто
      // ходил; на принимающей стороне state.turn ещё указывает на того же
      // игрока (ход применяется после проверки).
      if (data['ply'] != state.ply ||
          data['before'] != state.fingerprint ||
          data['color'] != state.turn.name) {
        throw const FormatException('Разные позиции');
      }
      final move = parseMove(data);
      if (move.color != state.turn) {
        throw const FormatException('Чужой цвет');
      }
      // Полная проверка по правилам.
      if (!rules.isValidMove(state, move)) {
        throw const FormatException('Недопустимый ход');
      }
      waitingForUndo = false;
      applyMove(move, remote: true);
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Партия рассинхронизировалась' : e.message);
    }
  }

  void _receiveUndoRequest(Map<String, Object?> data) {
    final ply = data['ply'];
    final before = data['before'];
    final valid = ply is int &&
        ply == state.ply &&
        before is String &&
        before == state.fingerprint &&
        _history.isNotEmpty &&
        _incomingUndoPly == null;
    if (valid) {
      _incomingUndoPly = ply;
      notifyListeners();
    } else {
      try {
        network!.service.send(NetworkMessage('undoResponse', {
          'ply': ply,
          'accepted': false,
        }));
      } catch (_) {}
    }
  }

  void respondToUndo(bool accepted) {
    final ply = _incomingUndoPly;
    if (ply == null) return;
    _incomingUndoPly = null;
    try {
      network!.service.send(NetworkMessage('undoResponse', {
        'ply': ply,
        'accepted': accepted,
      }));
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      notifyListeners();
      return;
    }
    if (accepted && state.ply == ply && _history.isNotEmpty) {
      _restore(1);
    } else {
      notifyListeners();
    }
  }

  void _receiveUndoResponse(Map<String, Object?> data) {
    if (!waitingForUndo) return;
    final ply = data['ply'];
    final accepted = data['accepted'];
    if (ply is! int ||
        ply != state.ply ||
        accepted is! bool) {
      return;
    }
    waitingForUndo = false;
    if (accepted && _history.isNotEmpty) {
      _restore(1);
    } else {
      notice = 'Друг решил продолжить без отмены хода.';
      notifyListeners();
    }
  }

  void _receiveEvent(Map<String, Object?> data) {
    final kind = data['kind'];
    if (kind == 'score') {
      final s = data;
      finalScore = ScoreSummary(
        blackTerritory: s['blackTerritory'] as int? ?? 0,
        whiteTerritory: s['whiteTerritory'] as int? ?? 0,
        blackCaptured: s['blackCaptured'] as int? ?? 0,
        whiteCaptured: s['whiteCaptured'] as int? ?? 0,
        komi: (s['komi'] as num?)?.toDouble() ?? 0,
        deadBlack: s['deadBlack'] as int? ?? 0,
        deadWhite: s['deadWhite'] as int? ?? 0,
      );
      notifyListeners();
    }
  }

  /// Запрос отмены хода по сети. Локально меняем состояние и ждём ответа.
  void requestNetworkUndo() {
    if (mode != GoGameMode.network ||
        waitingForUndo ||
        _incomingUndoPly != null ||
        _history.isEmpty) {
      return;
    }
    try {
      network!.service.send(NetworkMessage('undoRequest', {
        'ply': state.ply,
        'before': state.fingerprint,
      }));
      waitingForUndo = true;
      notifyListeners();
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      notifyListeners();
    }
  }

  void _desync(String reason) {
    try {
      network!.service.send(const NetworkMessage('desync'));
    } catch (_) {}
    fatalMessage = reason;
    phase = GoGamePhase.over;
    _generation++;
    notifyListeners();
  }

  int? get incomingUndoPly => _incomingUndoPly;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _aiTimer?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}

/// Запрос для поиска хода ИИ в отдельном изоляте.
class _SearchRequest {
  const _SearchRequest(this.state, this.difficulty, this.timeLimit);
  final GameState state;
  final Difficulty difficulty;
  final Duration timeLimit;
}

/// Топ-level функция для `compute`. Создаёт правила по режиму партии и зовёт
/// ИИ.
Point? _searchMoveIsolate(_SearchRequest req) {
  final rules = req.state.setup.mode == GoMode.capture
      ? CaptureGoRules(req.state.setup)
      : ClassicGoRules(req.state.setup);
  return GoAI().findBestMove(
    req.state,
    rules,
    req.difficulty,
    timeLimit: req.timeLimit,
  );
}
