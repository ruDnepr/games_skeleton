import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/network_game_service.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'engine/scoring.dart';
import 'network.dart';

/// Конфигурация партии в терминах приложения: режим правил, размер доски,
/// цвет человека на этом устройстве, цель захвата, коми, с кем играем и
/// (для сети) соединение. Это надстройка над чистым движковым [GameSetup].
class AppGameSetup {
  const AppGameSetup({
    required this.mode,
    required this.boardSize,
    required this.playerSide,
    this.captureTarget = CaptureTarget.one,
    this.komi = 6.5,
    this.appMode = AppGameMode.computer,
    this.difficulty = Difficulty.easy,
    this.network,
  });

  final GoMode mode; // capture / classic — режим правил
  final int boardSize;
  final StoneColor playerSide;
  final CaptureTarget captureTarget;
  final double komi;
  final AppGameMode appMode; // computer / local / network — с кем играем
  final Difficulty difficulty;
  final NetworkSession? network;

  GameSetup toEngine() => GameSetup(
        mode: mode,
        boardSize: boardSize,
        captureTarget: captureTarget,
        komi: komi,
      );
}

/// С кем играем: против компьютера, вдвоём на одном устройстве или по сети.
enum AppGameMode { computer, local, network }

class MoveRecord {
  const MoveRecord(this.color, this.point, {this.passed = false});
  final StoneColor color;
  final Point? point;
  final bool passed;
}

class MoveAnimation {
  const MoveAnimation(
    this.before,
    this.point,
    this.captured,
    this.color,
    this.duration,
  );
  final GameState before;
  final Point? point; // null для паса
  final List<Point> captured;
  final StoneColor color;
  final Duration duration;
}

/// Запрос для поиска хода ИИ в отдельном изоляте.
class _SearchRequest {
  const _SearchRequest(this.state, this.difficulty, this.timeLimit);
  final GameState state;
  final Difficulty difficulty;
  final Duration timeLimit;
}

Point? _searchMove(_SearchRequest req) {
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

/// Контроллер партии го. Один и тот же класс ведёт партию против компьютера,
/// вдвоём на одном устройстве и по сети: различия собраны в нескольких ветках,
/// а правила и история общие. Так расхождения между режимами быть не может.
class GoController extends ChangeNotifier {
  GoController(
    this.setup,
    this.settings, {
    GameSounds? sounds,
    this.animationDuration = const Duration(milliseconds: 260),
    GameState? initialState,
  })  : state = initialState ?? GameState.initial(setup.toEngine()),
        rules = setup.mode == GoMode.capture
            ? CaptureGoRules(setup.toEngine())
            : ClassicGoRules(setup.toEngine()),
        sounds = sounds ?? GameSounds(settings) {
    if (setup.appMode == AppGameMode.network && setup.network == null) {
      throw ArgumentError('Для сетевой игры необходимо соединение');
    }
    _refresh();
    settings.addListener(_settingsChanged);
    _networkSubscription =
        setup.network?.service.events.listen(_onNetworkMessage);
  }

  final AppGameSetup setup;
  final SettingsController settings;
  final GoRules rules;
  final GameSounds sounds;
  final Duration animationDuration;

  GameState state;
  late List<Point> legalPlacements;
  final List<GameState> _history = [];
  final List<MoveRecord> _records = [];
  List<MoveRecord> get history => List.unmodifiable(_records);

  Point? suggestedMove;
  String? hintText;
  String? notice;
  MoveAnimation? animation;
  bool computerThinking = false;
  bool hintThinking = false;
  bool waitingForUndo = false;
  int? incomingUndoPly;
  int? _deferredUndoPly;
  String? fatalMessage;
  StoneColor? _resignedWinner;
  ScoreSummary? finalScore;
  StreamSubscription<NetworkMessage>? _networkSubscription;
  int _generation = 0;
  bool _disposed = false;
  bool _started = false;

  bool get hints => settings.flag(goGameId, 'hints');
  bool get hintButton => settings.flag(goGameId, 'hintButton');

  StoneColor? get winner =>
      _resignedWinner ?? (rules.isOver(state) ? rules.winner(state) : null);

  bool get isOver => winner != null || rules.isOver(state);

  bool get isMyTurn =>
      !isOver &&
      fatalMessage == null &&
      (setup.appMode == AppGameMode.local ||
          state.turn == setup.playerSide);

  bool get isAnimating => animation != null;

  bool get canInteract =>
      !isOver &&
      fatalMessage == null &&
      !isAnimating &&
      !computerThinking &&
      !waitingForUndo &&
      incomingUndoPly == null &&
      _deferredUndoPly == null &&
      (setup.appMode == AppGameMode.local ||
          state.turn == setup.playerSide);

  bool get canPass =>
      canInteract &&
      !rules.isOver(state) &&
      (setup.appMode == AppGameMode.local ||
          state.turn == setup.playerSide);

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
    if (setup.appMode == AppGameMode.network) {
      return setup.network?.service.status == NetworkStatus.connected &&
          _history.isNotEmpty;
    }
    if (setup.appMode == AppGameMode.computer &&
        _history.last.turn != setup.playerSide) {
      return _history.length >= 2;
    }
    return true;
  }

  /// Группы под угрозой захвата (в атари) — для подсказки.
  Set<Point> get atariPoints {
    if (!hints) return const {};
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

  void start() {
    if (_started) return;
    _started = true;
    if (setup.appMode == AppGameMode.computer &&
        state.turn != setup.playerSide) {
      _startComputer();
    }
  }

  void _refresh() {
    legalPlacements = rules.legalPlacements(state);
  }

  void _settingsChanged() {
    if (!hints) {
      suggestedMove = null;
      hintText = null;
      if (notice != null && !waitingForUndo) notice = null;
    }
    _notify();
  }

  void clearHint() {
    if (suggestedMove == null && hintText == null) return;
    suggestedMove = null;
    hintText = null;
    _notify();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    _notify();
  }

  /// Тап по пересечению. Если ход допустим — ставит камень.
  void tap(Point point) {
    if (!canInteract) return;
    if (state.board.occupied(point)) {
      notice = 'Здесь уже стоит камень.';
      _notify();
      return;
    }
    if (point == state.koPoint) {
      notice = hints
          ? 'Это правило ко: нельзя сразу повторять позицию. Походи в другое место.'
          : 'Так ходить нельзя.';
      _notify();
      return;
    }
    if (!legalPlacements.contains(point)) {
      notice = hints
          ? 'Этот ход запретен: камень останется без дыханий (самоубийство).'
          : 'Так ходить нельзя.';
      _notify();
      return;
    }
    notice = null;
    suggestedMove = null;
    hintText = null;
    unawaited(_apply(GoMove.place(point, color: state.turn), remote: false));
  }

  /// Пас.
  void pass() {
    if (!canPass) return;
    notice = null;
    suggestedMove = null;
    hintText = null;
    unawaited(_apply(GoMove.pass(color: state.turn), remote: false));
  }

  Future<void> showHint() async {
    if (!hints || !canInteract || hintThinking) return;
    final snapshot = state;
    final generation = _generation;
    hintThinking = true;
    notice = null;
    _notify();
    try {
      final point = await compute(
        _searchMove,
        _SearchRequest(
          snapshot,
          setup.difficulty == Difficulty.easy
              ? Difficulty.medium
              : setup.difficulty,
          const Duration(milliseconds: 400),
        ),
      );
      if (!_disposed &&
          point != null &&
          generation == _generation &&
          snapshot.fingerprint == state.fingerprint &&
          hints) {
        suggestedMove = point;
        hintText = _describeHint(point);
      } else if (!_disposed && point == null) {
        notice = 'Подсказка: можно пасовать — хороших ходов не нашлось.';
      }
    } finally {
      if (!_disposed) {
        hintThinking = false;
        _notify();
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

  Future<void> _apply(GoMove move, {required bool remote}) async {
    if (_disposed || fatalMessage != null) return;
    final before = state;
    _history.add(before);
    _records.add(MoveRecord(before.turn, move.point, passed: move.isPass));
    state = rules.applyKnownLegal(before, move);
    _refresh();
    suggestedMove = null;
    hintText = null;
    notice = null;
    computerThinking = false;
    final captured = state.lastCaptured;
    animation = MoveAnimation(
      before,
      move.point,
      captured,
      before.turn,
      animationDuration,
    );
    final generation = ++_generation;
    // Звук хода: постановка и пас — move, захват — capture (отдельный звук,
    // как в оригинале; одновременная очередь не нужна, это один эффект).
    sounds.play(move.isPass || captured.isEmpty
        ? GameSound.move
        : GameSound.capture);
    _notify();
    await Future<void>.delayed(animationDuration);
    if (_disposed || generation != _generation) return;
    animation = null;
    if (_deferredUndoPly != null) {
      incomingUndoPly = _deferredUndoPly;
      _deferredUndoPly = null;
    }

    // Позитивное сообщение при захвате.
    if (captured.isNotEmpty &&
        before.turn == setup.playerSide &&
        setup.appMode != AppGameMode.network) {
      notice = _praiseForCapture(captured.length);
    }

    if (!remote && setup.appMode == AppGameMode.network) {
      try {
        setup.network!.service.send(NetworkMessage('move', {
          'ply': before.ply,
          'before': before.fingerprint,
          'color': before.turn.name,
          'pass': move.isPass,
          if (!move.isPass) 'point': move.point!.toJson(),
        }));
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
      }
    }

    // Классический режим: после двух пасов хост считает и рассылает счёт.
    if (rules.isOver(state) &&
        setup.mode == GoMode.classic &&
        setup.appMode == AppGameMode.network &&
        setup.network?.isHost == true) {
      final s = rules.score(state);
      if (s != null) {
        try {
          setup.network!.service.send(NetworkMessage('event', {
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
          // Связь пропадёт — фатальное сообщение поставит обработчик
          // события `disconnected`.
        }
      }
    }

    _notify();
    if (isOver || fatalMessage != null) {
      _recordResult();
      return;
    }
    if (setup.appMode == AppGameMode.computer &&
        state.turn != setup.playerSide) {
      _startComputer();
    }
  }

  String _praiseForCapture(int n) => switch (n) {
        1 => 'Отличный захват! Снят 1 камень.',
        2 => 'Великолепно! Снято 2 камня.',
        _ => 'Невероятно! Снято $n камней.',
      };

  void _recordResult() {
    if (setup.appMode == AppGameMode.network) {
      // В сети каждое устройство само считает свою статистику.
      final mine = setup.playerSide;
      final w = winner;
      final iWon = w == mine;
      if (w == null) {
        sounds.play(GameSound.draw);
      } else {
        sounds.play(iWon ? GameSound.win : GameSound.lose);
      }
      return;
    }
    final w = winner;
    if (w == null) {
      sounds.play(GameSound.draw);
      return;
    }
    final won = setup.appMode == AppGameMode.local || w == setup.playerSide;
    unawaited(settings.recordGame(won: won));
    sounds.play(won ? GameSound.win : GameSound.lose);
  }

  void _startComputer() {
    if (_disposed || computerThinking || isOver || fatalMessage != null) {
      return;
    }
    computerThinking = true;
    final generation = _generation;
    final snapshot = state;
    _notify();
    Future<void>(() async {
      if (_disposed || generation != _generation) return;
      try {
        final point = await compute(
          _searchMove,
          _SearchRequest(
            snapshot,
            setup.difficulty,
            setup.difficulty == Difficulty.hard
                ? const Duration(seconds: 1, milliseconds: 200)
                : Duration.zero,
          ),
        );
        if (_disposed ||
            generation != _generation ||
            snapshot.fingerprint != state.fingerprint) {
          return;
        }
        if (point == null) {
          // ИИ пасует, если нет осмысленного хода.
          await _apply(GoMove.pass(color: snapshot.turn), remote: false);
        } else {
          await _apply(GoMove.place(point, color: snapshot.turn), remote: false);
        }
      } catch (_) {
        if (!_disposed && generation == _generation) {
          computerThinking = false;
          fatalMessage = 'Не получилось сделать ход. Попробуй новую партию.';
          _notify();
        }
      }
    });
  }

  void undo() {
    if (!canUndo) return;
    if (setup.appMode == AppGameMode.network) {
      waitingForUndo = true;
      try {
        setup.network!.service.send(NetworkMessage('undoRequest', {
          'ply': state.ply,
          'before': state.fingerprint,
        }));
      } catch (_) {
        waitingForUndo = false;
        fatalMessage = 'Связь потеряна.';
      }
      _notify();
      return;
    }
    var count = 1;
    if (setup.appMode == AppGameMode.computer &&
        _history.last.turn != setup.playerSide) {
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
      if (_history.isEmpty) break;
      state = _history.removeLast();
      _records.removeLast();
    }
    _resignedWinner = null;
    finalScore = null;
    waitingForUndo = false;
    incomingUndoPly = null;
    _deferredUndoPly = null;
    suggestedMove = null;
    hintText = null;
    notice = null;
    _refresh();
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

  void resign() {
    if (isOver || fatalMessage != null) return;
    if (setup.appMode == AppGameMode.network) {
      try {
        setup.network!.service.send(const NetworkMessage('resign'));
      } catch (_) {
        // Связь пропадёт — фатальное сообщение поставит `disconnected`.
      }
      _resignedWinner = setup.playerSide.opponent;
    } else {
      _resignedWinner = setup.appMode == AppGameMode.local
          ? state.turn.opponent
          : setup.playerSide.opponent;
    }
    _generation++;
    computerThinking = false;
    animation = null;
    _recordResult();
    _notify();
  }

  void _onNetworkMessage(NetworkMessage message) {
    if (_disposed || fatalMessage != null) return;
    switch (message.type) {
      case 'move':
        try {
          // Цвет хода — это цвет того, кто ходил; на принимающей стороне
          // state.turn ещё указывает на того же игрока (ход применяется
          // после проверки).
          if (message.data['ply'] != state.ply ||
              message.data['before'] != state.fingerprint ||
              message.data['color'] != state.turn.name ||
              incomingUndoPly != null) {
            throw const FormatException('Разные позиции');
          }
          final isPass = message.data['pass'] == true;
          final GoMove move;
          if (isPass) {
            move = GoMove.pass(color: state.turn);
          } else {
            final point = Point.fromJson(message.data['point']);
            if (!legalPlacements.contains(point)) {
              throw const FormatException('Недопустимый ход');
            }
            move = GoMove.place(point, color: state.turn);
          }
          // Ответный ход отменяет любой запрос на отмену: ход — это новая
          // позиция, откатываться уже не к чему.
          waitingForUndo = false;
          // Если ещё идёт анимация предыдущего хода, не рвём связь: ход
          // соперника мог прийти за миллисекунды до конца анимации на
          // медленном устройстве. Прерывать анимацию нельзя — тогда
          // отправляющая сторона не успеет отправить свой ход, и позиции
          // разойдутся. Откладываем применение до конца текущей анимации.
          if (isAnimating) {
            // Анимация ещё идёт — откладываем применение хода.
            // Retry каждые 50мс пока анимация не закончится.
            final pending = move;
            final gen = _generation;
            void retry() {
              if (_disposed || gen != _generation || fatalMessage != null) {
                return;
              }
              if (isAnimating) {
                Future<void>.delayed(const Duration(milliseconds: 50), retry);
                return;
              }
              unawaited(_apply(pending, remote: true));
            }
            Future<void>.delayed(const Duration(milliseconds: 50), retry);
          } else {
            unawaited(_apply(move, remote: true));
          }
        } catch (_) {
          _desync();
        }
      case 'undoRequest':
        final valid = message.data['ply'] == state.ply &&
            message.data['before'] == state.fingerprint &&
            _history.isNotEmpty &&
            incomingUndoPly == null &&
            _deferredUndoPly == null;
        if (valid) {
          if (isAnimating) {
            _deferredUndoPly = state.ply;
          } else {
            incomingUndoPly = state.ply;
            _notify();
          }
        } else {
          try {
            setup.network!.service.send(NetworkMessage('undoResponse', {
              'ply': message.data['ply'],
              'accepted': false,
            }));
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
        _resignedWinner = setup.playerSide;
        _generation++;
        animation = null;
        _recordResult();
        _notify();
      case 'event':
        final kind = message.data['kind'];
        if (kind == 'score') {
          final s = message.data;
          finalScore = ScoreSummary(
            blackTerritory: s['blackTerritory'] as int? ?? 0,
            whiteTerritory: s['whiteTerritory'] as int? ?? 0,
            blackCaptured: s['blackCaptured'] as int? ?? 0,
            whiteCaptured: s['whiteCaptured'] as int? ?? 0,
            komi: (s['komi'] as num?)?.toDouble() ?? 0,
            deadBlack: s['deadBlack'] as int? ?? 0,
            deadWhite: s['deadWhite'] as int? ?? 0,
          );
          _notify();
        }
      case 'desync':
        fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
        _notify();
      case 'disconnected':
        if (!isOver) {
          fatalMessage = 'Связь потеряна. Вернись в меню и попробуй ещё раз.';
          _notify();
        }
      case 'error':
        final msg = message.data['message'];
        fatalMessage = msg is String ? msg : 'Связь потеряна.';
        _notify();
      default:
        break;
    }
  }

  void _desync() {
    try {
      setup.network!.service.send(const NetworkMessage('desync'));
    } catch (_) {}
    fatalMessage = 'Партии перестали совпадать. Начните новую игру.';
    _generation++;
    animation = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @visibleForTesting
  Future<void> playLegalMoveForTest(Point point) =>
      _apply(GoMove.place(point, color: state.turn), remote: true);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    settings.removeListener(_settingsChanged);
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }
}
