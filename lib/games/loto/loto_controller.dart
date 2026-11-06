import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режим партии лото.
enum LotoMode { computer, twoPlayers, network }

/// Фаза партии: идёт или окончена.
enum LotoPhase { playing, over }

/// Идентификатор игрока-человека в одиночной игре. В сетевой хост — `host`,
/// клиент — `client`; в режиме двух игроков — `p1` и `p2`.
const localHostPlayerId = 'me';

/// Контроллер партии лото. Содержит состояние, историю, звук, голос ведущего
/// и сеть; интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его
/// методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила и
/// история общие. Так расхождения между режимами быть не может.
class LotoController extends ChangeNotifier {
  LotoController({
    required this.settings,
    required this.sounds,
    this.network,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = LotoMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
    game = LotoGame.start(
      players: const [],
      winMode: WinMode.row,
      bag: BarrelBag.empty(),
    );
  }

  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  late final bool isHost;

  LotoMode mode = LotoMode.computer;
  LotoPhase phase = LotoPhase.playing;

  /// Режим победы, выбранный на экране старта. У сетевой игры его сообщает
  /// хост в снимке партии.
  WinMode winMode = WinMode.row;

  /// Идентификатор игрока на этом устройстве. В двух-игроках — `p1`, но
  /// тапать можно оба поля; мы держим «своего» только для подсказки и сдачи.
  String myPlayerId = localHostPlayerId;

  LotoGame game = LotoGame.start(
    players: const [],
    winMode: WinMode.row,
    bag: BarrelBag.empty(),
  );

  /// Снимки партии на начало каждого вытягивания — для отмены.
  final List<LotoGame> _history = [];

  /// Подсветка кнопки «Подсказка»: какие числа можно закрыть.
  Set<int> _hintHighlight = const <int>{};
  Set<int> get hintHighlight => _hintHighlight;

  /// Короткая подсказка для ребёнка: «Этот бочонок ещё в мешке».
  String? status;
  bool get hasStatus => status != null && status!.isNotEmpty;

  StreamSubscription<NetworkMessage>? _networkSub;
  Timer? _rivalTimer;
  Timer? _statusTimer;
  FlutterTts? _tts;
  bool _ttsReady = false;
  bool _disposed = false;
  bool _recorded = false;

  // ---- Настройки ------------------------------------------------------------

  bool get hintsEnabled => settings.flag(lotoGameId, 'hints');
  bool get hintButtonEnabled => settings.flag(lotoGameId, 'hintButton');
  bool get voiceEnabled => settings.flag(lotoGameId, 'voice');

  // ---- Удобные геттеры для интерфейса ---------------------------------------

  Barrel? get lastBarrel => game.lastBarrel;
  int get barrelsLeft => game.barrelsLeft;
  bool get isOver => phase == LotoPhase.over || game.isOver;
  bool get isBagEmpty => game.isBagEmpty;
  LotoPlayer? get winner => game.winner;
  List<int> get drawn => game.drawn;

  LotoPlayer? get me => game.playerById(myPlayerId);

  LotoCard? get myCard => me?.card;
  Set<int> get myClosed => me?.closed ?? const <int>{};

  /// Все игроки, кроме меня. В двух-игроках здесь будет второй человек, в
  /// режиме против компьютера — соперник, в сети — друг.
  List<LotoPlayer> get others =>
      [for (final player in game.players) if (player.id != myPlayerId) player];

  /// Бочонок, который я ещё не закрыл, но уже можно.
  int? get myPendingBarrel {
    final mine = me;
    final barrel = lastBarrel;
    if (mine == null || barrel == null) return null;
    return LotoRules.canClose(
      card: mine.card,
      closed: mine.closed,
      drawn: game.drawn,
      number: barrel.number,
    )
        ? barrel.number
        : null;
  }

  /// Числа моей карточки, которые уже можно закрыть.
  List<int> get myClosable {
    final mine = me;
    if (mine == null) return const [];
    return LotoRules.closableNumbers(
      card: mine.card,
      closed: mine.closed,
      drawn: game.drawn,
    );
  }

  /// Можно ли тянуть бочонок с кнопки.
  bool get canDraw {
    if (phase != LotoPhase.playing) return false;
    if (game.isBagEmpty) return false;
    if (game.players.isEmpty) return false;
    if (mode == LotoMode.network && !isHost) return false;
    return true;
  }

  /// Можно ли вообще играть: партия идёт и не ждёт никого по сети.
  bool get canInteract => phase == LotoPhase.playing && !game.isOver;

  /// Можно ли отменить последний бочонок.
  bool get canUndo {
    if (phase != LotoPhase.playing) return false;
    if (mode == LotoMode.network && !isHost) return false;
    return _history.isNotEmpty;
  }

  /// Можно ли сдаться. В режиме двух игроков на одном устройстве сдача
  /// особого смысла не имеет, поэтому кнопки нет.
  bool get canResign =>
      phase == LotoPhase.playing &&
      mode != LotoMode.twoPlayers &&
      game.players.isNotEmpty;

  // ---- Старт партий --------------------------------------------------------

  /// Партия против компьютера: человек тянет бочонок, соперник сам закрывает
  /// своё число через короткую паузу.
  void startComputer({WinMode mode = WinMode.row}) {
    this.mode = LotoMode.computer;
    winMode = mode;
    final me = LotoPlayer(
      id: localHostPlayerId,
      name: settings.nickname,
      card: LotoCard.generate(),
      isHost: true,
    );
    final rival = LotoPlayer(
      id: 'rival',
      name: 'Компьютер',
      card: LotoCard.generate(),
      isComputer: true,
    );
    myPlayerId = localHostPlayerId;
    _beginGame(LotoGame.start(players: [me, rival], winMode: mode));
  }

  /// Двое на одном устройстве: обе карточки видны, тапать может каждый.
  void startTwoPlayers({WinMode mode = WinMode.row}) {
    this.mode = LotoMode.twoPlayers;
    winMode = mode;
    final p1 = LotoPlayer(
      id: 'p1',
      name: settings.nickname,
      card: LotoCard.generate(),
      isHost: true,
    );
    final p2 = LotoPlayer(
      id: 'p2',
      name: 'Игрок 2',
      card: LotoCard.generate(),
    );
    myPlayerId = 'p1';
    _beginGame(LotoGame.start(players: [p1, p2], winMode: mode));
  }

  /// Сетевая партия. Хост раздаёт карточки и шлёт клиенту снимок, клиент
  /// ждёт этот снимок, чтобы узнать свою карточку.
  void startNetwork({WinMode mode = WinMode.row}) {
    this.mode = LotoMode.network;
    winMode = mode;
    phase = LotoPhase.playing;
    _history.clear();
    _hintHighlight = const {};
    _recorded = false;
    status = null;
    if (isHost) {
      myPlayerId = 'host';
      final host = LotoPlayer(
        id: 'host',
        name: settings.nickname,
        card: LotoCard.generate(),
        isHost: true,
      );
      final peer = LotoPlayer(
        id: 'client',
        name: network?.peerName ?? 'Друг',
        card: LotoCard.generate(),
      );
      game = LotoGame.start(players: [host, peer], winMode: mode);
      // Отправляем клиенту снимок — без него он не знает свою карточку.
      // Небольшая задержка, чтобы клиент успел открыть экран и подписаться.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (_disposed || phase != LotoPhase.playing) return;
        _sendSnapshot();
      });
    } else {
      myPlayerId = 'client';
      // Снимок придёт сообщением `event` — пока покажем заглушку.
      game = LotoGame.start(
        players: const [],
        winMode: mode,
        bag: BarrelBag.empty(),
      );
      status = 'Ждём, пока ведущий раздаст карточки…';
    }
    notifyListeners();
  }

  void _beginGame(LotoGame start) {
    phase = LotoPhase.playing;
    game = start;
    _history.clear();
    _hintHighlight = const {};
    _recorded = false;
    status = null;
    notifyListeners();
  }

  /// Новая партия с теми же настройками.
  void playAgain() {
    _rivalTimer?.cancel();
    _statusTimer?.cancel();
    _hintHighlight = const {};
    status = null;
    _recorded = false;
    phase = LotoPhase.playing;
    switch (mode) {
      case LotoMode.computer:
        startComputer(mode: winMode);
      case LotoMode.twoPlayers:
        startTwoPlayers(mode: winMode);
      case LotoMode.network:
        if (isHost) {
          startNetwork(mode: winMode);
        } else {
          // Клиент ждёт нового снимка от хоста.
          game = LotoGame.start(
            players: const [],
            winMode: winMode,
            bag: BarrelBag.empty(),
          );
          status = 'Ждём, пока ведущий начнёт новую партию…';
          notifyListeners();
        }
    }
  }

  // ---- Вытянуть бочонок -----------------------------------------------------

  /// Вытянуть следующий бочонок. В сети это делает только хост.
  void drawBarrel() {
    if (!canDraw) return;
    _rivalTimer?.cancel();
    _history.add(game);
    game = game.draw();
    final barrel = game.lastBarrel;
    _hintHighlight = const {};
    status = null;
    notifyListeners();
    if (barrel == null) return;
    sounds.play(GameSound.guess);
    _speakNumber(barrel.number);
    if (mode == LotoMode.network && isHost) {
      // Сообщаем клиенту бочонок — он показывает то же число.
      network!.service.send(
        NetworkMessage(
          'event',
          barrelMessageToJson(barrel.number, game.barrelsLeft),
        ),
      );
    }
    if (game.isBagEmpty && !game.isOver) {
      status = 'Бочонки закончились — закрой последнее число!';
      _scheduleStatusClear();
      notifyListeners();
    }
    _maybeScheduleRivalClose();
  }

  // ---- Закрыть число --------------------------------------------------------

  /// Закрыть число на карточке игрока [playerId] (или на своей, если не
  /// указан). В сети закрывает только свою карточку: клиент отправляет `move`
  /// хосту, хост проверяет и рассылает подтверждение.
  void closeNumber(int number, {String? playerId}) {
    if (phase != LotoPhase.playing) return;
    final who = playerId ?? myPlayerId;
    if (mode == LotoMode.network) {
      if (who != myPlayerId) return;
      if (isHost) {
        _hostApplyClose(myPlayerId, number);
      } else {
        network!.service.send(
          NetworkMessage('move', closeNumberToJson(myPlayerId, number)),
        );
      }
      return;
    }
    _applyLocalClose(who, number);
  }

  void _applyLocalClose(String playerId, int number) {
    final before = game.playerById(playerId);
    final outcome = game.close(playerId: playerId, number: number);
    if (!outcome.accepted) {
      status = outcome.status.hint.isEmpty
          ? 'Так закрыть нельзя'
          : outcome.status.hint;
      sounds.play(GameSound.miss);
      _scheduleStatusClear();
      notifyListeners();
      return;
    }
    game = outcome.game;
    final after = game.playerById(playerId);
    final closedRow = before != null &&
        after != null &&
        LotoRules.closedRows(card: after.card, closed: after.closed) >
            LotoRules.closedRows(card: before.card, closed: before.closed);
    sounds.play(closedRow ? GameSound.crown : GameSound.move);
    _hintHighlight = const {};
    status = null;
    if (game.isOver) {
      _onWin(playerId);
    } else {
      notifyListeners();
      _maybeScheduleRivalClose();
    }
  }

  /// Хост применяет закрытие числа (своё или присланное клиентом) и рассылает
  /// подтверждение всем.
  void _hostApplyClose(String playerId, int number) {
    if (game.isOver) {
      _sendCloseReject(playerId, number, 'Партия уже закончилась');
      return;
    }
    final status = LotoRules.checkClose(game, playerId, number);
    if (status != CloseStatus.closed) {
      _sendCloseReject(playerId, number, status.hint);
      return;
    }
    final before = game.playerById(playerId);
    final outcome = game.close(playerId: playerId, number: number);
    game = outcome.game;
    final after = game.playerById(playerId);
    final closedRow = before != null &&
        after != null &&
        LotoRules.closedRows(card: after.card, closed: after.closed) >
            LotoRules.closedRows(card: before.card, closed: before.closed);
    network!.service.send(
      NetworkMessage(
        'event',
        closeEventToJson(
          playerId: playerId,
          number: number,
          accepted: true,
        ),
      ),
    );
    sounds.play(closedRow ? GameSound.crown : GameSound.move);
    if (game.isOver) {
      _onWin(playerId);
    } else {
      notifyListeners();
    }
  }

  void _sendCloseReject(String playerId, int number, String reason) {
    network!.service.send(
      NetworkMessage(
        'event',
        closeEventToJson(
          playerId: playerId,
          number: number,
          accepted: false,
          reason: reason,
        ),
      ),
    );
  }

  // ---- Компьютер-соперник --------------------------------------------------

  /// Компьютерный соперник закрывает свой бочонок с небольшой задержкой,
  /// чтобы ребёнок успел заметить, что произошло. В режимах без компьютера
  /// ничего не делает.
  void _maybeScheduleRivalClose() {
    _rivalTimer?.cancel();
    if (mode != LotoMode.computer) return;
    if (game.isOver) return;
    final barrel = lastBarrel;
    if (barrel == null) return;
    final closing = [
      for (final player in game.players)
        if (player.isComputer &&
            LotoRules.canClose(
              card: player.card,
              closed: player.closed,
              drawn: game.drawn,
              number: barrel.number,
            ))
          player,
    ];
    if (closing.isEmpty) return;
    _rivalTimer = Timer(const Duration(milliseconds: 900), () {
      if (_disposed || phase != LotoPhase.playing) return;
      var current = game;
      var rowClosed = false;
      for (final player in closing) {
        final before = current.playerById(player.id);
        final outcome = current.close(
          playerId: player.id,
          number: barrel.number,
        );
        if (!outcome.accepted) continue;
        current = outcome.game;
        final after = current.playerById(player.id);
        if (before != null &&
            after != null &&
            LotoRules.closedRows(card: after.card, closed: after.closed) >
                LotoRules.closedRows(
                  card: before.card,
                  closed: before.closed,
                )) {
          rowClosed = true;
        }
      }
      if (identical(current, game)) return;
      game = current;
      sounds.play(rowClosed ? GameSound.crown : GameSound.move);
      if (game.isOver) {
        _onWin(closing.first.id);
      } else {
        notifyListeners();
      }
    });
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Подсветить числа карточки игрока [playerId] (или свою), которые уже
  /// можно закрыть. Повторный тап гасит подсветку.
  void showHint({String? playerId}) {
    if (phase != LotoPhase.playing) return;
    final who = playerId ?? myPlayerId;
    final player = game.playerById(who);
    if (player == null) return;
    if (_hintHighlight.isNotEmpty) {
      _hintHighlight = const {};
      status = null;
      notifyListeners();
      return;
    }
    final numbers = LotoRules.closableNumbers(
      card: player.card,
      closed: player.closed,
      drawn: game.drawn,
    );
    _hintHighlight = Set<int>.unmodifiable(numbers);
    status = numbers.isEmpty
        ? 'Пока закрывать нечего — ждём подходящий бочонок'
        : 'Можно закрыть: ${numbers.join(', ')}';
    _scheduleStatusClear();
    notifyListeners();
  }

  // ---- Отмена хода ---------------------------------------------------------

  /// Отменить последний вытянутый бочонок. В сети это может только хост: он
  /// откатывает своё состояние и рассылает новый снимок. В локальных режимах
  /// откатывает состояние и опционально останавливает таймер соперника.
  void undo() {
    if (!canUndo) return;
    _rivalTimer?.cancel();
    if (mode == LotoMode.network) {
      final previous = _history.removeLast();
      game = previous;
      status = 'Ход отменён';
      _hintHighlight = const {};
      _sendSnapshot();
      notifyListeners();
      return;
    }
    final previous = _history.removeLast();
    game = previous;
    _hintHighlight = const {};
    status = 'Ход отменён — бочонок вернулся в мешок';
    sounds.play(GameSound.move);
    _scheduleStatusClear();
    notifyListeners();
  }

  // ---- Сдача ---------------------------------------------------------------

  /// Сдаться. Победа достаётся сопернику.
  void resign() {
    if (!canResign) return;
    String winner;
    if (mode == LotoMode.network) {
      network!.service.send(const NetworkMessage('resign'));
      winner = myPlayerId == 'host' ? 'client' : 'host';
    } else {
      // computer mode — соперник выигрывает
      winner = 'rival';
    }
    game = game.declareWinner(winner);
    _onWin(winner, byResign: true);
  }

  // ---- Победа --------------------------------------------------------------

  void _onWin(String winnerId, {bool byResign = false}) {
    phase = LotoPhase.over;
    final winner = game.playerById(winnerId);
    final isMe = winnerId == myPlayerId;
    final local = mode != LotoMode.network;
    // В режиме двух игроков всегда «выиграл человек на этом устройстве» —
    // результат в статистику пишем как победу.
    final iWon = mode == LotoMode.twoPlayers ? true : isMe;
    sounds.play(
      resultSoundName(draw: false, local: local, iWon: iWon),
    );
    if (!_recorded) {
      _recorded = true;
      unawaited(settings.recordGame(won: iWon || mode == LotoMode.twoPlayers));
    }
    status = null;
    _hintHighlight = const {};
    notifyListeners();
    // `winner` и `byResign` нужны будущему голосовому поздравлению и
    // статистике; сейчас победитель виден на экране без них.
    if (winner != null && byResign) {
      // Сдача — без дополнительных эффектов.
    }
  }

  // ---- Сеть ----------------------------------------------------------------

  void _onNetworkEvent(NetworkMessage message) {
    if (_disposed) return;
    switch (message.type) {
      case 'event':
        _onEvent(message.data);
      case 'move':
        if (isHost) {
          // Клиент просит закрыть число — проверим и рассылаем подтверждение.
          try {
            final parsed = parseCloseNumber(message.data);
            _hostApplyClose(parsed.playerId, parsed.number);
          } on FormatException catch (e) {
            _desync(e.message.isEmpty ? 'Ход не распознан' : e.message);
          }
        }
      case 'resign':
        // Друг сдался — мы победили. Если хост получил resign от клиента,
        // выигрывает хост; и наоборот.
        final winner = isHost ? 'host' : 'client';
        game = game.declareWinner(winner);
        _onWin(winner, byResign: true);
      case 'disconnected':
        status = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        phase = LotoPhase.over;
        notifyListeners();
      case 'desync':
        _desync('Партия рассинхронизировалась');
      case 'error':
        final msg = message.data['message'];
        status = msg is String ? msg : 'Связь потеряна';
        phase = LotoPhase.over;
        notifyListeners();
    }
  }

  void _onEvent(Map<String, Object?> data) {
    final kind = data['kind'];
    try {
      if (kind == 'barrel') {
        final parsed = parseBarrelMessage(data);
        game = game.announce(parsed.number);
        sounds.play(GameSound.guess);
        _speakNumber(parsed.number);
        _hintHighlight = const {};
        status = null;
        notifyListeners();
      } else if (kind == 'closeNumber') {
        final parsed = parseCloseEvent(data);
        if (parsed.accepted) {
          final before = game.playerById(parsed.playerId);
          final outcome = game.close(
            playerId: parsed.playerId,
            number: parsed.number,
          );
          if (outcome.accepted) {
            game = outcome.game;
            final after = game.playerById(parsed.playerId);
            final closedRow = before != null &&
                after != null &&
                LotoRules.closedRows(
                      card: after.card,
                      closed: after.closed,
                    ) >
                    LotoRules.closedRows(
                      card: before.card,
                      closed: before.closed,
                    );
            sounds.play(closedRow ? GameSound.crown : GameSound.move);
            _hintHighlight = const {};
            if (game.isOver) {
              _onWin(parsed.playerId);
            } else {
              notifyListeners();
            }
          }
        } else if (parsed.playerId == myPlayerId) {
          // Хост отказал в закрытии — покажем причину.
          status = parsed.reason ?? 'Так закрыть нельзя';
          _scheduleStatusClear();
          notifyListeners();
        }
      } else if (kind == 'snapshot') {
        final snap = parseSnapshot(data);
        game = snap.game;
        winMode = snap.game.winMode;
        myPlayerId = isHost ? snap.hostPlayerId : snap.clientPlayerId;
        _hintHighlight = const {};
        status = null;
        notifyListeners();
      }
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Событие не распознано' : e.message);
    }
  }

  void _sendSnapshot() {
    if (network == null) return;
    network!.service.send(
      NetworkMessage(
        'event',
        snapshotToJson(
          game: game,
          hostPlayerId: 'host',
          clientPlayerId: 'client',
        ),
      ),
    );
  }

  void _desync(String reason) {
    status = reason;
    phase = LotoPhase.over;
    notifyListeners();
  }

  // ---- Голос ведущего ------------------------------------------------------

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    final tts = FlutterTts();
    _tts = tts;
    try {
      await tts.setLanguage('ru-RU');
      // Медленнее обычного: ребёнок должен успевать искать число.
      await tts.setSpeechRate(0.5);
      await tts.setPitch(1);
      await tts.setVolume(1);
      await tts.awaitSpeakCompletion(false);
      await tts.setSharedInstance(true);
    } catch (error, stack) {
      // Нет русского голоса — не повод останавливать игру.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'loto',
          context: ErrorDescription('озвучка чисел'),
        ),
      );
    }
  }

  /// Называет число голосом, если включены и звук, и озвучка.
  void _speakNumber(int number) {
    if (!voiceEnabled) return;
    if (!settings.sound) return;
    unawaited(() async {
      await _ensureTts();
      try {
        await _tts?.stop();
        await _tts?.speak('$number');
      } catch (_) {
        // Синтезатор мог быть уже освобождён системой — игра продолжается.
      }
    }());
  }

  // ---- Утилиты -------------------------------------------------------------

  void _scheduleStatusClear() {
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed) return;
      status = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _rivalTimer?.cancel();
    _statusTimer?.cancel();
    _networkSub?.cancel();
    unawaited(_tts?.stop());
    super.dispose();
  }
}
