import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart' hide Orientation;

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../network/protocol.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'battleship_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'network.dart';

/// Точка входа в партию морского боя: с сетевым соединением — сразу
/// расстановка по сети, без него — выбор режима и сложности.
class BattleshipEntryPage extends StatelessWidget {
  const BattleshipEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return BattleshipSetupPage(
        settings: settings,
        mode: GameMode.network,
        network: network,
      );
    }
    return BattleshipModePage(settings: settings);
  }
}

/// Выбор режима: против компьютера (с уровнем сложности) или вдвоём на одном
/// устройстве. Из режима «против компьютера» дальше ведёт DifficultyPage.
class BattleshipModePage extends StatelessWidget {
  const BattleshipModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Морской бой',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ЯКОРЯ НА СТАРТ ⚓',
              title: 'С кем сыграем?',
              subtitle: 'Против компьютера — три уровня сложности. '
                  'Можно и вдвоём на одном устройстве.',
            ),
            const SizedBox(height: 22),
            BigButton(
              title: 'Играть с компьютером',
              subtitle: 'Три уровня сложности',
              icon: Icons.smart_toy_rounded,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      BattleshipDifficultyPage(settings: settings),
                ),
              ),
            ),
            const SizedBox(height: 14),
            BigButton(
              title: 'Двое на одном устройстве',
              subtitle: 'Ходы по очереди — каждый расставляет свой флот',
              icon: Icons.people_rounded,
              color: const Color(0xFFF4CB67),
              foreground: ink,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BattleshipSetupPage(
                    settings: settings,
                    mode: GameMode.local,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Назад'),
            ),
          ],
        ),
      );
}

/// Страница выбора уровня сложности перед расстановкой.
class BattleshipDifficultyPage extends StatelessWidget {
  const BattleshipDifficultyPage({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Сложность',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ВЫБЕРИ СИЛУ',
              title: 'Какой соперник?',
              subtitle: 'На лёгком компьютер стреляет наугад, на сложном — '
                  'думает.',
            ),
            const SizedBox(height: 24),
            for (final d in Difficulty.values)
              ChoiceTile(
                title: d.russianName,
                subtitle: d.russianSubtitle,
                icon: d == Difficulty.easy
                    ? Icons.sentiment_satisfied_rounded
                    : (d == Difficulty.medium
                        ? Icons.sentiment_neutral_rounded
                        : Icons.sentiment_very_dissatisfied_rounded),
                color: d == Difficulty.easy
                    ? const Color(0xFFE6F4E5)
                    : (d == Difficulty.medium
                        ? const Color(0xFFFCE4D7)
                        : const Color(0xFFF6E2E2)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BattleshipSetupPage(
                      settings: settings,
                      mode: GameMode.computer,
                      difficulty: d,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Экран расстановки флота.
///
/// В режиме с компьютером — после «В бой» сразу стартует партия со случайным
/// флотом ИИ. В сетевом режиме — отправляет `fleetReady` и ждёт готовности
/// соперника, потом открывает [BattleshipGamePage]. Вдвоём на одном
/// устройстве — два прохода: первый игрок расставляет флот, потом второй.
class BattleshipSetupPage extends StatefulWidget {
  const BattleshipSetupPage({
    super.key,
    required this.settings,
    required this.mode,
    this.difficulty = Difficulty.easy,
    this.network,
  });
  final SettingsController settings;
  final GameMode mode;
  final Difficulty difficulty;
  final NetworkSession? network;

  @override
  State<BattleshipSetupPage> createState() => _BattleshipSetupPageState();
}

class _BattleshipSetupPageState extends State<BattleshipSetupPage> {
  final BattleshipRules rules = battleshipRules;
  Fleet _fleet = emptyFleet;
  ShipType? _selected = ShipType.battleship;
  Orientation _orientation = Orientation.horizontal;
  bool _navigatedToPlay = false;

  /// Для локального режима 2 на 1: флот первого игрока, спрятанный, пока
  /// расставляет второй.
  Fleet _stashedFleet = emptyFleet;
  int _setupTurn = 0; // 0 — первый игрок, 1 — второй

  /// Сетевая готовность: обе стороны должны отправить `fleetReady`.
  bool _myReady = false;
  bool _peerReady = false;
  StreamSubscription<NetworkMessage>? _netSub;

  @override
  void initState() {
    super.initState();
    if (widget.network != null) {
      _netSub = widget.network!.service.events.listen(_onNetworkEvent);
    }
  }

  @override
  void dispose() {
    _netSub?.cancel();
    super.dispose();
  }

  void _onNetworkEvent(NetworkMessage message) {
    if (!mounted) return;
    if (message.type == 'event' && message.data['kind'] == 'fleetReady') {
      setState(() => _peerReady = true);
      _maybeStartNetwork();
    } else if (message.type == 'disconnected') {
      _showFatal('Связь потеряна. Вернись в меню.');
    }
  }

  void _showFatal(String message) {
    if (!mounted) return;
    showDianaDialog<void>(
      context: context,
      title: 'Связь потеряна',
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<void>(label: 'В меню', value: null, primary: true),
      ],
    ).then((_) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  bool get _isNetwork => widget.network != null;

  bool get _waitingForPeer => _isNetwork && _myReady && !_peerReady;

  String get _statusText {
    if (_waitingForPeer) {
      return 'Ждём, пока друг расставит корабли…';
    }
    if (widget.mode == GameMode.local && _setupTurn == 1) {
      return 'Игрок 2 расставляет флот';
    }
    if (_fleet.isComplete) {
      return 'Флот готов! Жми «В бой». ⚓';
    }
    return 'Поставь все корабли. Можно случайно.';
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Расстановка',
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            children: [
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: _boardArea()),
              const SizedBox(height: 8),
              _arsenal(),
              const SizedBox(height: 8),
              _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardArea() {
    final validOrigins = _validOrigins();
    final cells = <Square, CellView>{};
    for (final s in allSquares()) {
      cells[s] = CellView(ship: _fleet.shipAt(s) != null);
    }
    final showHints =
        widget.settings.flag(battleshipGameId, 'hints');
    return Center(
      child: BattleshipBoardWidget(
        cells: cells,
        shipsToDraw: _fleet.ships,
        unfiredHighlight: showHints ? validOrigins : const {},
        own: true,
        canTap: true,
        onTap: _onCellTap,
      ),
    );
  }

  /// Клетки, откуда можно поставить выбранный корабль в текущей ориентации.
  Set<Square> _validOrigins() {
    if (_selected == null) return const {};
    final result = <Square>{};
    for (final s in allSquares()) {
      final ship = Ship(
        type: _selected!,
        origin: s,
        orientation: _orientation,
      );
      if (rules.canPlace(_fleet, ship)) result.add(s);
    }
    return result;
  }

  void _onCellTap(Square square) {
    final existing = _fleet.shipAt(square);
    if (existing != null) {
      // Тап по своему кораблю — снимаем его.
      setState(() {
        _fleet = rules.withoutShipAt(_fleet, square);
        _selected = existing.type;
      });
      return;
    }
    if (_selected == null) return;
    final ship = Ship(
      type: _selected!,
      origin: square,
      orientation: _orientation,
    );
    if (rules.canPlace(_fleet, ship)) {
      setState(() {
        _fleet = rules.withShip(_fleet, ship);
        _selected = _nextToPlace();
      });
    } else {
      // Попробуем автоматически перевернуть ориентацию.
      final flipped = Ship(
        type: _selected!,
        origin: square,
        orientation: _orientation.flipped,
      );
      if (rules.canPlace(_fleet, flipped)) {
        setState(() {
          _fleet = rules.withShip(_fleet, flipped);
          _orientation = _orientation.flipped;
          _selected = _nextToPlace();
        });
      }
    }
  }

  ShipType? _nextToPlace() {
    for (final t in ShipType.values) {
      if (_fleet.countOf(t) < t.count) return t;
    }
    return null;
  }

  Widget _arsenal() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Арсенал',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in ShipType.values) ...[
                  _arsenalChip(t),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _arsenalChip(ShipType t) {
    final placed = _fleet.countOf(t);
    final remaining = t.count - placed;
    final selected = _selected == t;
    final disabled = remaining <= 0;
    return GestureDetector(
      onTap: disabled
          ? null
          : () => setState(() {
                _selected = selected ? null : t;
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? purple.withValues(alpha: .15)
              : (disabled
                  ? const Color(0xFFF2F2F2)
                  : const Color(0xFFEDE6FF)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? purple : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              t == ShipType.submarine
                  ? Icons.circle
                  : Icons.directions_boat_filled_rounded,
              size: 18,
              color: disabled ? muted : purple,
            ),
            const SizedBox(width: 7),
            Text(
              '${t.russianLabel} (${t.size})',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: disabled ? muted : ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '×$remaining',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final complete = _fleet.isComplete;
    final waiting = _waitingForPeer;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: waiting
                    ? null
                    : () => setState(() {
                          _fleet = rules.autoFleet();
                          _selected = null;
                        }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: purple,
                  side: const BorderSide(color: Color(0xFFDAD0ED)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Случайно',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: waiting
                    ? null
                    : () => setState(() {
                          _fleet = emptyFleet;
                          _selected = ShipType.battleship;
                        }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: ink,
                  side: const BorderSide(color: Color(0xFFE3D8F5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Очистить',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: waiting
                  ? null
                  : () => setState(() {
                        _orientation = _orientation.flipped;
                      }),
              icon: Icon(
                _orientation == Orientation.horizontal
                    ? Icons.swap_horiz_rounded
                    : Icons.swap_vert_rounded,
                color: purple,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(46, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(color: Color(0xFFDAD0ED)),
              ),
              tooltip: 'Повернуть корабль',
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (complete && !waiting) ? _start : null,
            icon: waiting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.flag_rounded),
            label: Text(waiting ? 'Ждём друга…' : 'В бой!'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _start() {
    if (!_fleet.isComplete) return;
    if (_navigatedToPlay) return;
    if (_isNetwork) {
      // Сообщаем о своей готовности и ждём готовности соперника.
      try {
        widget.network!.service
            .send(NetworkMessage('event', fleetReadyToJson()));
      } catch (_) {
        _showFatal('Не удалось сообщить о готовности.');
        return;
      }
      setState(() => _myReady = true);
      _maybeStartNetwork();
      return;
    }
    if (widget.mode == GameMode.local) {
      if (_setupTurn == 0) {
        // Первый игрок готов — прячем его флот, расставляет второй.
        setState(() {
          _stashedFleet = _fleet;
          _fleet = emptyFleet;
          _selected = ShipType.battleship;
          _setupTurn = 1;
        });
        return;
      }
      // Второй игрок готов — оба флота на месте, начинаем.
      final setup = GameSetup(
        mode: GameMode.local,
        myFleet: _stashedFleet,
        enemyFleet: _fleet,
        iShootFirst: true,
      );
      _navigateToGame(setup);
      return;
    }
    // Соперник-компьютер получает случайный флот.
    final enemyFleet = rules.autoFleet();
    final setup = GameSetup(
      mode: GameMode.computer,
      myFleet: _fleet,
      enemyFleet: enemyFleet,
      iShootFirst: true,
      difficulty: widget.difficulty,
    );
    _navigateToGame(setup);
  }

  void _maybeStartNetwork() {
    if (!mounted || !_fleet.isComplete || _navigatedToPlay) return;
    if (!_myReady || !_peerReady) return;
    final iShootFirst = widget.network!.isHost;
    final setup = GameSetup(
      mode: GameMode.network,
      myFleet: _fleet,
      iShootFirst: iShootFirst,
      network: widget.network,
    );
    _navigateToGame(setup);
  }

  void _navigateToGame(GameSetup setup) {
    if (_navigatedToPlay) return;
    _navigatedToPlay = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BattleshipGamePage(
          setup: setup,
          settings: widget.settings,
        ),
      ),
    );
  }
}

/// Экран партии: поле соперника (стреляю я) и своё поле (стреляют по мне).
///
/// Под капотом — [BattleshipController]. UI только слушает его и рисует.
/// Контроллер можно передать снаружи (например, из теста с короткой задержкой
/// хода ИИ); если его нет — страница создаёт свой и владеет им.
class BattleshipGamePage extends StatefulWidget {
  const BattleshipGamePage({
    super.key,
    required this.setup,
    required this.settings,
    this.controller,
  });
  final GameSetup setup;
  final SettingsController settings;

  /// Внешний контроллер. Если null, страница создаёт свой.
  final BattleshipController? controller;

  @override
  State<BattleshipGamePage> createState() => _BattleshipGamePageState();
}

class _BattleshipGamePageState extends State<BattleshipGamePage> {
  late final BattleshipController controller;
  late final bool _ownsController;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      controller = widget.controller!;
      _ownsController = false;
    } else {
      final sounds = GameSounds(widget.settings);
      controller = BattleshipController(
        widget.setup,
        widget.settings,
        sounds: sounds,
      );
      _ownsController = true;
    }
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    if (controller.isOver && !_resultShown) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BattleshipResultPage(
              winner: controller.winner ?? Side.enemy,
              setup: widget.setup,
              settings: widget.settings,
              fatalMessage: controller.fatalMessage,
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([widget.settings, controller]),
            builder: (context, _) => Row(
              children: [
                _hintsToggle(),
                _suggestButton(),
                _soundToggle(),
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Сдаться',
                  onPressed:
                      controller.canResign && !controller.isOver ? _confirmResign : null,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final state = controller.state;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _statusLine(state),
                        const SizedBox(height: 6),
                        _boardLabel(_topBoardLabel(state), true),
                        Expanded(
                          child: Center(child: _enemyBoard(state)),
                        ),
                        _boardLabel(_bottomBoardLabel(state), false),
                        Expanded(
                          child: Center(child: _myBoard(state)),
                        ),
                      ],
                    ),
                    if (controller.notice != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 48,
                        child: _notice(controller.notice!),
                      ),
                    if (controller.incomingUndoPly != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 48,
                        child: _undoRequest(),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _title() => widget.setup.mode == GameMode.network
      ? 'Сетевая партия'
      : (widget.setup.mode == GameMode.local
          ? 'Морской бой · вдвоём'
          : 'Морской бой · ${widget.setup.difficulty.russianName}');

  Widget _boardLabel(String text, bool enemy) => Padding(
        padding: const EdgeInsets.only(bottom: 2, top: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: enemy ? deepPurple : muted,
          ),
        ),
      );

  String _topBoardLabel(GameState state) {
    if (widget.setup.mode == GameMode.local) {
      return state.turn == Side.me ? 'Поле игрока 2' : 'Поле игрока 1';
    }
    if (widget.setup.mode == GameMode.network) {
      return 'Поле друга';
    }
    return 'Поле соперника';
  }

  String _bottomBoardLabel(GameState state) {
    if (widget.setup.mode == GameMode.local) {
      return state.turn == Side.me ? 'Поле игрока 1' : 'Поле игрока 2';
    }
    return 'Моё поле';
  }

  Widget _soundToggle() => IconButton(
        tooltip: 'Звук',
        icon: Icon(
          widget.settings.sound
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          color: ink,
        ),
        onPressed: () => widget.settings.setSound(!widget.settings.sound),
      );

  Widget _hintsToggle() => IconButton(
        tooltip: 'Подсказки',
        icon: Icon(
          widget.settings.flag(battleshipGameId, 'hints')
              ? Icons.lightbulb_rounded
              : Icons.lightbulb_outline_rounded,
          color: widget.settings.flag(battleshipGameId, 'hints')
              ? purple
              : muted,
        ),
        onPressed: () => widget.settings.setFlag(
          battleshipGameId,
          'hints',
          !widget.settings.flag(battleshipGameId, 'hints'),
        ),
      );

  Widget _suggestButton() {
    final hintsOn = widget.settings.flag(battleshipGameId, 'hints');
    final showing = controller.suggestedShot != null;
    final canSuggest =
        hintsOn && controller.canInteract && !controller.hintThinking;
    return IconButton(
      tooltip: showing ? 'Скрыть подсказку' : 'Посоветовать выстрел',
      icon: controller.hintThinking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(
              showing ? Icons.lightbulb_rounded : Icons.gps_fixed_rounded,
              color: showing ? purple : (hintsOn ? ink : muted),
            ),
      onPressed: showing
          ? controller.clearHint
          : (canSuggest ? () => controller.showHint() : null),
    );
  }

  Widget _statusLine(GameState state) {
    final my = state.myBoard;
    final enemy = state.enemyBoard;
    final mySunk = my.fleet.ships.where((s) => !my.isAlive(s)).length;
    final enemySunkCount = enemy.shots.values
        .where((s) => s.result == ShotResult.sunk)
        .length;
    final mine = state.turn == Side.me;
    String text;
    if (controller.isOver) {
      text = controller.winner == Side.me
          ? 'Победа! Ты потопил весь флот! 🎉'
          : 'Партия окончена.';
    } else if (controller.waitingForPeer) {
      text = 'Ждём, когда друг расставит корабли…';
    } else if (controller.computerThinking) {
      text = 'Компьютер думает…';
    } else if (controller.isAnimating) {
      text = state.turn == Side.me ? 'Выстрел!' : 'Соперник стреляет…';
    } else if (mine) {
      text = 'Твой ход — стреляй по полю соперника!';
    } else {
      text = widget.setup.mode == GameMode.local
          ? 'Ход соперника…'
          : 'Ход соперника…';
    }
    return SizedBox(
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: ink,
                ),
              ),
            ),
            _counter('Потоплено', enemySunkCount, totalShips),
            const SizedBox(width: 10),
            _counter('Потеряно', mySunk, totalShips, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _counter(String label, int value, int total, {bool danger = false}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value/$total',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: danger
                  ? const Color(0xFFC0392B)
                  : const Color(0xFF1E8449),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        ],
      );

  /// Раскладка полей для текущего игрока. В локальном режиме 2 на 1, когда
  /// ход перешёл ко второму игроку, поля меняются местами.
  _Perspective _perspective(GameState state) {
    if (widget.setup.mode == GameMode.local && state.turn == Side.enemy) {
      return _Perspective(
        topFleet: widget.setup.myFleet,
        topShots: _shotsFromResults(state.myBoard.incoming),
        bottomFleet: widget.setup.enemyFleet ?? emptyFleet,
        bottomShots: state.enemyBoard.shots,
      );
    }
    return _Perspective(
      topFleet: widget.setup.enemyFleet ?? emptyFleet,
      topShots: state.enemyBoard.shots,
      bottomFleet: state.myBoard.fleet,
      bottomShots: _shotsFromResults(state.myBoard.incoming),
    );
  }

  static Map<Square, Shot> _shotsFromResults(Map<Square, ShotResult> results) =>
      results.map((k, v) => MapEntry(k, Shot(square: k, result: v)));

  Widget _enemyBoard(GameState state) {
    final p = _perspective(state);
    final cells = <Square, CellView>{};
    for (final s in allSquares()) {
      final shot = p.topShots[s];
      cells[s] = CellView(
        result: shot?.result,
        sunkSegment: shot?.result == ShotResult.sunk,
      );
    }
    final sunkOutlines = _enemySunkOutlines(p.topShots);
    final hintsOn = widget.settings.flag(battleshipGameId, 'hints');
    final unfired = hintsOn && controller.canInteract
        ? _unfired(p.topShots)
        : const <Square>{};
    final anim = controller.animation != null &&
            controller.animation!.shooter == Side.me
        ? controller.animation
        : null;
    return BattleshipBoardWidget(
      cells: cells,
      shipsToDraw: const [],
      sunkOutlines: sunkOutlines,
      unfiredHighlight: unfired,
      suggested: controller.suggestedShot,
      animation: anim,
      own: false,
      canTap: controller.canInteract,
      onTap: (s) => controller.shoot(s),
    );
  }

  Set<Square> _unfired(Map<Square, Shot> shots) {
    final fired = shots.keys.toSet();
    return allSquares().where((s) => !fired.contains(s)).toSet();
  }

  List<SunkOutline> _enemySunkOutlines(Map<Square, Shot> shots) {
    final outlines = <SunkOutline>[];
    final done = <Square>{};
    for (final shot in shots.values) {
      if (shot.result != ShotResult.sunk) continue;
      if (done.contains(shot.square)) continue;
      final cells = _contiguousHits(shots, shot.square);
      done.addAll(cells);
      outlines.add(SunkOutline(cells: cells.toList(), type: shot.sunkType));
    }
    return outlines;
  }

  Set<Square> _contiguousHits(Map<Square, Shot> shots, Square anchor) {
    Square? expand(Square from, int dr, int dc) {
      final next = Square(from.row + dr, from.col + dc);
      if (!next.inside) return null;
      final s = shots[next];
      if (s == null || s.result == ShotResult.miss) return null;
      return next;
    }

    final result = <Square>{anchor};
    for (final axis in [Axis.horizontal, Axis.vertical]) {
      final (dr, dc) = axis == Axis.horizontal ? (0, 1) : (1, 0);
      var cur = anchor;
      while (true) {
        final n = expand(cur, dr, dc);
        if (n == null) break;
        result.add(n);
        cur = n;
      }
      cur = anchor;
      while (true) {
        final n = expand(cur, -dr, -dc);
        if (n == null) break;
        result.add(n);
        cur = n;
      }
    }
    return result;
  }

  Widget _myBoard(GameState state) {
    final p = _perspective(state);
    final cells = <Square, CellView>{};
    for (final s in allSquares()) {
      final ship = p.bottomFleet.occupies(s);
      final incoming = p.bottomShots[s];
      final shipAtS = p.bottomFleet.shipAt(s);
      final sunk = ship && shipAtS != null && _isShipSunk(shipAtS, p.bottomShots);
      cells[s] = CellView(
        ship: ship,
        result: incoming?.result,
        sunkSegment: sunk,
      );
    }
    final sunkOutlines = <SunkOutline>[];
    for (final ship in p.bottomFleet.ships) {
      if (_isShipSunk(ship, p.bottomShots)) {
        sunkOutlines.add(SunkOutline(cells: ship.cells, type: ship.type));
      }
    }
    final anim = controller.animation != null &&
            controller.animation!.shooter == Side.enemy
        ? controller.animation
        : null;
    return BattleshipBoardWidget(
      cells: cells,
      shipsToDraw: p.bottomFleet.ships,
      sunkOutlines: sunkOutlines,
      animation: anim,
      own: true,
      canTap: false,
    );
  }

  static bool _isShipSunk(Ship ship, Map<Square, Shot> shots) =>
      ship.cells.every((c) {
        final s = shots[c];
        return s != null && s.result != ShotResult.miss;
      });

  Widget _notice(String text) => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: muted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _undoRequest() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE6FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.undo_rounded, color: purple, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Друг просит отменить последний ход.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            TextButton(
              onPressed: () => controller.respondToUndo(false),
              child: const Text('Нет'),
            ),
            FilledButton(
              onPressed: () => controller.respondToUndo(true),
              child: const Text('Да'),
            ),
          ],
        ),
      );

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
            label: 'Не сдаваться', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) controller.resign();
    });
  }
}

/// Раскладка полей: верхнее (поле соперника) и нижнее (своё).
class _Perspective {
  const _Perspective({
    required this.topFleet,
    required this.topShots,
    required this.bottomFleet,
    required this.bottomShots,
  });
  final Fleet topFleet;
  final Map<Square, Shot> topShots;
  final Fleet bottomFleet;
  final Map<Square, Shot> bottomShots;
}

/// Экран результата партии. Победа — радостная, поражение — поддерживающее.
class BattleshipResultPage extends StatelessWidget {
  const BattleshipResultPage({
    super.key,
    required this.winner,
    required this.setup,
    required this.settings,
    this.fatalMessage,
  });
  final Side winner;
  final GameSetup setup;
  final SettingsController settings;
  final String? fatalMessage;

  @override
  Widget build(BuildContext context) {
    // Side.me на этом устройстве — всегда «я». В сети это так же: каждое
    // устройство считает себя «me», а соперника — «enemy».
    final iWon = setup.mode == GameMode.local || winner == Side.me;
    final isFatal = fatalMessage != null;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _emoji(iWon, isFatal),
                    const SizedBox(height: 18),
                    Text(
                      isFatal
                          ? 'Связь прервалась'
                          : (iWon ? 'Победа!' : 'В этот раз не вышло'),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: ink,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isFatal
                          ? fatalMessage!
                          : (iWon
                              ? 'Ты потопил весь флот соперника! 🎉 Меткий командир!'
                              : 'Не расстраивайся — в следующий раз точно получится! 💪'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: muted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!isFatal)
                      Text(
                        'Сыграно партий: ${settings.gamesPlayed}  ·  '
                        'Побед: ${settings.gamesWon}',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: () => _again(context),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Ещё раз'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _toMenu(context),
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('В меню'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        foregroundColor: ink,
                        side: const BorderSide(color: Color(0xFFE3D8F5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emoji(bool won, bool fatal) => Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fatal
              ? const Color(0xFFF6E2E2)
              : (won ? const Color(0xFFE6F4E5) : const Color(0xFFFCE4D7)),
        ),
        child: Icon(
          fatal
              ? Icons.wifi_off_rounded
              : (won
                  ? Icons.emoji_events_rounded
                  : Icons.sentiment_dissatisfied_rounded),
          size: 60,
          color: fatal
              ? const Color(0xFFC0392B)
              : (won ? const Color(0xFF1E8449) : const Color(0xFFCA6F1E)),
        ),
      );

  void _again(BuildContext context) {
    if (setup.mode == GameMode.network) {
      // Сетевую партию проще начать через лобби заново.
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleshipSetupPage(
          settings: settings,
          mode: setup.mode,
          difficulty: setup.difficulty,
        ),
      ),
    );
  }

  void _toMenu(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

// ---- Виджет поля ---------------------------------------------------------

/// Что рисовать в одной клетке поля.
class CellView {
  const CellView({
    this.ship = false,
    this.sunkSegment = false,
    this.result,
  });
  final bool ship;
  final bool sunkSegment;
  final ShotResult? result;
  bool get isEmpty => !ship && !sunkSegment && result == null;
}

/// Контур потопленного корабля (для обводки).
class SunkOutline {
  const SunkOutline({required this.cells, required this.type});
  final List<Square> cells;
  final ShipType? type;
}

/// Поле морского боя: координаты, клетки, корабли, отметки, подсказки.
///
/// Один виджет используется и для своего поля (видны корабли и выстрелы
/// соперника по ним), и для поля соперника (туман войны — видны только свои
/// выстрелы и обводки потопленных кораблей).
class BattleshipBoardWidget extends StatelessWidget {
  const BattleshipBoardWidget({
    super.key,
    required this.cells,
    this.sunkOutlines = const [],
    this.shipsToDraw = const [],
    this.unfiredHighlight = const {},
    this.suggested,
    this.animation,
    this.onTap,
    this.canTap = false,
    this.showLabels = true,
    this.own = false,
  });

  final Map<Square, CellView> cells;
  final List<SunkOutline> sunkOutlines;
  final List<Ship> shipsToDraw;
  final Set<Square> unfiredHighlight;
  final Square? suggested;
  final ShotAnimation? animation;
  final ValueChanged<Square>? onTap;
  final bool canTap;
  final bool showLabels;
  final bool own;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : double.infinity;
          final labelW = showLabels ? 18.0 : 0.0;
          final labelH = showLabels ? 16.0 : 0.0;
          final byW = (maxW - labelW) / boardSize;
          final cell = maxH.isInfinite
              ? byW
              : math.min(byW, (maxH - labelH) / boardSize);
          final side = cell * boardSize;
          return SizedBox(
            width: labelW + side,
            height: labelH + side,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (showLabels) _letters(labelW, cell, labelH),
                if (showLabels) _numbers(labelW, cell, labelH),
                Positioned(
                  left: labelW,
                  top: labelH,
                  child: SizedBox(
                    width: cell * boardSize,
                    height: cell * boardSize,
                    child: Stack(
                      children: [
                        _grid(cell),
                        ..._shipBars(cell),
                        ..._marks(cell),
                        ..._sunkOutlines(cell),
                        if (canTap && onTap != null) _tapLayer(cell),
                        if (animation != null)
                          ShotOverlay(
                            animation: animation!,
                            cellSize: cell,
                            target: animation!.shot.square,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _letters(double labelW, double cell, double labelH) => Positioned(
        left: labelW,
        top: 0,
        height: labelH,
        width: cell * boardSize,
        child: Row(
          children: [
            for (final letter in columnLetters)
              SizedBox(
                width: cell,
                child: Center(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _numbers(double labelW, double cell, double labelH) => Positioned(
        left: 0,
        top: labelH,
        width: labelW,
        height: cell * boardSize,
        child: Column(
          children: [
            for (var r = 0; r < boardSize; r++)
              SizedBox(
                height: cell,
                child: Center(
                  child: Text(
                    '${r + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _grid(double cell) => Positioned.fill(
        child: CustomPaint(
          painter: _GridPainter(
            cell: cell,
            own: own,
            unfired: unfiredHighlight,
            suggested: suggested,
            cells: cells,
          ),
        ),
      );

  List<Widget> _shipBars(double cell) => shipsToDraw.map((ship) {
        final first = ship.cells.first;
        final last = ship.cells.last;
        final left = first.col * cell;
        final top = first.row * cell;
        // Ширина и высота корабля — по разнице между последней и первой
        // клетками: так учитывается и ориентация, и длина.
        final width = (last.col - first.col + 1) * cell;
        final height = (last.row - first.row + 1) * cell;
        return Positioned(
          left: left + cell * .08,
          top: top + cell * .10,
          width: width - cell * .16,
          height: height - cell * .20,
          child: _ShipBar(
            type: ship.type,
            orientation: ship.orientation,
            sunk: _isShipSunk(ship),
          ),
        );
      }).toList();

  bool _isShipSunk(Ship ship) =>
      ship.cells.every((c) => cells[c]?.sunkSegment == true);

  List<Widget> _marks(double cell) {
    final widgets = <Widget>[];
    for (final entry in cells.entries) {
      final s = entry.key;
      final v = entry.value;
      if (v.result == null) continue;
      widgets.add(
        Positioned(
          left: s.col * cell,
          top: s.row * cell,
          width: cell,
          height: cell,
          child: _ShotMark(result: v.result!),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _sunkOutlines(double cell) => sunkOutlines.map((o) {
        final rows = o.cells.map((c) => c.row).toList();
        final cols = o.cells.map((c) => c.col).toList();
        final minR = rows.reduce((a, b) => a < b ? a : b);
        final maxR = rows.reduce((a, b) => a > b ? a : b);
        final minC = cols.reduce((a, b) => a < b ? a : b);
        final maxC = cols.reduce((a, b) => a > b ? a : b);
        return Positioned(
          left: minC * cell + cell * .06,
          top: minR * cell + cell * .06,
          width: (maxC - minC + 1) * cell - cell * .12,
          height: (maxR - minR + 1) * cell - cell * .12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cell * .18),
              border: Border.all(
                color: const Color(0xFFC0392B),
                width: 2.5,
              ),
            ),
          ),
        );
      }).toList();

  Widget _tapLayer(double cell) => Positioned.fill(
        child: _TapLayer(cell: cell, onTap: (s) => onTap?.call(s)),
      );
}

class _ShipBar extends StatelessWidget {
  const _ShipBar({
    required this.type,
    required this.orientation,
    required this.sunk,
  });
  final ShipType type;
  final Orientation orientation;
  final bool sunk;

  (Color hull, Color cabin) get _colors => switch (type) {
        ShipType.battleship => sunk
            ? (const Color(0xFF7F8C9A), const Color(0xFF566573))
            : (const Color(0xFF5D6D7E), const Color(0xFF34495E)),
        ShipType.cruiser => sunk
            ? (const Color(0xFF9C7C0B), const Color(0xFF5D4A06))
            : (const Color(0xFFB7950B), const Color(0xFF7D6608)),
        ShipType.destroyer => sunk
            ? (const Color(0xFFA0571A), const Color(0xFF521F00))
            : (const Color(0xFFCA6F1E), const Color(0xFF6E2C00)),
        ShipType.submarine => sunk
            ? (const Color(0xFF3A6A8A), const Color(0xFF16425E))
            : (const Color(0xFF2874A6), const Color(0xFF1B4F72)),
      };

  @override
  Widget build(BuildContext context) {
    final (hull, cabin) = _colors;
    return CustomPaint(
      painter: _ShipPainter(
        type: type,
        orientation: orientation,
        sunk: sunk,
        hull: hull,
        cabin: cabin,
      ),
    );
  }
}

/// Рисует корабль: корпус с острым носом, надстройка (рубка), иллюминаторы.
/// Для подлодки — округлый корпус и перископ. Вертикальная ориентация
/// получается поворотом холста на 90°.
class _ShipPainter extends CustomPainter {
  _ShipPainter({
    required this.type,
    required this.orientation,
    required this.sunk,
    required this.hull,
    required this.cabin,
  });
  final ShipType type;
  final Orientation orientation;
  final bool sunk;
  final Color hull;
  final Color cabin;

  @override
  void paint(Canvas canvas, Size size) {
    final vertical = orientation == Orientation.vertical;
    canvas.save();
    if (vertical) {
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
    }
    final long = vertical ? size.height : size.width;
    final short = vertical ? size.width : size.height;
    final cy = short / 2;
    final r = short * 0.30;

    final path = Path()
      ..moveTo(0, cy - r * 0.7)
      ..quadraticBezierTo(0, cy - r, r * 0.8, cy - r)
      ..lineTo(long - r * 1.6, cy - r)
      ..lineTo(long, cy)
      ..lineTo(long - r * 1.6, cy + r)
      ..lineTo(r * 0.8, cy + r)
      ..quadraticBezierTo(0, cy + r, 0, cy + r * 0.7)
      ..close();
    canvas.drawPath(path, Paint()..color = hull);
    canvas.drawPath(
      path,
      Paint()
        ..color = hull.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      Path()
        ..moveTo(r * 0.8, cy - r * 0.7)
        ..lineTo(long - r * 1.6, cy - r * 0.7),
      Paint()
        ..color = Colors.white.withValues(alpha: sunk ? .15 : .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (type == ShipType.submarine) {
      final px = long * 0.45;
      canvas.drawLine(
        Offset(px, cy - r * 0.8),
        Offset(px, cy - r * 1.9),
        Paint()
          ..color = cabin
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(
        Offset(px, cy - r * 1.9),
        r * 0.28,
        Paint()..color = cabin,
      );
    } else {
      final cabinW = long * 0.22;
      final cabinH = r * 1.5;
      final cabinRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(long * 0.30, cy - r * 0.5 - cabinH, cabinW, cabinH),
        Radius.circular(r * 0.3),
      );
      canvas.drawRRect(cabinRect, Paint()..color = cabin);
      if (type == ShipType.battleship || type == ShipType.cruiser) {
        final mastX = long * 0.30 + cabinW * 0.7;
        canvas.drawLine(
          Offset(mastX, cy - r * 0.5 - cabinH),
          Offset(mastX, cy - r * 2.2),
          Paint()
            ..color = cabin
            ..strokeWidth = 1.3,
        );
      }
    }

    final portPaint = Paint()
      ..color = Colors.white.withValues(alpha: sunk ? .25 : .75);
    final n = type == ShipType.submarine ? 1 : math.max(1, type.size - 1);
    for (var i = 0; i < n; i++) {
      final px = long * (0.16 + i * 0.16);
      canvas.drawCircle(Offset(px, cy), r * 0.18, portPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShipPainter old) =>
      old.type != type ||
      old.orientation != orientation ||
      old.sunk != sunk ||
      old.hull != hull ||
      old.cabin != cabin;
}

class _ShotMark extends StatelessWidget {
  const _ShotMark({required this.result});
  final ShotResult result;
  @override
  Widget build(BuildContext context) {
    switch (result) {
      case ShotResult.miss:
        return Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF7FB3D5),
            ),
          ),
        );
      case ShotResult.hit:
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE74C3C).withValues(alpha: .25),
                ),
              ),
              Transform.rotate(
                angle: .785,
                child: Container(
                  width: 16,
                  height: 4,
                  color: const Color(0xFFC0392B),
                ),
              ),
              Transform.rotate(
                angle: -.785,
                child: Container(
                  width: 16,
                  height: 4,
                  color: const Color(0xFFC0392B),
                ),
              ),
            ],
          ),
        );
      case ShotResult.sunk:
        return Center(
          child: Transform.rotate(
            angle: .785,
            child: Container(
              width: 16,
              height: 4,
              color: const Color(0xFF7B241C),
            ),
          ),
        );
    }
  }
}

/// Рисует фон клеток (море/туман), подсветку необстрелянных и подсказку.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cell,
    required this.own,
    required this.unfired,
    required this.suggested,
    required this.cells,
  });
  final double cell;
  final bool own;
  final Set<Square> unfired;
  final Square? suggested;
  final Map<Square, CellView> cells;

  @override
  void paint(Canvas canvas, Size size) {
    final bgColor =
        own ? const Color(0xFFEAF2F8) : const Color(0xFFBFDCEE);
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    final inset = cell > 4 ? 1.5 : (cell > 1 ? (cell - 1) / 2 : 0.0);
    final radius = Radius.circular(math.max(0.0, cell * .12));
    for (final s in allSquares()) {
      final rect = Rect.fromLTWH(s.col * cell, s.row * cell, cell, cell);
      final isShip = cells[s]?.ship ?? false;
      final base = own
          ? (isShip ? const Color(0xFFD9E8F2) : const Color(0xFFEAF2F8))
          : const Color(0xFFBFDCEE);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(-inset), radius),
        Paint()..color = base,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(-inset), radius),
        Paint()
          ..color = Colors.white.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      if (unfired.contains(s)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect.inflate(-math.min(3.5, inset + 1)), radius),
          Paint()..color = const Color(0xFFFFD66D).withValues(alpha: .35),
        );
      }
      if (suggested == s) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect.inflate(-math.min(2.0, inset + 0.5)), radius),
          Paint()
            ..color = const Color(0xFF8266D5).withValues(alpha: .55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.min(3.0, cell * .15),
        );
      }
    }
  }

  /// Сравниваем value-поля: клетки, подсветку и подсказку. Контроллер не
  /// передаём — иначе сравнение по одному и тому же объекту всегда давало бы
  /// false и поле не перерисовывалось бы после выстрела.
  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.cells != cells ||
      old.unfired != unfired ||
      old.suggested != suggested;
}

/// Слой нажатий: делит поле на 10×10 и вызывает onTap с координатой.
class _TapLayer extends StatelessWidget {
  const _TapLayer({required this.cell, required this.onTap});
  final double cell;
  final void Function(Square) onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final c = (details.localPosition.dx / cell).floor();
          final r = (details.localPosition.dy / cell).floor();
          final s = Square(r, c);
          if (s.inside) onTap(s);
        },
      );
}

// ---- Оверлей анимации выстрела -------------------------------------------

/// Оверлей анимации выстрела поверх поля. Завершается по таймеру
/// (длительность берётся из [ShotAnimation.duration]).
class ShotOverlay extends StatefulWidget {
  const ShotOverlay({
    super.key,
    required this.animation,
    required this.cellSize,
    required this.target,
  });
  final ShotAnimation animation;
  final double cellSize;
  final Square target;

  @override
  State<ShotOverlay> createState() => _ShotOverlayState();
}

class _ShotOverlayState extends State<ShotOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animation.duration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.animation;
    final cell = widget.cellSize;
    final cx = widget.target.col * cell + cell / 2;
    final cy = widget.target.row * cell + cell / 2;
    return Positioned(
      left: cx - cell,
      top: cy - cell,
      width: cell * 2,
      height: cell * 2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ShotPainter(
            progress: _controller.value,
            result: a.shot.result,
            cell: cell,
          ),
        ),
      ),
    );
  }
}

class _ShotPainter extends CustomPainter {
  _ShotPainter({
    required this.progress,
    required this.result,
    required this.cell,
  });
  final double progress;
  final ShotResult result;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final double p = progress.clamp(0.0, 1.0).toDouble();
    final double fade = 1 - p;

    if (result == ShotResult.miss) {
      final ring = radius * (0.2 + 0.8 * p);
      final paint = Paint()
        ..color = const Color(0xFF7FB3D5).withValues(alpha: fade * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * fade + 1;
      canvas.drawCircle(center, ring, paint);
      final dropPaint = Paint()..color = const Color(0xFF5499C7);
      for (var i = 0; i < 6; i++) {
        final angle = i * 1.0472; // π/3
        final dist = radius * 0.4 * p;
        canvas.drawCircle(
          Offset(
            center.dx + dist * math.cos(angle),
            center.dy + dist * math.sin(angle),
          ),
          3 * fade + 0.5,
          dropPaint,
        );
      }
      return;
    }

    if (result == ShotResult.hit || result == ShotResult.sunk) {
      final flash = radius * (0.3 + 0.9 * p);
      final double alpha = 1 - p * 0.7;
      canvas.drawCircle(
        center,
        flash,
        Paint()
          ..color = const Color(0xFFE74C3C).withValues(alpha: alpha * 0.6),
      );
      canvas.drawCircle(
        center,
        flash * 0.6,
        Paint()..color = const Color(0xFFFFD66D).withValues(alpha: alpha),
      );
      final frag = Paint()..color = const Color(0xFFC0392B);
      for (var i = 0; i < 8; i++) {
        final angle = i * 0.785; // π/4
        final dist = radius * 0.5 * p;
        canvas.drawCircle(
          Offset(
            center.dx + dist * math.cos(angle),
            center.dy + dist * math.sin(angle),
          ),
          3 * fade + 0.8,
          frag,
        );
      }
      if (result == ShotResult.sunk) {
        final smoke = Paint()
          ..color = Colors.black54.withValues(alpha: p * 0.5);
        canvas.drawCircle(center, radius * 0.8 * p, smoke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShotPainter old) =>
      old.progress != progress || old.result != result;
}
