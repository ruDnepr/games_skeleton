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

/// Режим партии: против компьютера, вдвоём на одном устройстве или по сети.
enum GameMode { computer, local, network }

/// Фаза партии: идёт или окончена.
enum GamePhase { playing, over }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно интерфейсу для правильной подписи.
enum ActiveSide { me, computer, friend, nobody }

/// Исход партии. `null` — ещё идёт.
enum GameResult { white, black, draw }

/// Настройка партии: что выбрал ребёнок на экранах «вариант → режим → сложность
/// → жеребьёвка цвета».
class GameSetup {
  const GameSetup({
    required this.variant,
    required this.mode,
    required this.playerSide,
    this.difficulty = Difficulty.easy,
    this.network,
  });
  final GameVariant variant;
  final GameMode mode;
  final Side playerSide;
  final Difficulty difficulty;
  final NetworkSession? network;
}

/// Одна запись в истории ходов.
class MoveRecord {
  const MoveRecord(this.side, this.move);
  final Side side;
  final Move move;
}

/// Анимация хода: позиция до хода, сам ход и длительность. Шашка скользит по
/// `landings`, поднимаясь по синусоиде; серия взятий рисуется как один путь.
class MoveAnimation {
  const MoveAnimation(this.before, this.move, this.duration);
  final GameState before;
  final Move move;
  final Duration duration;
}

/// Всё, что нужно для поиска хода в отдельном изоляте: позиция, глубина и
/// эвристики. Чистые данные, без ссылок на контроллер.
class _SearchRequest {
  const _SearchRequest(this.state, this.depth, this.noise, this.materialOnly);
  final GameState state;
  final int depth;
  final bool noise;
  final bool materialOnly;
}

/// Точка входа в изолят: ищет лучший ход в позиции.
Move? _searchMove(_SearchRequest request) => CheckersAI().findBestMove(
  request.state,
  request.depth,
  easyNoise: request.noise,
  materialOnly: request.materialOnly,
);

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
    required GameVariant variant,
    this.mode = GameMode.local,
    this.difficulty = Difficulty.easy,
    this.humanColor = Side.white,
    this.animationPerLanding = const Duration(milliseconds: 350),
    this.network,
    GameState? initialState,
  }) : isHost = network?.isHost ?? false,
       rules = GameRules.forVariant(variant) as StandardRules {
    if (network != null) {
      mode = GameMode.network;
      humanColor = isHost ? Side.white : Side.black;
      _networkSub = network!.service.events.listen(_onNetworkMessage);
    }
    state = initialState ?? GameState.initial(variant);
    _refresh();
    settings.addListener(_onSettingsChanged);
  }

  final SettingsController settings;
  final GameSounds sounds;
  final StandardRules rules;
  final NetworkSession? network;
  final bool isHost;
  final Duration animationPerLanding;

  GameMode mode;
  late GameState state;
  GameVariant get variant => state.variant;
  Side humanColor;
  Difficulty difficulty;
  late List<Move> legalMoves;

  /// Снимки на начало каждого хода — для отмены. По сети оба устройства кладут
  /// сюда по одному снимку на ход, поэтому они симметричны и отмена работает
  /// одинаково с обеих сторон.
  final List<GameState> _history = [];

  /// Записи ходов для модального окна истории.
  final List<MoveRecord> _records = [];
  List<MoveRecord> get history => List.unmodifiable(_records);

  Square? selected;
  final List<Square> _prefix = [];
  List<Square> get selectedPath => List.unmodifiable(_prefix);

  Move? suggestedMove;
  String? hintText;
  String? notice;
  String? fatalMessage;

  MoveAnimation? animation;
  bool computerThinking = false;
  bool hintThinking = false;
  bool waitingForUndo = false;
  int? incomingUndoPly;
  int? _deferredUndoPly;
  Side? _resignedWinner;

  StreamSubscription<NetworkMessage>? _networkSub;
  int _generation = 0;
  bool _disposed = false;
  bool _started = false;

  /// Сколько раз текущая позиция (доска + сторона хода) уже встречалась.
  int _repetitions = 1;

  // ---- Настройки -----------------------------------------------------------

  bool get hintsEnabled => settings.flag(checkersGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(checkersGameId, 'hintButton');

  // ---- Подсчёт исхода ------------------------------------------------------

  /// Порог тихих полуходов для ничьей: выше, если на доске только дамки.
  int get quietLimit => state.board.pieces.values.any((piece) => !piece.king)
      ? drawQuietPlies
      : drawQuietPliesKings;

  /// Ничья по третьему повтору позиции или по длинной серии тихих полуходов.
  /// Оба устройства считают её из одной истории, так что в сети совпадает.
  bool get isDraw =>
      winner == null &&
      (_repetitions >= drawRepetitions || state.quietPlies >= quietLimit);

  Side? get winner =>
      _resignedWinner ??
      (legalMoves.isEmpty || state.board.count(state.turn) == 0
          ? (state.variant.reverseGoal ? state.turn : state.turn.opponent)
          : null);

  bool get isOver => winner != null || isDraw;
  bool get isAnimating => animation != null;

  /// Фаза партии — производная от [isOver].
  GamePhase get phase => isOver ? GamePhase.over : GamePhase.playing;

  /// Исход партии — производная от [winner] и [isDraw].
  GameResult? get result {
    if (!isOver) return null;
    if (isDraw) return GameResult.draw;
    final w = winner;
    return w == null ? null : (w == Side.white ? GameResult.white : GameResult.black);
  }

  /// Сейчас ход человека на этом устройстве, партия идёт и связи нет.
  bool get isMyTurn =>
      !isOver &&
      fatalMessage == null &&
      (mode == GameMode.local || state.turn == humanColor);

  /// Можно ли принимать тапы.
  bool get canInteract =>
      !isOver &&
      fatalMessage == null &&
      !isAnimating &&
      !computerThinking &&
      !waitingForUndo &&
      incomingUndoPly == null &&
      _deferredUndoPly == null &&
      (mode == GameMode.local || state.turn == humanColor);

  bool get hasCapture => legalMoves.isNotEmpty && legalMoves.first.isCapture;
  int get maximumCapture => hasCapture ? legalMoves.first.captures.length : 0;

  bool get canUndo {
    if (_history.isEmpty ||
        _resignedWinner != null ||
        isAnimating ||
        waitingForUndo ||
        incomingUndoPly != null ||
        _deferredUndoPly != null ||
        fatalMessage != null) {
      return false;
    }
    if (mode == GameMode.network) {
      // В сети отмена — только по согласию, пока ждём своего хода.
      return _history.last.turn == humanColor &&
          state.turn == humanColor.opponent;
    }
    if (mode == GameMode.computer && _history.last.turn != humanColor) {
      // Отменяем свою пару «мой ход + ответ ИИ», когда снова наша очередь.
      return _history.length >= 2 &&
          _history[_history.length - 2].turn == humanColor;
    }
    return true;
  }

  /// Кандидаты хода для текущего выбора и уже сыгранного префикса серии.
  List<Move> get selectedCandidates {
    if (selected == null) return [];
    return legalMoves.where((move) {
      if (move.from != selected || move.landings.length < _prefix.length) {
        return false;
      }
      for (var i = 0; i < _prefix.length; i++) {
        if (move.landings[i] != _prefix[i]) return false;
      }
      return true;
    }).toList();
  }

  /// Клетки, куда можно пойти (или продолжить серию) из текущего выбора.
  Set<Square> get suggestedDestinations => selectedCandidates
      .where((m) => m.landings.length > _prefix.length)
      .map((m) => m.landings[_prefix.length])
      .toSet();

  /// Совпадает с [suggestedDestinations] — для интерфейса.
  Set<Square> get destinations => suggestedDestinations;

  /// Шашки, которыми можно начать ход (когда ничего не выбрано и подсветки
  /// включены). Лёгкая подсказка: «начни с любой из этих».
  Set<Square> get movablePieces {
    if (!hintsEnabled || !canInteract) return const {};
    if (selected != null || _prefix.isNotEmpty) return const {};
    final points = <Square>{};
    for (final move in legalMoves) {
      points.add(move.from);
    }
    return points;
  }

  /// Можно ли остановить серию взятия здесь, пока более длинная серия ещё
  /// доступна. Только русские/поддавки разрешают это простой шашкой.
  Move? get _stopHere => _prefix.isEmpty
      ? null
      : selectedCandidates
            .where((m) => m.landings.length == _prefix.length)
            .firstOrNull;
  bool get canFinishCapture =>
      _stopHere != null && suggestedDestinations.isNotEmpty;

  /// Завершает серию взятия на текущем префиксе, даже если более длинная серия
  /// доступна. Только для русской шашки и поддавков.
  void finishCapture() {
    if (!canInteract) return;
    final move = _stopHere;
    if (move == null) return;
    _clearSelection();
    notice = null;
    unawaited(_apply(move, remote: false));
  }

  // ---- Имена и подписи -----------------------------------------------------

  String playerName(Side side) {
    if (mode == GameMode.local) {
      return side == humanColor ? 'Игрок 1' : 'Игрок 2';
    }
    if (side == humanColor) return settings.nickname;
    if (mode == GameMode.computer) return 'Компьютер';
    final hostName = network?.lobby.hostName ?? '';
    return network != null && network!.isHost
        ? network!.peerName
        : (hostName.isEmpty ? 'Друг' : hostName);
  }

  /// Активная сторона — для подписи «чей ход».
  ActiveSide get activeSide {
    if (isOver) return ActiveSide.nobody;
    if (mode == GameMode.computer) {
      return state.turn == humanColor ? ActiveSide.me : ActiveSide.computer;
    }
    if (mode == GameMode.network) {
      return state.turn == humanColor ? ActiveSide.me : ActiveSide.friend;
    }
    return ActiveSide.me;
  }

  Side get currentTurn => state.turn;

  /// Текст под доской. Сначала — объяснение неудачного тапа, потом подсказка,
  /// потом особые состояния (ждём ответа, ИИ думает), и только в конце — чей ход.
  String get turnLabel {
    if (notice != null) return notice!;
    if (hintText != null) return hintText!;
    if (waitingForUndo) return 'Ждём ответа друга…';
    if (computerThinking) return 'Компьютер думает…';
    if (isDraw) return 'Ничья — отличная партия!';
    if (hintsEnabled && variant == GameVariant.giveaway) {
      return 'В поддавках выгодно отдавать шашки!';
    }
    if (mode == GameMode.network) {
      return isMyTurn ? 'Твой ход' : 'Ходит друг…';
    }
    return 'Ходят ${state.turn == Side.white ? 'белые' : 'чёрные'}';
  }

  // ---- Старт ---------------------------------------------------------------

  /// Запускает ИИ, если он ходит первым. Вызывается из `initState` страницы
  /// после того, как слушатель контроллера подключён.
  void start() {
    if (_started) return;
    _started = true;
    if (mode == GameMode.computer && state.turn != humanColor) {
      _startComputer();
    }
  }

  void _refresh() {
    legalMoves = rules.legalMoves(state);
    _repetitions = _countRepetitions();
  }

  int _countRepetitions() {
    final key = state.positionKey;
    var count = 1;
    for (final past in _history) {
      if (past.positionKey == key) count++;
    }
    return count;
  }

  void _onSettingsChanged() {
    if (!hintsEnabled) {
      suggestedMove = null;
      hintText = null;
      if (notice != null && !waitingForUndo) notice = null;
    }
    _notify();
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Превращает число в слово для подписи: «1 шашку», «2 шашки», «5 шашек».
  static String _captureCount(int count) => switch (count) {
    1 => '1 шашку',
    2 => '2 шашки',
    3 => '3 шашки',
    4 => '4 шашки',
    _ => '$count шашек',
  };

  String _captureDutyText() => variant == GameVariant.international
      ? 'Сейчас нужно бить как можно больше шашек: $maximumCapture.'
      : 'Сейчас бой обязателен: спокойно походить нельзя, нужно бить шашку.';

  /// Описание хода-подсказки: «подсвечен лучший ход, он бьёт N шашек. …».
  String _describeHint(Move move) {
    final buffer = StringBuffer('Подсказка: подсвечен лучший ход');
    if (move.isCapture) {
      buffer.write(', он бьёт ${_captureCount(move.captures.length)}');
    }
    if (hasCapture) {
      buffer.write(
        variant == GameVariant.international
            ? '. Бить нужно как можно больше шашек: $maximumCapture'
            : '. Сейчас бой обязателен',
      );
    }
    if (variant == GameVariant.giveaway) {
      buffer.write('. В поддавках выгодно отдавать свои шашки');
    }
    return '${buffer.toString()}.';
  }

  /// Объясняет, почему тап ни к чему не привёл. С подсказками — подробно, без
  /// них — коротко: «Так ходить нельзя.».
  String _explainTap(Square square, {required bool hadSelection}) {
    if (!hintsEnabled) return 'Так ходить нельзя.';
    final piece = state.board.at(square);
    if (piece == null) {
      if (hasCapture) return _captureDutyText();
      if (hadSelection) {
        return 'Так ходить нельзя: подсвечены только разрешённые клетки.';
      }
      return 'Сначала выбери свою шашку, потом подсвеченную клетку.';
    }
    if (piece.side != state.turn) {
      return 'Это шашка соперника: ходить можно только своей.';
    }
    if (hasCapture) {
      return variant == GameVariant.international
          ? '${_captureDutyText()} Эта шашка не бьёт — выбери ту, которая бьёт.'
          : 'Сейчас бой обязателен: эта шашка не бьёт, выбери ту, которая бьёт.';
    }
    return 'Эта шашка сейчас не может ходить — выбери другую.';
  }

  /// Убирает подсветку подсказки и текст «Подсказка: …».
  void clearHint() {
    if (suggestedMove == null && hintText == null) return;
    suggestedMove = null;
    hintText = null;
    _notify();
  }

  /// Убирает пояснение после неудачного тапа.
  void clearNotice() {
    if (notice == null) return;
    notice = null;
    _notify();
  }

  /// Ищет лучший ход в изоляте и подсвечивает его. До нажатия кнопки ничего о
  /// лучшем ходе не сообщается.
  Future<void> showHint() async {
    if (!hintsEnabled || !canInteract || hintThinking) return;
    final snapshot = state;
    final generation = _generation;
    hintThinking = true;
    notice = null;
    _notify();
    try {
      // Три полухода: свой ход, ответ соперника, свой ответ. Достаточно, чтобы
      // увидеть, что шашка попадёт под бой, и быстро для телефона.
      final move = await compute(
        _searchMove,
        _SearchRequest(snapshot, 3, false, false),
      );
      if (!_disposed &&
          move != null &&
          generation == _generation &&
          snapshot.fingerprint == state.fingerprint &&
          hintsEnabled) {
        _clearSelection();
        suggestedMove = move;
        hintText = _describeHint(move);
      }
    } finally {
      if (!_disposed) {
        hintThinking = false;
        _notify();
      }
    }
  }

  // ---- Тапы ----------------------------------------------------------------

  /// Тап по клетке. Выбирает свою шашку, добавляет шаг в серию взятия или
  /// завершает ход.
  void tap(Square square) {
    if (!canInteract) return;
    notice = null;
    suggestedMove = null;
    hintText = null;
    final candidates = selectedCandidates;
    final next = candidates
        .where(
          (m) =>
              m.landings.length > _prefix.length &&
              m.landings[_prefix.length] == square,
        )
        .toList();
    if (next.isNotEmpty) {
      _prefix.add(square);
      final completed = next
          .where((m) => m.landings.length == _prefix.length)
          .firstOrNull;
      // Серию можно продолжить — ждём следующего тапа. Если продолжения нет,
      // применяем ход сразу. Если серию можно закончить здесь, оставляем выбор
      // за ребёнком: тап по следующей клетке продолжит, «Закончить бой»
      // остановит.
      if (completed != null && !canFinishCapture) {
        _clearSelection();
        unawaited(_apply(completed, remote: false));
      } else {
        _notify();
      }
      return;
    }
    // Серию начал — должен закончить той же шашкой.
    if (_prefix.isNotEmpty) {
      notice = canFinishCapture
          ? 'Можно закончить бой здесь — нажми «Закончить бой», '
                'или продолжай бить этой шашкой.'
          : 'Серия взятий уже начата — закончи её этой же шашкой.';
      _notify();
      return;
    }
    if (legalMoves.any((m) => m.from == square)) {
      selected = square;
      _notify();
      return;
    }
    final hadSelection = selected != null;
    _clearSelection();
    notice = _explainTap(square, hadSelection: hadSelection);
    _notify();
  }

  /// Снимает выбор шашки и обнуляет начатую серию.
  void clearSelection() {
    if (selected != null || _prefix.isNotEmpty) {
      _clearSelection();
      _notify();
    }
  }

  void _clearSelection() {
    selected = null;
    _prefix.clear();
  }

  // ---- Применение хода -----------------------------------------------------

  /// Применяет ход. Звук играется сразу, шашка скользит по пути, после
  /// окончания анимации ход отправляется по сети и (если нужно) зовётся ИИ.
  Future<void> _apply(Move move, {required bool remote}) async {
    if (_disposed || fatalMessage != null || !legalMoves.contains(move)) return;
    final before = state;
    _history.add(before);
    _records.add(MoveRecord(before.turn, move));
    state = rules.applyKnownLegal(before, move);
    _refresh();
    _clearSelection();
    suggestedMove = null;
    hintText = null;
    notice = null;
    computerThinking = false;
    final duration = animationPerLanding * move.landings.length;
    animation = MoveAnimation(before, move, duration);
    final generation = ++_generation;
    final becameKing =
        !(before.board.at(move.from)?.king ?? false) &&
        (state.board.at(move.to)?.king ?? false);
    sounds.play(
      becameKing
          ? GameSound.crown
          : (move.isCapture ? GameSound.capture : GameSound.move),
    );
    _notify();
    if (duration > Duration.zero) await Future<void>.delayed(duration);
    if (_disposed || generation != _generation) return;
    animation = null;
    if (_deferredUndoPly != null) {
      incomingUndoPly = _deferredUndoPly;
      _deferredUndoPly = null;
    }
    if (!remote && mode == GameMode.network) {
      try {
        network!.service.send(
          NetworkMessage('move', {
            'ply': before.ply,
            'before': before.fingerprint,
            'move': move.toJson(),
          }),
        );
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
      }
    }
    _notify();
    if (isOver || fatalMessage != null) return;
    if (mode == GameMode.computer && state.turn != humanColor) {
      _startComputer();
    }
  }

  void _startComputer() {
    if (_disposed || computerThinking || isOver || fatalMessage != null) {
      return;
    }
    computerThinking = true;
    final generation = _generation;
    final snapshot = state;
    _notify();
    // ИИ работает в изоляте, поэтому интерфейс не замирает.
    Future<void>(() async {
      if (_disposed || generation != _generation) return;
      try {
        final move = await compute(
          _searchMove,
          _SearchRequest(
            snapshot,
            difficulty.depth,
            difficulty == Difficulty.easy,
            difficulty.materialOnly,
          ),
        );
        if (_disposed ||
            generation != _generation ||
            snapshot.fingerprint != state.fingerprint) {
          return;
        }
        if (move != null) await _apply(move, remote: false);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          computerThinking = false;
          fatalMessage =
              'Не получилось сделать ход. Попробуй начать новую партию.';
          _notify();
        }
      }
    });
  }

  // ---- Отмена --------------------------------------------------------------

  /// Отменить последний ход. В сети — просит согласия друга, пока ждём своего
  /// хода; против компьютера — отматывает пару «свой ход + ответ ИИ»; вдвоём —
  /// один ход.
  void undo() {
    if (!canUndo) return;
    if (mode == GameMode.network) {
      waitingForUndo = true;
      try {
        network!.service.send(
          NetworkMessage('undoRequest', {
            'ply': state.ply,
            'before': state.fingerprint,
          }),
        );
      } catch (_) {
        waitingForUndo = false;
        fatalMessage = 'Связь потеряна.';
      }
      _notify();
      return;
    }
    var count = 1;
    if (mode == GameMode.computer &&
        _history.last.turn != humanColor) {
      count = 2;
    }
    _restore(count);
  }

  void _restore(int count) {
    _generation++;
    computerThinking = false;
    hintThinking = false;
    animation = null;
    for (var i = 0; i < count; i++) {
      state = _history.removeLast();
      _records.removeLast();
    }
    _resignedWinner = null;
    waitingForUndo = false;
    incomingUndoPly = null;
    _deferredUndoPly = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    _clearSelection();
    _refresh();
    _notify();
  }

  /// Ответ на просьбу друга об отмене хода по сети.
  void respondToUndo(bool accepted) {
    final ply = incomingUndoPly;
    if (ply == null) return;
    try {
      network!.service.send(
        NetworkMessage('undoResponse', {'ply': ply, 'accepted': accepted}),
      );
      incomingUndoPly = null;
      if (accepted && state.ply == ply && _history.isNotEmpty) {
        _restore(1);
      } else {
        _notify();
      }
    } catch (_) {
      fatalMessage = 'Связь потеряна.';
      _notify();
    }
  }

  // ---- Сдача ---------------------------------------------------------------

  void resign() {
    if (isOver || fatalMessage != null) return;
    if (mode == GameMode.network) {
      try {
        network!.service.send(const NetworkMessage('resign'));
      } catch (_) {}
      _resignedWinner = humanColor.opponent;
    } else {
      _resignedWinner = mode == GameMode.local
          ? state.turn.opponent
          : humanColor.opponent;
    }
    _generation++;
    computerThinking = false;
    animation = null;
    _notify();
  }

  // ---- Сеть ----------------------------------------------------------------

  void _onNetworkMessage(NetworkMessage message) {
    if (_disposed || fatalMessage != null) return;
    switch (message.type) {
      case 'move':
        try {
          if (message.data['ply'] != state.ply ||
              message.data['before'] != state.fingerprint ||
              state.turn != humanColor.opponent ||
              incomingUndoPly != null) {
            throw const FormatException('Разные позиции');
          }
          final move = Move.fromJson(message.data['move']);
          if (!legalMoves.contains(move)) {
            throw const FormatException('Недопустимый ход');
          }
          // Ответ на ход отменяет любой запрос на отмену: ход — это новая
          // позиция, откатываться уже не к чему.
          waitingForUndo = false;
          // Если ещё идёт анимация предыдущего хода, не рвём связь: ход
          // соперника мог прийти за мгновения до конца анимации. Прерывать
          // анимацию нельзя — тогда собственный ход не успеет уйти в сеть,
          // и позиции разойдутся. Откладываем применение до конца текущей
          // анимации.
          if (isAnimating) {
            final pending = move;
            final gen = _generation;
            Future<void>.delayed(const Duration(milliseconds: 30), () {
              if (_disposed || gen != _generation || fatalMessage != null) {
                return;
              }
              if (isAnimating) {
                Future<void>.delayed(const Duration(milliseconds: 60), () {
                  if (_disposed ||
                      gen != _generation ||
                      fatalMessage != null) {
                    return;
                  }
                  unawaited(_apply(pending, remote: true));
                });
                return;
              }
              unawaited(_apply(pending, remote: true));
            });
          } else {
            unawaited(_apply(move, remote: true));
          }
        } catch (_) {
          _desync();
        }
      case 'undoRequest':
        final valid =
            message.data['ply'] == state.ply &&
            message.data['before'] == state.fingerprint &&
            _history.isNotEmpty &&
            _history.last.turn == humanColor.opponent &&
            state.turn == humanColor &&
            incomingUndoPly == null &&
            _deferredUndoPly == null;
        if (valid) {
          // Запрос мог прийти во время анимации хода. Подождём её конца и
          // спросим сразу после.
          if (isAnimating) {
            _deferredUndoPly = state.ply;
          } else {
            incomingUndoPly = state.ply;
            _notify();
          }
        } else {
          try {
            network!.service.send(
              NetworkMessage('undoResponse', {
                'ply': message.data['ply'],
                'accepted': false,
              }),
            );
          } catch (_) {}
        }
      case 'undoResponse':
        if (waitingForUndo &&
            message.data['ply'] == state.ply &&
            message.data['accepted'] is bool) {
          waitingForUndo = false;
          if (message.data['accepted'] == true && _history.isNotEmpty) {
            _restore(1);
          } else {
            notice = 'Друг решил продолжить без отмены хода.';
            _notify();
          }
        }
      case 'resign':
        _resignedWinner = humanColor;
        _generation++;
        animation = null;
        _notify();
      case 'desync':
        fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
        _notify();
      case 'disconnected':
        if (!isOver) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
          _notify();
        }
      default:
        break;
    }
  }

  void _desync() {
    try {
      network!.service.send(const NetworkMessage('desync'));
    } catch (_) {}
    fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
    _generation++;
    animation = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Для тестов: применяет ход, не отправляя его по сети.
  @visibleForTesting
  Future<void> playLegalMoveForTest(Move move) => _apply(move, remote: true);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    settings.removeListener(_onSettingsChanged);
    unawaited(_networkSub?.cancel());
    super.dispose();
  }
}
