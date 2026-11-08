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

/// Режим партии «Билета на поезд».
enum TtrMode { local, computer, network }

/// Кого сейчас ждём на ход: человека на этом устройстве, компьютера или друга
/// по сети. Нужно, чтобы интерфейс показывал правильную подсказку.
enum TtrActive { me, computer, friend, nobody }

/// Одна запись истории партии: кто и что сделал. Текст — готовый, для ленты
/// истории на экране. Список таких записей хранится в контроллере и сбрасывается
/// на новой партии.
@immutable
class TtrMoveRecord {
  const TtrMoveRecord({
    required this.seat,
    required this.text,
    required this.kind,
  });

  /// Чей это был ход: 0 или 1.
  final int seat;

  /// Готовая подпись: «Аня заняла Москва — Тверь (+3)» и так далее.
  final String text;

  /// Тип действия: `claim`, `drawFaceUp`, `drawDeck`, `drawDestinations`,
  /// `keepDestinations`. Нужен, чтобы лента могла раскрасить строку.
  final String kind;

  @override
  String toString() => '[$seat] $text';
}

/// Контроллер партии «Билета на поезд». Содержит состояние, историю, звук и
/// сеть; интерфейс только рисует то, что контроллер ему отдаёт, и зовёт его
/// методы.
///
/// Один и тот же контроллер ведёт партию против компьютера, вдвоём на одном
/// устройстве и по сети: различия собраны в нескольких ветках, а правила
/// общие. По сети хост авторитарный: у него обе руки и колода, он проверяет
/// ходы и рассылает снимки; клиент только показывает снимок и шлёт свои
/// действия.
class TicketToRideController extends ChangeNotifier {
  TicketToRideController({
    required this.settings,
    required this.sounds,
    this.network,
  }) : isHost = network?.isHost ?? false {
    if (network != null) {
      mode = TtrMode.network;
      _networkSub = network!.service.events.listen(_onNetworkEvent);
    }
  }

  final bool isHost;
  final SettingsController settings;
  final GameSounds sounds;
  final NetworkSession? network;
  bool get _isNetwork => mode == TtrMode.network;

  /// Один генератор случайных чисел на всю партию: раздача, ИИ и подсказки.
  final Random _rng = Random();
  static const _rules = TicketToRideRules();

  TtrMode mode = TtrMode.local;
  Difficulty difficulty = Difficulty.medium;

  GameState? _state;
  GameState get state => _state!;
  GameState? get stateOrNull => _state;
  bool get isReady => _state != null;

  bool get isOver => _state?.isOver ?? false;
  int? get winner => _state?.winner;
  bool get isDraw => isOver && winner == null;

  /// Игрок-человек на этом устройстве. В режиме ИИ — место 0; в сети у хоста 0,
  /// у клиента 1; вдвоём на одном устройстве — текущее состояние, чья очередь.
  int get mySeat {
    switch (mode) {
      case TtrMode.local:
        return state.turn;
      case TtrMode.computer:
        return 0;
      case TtrMode.network:
        return isHost ? 0 : 1;
    }
  }

  int get opponentSeat => 1 - mySeat;

  List<TrainCard> get myHand =>
      isReady ? state.players[mySeat].hand : const [];
  List<Destination> get myDestinations =>
      isReady ? state.players[mySeat].destinations : const [];
  int get opponentHandSize =>
      isReady ? state.players[opponentSeat].hand.length : 0;
  int get opponentDestinationsCount =>
      isReady ? state.players[opponentSeat].destinations.length : 0;
  List<TrainCard> get faceUpCards => _state?.faceUpCards ?? const [];
  int get deckCount => _state?.deck.length ?? 0;
  List<Route> get routes => _state?.routes ?? const [];
  int get turn => _state?.turn ?? 0;
  TtrPhase get phase => _state?.phase ?? TtrPhase.main;
  List<Destination> get pendingDestinations =>
      _state?.pendingDestinations ?? const [];
  int get myScore => isReady ? state.players[mySeat].score : 0;
  int get opponentScore => isReady ? state.players[opponentSeat].score : 0;
  int get myTrainsLeft => isReady ? state.players[mySeat].trainsLeft : 0;
  int get opponentTrainsLeft =>
      isReady ? state.players[opponentSeat].trainsLeft : 0;

  /// Чей сейчас ход — для подписи «Твой ход / Ход соперника / Компьютер
  /// думает».
  TtrActive get activeSide {
    if (isOver || !isReady) return TtrActive.nobody;
    switch (mode) {
      case TtrMode.local:
        return TtrActive.me; // оба места за одним устройством
      case TtrMode.computer:
        return state.turn == mySeat ? TtrActive.me : TtrActive.computer;
      case TtrMode.network:
        return state.turn == mySeat ? TtrActive.me : TtrActive.friend;
    }
  }

  String get turnLabel {
    if (fatalMessage != null) return 'Связь потеряна';
    if (isOver) {
      if (isDraw) return 'Ничья!';
      if (mode == TtrMode.local) return 'Партия окончена';
      return winner == mySeat ? 'Ты выиграл!' : 'Партия окончена';
    }
    switch (activeSide) {
      case TtrActive.me:
        return phase == TtrPhase.drawSecond
            ? 'Возьми ещё одну карту'
            : (phase == TtrPhase.choosingDestinations
                ? 'Выбери путешествия'
                : 'Твой ход');
      case TtrActive.computer:
        return 'Компьютер думает…';
      case TtrActive.friend:
        return 'Ходит друг…';
      case TtrActive.nobody:
        return '';
    }
  }

  /// Можно ли взаимодействовать с картой и столом.
  bool get canInteract {
    if (!isReady || isOver || fatalMessage != null) return false;
    if (computerThinking) return false;
    if (_isNetwork && state.turn != mySeat) return false;
    if (mode == TtrMode.computer && state.turn != mySeat) return false;
    return true;
  }

  bool computerThinking = false;
  String? notice;
  String? fatalMessage;
  int? hintedRouteIndex;

  /// Лента хода партии. Каждая запись — это одно действие игрока или
  /// компьютера: текст готов для экрана. История растёт по мере ходов и
  /// сбрасывается в начале новой партии.
  final List<TtrMoveRecord> _history = <TtrMoveRecord>[];
  List<TtrMoveRecord> get history => List.unmodifiable(_history);

  /// Снимки состояний перед каждым действием — для отмены (офлайн и против
  /// компьютера). По сети отмена не работает: у клиента нет чужой руки, чтобы
  /// восстановить позицию, а у хоста нет согласия клиента.
  final List<GameState> _undo = <GameState>[];

  StreamSubscription<NetworkMessage>? _networkSub;
  bool _disposed = false;
  int? _resignedWinner;
  bool _advancing = false;

  // ---- Настройки -----------------------------------------------------------

  bool get hintsEnabled => settings.flag(ticketToRideGameId, 'hints');

  // ---- Старт партий --------------------------------------------------------

  /// Раздаёт карты, путешествия и открытые карты. Общая часть локального и
  /// компьютерного режимов.
  void _deal() {
    final names = mode == TtrMode.local
        ? const ['Игрок 1', 'Игрок 2']
        : [settings.nickname, 'Компьютер'];
    _state = _rules.newGame(random: _rng, playerNames: names);
    _undo.clear();
    _history.clear();
    notice = null;
    fatalMessage = null;
    _resignedWinner = null;
    hintedRouteIndex = null;
    computerThinking = false;
  }

  void startLocal() {
    mode = TtrMode.local;
    _deal();
    notifyListeners();
    unawaited(_advance());
  }

  void startComputer(Difficulty level) {
    mode = TtrMode.computer;
    difficulty = level;
    _deal();
    notifyListeners();
    unawaited(_advance());
  }

  /// Сеть: хост раздаёт и шлёт первый снимок; клиент ждёт.
  void startNetwork() {
    mode = TtrMode.network;
    if (isHost) {
      final names = [settings.nickname, network?.peerName ?? 'Друг'];
      _state = _rules.newGame(random: _rng, playerNames: names);
      _undo.clear();
      _history.clear();
      notice = null;
      fatalMessage = null;
      _resignedWinner = null;
      hintedRouteIndex = null;
      notifyListeners();
      // Небольшая задержка, чтобы клиент успел открыть экран партии и
      // подписаться на события: иначе первый снимок может прийти раньше и
      // потеряться.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (_disposed || !_isNetwork || !isHost) return;
        _broadcastSnapshot();
      });
    } else {
      // Клиент: состояние пришлёт хост первым снимком. Пока покажем заглушку.
      _state = null;
      _history.clear();
      notifyListeners();
    }
  }

  // ---- Действия человека ---------------------------------------------------

  void drawFaceUpCard(int index) {
    if (!canInteract) return;
    if (phase != TtrPhase.main && phase != TtrPhase.drawSecond) return;
    if (index < 0 || index >= faceUpCards.length) return;
    _applyLocalAction(TtrAction.drawFaceUp(index));
  }

  void drawDeckCard() {
    if (!canInteract) return;
    if (phase != TtrPhase.main && phase != TtrPhase.drawSecond) return;
    if (deckCount == 0 && state.discardPile.isEmpty) return;
    _applyLocalAction(const TtrAction.drawDeck());
  }

  void claimRoute(int routeIndex, {int? locomotiveCount}) {
    if (!canInteract) return;
    if (phase != TtrPhase.main) return;
    if (!_rules.canClaimRoute(state, mySeat, routeIndex)) {
      final route = state.routes[routeIndex];
      notice = _explainClaimFail(route);
      hintedRouteIndex = null;
      notifyListeners();
      return;
    }
    // Если игрок передал число локомотивов — дополнительно проверим, что оно
    // укладывается в то, что есть в руке. Правила тоже проверят, но здесь мы
    // можем дать понятное уведомление вместо StateError.
    if (locomotiveCount != null) {
      final route = state.routes[routeIndex];
      final colorCount = myHand.where((c) => c.color == route.color).length;
      final locoCount = myHand
          .where((c) => c.color == CardColor.locomotive)
          .length;
      if (locomotiveCount < 0 || locomotiveCount > locoCount) {
        notice = 'Локомотивов в руке всего $locoCount.';
        notifyListeners();
        return;
      }
      final colorNeeded = route.length - locomotiveCount;
      if (colorNeeded < 0 || colorNeeded > colorCount) {
        notice = 'Не хватит карт: нужно $colorNeeded ${route.color.russianName
            .toLowerCase()}, а есть $colorCount.';
        notifyListeners();
        return;
      }
    }
    _applyLocalAction(
      TtrAction.claim(routeIndex, locomotiveCount: locomotiveCount),
    );
  }

  String _explainClaimFail(Route route) {
    if (route.isClaimed) {
      return 'Маршрут ${route.cityA.russianName} — ${route.cityB.russianName} '
          'уже занят.';
    }
    if (state.players[mySeat].trainsLeft < route.length) {
      return 'Не хватает вагонов: нужно ${route.length}, а осталось '
          '${state.players[mySeat].trainsLeft}.';
    }
    final colorCount = myHand
        .where((c) => c.color == route.color)
        .length;
    final locoCount = myHand
        .where((c) => c.color == CardColor.locomotive)
        .length;
    return 'Не хватает карт: нужно ${route.length} ${route.color.russianName
        .toLowerCase()}, у тебя $colorCount и $locoCount локомотивов.';
  }

  void drawDestinations() {
    if (!canInteract) return;
    if (phase != TtrPhase.main) return;
    if (state.destinationDeck.isEmpty) return;
    _applyLocalAction(const TtrAction.drawDestinations());
  }

  void keepDestinations(List<int> indices) {
    if (!canInteract) return;
    if (phase != TtrPhase.choosingDestinations) return;
    if (indices.isEmpty) {
      notice = 'Оставь хотя бы одно путешествие.';
      notifyListeners();
      return;
    }
    _applyLocalAction(TtrAction.keepDestinations(indices));
  }

  /// Применяет действие локально (или отправляет по сети, если мы клиент).
  /// Звук и продвижение партии — общая часть.
  void _applyLocalAction(TtrAction action) {
    if (!isReady) return;
    final beforeClaim = state;

    if (_isNetwork && !isHost) {
      // Клиент: отправляем действие хосту, ждём снимок.
      try {
        network!.service.send(NetworkMessage('move', actionToJson(action)));
      } catch (_) {
        fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
        notifyListeners();
        return;
      }
      // Подсказка снимается, уведомление чистится — придёт снимок.
      hintedRouteIndex = null;
      notice = null;
      notifyListeners();
      return;
    }

    // Хост, локальный и компьютерный режимы — применяем сами.
    try {
      final before = state;
      final next = _rules.applyAction(before, mySeat, action);
      _undo.add(before);
      _state = next;
      _history.add(_recordFor(action, before, next, before.turn));
      _playActionSound(beforeClaim, next, action);
      hintedRouteIndex = null;
      notice = _noticeForAction(action, beforeClaim, next);
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
        if (_isNetwork && isHost) _broadcastSnapshot();
        return;
      }
      if (_isNetwork && isHost) {
        _broadcastSnapshot();
        return;
      }
      // Локальный и компьютерный режимы: если ход перешёл к компьютеру —
      // просим его подумать. В локальном режиме mySeat всегда совпадает с
      // state.turn, поэтому проверка выше не мешает.
      if (mode == TtrMode.computer &&
          state.turn != mySeat &&
          state.phase == TtrPhase.main) {
        unawaited(_advance());
      }
    } on Object catch (e) {
      if (_isNetwork) {
        _desync(e.toString());
      } else {
        notice = 'Что-то пошло не так: $e';
        notifyListeners();
      }
    }
  }

  /// Звук под действие. Занятие маршрута — `move`; взятие карты — `guess`;
  /// если маршрут замкнул путешествие — добавим `crown`.
  void _playActionSound(GameState before, GameState after, TtrAction action) {
    switch (action.kind) {
      case 'claim':
        sounds.play(GameSound.move);
        final seat = before.turn;
        for (final d in state.players[seat].destinations) {
          if (!_rules.isDestinationCompleted(before, seat, d) &&
              _rules.isDestinationCompleted(after, seat, d)) {
            sounds.play(GameSound.crown);
            break;
          }
        }
      case 'drawFaceUp':
      case 'drawDeck':
      case 'drawDestinations':
      case 'keepDestinations':
        sounds.play(GameSound.guess);
    }
  }

  String? _noticeForAction(TtrAction action, GameState before, GameState after) {
    switch (action.kind) {
      case 'claim':
        final route = before.routes[action.routeIndex!];
        final seat = before.turn;
        final completed = <String>[];
        for (final d in state.players[seat].destinations) {
          if (!_rules.isDestinationCompleted(before, seat, d) &&
              _rules.isDestinationCompleted(after, seat, d)) {
            completed.add('${d.from.russianName} — ${d.to.russianName}');
          }
        }
        if (completed.isEmpty) {
          return 'Маршрут ${route.cityA.russianName} — '
              '${route.cityB.russianName} занят! +${route.points}';
        }
        return 'Маршрут занят! +${route.points}. Завершено путешествие: '
            '${completed.join(", ")}';
      case 'drawFaceUp':
        return null;
      case 'drawDeck':
        return null;
      case 'drawDestinations':
        return 'Выбери, какие путешествия оставить.';
      case 'keepDestinations':
        return 'Путешествия оставлены.';
      default:
        return null;
    }
  }

  /// Готовит одну запись истории для действия [action]. Текст зависит от типа
  /// действия и от того, как поменялось состояние: например, для занятия
  /// маршрута — «занял Москва — Тверь (+3)», для взятия карты — «взял карту».
  /// Имя игрока подставляет сам экран: здесь — только нейтральный текст,
  /// потому что один и тот же контроллер работает и для хоста, и для клиента.
  TtrMoveRecord _recordFor(
    TtrAction action,
    GameState before,
    GameState after,
    int seat,
  ) {
    switch (action.kind) {
      case 'claim':
        final route = before.routes[action.routeIndex!];
        final completed = <String>[];
        for (final d in after.players[seat].destinations) {
          if (!_rules.isDestinationCompleted(before, seat, d) &&
              _rules.isDestinationCompleted(after, seat, d)) {
            completed.add('${d.from.russianName} — ${d.to.russianName}');
          }
        }
        var text = 'занял ${route.cityA.russianName} — '
            '${route.cityB.russianName} (+${route.points})';
        if (completed.isNotEmpty) {
          text += '. Путешествие: ${completed.join(", ")}';
        }
        return TtrMoveRecord(seat: seat, text: text, kind: action.kind);
      case 'drawFaceUp':
        final card = before.faceUpCards[action.faceUpIndex!];
        return TtrMoveRecord(
          seat: seat,
          text: 'взял открытую карту: ${card.color.russianName.toLowerCase()}',
          kind: action.kind,
        );
      case 'drawDeck':
        return TtrMoveRecord(
          seat: seat,
          text: 'взял карту из колоды',
          kind: action.kind,
        );
      case 'drawDestinations':
        return TtrMoveRecord(
          seat: seat,
          text: 'тянет путешествия',
          kind: action.kind,
        );
      case 'keepDestinations':
        final kept = after.players[seat].destinations.length -
            before.players[seat].destinations.length;
        return TtrMoveRecord(
          seat: seat,
          text: 'оставил $kept путешестви${kept == 1 ? "е" : "й"}',
          kind: action.kind,
        );
      default:
        return TtrMoveRecord(seat: seat, text: 'сходил', kind: 'unknown');
    }
  }

  // ---- Продвижение партии: ответ компьютера --------------------------------

  /// Следующий шаг: если ход компьютера — думаем и действуем. В сети хост
  /// продвижением не занимается: клиент сам пришлёт ход.
  Future<void> _advance() async {
    if (_disposed || !isReady || isOver || _isNetwork) return;
    if (_advancing) return;
    _advancing = true;
    try {
      if (mode == TtrMode.computer && state.turn != mySeat) {
        await _computerTurn();
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> _computerTurn() async {
    if (_disposed || isOver) return;
    if (state.turn == mySeat) return;
    computerThinking = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (_disposed || isOver) {
      computerThinking = false;
      notifyListeners();
      return;
    }
    final action = TicketToRideAI.findBestAction(
      state,
      state.turn,
      difficulty,
      _rng,
    );
    if (action == null) {
      computerThinking = false;
      notifyListeners();
      return;
    }
    final before = state;
    final beforeClaim = state;
    try {
      final next = _rules.applyAction(before, state.turn, action);
      _undo.add(before);
      _state = next;
      _history.add(_recordFor(action, before, next, before.turn));
      _playActionSound(beforeClaim, next, action);
      notice = _noticeForAction(action, beforeClaim, next);
      final stillComputer = state.turn != mySeat &&
          state.phase != TtrPhase.over;
      if (isOver) {
        computerThinking = false;
        notifyListeners();
        unawaited(_onWin());
        return;
      }
      computerThinking = false;
      notifyListeners();
      // Если ход остался у компьютера (drawSecond или choosingDestinations) —
      // продолжаем его же ход.
      if (stillComputer) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!_disposed && !isOver && state.turn != mySeat) {
          await _computerTurn();
        }
      }
    } on Object catch (e) {
      computerThinking = false;
      notice = 'Компьютер растерялся: $e';
      notifyListeners();
    }
  }

  // ---- Подсказка -----------------------------------------------------------

  /// Подсвечивает один доступный маршрут, который имеет смысл занять. Не
  /// делает ход за ребёнка — только показывает.
  void showHint() {
    if (!canInteract || !hintsEnabled) return;
    if (phase != TtrPhase.main) {
      notice = phase == TtrPhase.drawSecond
          ? 'Возьми ещё одну карту — ход закончится.'
          : 'Сначала выбери путешествия.';
      hintedRouteIndex = null;
      notifyListeners();
      return;
    }
    final action = TicketToRideAI.findBestAction(
      state,
      mySeat,
      Difficulty.medium,
      _rng,
    );
    if (action == null) {
      notice = 'Ходов нет — возьми карты.';
      hintedRouteIndex = null;
      notifyListeners();
      return;
    }
    if (action.kind == 'claim') {
      hintedRouteIndex = action.routeIndex;
      final route = state.routes[action.routeIndex!];
      notice = 'Попробуй занять ${route.cityA.russianName} — '
          '${route.cityB.russianName} (${route.color.russianName.toLowerCase()}, '
          '${route.length}).';
      notifyListeners();
      return;
    }
    if (action.kind == 'drawDeck') {
      notice = 'Возьми карту из колоды.';
    } else if (action.kind == 'drawFaceUp') {
      final card = state.faceUpCards[action.faceUpIndex!];
      notice = 'Возьми открытую карту: ${card.color.russianName.toLowerCase()}.';
    } else if (action.kind == 'drawDestinations') {
      notice = 'Возьми новые путешествия.';
    } else {
      notice = 'Подумай над путешествиями.';
    }
    hintedRouteIndex = null;
    notifyListeners();
  }

  void clearHint() {
    if (hintedRouteIndex != null) {
      hintedRouteIndex = null;
      notifyListeners();
    }
  }

  // ---- Отмена --------------------------------------------------------------

  bool get canUndo {
    if (isOver) return false;
    if (_isNetwork) return false;
    if (!isReady) return false;
    if (_undo.isEmpty) return false;
    if (mode == TtrMode.computer && state.turn != mySeat) return false;
    return true;
  }

  void undo() {
    if (!canUndo) return;
    if (_undo.isEmpty) return;
    // В режиме ИИ отменяем до своего хода: откатываем сразу два снимка —
    // последний ход компьютера и свой последний ход.
    if (mode == TtrMode.computer && state.turn == mySeat && _undo.length >= 2) {
      _undo.removeLast(); // ход компьютера
      final prev = _undo.removeLast();
      _state = prev;
      // История: снимаем две последние записи — ход компьютера и свой.
      if (_history.length >= 2) {
        _history.removeLast();
        _history.removeLast();
      } else if (_history.isNotEmpty) {
        _history.removeLast();
      }
    } else {
      final prev = _undo.removeLast();
      _state = prev;
      if (_history.isNotEmpty) _history.removeLast();
    }
    hintedRouteIndex = null;
    notice = 'Ход отменён';
    notifyListeners();
  }

  // ---- Сдача ---------------------------------------------------------------

  void resign() {
    if (isOver) return;
    if (mode == TtrMode.local) return;
    _resignedWinner = opponentSeat;
    _markResigned();
    if (_isNetwork) {
      try {
        network!.service.send(const NetworkMessage('resign'));
      } catch (_) {
        // Связь уже могла пропасть — всё равно фиксируем итог.
      }
    }
    unawaited(_onWin());
  }

  /// Помечает состояние партии как оконченное: фаза `over`, победитель —
  /// `_resignedWinner`. Нужно, чтобы экран увидел `isOver` и показал диалог
  /// результата сразу после сдачи, не дожидаясь окончания хода.
  void _markResigned() {
    if (_state == null) return;
    if (_resignedWinner == null) return;
    _state = _state!.copyWith(
      phase: TtrPhase.over,
      winner: _resignedWinner,
    );
    notifyListeners();
  }

  // ---- Победа --------------------------------------------------------------

  Future<void> _onWin() async {
    if (!isOver && _resignedWinner == null) return;
    final draw = _resignedWinner == null && isDraw;
    final iWon = mode == TtrMode.local
        ? true
        : (_resignedWinner != null
              ? _resignedWinner == mySeat
              : winner == mySeat);
    sounds.play(
      resultSoundName(
        draw: draw,
        local: mode == TtrMode.local,
        iWon: iWon,
      ),
    );
    await settings.recordGame(won: iWon || mode == TtrMode.local);
    notifyListeners();
  }

  /// Итоговые очки игрока — для экрана конца партии.
  int finalScore(int seat) =>
      isReady ? _rules.finalScore(state, seat) : 0;

  /// Выполнено ли путешествие игрока [seat].
  bool isDestinationCompleted(int seat, Destination dest) =>
      isReady ? _rules.isDestinationCompleted(state, seat, dest) : false;

  // ---- Имя игрока ----------------------------------------------------------

  String nameFor(int seat) {
    if (!isReady) return seat == 0 ? 'Игрок 1' : 'Игрок 2';
    switch (mode) {
      case TtrMode.local:
        return state.players[seat].name;
      case TtrMode.computer:
        return seat == mySeat ? settings.nickname : 'Компьютер';
      case TtrMode.network:
        if (seat == mySeat) return settings.nickname;
        return network?.peerName ?? 'Друг';
    }
  }

  // ---- Сеть: хост ----------------------------------------------------------

  void _broadcastSnapshot() {
    if (!_isNetwork || !isHost || !isReady) return;
    try {
      network!.service.send(
        NetworkMessage('event', snapshotToJson(state, 1)),
      );
    } catch (_) {
      fatalMessage = 'Связь потеряна. Вернись в меню и попробуй снова.';
      notifyListeners();
    }
  }

  /// Хост получил действие от клиента. Применяет, проверяя правила, и
  /// рассылает снимок. Нелегальный ход — это рассинхрон: обрываем связь.
  void _hostReceiveAction(Map<String, Object?> data) {
    if (!_isNetwork || !isHost || !isReady) return;
    if (state.turn != 1) return; // не клиентский ход
    try {
      final action = parseAction(data);
      final before = state;
      final beforeClaim = state;
      final next = _rules.applyAction(before, 1, action);
      _undo.add(before);
      _state = next;
      _history.add(_recordFor(action, before, next, 1));
      _playActionSound(beforeClaim, next, action);
      notice = _noticeForAction(action, beforeClaim, next);
      hintedRouteIndex = null;
      notifyListeners();
      if (isOver) {
        unawaited(_onWin());
      }
      _broadcastSnapshot();
    } on FormatException catch (e) {
      _desync(e.message.isEmpty ? 'Действие не распознано' : e.message);
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
      hintedRouteIndex = null;
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
          _hostReceiveAction(event.data);
        }
        // Клиент не получает ходы напрямую: только снимки.
        break;
      case 'event':
        final kind = event.data['kind'];
        if (kind == 'snapshot') {
          _clientApplySnapshot(event.data);
        }
        break;
      case 'resign':
        // Соперник сдался — победа за этим устройством.
        _resignedWinner = mySeat;
        _markResigned();
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

  bool canClaimRoute(int routeIndex) =>
      isReady && _rules.canClaimRoute(state, mySeat, routeIndex);

  @override
  void dispose() {
    _disposed = true;
    _networkSub?.cancel();
    super.dispose();
  }
}
