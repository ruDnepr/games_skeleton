import 'dart:math' as math;

import 'package:flutter/material.dart' hide Route;

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/games_page.dart' show popToGamesList;
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/board.dart';
import 'engine/model.dart';
import 'ticket_to_ride_controller.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети, без него
/// — выбор режима (против компьютера или вдвоём на одном устройстве).
class TicketToRideEntryPage extends StatelessWidget {
  const TicketToRideEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return TicketToRideSessionPage(settings: settings, network: network);
    }
    return TicketToRideModePage(settings: settings);
  }
}

/// Выбор режима: против компьютера (с уровнем) или вдвоём на одном устройстве.
class TicketToRideModePage extends StatefulWidget {
  const TicketToRideModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<TicketToRideModePage> createState() => _TicketToRideModePageState();
}

class _TicketToRideModePageState extends State<TicketToRideModePage> {
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Билет на поезд',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
          title: 'С кем сыграем?',
          subtitle: 'Можно тренироваться с компьютером или играть вдвоём '
              'на одном устройстве.',
        ),
        const SizedBox(height: 22),
        _ModeTile(
          title: 'Против компьютера',
          subtitle: 'Три уровня сложности — от лёгкого до сложного',
          icon: Icons.smart_toy_rounded,
          color: const Color(0xFFEDE6FF),
          selected: _vsAi,
          onTap: () => setState(() => _vsAi = true),
        ),
        if (_vsAi) ...[
          const SizedBox(height: 14),
          const Text(
            'Уровень сложности',
            style: TextStyle(fontWeight: FontWeight.w900, color: ink),
          ),
          const SizedBox(height: 8),
          _DifficultyRow(
            value: _difficulty,
            onChanged: (d) => setState(() => _difficulty = d),
          ),
        ],
        const SizedBox(height: 14),
        _ModeTile(
          title: 'Двое на одном устройстве',
          subtitle: 'Ходы по очереди — карта одна на двоих',
          icon: Icons.people_rounded,
          color: const Color(0xFFDDF1DF),
          selected: !_vsAi,
          onTap: () => setState(() => _vsAi = false),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            key: const Key('ticket-to-ride-start'),
            onPressed: () => _start(context),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Начать партию'),
          ),
        ),
      ],
    ),
  );

  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TicketToRideSessionPage(
          settings: widget.settings,
          vsAi: _vsAi,
          difficulty: _difficulty,
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: selected ? purple : const Color(0xFFF2EAE3),
        width: selected ? 2 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: ink, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? purple : const Color(0xFFC7BDCA),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({required this.value, required this.onChanged});
  final Difficulty value;
  final ValueChanged<Difficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: Difficulty.values[i].label,
              desc: Difficulty.values[i].hint,
              selected: value.index == i,
              onTap: () => onChanged(Difficulty.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? purple : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? purple : const Color(0xFFE3D8F5)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : ink,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white.withValues(alpha: .85) : muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Экран партии: сверху — соперник, в центре — карта России, снизу —
/// открытые карты, колода, моя рука и мои путешествия.
class TicketToRideSessionPage extends StatefulWidget {
  const TicketToRideSessionPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.network,
    this.controller,
  });
  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final NetworkSession? network;

  /// Внешний контроллер — для тестов. Если `null`, страница создаёт и
  /// уничтожает свой собственный. Если передан — страница его использует,
  /// но не уничтожает: это забота того, кто передал.
  final TicketToRideController? controller;

  @override
  State<TicketToRideSessionPage> createState() =>
      _TicketToRideSessionPageState();
}

class _TicketToRideSessionPageState extends State<TicketToRideSessionPage> {
  late final TicketToRideController _controller;
  bool _ownedController = false;
  bool _overShown = false;
  bool _destinationsShown = false;
  // Фаза выбора путешествий в предыдущем кадре. Нужна, чтобы показывать диалог
  // ровно один раз на переход: иначе после отправки действия контроллер звал
  // `notifyListeners`, фаза ещё не сменилась, и диалог всплывал бы снова.
  bool _wasChoosingDestinations = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      final sounds = GameSounds(widget.settings);
      _controller = TicketToRideController(
        settings: widget.settings,
        sounds: sounds,
        network: widget.network,
      );
      _ownedController = true;
    }
    if (widget.network != null) {
      _controller.startNetwork();
    } else if (widget.vsAi) {
      _controller.startComputer(widget.difficulty);
    } else {
      _controller.startLocal();
    }
  }

  @override
  void dispose() {
    if (_ownedController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _maybeShowOver() {
    if (_controller.isOver && !_overShown && _controller.fatalMessage == null) {
      _overShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverDialog());
    } else if (_controller.fatalMessage != null && !_overShown) {
      _overShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFatalDialog());
    }
    // Показываем диалог выбора путешествий ровно на переходе в фазу
    // `choosingDestinations`, и только если ход моего устройства.
    final choosingNow = _controller.phase == TtrPhase.choosingDestinations &&
        _controller.canInteract;
    if (choosingNow && !_wasChoosingDestinations && !_destinationsShown) {
      // Флаг `_destinationsShown` ставится уже внутри `_showDestinations`,
      // когда диалог действительно открылся. Здесь мы только планируем показ.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDestinations());
    }
    _wasChoosingDestinations = choosingNow;
  }

  void _showDestinations() {
    if (!mounted) return;
    if (_controller.phase != TtrPhase.choosingDestinations) return;
    if (!_controller.canInteract) return;
    if (_destinationsShown) return;
    _destinationsShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DestinationsDialog(
        controller: _controller,
        onClose: () {
          _destinationsShown = false;
          Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  void _showOverDialog() {
    if (!mounted) return;
    final draw = _controller.isDraw;
    final iWon = _controller.mode == TtrMode.local
        ? true
        : _controller.winner == _controller.mySeat;
    final winner = _controller.winner;
    String title;
    if (draw) {
      title = 'Ничья!';
    } else if (_controller.mode == TtrMode.local) {
      title = winner != null
          ? '${_controller.nameFor(winner)} победил!'
          : 'Партия окончена';
    } else {
      title = iWon ? 'Ты выиграл! 🎉' : 'Партия окончена';
    }
    final myScore = _controller.finalScore(_controller.mySeat);
    final oppScore = _controller.finalScore(_controller.opponentSeat);
    final myRoutes = _controller.state.players[_controller.mySeat].score;
    final oppRoutes = _controller.state.players[_controller.opponentSeat].score;
    final myDestBonus = myScore - myRoutes;
    final oppDestBonus = oppScore - oppRoutes;
    showDianaDialog<_OverChoice>(
      context: context,
      title: title,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Маршруты + путешествия = итог. Кто больше — тот победил.',
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
          const SizedBox(height: 14),
          _ScoreTable(
            myName: _controller.nameFor(_controller.mySeat),
            oppName: _controller.nameFor(_controller.opponentSeat),
            myRoutes: myRoutes,
            oppRoutes: oppRoutes,
            myDestBonus: myDestBonus,
            oppDestBonus: oppDestBonus,
            myTotal: myScore,
            oppTotal: oppScore,
            iWon: iWon,
            draw: draw,
          ),
        ],
      ),
      actions: [
        if (widget.network == null)
          const DianaDialogButton<_OverChoice>(
            label: 'Играть снова',
            value: _OverChoice.again,
            primary: true,
          ),
        const DianaDialogButton<_OverChoice>(
          label: 'В меню',
          value: _OverChoice.home,
        ),
      ],
    ).then((choice) {
      if (!mounted) return;
      if (choice == _OverChoice.again && widget.network == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => TicketToRideSessionPage(
              settings: widget.settings,
              vsAi: widget.vsAi,
              difficulty: widget.difficulty,
            ),
          ),
        );
      } else if (choice == _OverChoice.home || widget.network != null) {
        popToGamesList(context);
      }
    });
  }

  void _showFatalDialog() {
    if (!mounted) return;
    showDianaDialog<void>(
      context: context,
      title: 'Ой, что-то случилось',
      barrierDismissible: false,
      content: Text(
        _controller.fatalMessage ?? 'Связь потеряна.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<void>(label: 'В меню', value: null, primary: true),
      ],
    ).then((_) {
      if (mounted) {
        popToGamesList(context);
      }
    });
  }

  void _confirmResign() {
    showDianaDialog<bool>(
      context: context,
      title: 'Сдаться?',
      content: const Text(
        'Партия закончится, победа достанется сопернику.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(
          label: 'Не сдаваться',
          value: false,
          primary: true,
        ),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) _controller.resign();
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowOver();
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Билет на поезд'),
        ),
        actions: [
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => IconButton(
              tooltip: widget.settings.sound
                  ? 'Выключить звук'
                  : 'Включить звук',
              onPressed: () =>
                  widget.settings.setSound(!widget.settings.sound),
              icon: Icon(
                widget.settings.sound
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: purple,
              ),
            ),
          ),
          if (_controller.mode != TtrMode.local)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Сдаться',
              onPressed: _controller.isOver ? null : _confirmResign,
            ),
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'В меню',
            onPressed: () => popToGamesList(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  if (!_controller.isReady) {
                    return const _WaitingPane(
                      message: 'Ждём друга — партия вот-вот начнётся…',
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _opponentPanel(),
                        const SizedBox(height: 6),
                        _turnBanner(),
                        const SizedBox(height: 6),
                        Expanded(
                          child: _mapArea(),
                        ),
                        const SizedBox(height: 6),
                        _cardRow(),
                        const SizedBox(height: 6),
                        _myPanel(),
                        const SizedBox(height: 6),
                        _handRow(),
                        const SizedBox(height: 6),
                        _destinationsRow(),
                        const SizedBox(height: 6),
                        _bottomBar(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Верхняя панель соперника -------------------------------------------

  Widget _opponentPanel() {
    final name = _controller.nameFor(_controller.opponentSeat);
    final trains = _controller.opponentTrainsLeft;
    final score = _controller.opponentScore;
    final destCount = _controller.opponentDestinationsCount;
    final active = _controller.activeSide == TtrActive.friend ||
        _controller.activeSide == TtrActive.computer;
    return _PlayerPanel(
      key: const Key('opponent-panel'),
      name: name,
      trains: trains,
      score: score,
      destinations: destCount,
      active: active,
      avatarColor: yellow,
      avatarIcon: Icons.person_rounded,
      activeLabel: 'ХОД',
    );
  }

  // ---- Панель игрока на этом устройстве -----------------------------------

  Widget _myPanel() {
    final name = _controller.nameFor(_controller.mySeat);
    final trains = _controller.myTrainsLeft;
    final score = _controller.myScore;
    final destCount = _controller.myDestinations.length;
    final active = _controller.activeSide == TtrActive.me;
    return _PlayerPanel(
      key: const Key('my-panel'),
      name: name,
      trains: trains,
      score: score,
      destinations: destCount,
      active: active,
      avatarColor: purple,
      avatarIcon: Icons.person_rounded,
      activeLabel: 'МОЙ ХОД',
      highlightAvatar: true,
    );
  }

  // ---- Баннер хода --------------------------------------------------------

  Widget _turnBanner() {
    final label = _controller.turnLabel;
    final isMyTurn = _controller.activeSide == TtrActive.me;
    final notice = _controller.notice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isMyTurn ? purple : Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isMyTurn
                ? Icons.play_arrow_rounded
                : Icons.hourglass_top_rounded,
            color: isMyTurn ? Colors.white : ink,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isMyTurn ? Colors.white : ink,
                    ),
                  ),
                ),
                // Резервируем место под подсказку всегда — баннер хода не
                // меняет высоту при появлении/исчезновении замечания.
                Visibility(
                  visible: notice != null && notice.isNotEmpty,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      notice ?? '',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isMyTurn
                            ? Colors.white.withValues(alpha: .85)
                            : muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Карта ---------------------------------------------------------------

  Widget _mapArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (details) => _handleMapTap(details.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: const Color(0xFFFFFBF1),
              child: CustomPaint(
                size: size,
                painter: _MapPainter(
                  state: _controller.state,
                  mySeat: _controller.mySeat,
                  hintsEnabled: _controller.hintsEnabled,
                  canClaim: _controller.canClaimRoute,
                  hintedRouteIndex: _controller.hintedRouteIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleMapTap(Offset local, Size size) {
    if (!_controller.canInteract) return;
    if (_controller.phase != TtrPhase.main) return;
    final tap = _MapPoint(local.dx, local.dy);
    final routeIndex = _hitTestRoute(tap, size);
    if (routeIndex == null) return;
    _attemptClaim(routeIndex);
  }

  /// Пробует занять маршрут. Если у игрока есть выбор, сколько локомотивов
  /// потратить, — открывает диалог. Если выбора нет (например, локомотивов
  /// ноль или цветных карт ровно столько, сколько нужно) — занимает сразу.
  void _attemptClaim(int routeIndex) {
    if (!_controller.canInteract) return;
    if (_controller.phase != TtrPhase.main) return;
    if (!_controller.canClaimRoute(routeIndex)) {
      // Контроллер сам поднимет понятное уведомление.
      _controller.claimRoute(routeIndex);
      return;
    }
    final route = _controller.routes[routeIndex];
    final hand = _controller.myHand;
    final colorCount = hand.where((c) => c.color == route.color).length;
    final locoCount = hand
        .where((c) => c.color == CardColor.locomotive)
        .length;
    final minLoco = (route.length - colorCount).clamp(0, route.length);
    final maxLoco = locoCount.clamp(0, route.length);
    if (minLoco >= maxLoco) {
      // Выбора нет — занимаем сразу с единственно возможным числом локомотивов.
      _controller.claimRoute(routeIndex, locomotiveCount: minLoco);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ClaimRouteDialog(
        controller: _controller,
        routeIndex: routeIndex,
        minLocomotives: minLoco,
        maxLocomotives: maxLoco,
        onConfirm: (locoCount) {
          Navigator.of(dialogContext).pop();
          _controller.claimRoute(routeIndex, locomotiveCount: locoCount);
        },
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  int? _hitTestRoute(_MapPoint tap, Size size) {
    int? best;
    var bestDist = 28.0; // пиксели — радиус тапа вокруг линии
    for (var i = 0; i < _controller.routes.length; i++) {
      final route = _controller.routes[i];
      final a = cityPositions[route.cityA]!;
      final b = cityPositions[route.cityB]!;
      final ax = a.x * size.width;
      final ay = a.y * size.height;
      final bx = b.x * size.width;
      final by = b.y * size.height;
      final dist = _distanceToSegment(tap, ax, ay, bx, by);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  double _distanceToSegment(
    _MapPoint p,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      return math.sqrt((p.x - ax) * (p.x - ax) + (p.y - ay) * (p.y - ay));
    }
    var t = ((p.x - ax) * dx + (p.y - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
  }

  // ---- Открытые карты и колода --------------------------------------------

  Widget _cardRow() {
    final faceUp = _controller.faceUpCards;
    final deckCount = _controller.deckCount;
    final canDraw = _controller.canInteract &&
        (_controller.phase == TtrPhase.main ||
            _controller.phase == TtrPhase.drawSecond);
    final isSecondDraw = _controller.phase == TtrPhase.drawSecond;
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: i < faceUp.length
                  ? _FaceUpCard(
                      card: faceUp[i],
                      onTap: canDraw ? () => _controller.drawFaceUpCard(i) : null,
                      disabled: isSecondDraw &&
                          faceUp[i].color == CardColor.locomotive,
                    )
                  : _EmptyCard(),
            ),
          ],
          const SizedBox(width: 6),
          GestureDetector(
            onTap: canDraw && deckCount > 0
                ? _controller.drawDeckCard
                : null,
            child: _DeckCard(count: deckCount),
          ),
        ],
      ),
    );
  }

  // ---- Моя рука -----------------------------------------------------------

  Widget _handRow() {
    final hand = _controller.myHand;
    final byColor = <CardColor, int>{};
    for (final card in hand) {
      byColor[card.color] = (byColor[card.color] ?? 0) + 1;
    }
    final order = const [
      CardColor.locomotive,
      CardColor.red,
      CardColor.blue,
      CardColor.green,
    ];
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1EAE5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pan_tool_rounded, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: hand.isEmpty
                ? const Text(
                    'В руке пусто — возьми карту',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final color in order)
                        if (byColor[color] != null) ...[
                          if (byColor[color]! > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _HandCardGroup(
                                color: color,
                                count: byColor[color]!,
                              ),
                            ),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---- Мои путешествия ----------------------------------------------------

  Widget _destinationsRow() {
    final dests = _controller.myDestinations;
    // Высота строки путешествий зафиксирована: даже когда путешествий ещё нет,
    // место под них зарезервировано — карта не «прыгает» при их появлении.
    return SizedBox(
      height: 56,
      child: dests.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final dest in dests)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _DestinationChip(
                      destination: dest,
                      completed: _controller.isDestinationCompleted(
                        _controller.mySeat,
                        dest,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ---- Нижняя панель кнопок -----------------------------------------------

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: Row(
        children: [
          Expanded(
            child: _CtrlButton(
              key: const Key('ttr-undo'),
              icon: Icons.undo_rounded,
              label: 'Отменить',
              enabled: _controller.canUndo,
              onTap: _controller.undo,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _CtrlButton(
              key: const Key('ttr-hint'),
              icon: Icons.lightbulb_rounded,
              label: 'Подсказать',
              enabled: _controller.hintsEnabled &&
                  _controller.canInteract &&
                  _controller.phase == TtrPhase.main,
              onTap: _controller.showHint,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _CtrlButton(
              key: const Key('ttr-destinations'),
              icon: Icons.card_giftcard_rounded,
              label: 'Путешествия',
              enabled: _controller.canInteract &&
                  _controller.phase == TtrPhase.main &&
                  _controller.state.destinationDeck.isNotEmpty,
              onTap: _controller.drawDestinations,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _CtrlButton(
              key: const Key('ttr-history'),
              icon: Icons.history_rounded,
              label: 'История',
              enabled: _controller.history.isNotEmpty,
              onTap: _showHistory,
            ),
          ),
        ],
      ),
    );
  }

  void _showHistory() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _HistoryDialog(
        controller: _controller,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }
}

// ---- Карта: CustomPainter --------------------------------------------------

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.state,
    required this.mySeat,
    required this.hintsEnabled,
    required this.canClaim,
    required this.hintedRouteIndex,
  });

  final GameState state;
  final int mySeat;
  final bool hintsEnabled;
  final bool Function(int) canClaim;
  final int? hintedRouteIndex;

  @override
  void paint(Canvas canvas, Size size) {
    // Фон карты: мягкий градиент, как пергамент.
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFFFFBF1), Color(0xFFF6EEDB)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Сначала рисуем все маршруты, потом — города поверх.
    for (var i = 0; i < state.routes.length; i++) {
      _drawRoute(canvas, size, i, state.routes[i]);
    }
    for (final city in City.values) {
      _drawCity(canvas, size, city);
    }
  }

  void _drawRoute(Canvas canvas, Size size, int index, Route route) {
    final a = cityPositions[route.cityA]!;
    final b = cityPositions[route.cityB]!;
    final ax = a.x * size.width;
    final ay = a.y * size.height;
    final bx = b.x * size.width;
    final by = b.y * size.height;

    final isHinted = index == hintedRouteIndex;
    final claimable = hintsEnabled && route.claimedBy == null && canClaim(index);

    Color color;
    if (route.claimedBy == 0) {
      color = purple;
    } else if (route.claimedBy == 1) {
      color = yellow;
    } else {
      color = _routeColor(route.color);
    }

    // Подсветка-обводка для доступных маршрутов и подсказки.
    if (isHinted || claimable) {
      final glow = Paint()
        ..color = (isHinted ? yellow : purple).withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHinted ? 22 : 16
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), glow);
    }

    // Тень/обводка линии маршрута.
    final outline = Paint()
      ..color = const Color(0xFF3D3154).withValues(alpha: .25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(ax, ay), Offset(bx, by), outline);

    // Сама линия маршрута: цветная, если свободна; цветом игрока — если занята.
    final line = Paint()
      ..color = route.claimedBy == null
          ? color.withValues(alpha: .85)
          : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(ax, ay), Offset(bx, by), line);

    // Вагончики вдоль линии: маленькие кружки, по числу длины маршрута.
    final dx = (bx - ax) / (route.length + 1);
    final dy = (by - ay) / (route.length + 1);
    final carPaint = Paint()
      ..color = route.claimedBy == null
          ? Colors.white.withValues(alpha: .85)
          : Colors.white.withValues(alpha: .95)
      ..style = PaintingStyle.fill;
    final carOutline = Paint()
      ..color = const Color(0xFF3D3154).withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 1; i <= route.length; i++) {
      final cx = ax + dx * i;
      final cy = ay + dy * i;
      canvas.drawCircle(Offset(cx, cy), 5, carPaint);
      canvas.drawCircle(Offset(cx, cy), 5, carOutline);
    }
  }

  Color _routeColor(CardColor color) {
    return switch (color) {
      CardColor.red => const Color(0xFFE15554),
      CardColor.blue => const Color(0xFF3D7EA6),
      CardColor.green => const Color(0xFF4DAA57),
      CardColor.locomotive => const Color(0xFF8B8298),
    };
  }

  void _drawCity(Canvas canvas, Size size, City city) {
    final pos = cityPositions[city]!;
    final cx = pos.x * size.width;
    final cy = pos.y * size.height;
    // Тень-капля.
    final shadow = Paint()
      ..color = const Color(0xFF3D3154).withValues(alpha: .18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy + 3), 17, shadow);
    // Сам кружок города.
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset(cx, cy), 17, fill);
    canvas.drawCircle(Offset(cx, cy), 17, outline);
    // Иконка поезда в центре города.
    final dot = Paint()
      ..color = purple
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 5, dot);
    // Подпись города.
    final textSpan = TextSpan(
      text: city.russianName,
      style: const TextStyle(
        color: ink,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        fontFamily: 'Nunito',
      ),
    );
    final painter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    // Подпись помещаем в рамке для читаемости поверх карты.
    final boxW = painter.width + 12;
    final boxH = painter.height + 6;
    final boxLeft = cx - boxW / 2;
    final boxTop = cy + 22;
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.fill;
    final bgOutline = Paint()
      ..color = purple.withValues(alpha: .3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(boxLeft, boxTop, boxW, boxH),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, bgPaint);
    canvas.drawRRect(rect, bgOutline);
    painter.paint(
      canvas,
      Offset(boxLeft + 6, boxTop + 3),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.state != state ||
      old.mySeat != mySeat ||
      old.hintsEnabled != hintsEnabled ||
      old.hintedRouteIndex != hintedRouteIndex;
}

// ---- Карточки в нижнем ряду ------------------------------------------------

class _FaceUpCard extends StatelessWidget {
  const _FaceUpCard({
    required this.card,
    required this.onTap,
    required this.disabled,
  });
  final TrainCard card;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = _cardColor(card.color);
    final isLoco = card.color == CardColor.locomotive;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: .6),
                width: 2,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    isLoco
                        ? Icons.local_fire_department_rounded
                        : Icons.train_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 3,
                  child: Text(
                    isLoco ? '★' : '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.white.withValues(alpha: .5),
        width: 2,
      ),
    ),
    child: const Center(
      child: Icon(Icons.remove, color: muted, size: 20),
    ),
  );
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [deepPurple, purple],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.white.withValues(alpha: .5),
        width: 2,
      ),
    ),
    child: Stack(
      children: [
        const Center(
          child: Icon(Icons.train_rounded, color: Colors.white, size: 26),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 4,
          child: Text(
            '×$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _HandCardGroup extends StatelessWidget {
  const _HandCardGroup({required this.color, required this.count});
  final CardColor color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = _cardColor(color);
    final isLoco = color == CardColor.locomotive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: .6),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLoco
                ? Icons.local_fire_department_rounded
                : Icons.train_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '×$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Color _cardColor(CardColor color) {
  return switch (color) {
    CardColor.red => const Color(0xFFE15554),
    CardColor.blue => const Color(0xFF3D7EA6),
    CardColor.green => const Color(0xFF4DAA57),
    CardColor.locomotive => const Color(0xFF8B6518),
  };
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.destination,
    required this.completed,
  });
  final Destination destination;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: completed
            ? const Color(0xFFDDF1DF)
            : Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: completed ? const Color(0xFF4DAA57) : const Color(0xFFF1EAE5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.place_rounded,
            size: 14,
            color: completed ? const Color(0xFF4DAA57) : purple,
          ),
          const SizedBox(width: 6),
          Text(
            '${destination.from.russianName} — '
            '${destination.to.russianName}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: purple,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+${destination.points}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Диалог выбора путешествий --------------------------------------------

class _DestinationsDialog extends StatefulWidget {
  const _DestinationsDialog({
    required this.controller,
    required this.onClose,
  });
  final TicketToRideController controller;
  final VoidCallback onClose;

  @override
  State<_DestinationsDialog> createState() => _DestinationsDialogState();
}

class _DestinationsDialogState extends State<_DestinationsDialog> {
  late final List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.controller.pendingDestinations.length, true);
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.controller.pendingDestinations;
    return AlertDialog(
      title: const Text(
        'Выбери путешествия',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Оставь хотя бы одно. Ненужные вернутся в колоду.',
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < pending.length; i++) ...[
            _DestinationToggle(
              destination: pending[i],
              selected: _selected[i],
              onTap: () => setState(() {
                // Нельзя снять последнее.
                if (_selected[i] && _selected.where((s) => s).length <= 1) {
                  return;
                }
                _selected[i] = !_selected[i];
              }),
            ),
            if (i < pending.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Готово'),
          ),
        ),
      ],
    );
  }

  void _confirm() {
    final indices = <int>[];
    for (var i = 0; i < _selected.length; i++) {
      if (_selected[i]) indices.add(i);
    }
    if (indices.isEmpty) return;
    widget.controller.keepDestinations(indices);
    widget.onClose();
  }
}

class _DestinationToggle extends StatelessWidget {
  const _DestinationToggle({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFEDE6FF)
            : Colors.white.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? purple : const Color(0xFFE3D8F5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            color: selected ? purple : muted,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${destination.from.russianName} — '
              '${destination.to.russianName}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: purple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+${destination.points}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- Таблица счёта в конце партии -----------------------------------------

class _ScoreTable extends StatelessWidget {
  const _ScoreTable({
    required this.myName,
    required this.oppName,
    required this.myRoutes,
    required this.oppRoutes,
    required this.myDestBonus,
    required this.oppDestBonus,
    required this.myTotal,
    required this.oppTotal,
    required this.iWon,
    required this.draw,
  });

  final String myName;
  final String oppName;
  final int myRoutes;
  final int oppRoutes;
  final int myDestBonus;
  final int oppDestBonus;
  final int myTotal;
  final int oppTotal;
  final bool iWon;
  final bool draw;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF1EAE5)),
    ),
    child: Column(
      children: [
        _scoreRow('Игрок', myName, oppName, header: true),
        const Divider(height: 12),
        _scoreRow('Маршруты', '$myRoutes', '$oppRoutes'),
        _scoreRow(
          'Путешествия',
          myDestBonus >= 0 ? '+$myDestBonus' : '$myDestBonus',
          oppDestBonus >= 0 ? '+$oppDestBonus' : '$oppDestBonus',
        ),
        const Divider(height: 12),
        _scoreRow(
          'Итог',
          '$myTotal',
          '$oppTotal',
          highlightMine: !draw && iWon,
          highlightOpp: !draw && !iWon,
        ),
      ],
    ),
  );

  Widget _scoreRow(
    String label,
    String mine,
    String opp, {
    bool header = false,
    bool highlightMine = false,
    bool highlightOpp = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: header ? ink : muted,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: highlightMine
                  ? purple.withValues(alpha: .15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              mine,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: highlightMine ? purple : ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: highlightOpp
                  ? yellow.withValues(alpha: .25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              opp,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: highlightOpp ? const Color(0xFFB98800) : ink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// ---- Кнопки управления -----------------------------------------------------

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: purple, size: 20),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---- Заглушка ожидания сети -----------------------------------------------

class _WaitingPane extends StatelessWidget {
  const _WaitingPane({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.train_rounded, size: 64, color: purple),
        const SizedBox(height: 18),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
        const SizedBox(height: 18),
        const CircularProgressIndicator(color: purple),
      ],
    ),
  );
}

// ---- Вспомогательные типы -------------------------------------------------

/// Простая точка для hit-теста по маршрутам, без зависимости от dart:ui.
class _MapPoint {
  const _MapPoint(this.x, this.y);
  final double x;
  final double y;
}

enum _OverChoice { again, home }

// ---- Панель игрока (общая для соперника и меня) ---------------------------

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    super.key,
    required this.name,
    required this.trains,
    required this.score,
    required this.destinations,
    required this.active,
    required this.avatarColor,
    required this.avatarIcon,
    required this.activeLabel,
    this.highlightAvatar = false,
  });

  final String name;
  final int trains;
  final int score;
  final int destinations;
  final bool active;
  final Color avatarColor;
  final IconData avatarIcon;
  final String activeLabel;
  final bool highlightAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEDE5FD)
            : Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0xFFB9A3EF) : const Color(0xFFF1EAE5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: avatarColor,
              borderRadius: BorderRadius.circular(12),
              border: highlightAvatar
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: Icon(avatarIcon, color: ink, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.train_rounded,
                      value: '$trains',
                      tooltip: 'Вагонов осталось',
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.card_giftcard_rounded,
                      value: '$destinations',
                      tooltip: 'Путешествий',
                    ),
                    const SizedBox(width: 6),
                    _StatChip(
                      icon: Icons.star_rounded,
                      value: '$score',
                      tooltip: 'Очки за маршруты',
                      accent: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (active)
            Eyebrow(
              activeLabel,
              color: deepPurple,
              background: const Color(0xFFDCCDF8),
              fontSize: 10,
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.tooltip,
    this.accent = false,
  });
  final IconData icon;
  final String value;
  final String tooltip;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: accent ? purple : ink.withValues(alpha: .6),
          ),
          const SizedBox(width: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: accent ? purple : ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Диалог занятия маршрута ----------------------------------------------

/// Показывает, сколько цветных карт и локомотивов потратится на маршрут, и
/// даёт выбрать число локомотивов степпером. Дальше нажимаем «Занять» —
/// и контроллер применяет ход с выбранным числом.
class _ClaimRouteDialog extends StatefulWidget {
  const _ClaimRouteDialog({
    required this.controller,
    required this.routeIndex,
    required this.minLocomotives,
    required this.maxLocomotives,
    required this.onConfirm,
    required this.onCancel,
  });

  final TicketToRideController controller;
  final int routeIndex;
  final int minLocomotives;
  final int maxLocomotives;
  final ValueChanged<int> onConfirm;
  final VoidCallback onCancel;

  @override
  State<_ClaimRouteDialog> createState() => _ClaimRouteDialogState();
}

class _ClaimRouteDialogState extends State<_ClaimRouteDialog> {
  late int _locomotives;

  @override
  void initState() {
    super.initState();
    // По умолчанию бережём локомотивы: тратим минимум. Если цветных не
    // хватает, минимум больше нуля — степпер встанет правильно.
    _locomotives = widget.minLocomotives;
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.controller.routes[widget.routeIndex];
    final hand = widget.controller.myHand;
    final colorCount = hand.where((c) => c.color == route.color).length;
    final locoCount = hand
        .where((c) => c.color == CardColor.locomotive)
        .length;
    final colorToSpend = route.length - _locomotives;
    final routeColor = _cardColor(route.color);
    final locoColor = _cardColor(CardColor.locomotive);
    return AlertDialog(
      title: const Text(
        'Занять маршрут',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${route.cityA.russianName} — ${route.cityB.russianName}',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${route.color.russianName.toLowerCase()}, '
              'длина ${route.length}, очков +${route.points}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SplitRow(
            label: 'Цветные карты',
            color: routeColor,
            spent: colorToSpend,
            total: colorCount,
          ),
          const SizedBox(height: 8),
          _SplitRow(
            label: 'Локомотивы',
            color: locoColor,
            spent: _locomotives,
            total: locoCount,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Локомотивов:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    key: const Key('ttr-claim-loco-minus'),
                    icon: const Icon(Icons.remove_circle_rounded),
                    color: purple,
                    onPressed: _locomotives > widget.minLocomotives
                        ? () => setState(() => _locomotives--)
                        : null,
                  ),
                  SizedBox(
                    width: 32,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$_locomotives',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('ttr-claim-loco-plus'),
                    icon: const Icon(Icons.add_circle_rounded),
                    color: purple,
                    onPressed: _locomotives < widget.maxLocomotives
                        ? () => setState(() => _locomotives++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: widget.onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFE3D8F5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Отмена'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            key: const Key('ttr-claim-confirm'),
            onPressed: () => widget.onConfirm(_locomotives),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Занять'),
          ),
        ),
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.label,
    required this.color,
    required this.spent,
    required this.total,
  });
  final String label;
  final Color color;
  final int spent;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Colors.white.withValues(alpha: .7),
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$label: $spent из $total',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Диалог истории ходов -------------------------------------------------

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({
    required this.controller,
    required this.onClose,
  });
  final TicketToRideController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    return AlertDialog(
      title: const Text(
        'История ходов',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: history.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Ходов ещё не было.',
                  textAlign: TextAlign.center,
                  style: dialogTextStyle,
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final record = history[history.length - 1 - index];
                  final name = controller.nameFor(record.seat);
                  final isMine = record.seat == controller.mySeat;
                  return _HistoryRow(
                    name: name,
                    text: record.text,
                    isMine: isMine,
                    kind: record.kind,
                  );
                },
              ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: onClose,
            child: const Text('Закрыть'),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.name,
    required this.text,
    required this.isMine,
    required this.kind,
  });
  final String name;
  final String text;
  final bool isMine;
  final String kind;

  Color _kindAccent() {
    return switch (kind) {
      'claim' => const Color(0xFF4DAA57),
      'drawFaceUp' || 'drawDeck' => const Color(0xFF3D7EA6),
      'drawDestinations' || 'keepDestinations' => const Color(0xFFB98800),
      _ => muted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMine
            ? const Color(0xFFEDE6FF)
            : Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMine ? purple : const Color(0xFFF1EAE5),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _kindAccent(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: isMine ? purple : ink,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
