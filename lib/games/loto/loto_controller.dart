import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Режимы партии лото на одном устройстве. Сетевая игра — отдельный режим
/// [LotoMode.network], в который контроллер переходит при получении
/// [NetworkSession].
///
/// Режимы повторяют оригинальное «Лото для Дианы»:
/// * [computerHost] — компьютер сам тянет бочонки и играет за соперника;
/// * [twoPlayers] — две карточки на одном устройстве, бочонки тянет компьютер;
/// * [humanHost] — взрослый тянет бочонки кнопкой, ребёнок закрывает числа;
/// * [network] — хост тянет бочонки и объявляет их всем участникам.
enum LotoMode {
  computerHost(
    title: 'Ведущий-компьютер',
    subtitle: 'Компьютер тянет бочонки и играет за соперника',
  ),
  twoPlayers(
    title: 'Два игрока',
    subtitle: 'Две карточки рядом, бочонки тянет компьютер',
  ),
  humanHost(
    title: 'Ведущий-человек',
    subtitle: 'Бочонки тянет взрослый, ребёнок закрывает числа',
  ),
  network(
    title: 'Игра по Wi-Fi',
    subtitle: 'Хост тянет бочонки и объявляет их всем',
  );

  const LotoMode({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  /// В этом режиме есть компьютерный соперник, который сам закрывает числа.
  bool get hasComputerRival => this == LotoMode.computerHost;

  /// В этом режиме на одном устройстве играют двое: у каждого своя карточка.
  bool get hasSecondCard => this != LotoMode.humanHost;

  /// В этом режиме бочонок достаёт человек, а не таймер.
  bool get needsManualDraw => this == LotoMode.humanHost;
}

/// Фаза партии: идёт или окончена.
enum LotoPhase { playing, over }

/// Идентификатор игрока-человека в одиночной игре. В сетевой хост — `host`,
/// клиент — `client`; в режиме двух игроков — `p1` и `p2`.
const localHostPlayerId = 'me';

/// Всё, что нужно знать перед раздачей карточек.
///
/// Повторяет оригинальный `GameSetup`: режим, режим победы, имена игроков и
/// тайминги компьютерного ведущего. Тесты подставляют свои задержки и
/// фиксированный `seed`, чтобы партия была детерминированной.
class GameSetup {
  const GameSetup({
    required this.mode,
    this.winMode = WinMode.row,
    this.playerName = 'Диана',
    this.opponentName = 'Компьютер',
    this.drawDelay = const Duration(milliseconds: 3800),
    this.rivalReaction = const Duration(milliseconds: 1100),
    this.firstDrawDelay = const Duration(milliseconds: 900),
    this.seed,
  });

  final LotoMode mode;
  final WinMode winMode;
  final String playerName;

  /// Имя второго игрока: компьютерного соперника или соседа по устройству.
  final String opponentName;

  /// Пауза между бочонками у компьютера-ведущего.
  final Duration drawDelay;

  /// Сколько «думает» компьютерный соперник перед закрытием числа.
  final Duration rivalReaction;

  final Duration firstDrawDelay;

  /// Задаётся тестами: с ним карточки и мешок всегда одинаковые.
  final int? seed;

  GameSetup copyWith({
    LotoMode? mode,
    WinMode? winMode,
    String? playerName,
    String? opponentName,
    Duration? drawDelay,
    Duration? rivalReaction,
    Duration? firstDrawDelay,
    int? seed,
  }) => GameSetup(
    mode: mode ?? this.mode,
    winMode: winMode ?? this.winMode,
    playerName: playerName ?? this.playerName,
    opponentName: opponentName ?? this.opponentName,
    drawDelay: drawDelay ?? this.drawDelay,
    rivalReaction: rivalReaction ?? this.rivalReaction,
    firstDrawDelay: firstDrawDelay ?? this.firstDrawDelay,
    seed: seed ?? this.seed,
  );
}

/// Контроллер партии лото. Содержит состояние, историю, звук, голос ведущего
/// и сеть; интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его
/// методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве, с ведущим-человеком и по сети: различия собраны в нескольких
/// ветках, а правила и история общие. Так расхождения между режимами быть не
/// может. Повторяет оригинальный `LotoRoundNotifier`.
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

  LotoMode mode = LotoMode.computerHost;
  LotoPhase phase = LotoPhase.playing;

  /// Режим победы, выбранный на экране старта. У сетевой игры его сообщает
  /// хост в снимке партии.
  WinMode winMode = WinMode.row;

  /// Идентификатор игрока на этом устройстве. В двух-игроках — `p1`, но
  /// тапать можно оба поля; мы держим «своего» только для подсказки и сдачи.
  String myPlayerId = localHostPlayerId;

  /// Текущая раздача. Карточки и мешок — внутри.
  LotoGame game = LotoGame.start(
    players: const [],
    winMode: WinMode.row,
    bag: BarrelBag.empty(),
  );

  /// Настройки текущей партии: режим, имена, тайминги. Нужны для отмены и
  /// новой партии с теми же параметрами.
  GameSetup setup = const GameSetup(mode: LotoMode.computerHost);

  /// Снимки партии на начало каждого вытягивания — для отмены.
  final List<LotoGame> _history = [];

  /// Подсветка кнопки «Подсказка»: какие числа можно закрыть.
  Set<int> _hintHighlight = const <int>{};
  Set<int> get hintHighlight => _hintHighlight;

  /// Короткая подсказка для ребёнка: «Этот бочонок ещё в мешке».
  String? notice;
  bool noticeWarning = false;
  bool get hasNotice => notice != null && notice!.isNotEmpty;

  StreamSubscription<NetworkMessage>? _networkSub;
  Timer? _drawTimer;
  Timer? _rivalTimer;
  Timer? _noticeTimer;
  FlutterTts? _tts;
  bool _ttsReady = false;
  bool _disposed = false;
  bool _recorded = false;
  bool _resultPlayed = false;

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
  bool get started => game.players.isNotEmpty;

  LotoPlayer? get me => game.playerById(myPlayerId);

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

  /// Кнопка «Вытянуть бочонок» в режиме, где ведущий — человек, или в сети
  /// для хоста.
  bool get canDrawManually {
    if (phase != LotoPhase.playing) return false;
    if (game.isBagEmpty || game.players.isEmpty) return false;
    if (mode == LotoMode.network) return isHost;
    return mode.needsManualDraw;
  }

  /// Можно ли вообще играть: партия идёт и не ждёт никого по сети.
  bool get canInteract => phase == LotoPhase.playing && !game.isOver;

  /// Можно ли отменить последний бочонок.
  bool get canUndo {
    if (phase != LotoPhase.playing) return false;
    if (mode == LotoMode.network) return isHost && _history.isNotEmpty;
    return _history.isNotEmpty;
  }

  /// Можно ли сдаться. В режиме двух игроков на одном устройстве сдача
  /// особого смысла не имеет, поэтому кнопки нет.
  bool get canResign =>
      phase == LotoPhase.playing &&
      mode != LotoMode.twoPlayers &&
      mode != LotoMode.humanHost &&
      game.players.isNotEmpty;

  /// Победил ли игрок за этим устройством. В режиме двух игроков всегда true:
  /// кто-то из своих закрыл первым.
  bool get iWon {
    final winner = game.winner;
    if (winner == null) return false;
    if (mode == LotoMode.twoPlayers) return true;
    return winner.id == myPlayerId;
  }

  // ---- Старт партий --------------------------------------------------------

  /// Раздаёт карточки и начинает партию по настрою [setup].
  ///
  /// В сетевом режиме [start] не используется: там хост раздаёт карточки сам,
  /// а клиент ждёт снимок. Для сети предназначен [startNetwork].
  void start(GameSetup setup, {Random? random}) {
    _cancelTimers();
    _history.clear();
    _hintHighlight = const {};
    _recorded = false;
    _resultPlayed = false;
    notice = null;
    noticeWarning = false;
    this.setup = setup;
    mode = setup.mode;
    winMode = setup.winMode;
    myPlayerId = localHostPlayerId;
    phase = LotoPhase.playing;
    final rng = random ?? (setup.seed == null ? Random() : Random(setup.seed));
    final players = <LotoPlayer>[
      LotoPlayer(
        id: localHostPlayerId,
        name: setup.playerName,
        card: LotoCard.generate(random: rng),
        isHost: setup.mode.needsManualDraw,
      ),
      if (setup.mode.hasSecondCard)
        LotoPlayer(
          id: setup.mode.hasComputerRival ? 'rival' : 'friend',
          name: setup.opponentName,
          card: LotoCard.generate(random: rng),
          isComputer: setup.mode.hasComputerRival,
        ),
    ];
    game = LotoGame.start(players: players, winMode: setup.winMode, random: rng);
    sounds.play(GameSound.guess);
    notifyListeners();
    _scheduleDraw(setup.firstDrawDelay);
  }

  /// Новая партия с теми же настройками.
  void restart() {
    if (mode == LotoMode.network) {
      playAgain();
      return;
    }
    start(setup);
  }

  /// Останавливает таймеры, когда экран партии закрыли: компьютер не должен
  /// тянуть бочонки за спиной у ребёнка.
  void stop() {
    _cancelTimers();
  }

  /// Сетевая партия. Хост раздаёт карточки и шлёт клиенту снимок, клиент
  /// ждёт этот снимок, чтобы узнать свою карточку.
  void startNetwork({WinMode? mode}) {
    final winMode = mode ?? this.winMode;
    this.mode = LotoMode.network;
    this.winMode = winMode;
    phase = LotoPhase.playing;
    _history.clear();
    _hintHighlight = const {};
    _recorded = false;
    _resultPlayed = false;
    notice = null;
    noticeWarning = false;
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
      game = LotoGame.start(players: [host, peer], winMode: winMode);
      // Отправляем клиенту снимок — без него он не знает свою карточку.
      // Небольшая задержка, чтобы клиент успел открыть экран и подписаться.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (_disposed || phase != LotoPhase.playing) return;
        _sendSnapshot();
        // После снимка хост начинает авто-вытягивание бочонков — как
        // компьютер-ведущий в локальных режимах. Клиент видит то, что
        // объявил хост.
        _scheduleDraw(setup.firstDrawDelay);
      });
    } else {
      myPlayerId = 'client';
      // Снимок придёт сообщением `event` — пока покажем заглушку.
      game = LotoGame.start(
        players: const [],
        winMode: winMode,
        bag: BarrelBag.empty(),
      );
      notice = 'Ждём, пока ведущий раздаст карточки…';
    }
    notifyListeners();
  }

  /// Новая партия (для экрана «Играть снова» и сетевой «Ещё партия»).
  void playAgain() {
    _rivalTimer?.cancel();
    _noticeTimer?.cancel();
    _hintHighlight = const {};
    notice = null;
    noticeWarning = false;
    _recorded = false;
    _resultPlayed = false;
    phase = LotoPhase.playing;
    if (mode == LotoMode.network) {
      if (isHost) {
        startNetwork(mode: winMode);
      } else {
        // Клиент ждёт нового снимка от хоста.
        game = LotoGame.start(
          players: const [],
          winMode: winMode,
          bag: BarrelBag.empty(),
        );
        notice = 'Ждём, пока ведущий начнёт новую партию…';
        notifyListeners();
      }
      return;
    }
    start(setup);
  }

  // ---- Вытянуть бочонок -----------------------------------------------------

  /// Вытянуть следующий бочонок. В сети это делает только хост; в режиме
  /// ведущего-человека — взрослый кнопкой. В компьютерных режимах бочонок
  /// достаёт таймер, но кнопку тоже оставляем — иногда хочется поторопить.
  void drawBarrel() {
    if (phase != LotoPhase.playing) return;
    if (game.isOver || game.isBagEmpty) return;
    if (mode == LotoMode.network && !isHost) return;
    _drawNow();
  }

  void _drawNow() {
    _cancelDrawTimer();
    _history.add(game);
    game = game.draw();
    final barrel = game.lastBarrel;
    _hintHighlight = const {};
    notice = null;
    noticeWarning = false;
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
      notice = 'Бочонки закончились — закрой последнее число!';
      _scheduleNoticeClear();
      notifyListeners();
    }
    _reactForRival(barrel);
    _afterMove();
  }

  // ---- Закрыть число --------------------------------------------------------

  /// Закрыть число на карточке игрока [playerId] (или на своей, если не
  /// указан). В сети закрывает только свою карточку: клиент отправляет `move`
  /// хосту, хост проверяет и рассылает подтверждение.
  void close({required String playerId, required int number}) {
    if (phase != LotoPhase.playing) return;
    if (mode == LotoMode.network) {
      if (playerId != myPlayerId) return;
      if (isHost) {
        _hostApplyClose(myPlayerId, number);
      } else {
        network!.service.send(
          NetworkMessage('move', closeNumberToJson(myPlayerId, number)),
        );
      }
      return;
    }
    _applyLocalClose(playerId, number);
  }

  /// Закрывает число на своей карточке.
  void closeMine(int number) =>
      close(playerId: myPlayerId, number: number);

  void _applyLocalClose(String playerId, int number) {
    final before = game.playerById(playerId);
    final outcome = game.close(playerId: playerId, number: number);
    if (!outcome.accepted) {
      notice = outcome.status.hint.isEmpty
          ? 'Так закрыть нельзя'
          : outcome.status.hint;
      noticeWarning = true;
      sounds.play(GameSound.miss);
      _scheduleNoticeClear();
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
    notice = null;
    noticeWarning = false;
    if (game.isOver) {
      _onWin(playerId);
    } else {
      notifyListeners();
      _afterMove();
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
      // После закрытия числа кем-либо из игроков хост может снова тянуть
      // бочонок: возможно, это закрытие разблокировало авто-вытягивание,
      // которое ждало, пока человек закроет свой бочонок.
      _afterMove();
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
  void _reactForRival(Barrel? barrel) {
    _rivalTimer?.cancel();
    if (barrel == null || game.isOver) return;
    if (mode != LotoMode.computerHost) return;
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
    _rivalTimer = Timer(setup.rivalReaction, () {
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
        _afterMove();
      }
    });
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Кнопка «Подсказка»: подсвечивает числа, которые можно закрыть. Повторный
  /// тап гасит подсветку.
  void toggleHint() {
    if (phase != LotoPhase.playing) return;
    if (_hintHighlight.isNotEmpty) {
      _hintHighlight = const {};
      notice = null;
      notifyListeners();
      return;
    }
    final numbers = myClosable;
    _hintHighlight = Set<int>.unmodifiable(numbers);
    noticeWarning = false;
    notice = numbers.isEmpty
        ? 'Пока закрывать нечего — ждём подходящий бочонок'
        : 'Можно закрыть: ${numbers.join(', ')}';
    _scheduleNoticeClear();
    notifyListeners();
  }

  // ---- Отмена хода ---------------------------------------------------------

  /// Отменить последний вытянутый бочонок. В сети это может только хост: он
  /// откатывает своё состояние и рассылает новый снимок.
  void undo() {
    if (!canUndo) return;
    _rivalTimer?.cancel();
    if (mode == LotoMode.network) {
      final previous = _history.removeLast();
      game = previous;
      notice = 'Ход отменён';
      noticeWarning = false;
      _hintHighlight = const {};
      _sendSnapshot();
      notifyListeners();
      return;
    }
    final previous = _history.removeLast();
    game = previous;
    _hintHighlight = const {};
    notice = 'Ход отменён — бочонок вернулся в мешок';
    noticeWarning = false;
    sounds.play(GameSound.move);
    _scheduleNoticeClear();
    notifyListeners();
  }

  // ---- Сдача ---------------------------------------------------------------

  /// Сдаться. Победа достаётся сопернику.
  void resign() {
    if (!canResign) return;
    String winnerId;
    if (mode == LotoMode.network) {
      network!.service.send(const NetworkMessage('resign'));
      winnerId = myPlayerId == 'host' ? 'client' : 'host';
    } else {
      // computer mode — соперник выигрывает
      winnerId = 'rival';
    }
    game = game.declareWinner(winnerId);
    _onWin(winnerId, byResign: true);
  }

  // ---- Победа и общие последствия хода ------------------------------------

  /// Общие последствия хода: победа, конец мешка или следующий бочонок.
  void _afterMove() {
    if (_disposed || phase != LotoPhase.playing) return;
    if (game.isOver) {
      _cancelTimers();
      return;
    }
    if (game.isBagEmpty) {
      _cancelTimers();
      return;
    }
    _scheduleDraw(setup.drawDelay);
  }

  void _onWin(String winnerId, {bool byResign = false}) {
    phase = LotoPhase.over;
    final winner = game.playerById(winnerId);
    final isMe = winnerId == myPlayerId;
    final local = mode != LotoMode.network;
    // В режиме двух игроков всегда «выиграл человек на этом устройстве» —
    // результат в статистику пишем как победу.
    final iWon = mode == LotoMode.twoPlayers ? true : isMe;
    if (!_resultPlayed) {
      _resultPlayed = true;
      sounds.play(
        resultSoundName(draw: false, local: local, iWon: iWon),
      );
    }
    if (!_recorded) {
      _recorded = true;
      unawaited(settings.recordGame(won: iWon || mode == LotoMode.twoPlayers));
    }
    notice = null;
    _hintHighlight = const {};
    notifyListeners();
    // `winner` и `byResign` нужны будущему голосовому поздравлению; сейчас
    // победитель виден на экране без них.
    if (winner != null && byResign) {
      // Сдача — без дополнительных эффектов.
    }
  }

  void _scheduleDraw(Duration delay) {
    _cancelDrawTimer();
    if (_disposed) return;
    if (mode.needsManualDraw) return;
    // В сети хост — ведущий: он тянет бочонки и автоматически (как
    // компьютер в локальных режимах), и кнопкой (если хочется поторопить).
    // Клиент лишь показывает то, что объявил хост.
    if (mode == LotoMode.network && !isHost) return;
    if (game.players.isEmpty || game.isOver || game.isBagEmpty) return;
    // Пока компьютерный соперник не закрыл свой бочонок, новый не тянем.
    if (_rivalTimer?.isActive ?? false) return;
    // И ждём ребёнка: он должен успеть закрыть своё число.
    if (game.pendingClosers.any((player) => !player.isComputer)) return;
    _drawTimer = Timer(delay, _drawNow);
  }

  void _scheduleNoticeClear() {
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed) return;
      notice = null;
      notifyListeners();
    });
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
        notice = 'Связь потеряна. Проверь Wi-Fi и попробуй снова.';
        noticeWarning = true;
        phase = LotoPhase.over;
        notifyListeners();
      case 'desync':
        _desync('Партия рассинхронизировалась');
      case 'error':
        final msg = message.data['message'];
        notice = msg is String ? msg : 'Связь потеряна';
        noticeWarning = true;
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
        notice = null;
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
          notice = parsed.reason ?? 'Так закрыть нельзя';
          noticeWarning = true;
          _scheduleNoticeClear();
          notifyListeners();
        }
      } else if (kind == 'snapshot') {
        final snap = parseSnapshot(data);
        game = snap.game;
        winMode = snap.game.winMode;
        myPlayerId = isHost ? snap.hostPlayerId : snap.clientPlayerId;
        _hintHighlight = const {};
        notice = null;
        _resultPlayed = false;
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
    notice = reason;
    noticeWarning = true;
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

  void _cancelDrawTimer() {
    _drawTimer?.cancel();
    _drawTimer = null;
  }

  void _cancelTimers() {
    _cancelDrawTimer();
    _rivalTimer?.cancel();
    _rivalTimer = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    _networkSub?.cancel();
    final tts = _tts;
    if (tts != null) {
      // TTS может быть недоступен (в тестах): глушим ошибки, чтобы dispose
      // всегда завершался тихо.
      unawaited(
        () async {
          try {
            await tts.stop();
          } catch (_) {
            // Синтезатор мог быть уже освобождён или недоступен.
          }
        }(),
      );
    }
    super.dispose();
  }
}
