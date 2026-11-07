import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/network_game_service.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режим партии.
enum RendzuMode { local, ai, network }

/// Кого сейчас ждём на ход. Нужно для подписи «чей ход».
enum RendzuActiveSide { me, computer, friend, nobody }

/// Контроллер партии рэндзю. Содержит состояние, историю, звук и сеть;
/// интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
class RendzuController extends ChangeNotifier {
  RendzuController({
    required this.settings,
    required this.sounds,
    required this.ruleset,
    required this.boardSize,
    this.network,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = RendzuMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    _resetBoard();
  }

  final SettingsController settings;
  final GameSounds sounds;
  final Ruleset ruleset;
  final BoardSize boardSize;
  final NetworkSession? network;
  late final bool isHost;

  /// Правила как объект — вычисляются один раз из [ruleset].
  late final GameRules rules = rulesFor(ruleset);

  RendzuMode mode = RendzuMode.local;
  Difficulty difficulty = Difficulty.medium;

  /// Цвет человека на этом устройстве. В режиме ИИ — цвет ребёнка; в сети у
  /// хоста black, у клиента white; вдвоём на одном устройстве оба «человеческие»,
  /// тут хранится цвет, чья очередь (для подсветки активного игрока).
  StoneColor playerSide = StoneColor.black;

  late Board _board;
  StoneColor _currentColor = StoneColor.black;
  final List<Move> _history = [];
  WinResult? _winner;
  bool _isDraw = false;
  List<Point> _winningLine = const [];
  Point? _lastMove;
  String? _warning;
  Point? _hintPoint;
  Set<Point> _forbiddenHints = {};
  List<List<Point>> _patternThrees = [];
  List<List<Point>> _patternFours = [];
  bool _busy = false;
  String? _status;
  bool _disposed = false;
  Timer? _aiTimer;
  StreamSubscription<NetworkMessage>? _networkSub;

  // ---- Доступ к состоянию ---------------------------------------------------

  Board get board => _board;
  StoneColor get currentColor => _currentColor;
  WinResult? get winner => _winner;
  StoneColor? get winnerColor => _winner?.winner;
  bool get isOver => _winner != null || _isDraw;
  bool get isDraw => _isDraw;
  List<Point> get winningLine => _winningLine;
  Point? get lastMove => _lastMove;
  String? get warning => _warning;
  Point? get hintPoint => _hintPoint;
  Set<Point> get forbiddenHints => _forbiddenHints;
  List<List<Point>> get patternThrees => _patternThrees;
  List<List<Point>> get patternFours => _patternFours;
  bool get busy => _busy;
  String? get status => _status;
  int get moveNumber => _history.length;

  /// Признак: подсказки включены в настройках.
  bool get hintsEnabled => settings.flag(rendzuGameId, 'hints');

  /// Признак: подсветка паттернов включена в настройках.
  bool get patternHighlightEnabled =>
      settings.flag(rendzuGameId, 'patternHighlight');

  /// Активная сторона — для подписи «чей ход».
  RendzuActiveSide get activeSide {
    if (isOver) return RendzuActiveSide.nobody;
    if (mode == RendzuMode.ai) {
      return _currentColor == playerSide
          ? RendzuActiveSide.me
          : RendzuActiveSide.computer;
    }
    if (mode == RendzuMode.network) {
      final mine = isHost ? StoneColor.black : StoneColor.white;
      return _currentColor == mine
          ? RendzuActiveSide.me
          : RendzuActiveSide.friend;
    }
    return RendzuActiveSide.me; // вдвоём на одном устройстве — всегда человек
  }

  /// Имя игрока цвета [side] для панели.
  String playerName(StoneColor side) {
    if (mode == RendzuMode.local) {
      return side == StoneColor.black ? 'Игрок 1' : 'Игрок 2';
    }
    if (mode == RendzuMode.ai) {
      return side == playerSide ? settings.nickname : 'Компьютер';
    }
    // Сеть: хост — black, клиент — white.
    final mine = isHost ? StoneColor.black : StoneColor.white;
    if (side == mine) return settings.nickname;
    return network?.peerName ?? 'Друг';
  }

  /// Подпись «чей ход» в строку состояния.
  String get turnLabel {
    switch (activeSide) {
      case RendzuActiveSide.me:
        return 'Твой ход';
      case RendzuActiveSide.computer:
        return 'Ход компьютера…';
      case RendzuActiveSide.friend:
        return 'Ходит друг…';
      case RendzuActiveSide.nobody:
        return isOver ? 'Партия окончена' : '';
    }
  }

  /// Можно ли тапать по доске прямо сейчас.
  bool get canInteract {
    if (isOver) return false;
    if (mode == RendzuMode.ai) return _currentColor == playerSide && !_busy;
    if (mode == RendzuMode.network) {
      // Связь потеряна — ходить нельзя.
      if (network?.service.status != NetworkStatus.connected) return false;
      final mine = isHost ? StoneColor.black : StoneColor.white;
      return _currentColor == mine;
    }
    return true; // local
  }

  /// Можно ли отменить ход. После победы в офлайн-режиме отмену разрешаем —
  /// так кнопка «Отменить ход» в диалоге результата действительно отматывает
  /// победный ход и даёт ребёнку доиграть.
  bool get canUndo {
    if (_history.isEmpty) return false;
    if (mode == RendzuMode.network) return false; // по сети отмены нет
    if (mode == RendzuMode.ai) {
      // В режиме ИИ отменяем пару «свой + компьютер», когда наша очередь.
      // После победы — тоже можно, чтобы откатить последний ход.
      if (!isOver && !_isMyTurn) return false;
      return _history.length >= 2;
    }
    return true; // local
  }

  bool get _isMyTurn {
    if (mode == RendzuMode.ai) return _currentColor == playerSide;
    if (mode == RendzuMode.network) {
      final mine = isHost ? StoneColor.black : StoneColor.white;
      return _currentColor == mine;
    }
    return true; // local
  }

  /// Легальные точки хода для текущего игрока: все пустые, кроме запрещённых
  /// (для чёрных в рэндзю). Нужно для подсветки курсора и подсказок.
  Set<Point> get legalPoints {
    if (isOver || !canInteract) return const {};
    final empty = <Point>{};
    for (var y = 0; y < _board.size; y++) {
      for (var x = 0; x < _board.size; x++) {
        final p = Point(x, y);
        if (_board.at(p) == null) empty.add(p);
      }
    }
    if (ruleset == Ruleset.renju && _currentColor == StoneColor.black) {
      return empty.difference(_forbiddenHints);
    }
    return empty;
  }

  // ---- Старт партий --------------------------------------------------------

  void _resetBoard() {
    _board = Board(boardSize.dimension);
    _currentColor = StoneColor.black; // чёрные ходят первыми
    _history.clear();
    _winner = null;
    _isDraw = false;
    _winningLine = const [];
    _lastMove = null;
    _warning = null;
    _hintPoint = null;
    _forbiddenHints = {};
    _patternThrees = [];
    _patternFours = [];
    _busy = false;
    _status = null;
    _recomputeHints();
  }

  /// Старт против компьютера.
  void startAi(Difficulty level, StoneColor human) {
    mode = RendzuMode.ai;
    difficulty = level;
    playerSide = human;
    _resetBoard();
    notifyListeners();
    // Чёрные ходят первыми. Если компьютер — чёрные, он ходит сам.
    if (_currentColor != playerSide) {
      _scheduleAiTurn();
    }
  }

  /// Старт вдвоём на одном устройстве.
  void startLocal() {
    mode = RendzuMode.local;
    playerSide = StoneColor.black;
    _resetBoard();
    notifyListeners();
  }

  /// Старт по сети. Хост — чёрные и ходит первым.
  void startNetwork() {
    mode = RendzuMode.network;
    playerSide = isHost ? StoneColor.black : StoneColor.white;
    _resetBoard();
    notifyListeners();
  }

  /// Перезапуск той же партии. Используется кнопкой «Играть снова» офлайн.
  void playAgain() {
    _aiTimer?.cancel();
    _resetBoard();
    notifyListeners();
    if (mode == RendzuMode.ai && _currentColor != playerSide) {
      _scheduleAiTurn();
    }
  }

  // ---- Главный вход: тап по доске ------------------------------------------

  /// Тап по точке [p]. Применяет ход, если сейчас наша очередь и ход не
  /// запрещён. Запрещённый ход НЕ применяется: в [_warning] кладётся детское
  /// пояснение, и партия ждёт другого хода.
  void tap(Point p) {
    if (isOver || !canInteract) return;
    if (!p.inBounds(_board.size)) return;
    if (_board.at(p) != null) return;
    _applyMove(p, remote: false);
  }

  /// Применяет ход в точку [p] от текущего игрока. При `remote: true` ход
  /// пришёл по сети — его не отправляем обратно. Проверяет запрещённый ход
  /// (рэндзю, чёрные): запрещённый локальный ход отклоняется с пояснением,
  /// запрещённый сетевой — рассинхронизация (такого быть не должно, потому что
  /// хост играет чёрными, а белых запретов нет).
  void _applyMove(Point p, {required bool remote}) {
    final color = _currentColor;

    // Проверка запрещённого хода (только рэндзю, только чёрные).
    final forbidden = rules.forbiddenIfPlaced(_board, p, color);
    if (forbidden != null) {
      if (remote) {
        // Этого не должно случаться: белых запретов нет, а чёрные ходы
        // отправляет только хост, и он их проверяет локально. На всякий случай
        // считаем партию рассинхронизированной.
        _desync('Соперник сделал запрещённый ход');
        return;
      }
      _warning = forbidden.kidExplanation;
      _hintPoint = null;
      notifyListeners();
      return;
    }

    _warning = null;
    _hintPoint = null;
    _board.place(p, color);
    final move = Move(point: p, color: color, number: _history.length + 1);
    _history.add(move);
    _lastMove = p;
    sounds.play(GameSound.move);

    // Проверка победы.
    final win = rules.checkWin(_board, p);
    if (win != null) {
      _winner = win;
      _winningLine = win.line.stones;
      _patternThrees = [];
      _patternFours = [];
      _forbiddenHints = {};
      _onWin();
      notifyListeners();
      if (!remote && mode == RendzuMode.network) {
        _send(NetworkMessage('move', moveToJson(p, color)));
      }
      return;
    }

    // Ничья — доска заполнена.
    if (rules.isDraw(_board)) {
      _isDraw = true;
      _patternThrees = [];
      _patternFours = [];
      _forbiddenHints = {};
      _onDraw();
      notifyListeners();
      if (!remote && mode == RendzuMode.network) {
        _send(NetworkMessage('move', moveToJson(p, color)));
      }
      return;
    }

    // Ход переходит сопернику.
    _currentColor = color.opponent;
    _recomputeHints();

    if (!remote && mode == RendzuMode.network) {
      _send(NetworkMessage('move', moveToJson(p, color)));
    }

    notifyListeners();

    // В режиме ИИ, если теперь очередь компьютера, ходит он.
    if (mode == RendzuMode.ai && _currentColor != playerSide && !isOver) {
      _scheduleAiTurn();
    }
  }

  /// Пересчитывает подсказки запрещённых ходов и подсветку паттернов для
  /// текущего игрока. Дорогую проверку запрещённых делаем только для чёрных в
  /// рэндзю; паттерны считаем для текущего цвета, если включена подсветка.
  void _recomputeHints() {
    if (isOver) {
      _forbiddenHints = {};
      _patternThrees = [];
      _patternFours = [];
      return;
    }
    if (ruleset == Ruleset.renju && _currentColor == StoneColor.black) {
      _forbiddenHints = RenjuForbiddenChecker.forbiddenMoves(_board);
    } else {
      _forbiddenHints = {};
    }
    if (patternHighlightEnabled) {
      _patternThrees = _findPatterns(
        _currentColor,
        PatternDetector.openThreePatternsThrough,
        minCount: 3,
      );
      _patternFours = _findPatterns(
        _currentColor,
        PatternDetector.fourPatternsThrough,
        minCount: 4,
      );
    } else {
      _patternThrees = [];
      _patternFours = [];
    }
  }

  /// Сканирует доску и собирает уникальные подсвечиваемые паттерны цвета
  /// [color]. Использует [detector] для каждого занятого камня, дедуплицирует
  /// по ключу позиций. Так тройка `XXX__` посчитается один раз, а не три.
  List<List<Point>> _findPatterns(
    StoneColor color,
    List<List<Point>> Function(Board, Point) detector, {
    required int minCount,
  }) {
    final seen = <String>{};
    final out = <List<Point>>[];
    for (final stone in _board.occupiedPoints()) {
      if (_board.at(stone) != color) continue;
      final patterns = detector(_board, stone);
      for (final ptn in patterns) {
        if (ptn.length < minCount) continue;
        final key = ptn.map((q) => '${q.x},${q.y}').join('|');
        if (seen.add(key)) out.add(ptn);
      }
    }
    return out;
  }

  // ---- Подсказка ------------------------------------------------------------

  /// Показать хороший ход: выбирает точку через ИИ (средний уровень) и кладёт
  /// её в [_hintPoint]. Сам ход не делает — ребёнок сам ставит камень.
  void showHint() {
    if (isOver || !canInteract) return;
    final move = RenjuAI.findBestMove(
      _board,
      _currentColor,
      Difficulty.medium,
      ruleset: ruleset,
    );
    if (move == null) {
      _status = 'Ходов нет';
      notifyListeners();
      return;
    }
    _hintPoint = move;
    _status = 'Попробуй сюда';
    notifyListeners();
  }

  /// Сбрасывает одноразовое предупреждение (после показа снэкбара).
  void clearWarning() {
    if (_warning != null) {
      _warning = null;
      notifyListeners();
    }
  }

  /// Сбрасывает одноразовый статус.
  void clearStatus() {
    if (_status != null) {
      _status = null;
      notifyListeners();
    }
  }

  // ---- Отмена хода ---------------------------------------------------------

  /// Отменяет последний ход (или пару «свой + компьютер» в режиме ИИ).
  void undo() {
    if (!canUndo) return;
    if (mode == RendzuMode.ai) {
      // Откатываем пару: последний ход компьютера и свой последний ход.
      _popMove();
      if (_history.isNotEmpty && _currentColor != playerSide) {
        // после одного pop мог оказаться ход компьютера — откатим и его
        _popMove();
      }
    } else {
      _popMove();
    }
    _warning = null;
    _hintPoint = null;
    _status = 'Ход отменён';
    _recomputeHints();
    notifyListeners();
  }

  void _popMove() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    _board.remove(last.point);
    _currentColor = last.color;
    _lastMove = _history.isEmpty ? null : _history.last.point;
    _winner = null;
    _isDraw = false;
    _winningLine = const [];
  }

  // ---- Сдача ---------------------------------------------------------------

  /// Сдаться: победа достаётся сопернику.
  void resign() {
    if (isOver) return;
    final winnerColor = _currentColor.opponent;
    _winner = WinResult(
      winner: winnerColor,
      line: const WinLine([], StoneColor.black),
    );
    _isDraw = false;
    if (mode == RendzuMode.network) {
      _send(const NetworkMessage('resign'));
    }
    _onWin();
    notifyListeners();
  }

  // ---- Победа / ничья ------------------------------------------------------

  void _onWin() {
    final iWon = mode == RendzuMode.network
        ? winnerColor == (isHost ? StoneColor.black : StoneColor.white)
        : (mode == RendzuMode.ai
            ? winnerColor == playerSide
            : true);
    sounds.play(
      resultSoundName(draw: false, local: mode != RendzuMode.network, iWon: iWon),
    );
    settings.recordGame(won: iWon || mode == RendzuMode.local);
  }

  void _onDraw() {
    sounds.play(
      resultSoundName(draw: true, local: mode != RendzuMode.network, iWon: false),
    );
    settings.recordGame(won: false);
  }

  // ---- ИИ -------------------------------------------------------------------

  void _scheduleAiTurn() {
    _busy = true;
    notifyListeners();
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 400), _runAiTurn);
  }

  void _runAiTurn() {
    if (_disposed || isOver) return;
    if (mode != RendzuMode.ai) return;
    if (_currentColor == playerSide) {
      _busy = false;
      notifyListeners();
      return;
    }
    final move = RenjuAI.findBestMove(
      _board,
      _currentColor,
      difficulty,
      ruleset: ruleset,
      random: _rng,
    );
    _busy = false;
    if (move == null) {
      // Нет легальных ходов — это редчайший случай в рэндзю, когда все ходы
      // чёрных запрещены. Если доска заполнена — ничья; иначе ИИ проигрывает
      // по отсутствию ходов (победа достаётся человеку).
      if (rules.isDraw(_board)) {
        _isDraw = true;
        _onDraw();
      } else {
        _winner = WinResult(
          winner: playerSide,
          line: const WinLine([], StoneColor.black),
        );
        _onWin();
      }
      notifyListeners();
      return;
    }
    _applyMove(move, remote: false);
  }

  final Random _rng = Random();

  // ---- Сеть -----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage event) {
    if (_disposed) return;
    switch (event.type) {
      case 'move':
        _receiveMove(event.data);
        break;
      case 'resign':
        // Соперник сдался — мы победили.
        if (isOver) return;
        final mine = isHost ? StoneColor.black : StoneColor.white;
        _winner = WinResult(
          winner: mine,
          line: const WinLine([], StoneColor.black),
        );
        _onWin();
        notifyListeners();
        break;
      case 'disconnected':
        _status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        if (!isOver) {
          _winner = null;
          _isDraw = false;
        }
        notifyListeners();
        break;
      case 'desync':
        _desync('Партия рассинхронизировалась');
        break;
      case 'error':
        final msg = event.data['message'];
        _status = msg is String ? msg : 'Связь потеряна';
        notifyListeners();
        break;
    }
  }

  void _receiveMove(Map<String, Object?> data) {
    try {
      final parsed = parseMove(data);
      // Ход должен быть от соперника, не от нас.
      final mine = isHost ? StoneColor.black : StoneColor.white;
      if (parsed.color == mine) {
        _desync('Соперник прислал наш ход');
        return;
      }
      // Должен быть сейчас ход соперника.
      if (_currentColor != parsed.color) {
        _desync('Не та очередь хода');
        return;
      }
      // Точка должна быть свободна.
      if (_board.at(parsed.point) != null) {
        _desync('Клетка занята');
        return;
      }
      _applyMove(parsed.point, remote: true);
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Ход не распознан' : e.message);
    }
  }

  void _desync(String reason) {
    _status = reason;
    notifyListeners();
    // Транспорт уже разорвёт связь; закрывать сервис здесь не нужно — лобби
    // владеет им и закроет при выходе.
  }

  /// Отправляет сообщение по сети, молча игнорируя ошибку, если связь
  /// потеряна — статус покажет пользовательский текст, а не падение.
  void _send(NetworkMessage message) {
    try {
      network?.service.send(message);
    } catch (_) {
      _status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _aiTimer?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}
