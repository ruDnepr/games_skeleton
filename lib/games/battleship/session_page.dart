import 'dart:math' as math;

import 'package:flutter/material.dart' hide Orientation;

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'battleship_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';

/// Точка входа в партию: с сетевым соединением — сразу расстановка по сети,
/// без него — выбор режима (против компьютера или вдвоём на одном устройстве).
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
        network: network,
      );
    }
    return BattleshipModePage(settings: settings);
  }
}

/// Выбор режима: против компьютера (с уровнем и правом первого хода) или вдвоём.
class BattleshipModePage extends StatefulWidget {
  const BattleshipModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<BattleshipModePage> createState() => _BattleshipModePageState();
}

class _BattleshipModePageState extends State<BattleshipModePage> {
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;
  bool _meFirst = true;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Морской бой',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ЯКОРЯ НА СТАРТ ⚓',
              title: 'С кем сыграем?',
              subtitle: 'Выбери режим — против компьютера или вдвоём на одном '
                  'устройстве.',
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
              const SizedBox(height: 14),
              const Text(
                'Кто ходит первым',
                style: TextStyle(fontWeight: FontWeight.w900, color: ink),
              ),
              const SizedBox(height: 8),
              _FirstRow(
                meFirst: _meFirst,
                onChanged: (v) => setState(() => _meFirst = v),
              ),
            ],
            const SizedBox(height: 14),
            _ModeTile(
              title: 'Двое на одном устройстве',
              subtitle: 'Ходы по очереди — каждый расставляет свой флот',
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
                key: const Key('battleship-start'),
                onPressed: () => _start(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('К расстановке'),
              ),
            ),
          ],
        ),
      );

  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BattleshipSetupPage(
          settings: widget.settings,
          vsAi: _vsAi,
          difficulty: _difficulty,
          meFirst: _meFirst,
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
              label: Difficulty.values[i].russianName,
              desc: Difficulty.values[i].russianSubtitle,
              selected: value.index == i,
              onTap: () => onChanged(Difficulty.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _FirstRow extends StatelessWidget {
  const _FirstRow({required this.meFirst, required this.onChanged});
  final bool meFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: 'Я первый',
              desc: 'Стреляешь первым',
              selected: meFirst,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: 'Компьютер первый',
              desc: 'Компьютер стреляет первым',
              selected: !meFirst,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      );
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? purple : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? purple : const Color(0xFFE3D8F5),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : ink,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? Colors.white.withValues(alpha: .85) : muted,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Экран расстановки кораблей. Один экран — один игрок. В локальном режиме
/// 2 на 1 экран сам переключается на второго игрока после готовности первого.
class BattleshipSetupPage extends StatefulWidget {
  const BattleshipSetupPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.meFirst = true,
    this.network,
  });
  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final bool meFirst;
  final NetworkSession? network;

  @override
  State<BattleshipSetupPage> createState() => _BattleshipSetupPageState();
}

class _BattleshipSetupPageState extends State<BattleshipSetupPage> {
  late final BattleshipController _controller;
  ShipType _selected = ShipType.battleship;
  Orientation _orientation = Orientation.horizontal;
  bool _navigatedToPlay = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = BattleshipController(
      settings: widget.settings,
      sounds: sounds,
      network: widget.network,
    );
    if (widget.network != null) {
      _controller.startNetwork();
    } else if (widget.vsAi) {
      _controller.startAi(widget.difficulty, meFirst: widget.meFirst);
    } else {
      _controller.startLocal();
    }
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (!mounted) return;
    if (_controller.phase == BattleshipPhase.playing && !_navigatedToPlay) {
      _navigatedToPlay = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BattleshipSessionPage(
              controller: _controller,
              settings: widget.settings,
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _selectNextShipType() {
    for (final type in ShipType.values) {
      if (_controller.remainingToPlace(type) > 0) {
        _selected = type;
        return;
      }
    }
  }

  void _onCellTap(Square cell) {
    if (_controller.myReady) return;
    if (_controller.remainingToPlace(_selected) <= 0) {
      _selectNextShipType();
    }
    // Сначала попробуем поставить выбранный корабль.
    if (_controller.remainingToPlace(_selected) > 0) {
      final placed = _controller.placeShip(_selected, cell, _orientation);
      if (placed) {
        if (_controller.remainingToPlace(_selected) == 0) {
          _selectNextShipType();
        }
        setState(() {});
        return;
      }
    }
    // Не вышло — может, тапнули по стоящему кораблю: уберём его.
    final ship = _controller.myFleet.shipAt(cell);
    if (ship != null) {
      _controller.removeShipAt(cell);
      setState(() {
        _selected = ship.type;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerLabel = _controller.mode == BattleshipMode.local
        ? (_controller.setupTurn == 0
            ? 'Игрок 1 расставляет флот'
            : 'Игрок 2 расставляет флот')
        : (_controller.mode == BattleshipMode.network
            ? 'Расставь свой флот'
            : 'Расставь свой флот');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Морской бой · Расстановка'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'В меню',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 510),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        playerLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Arsenal(
                        controller: _controller,
                        selected: _selected,
                        onSelect: (t) => setState(() => _selected = t),
                      ),
                      const SizedBox(height: 12),
                      _OrientationToggle(
                        orientation: _orientation,
                        onChanged: (o) => setState(() => _orientation = o),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: _SetupBoard(
                          fleet: _controller.myFleet,
                          orientation: _orientation,
                          selected: _selected,
                          canPlace: (origin) => _controller.canPlaceShip(
                            _selected,
                            origin,
                            _orientation,
                          ),
                          onTap: _onCellTap,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionChip(
                              icon: Icons.shuffle_rounded,
                              label: 'Случайно',
                              onTap: () {
                                _controller.autoArrange();
                                _selectNextShipType();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionChip(
                              icon: Icons.delete_outline_rounded,
                              label: 'Очистить',
                              onTap: () {
                                _controller.clearFleet();
                                _selected = ShipType.battleship;
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ReadyButton(
                        controller: _controller,
                        onTap: () {
                          _controller.fleetReady();
                        },
                      ),
                      if (_controller.status != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _controller.status!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Арсенал кораблей: четыре типа с остатком. Тап по типу выбирает его.
class _Arsenal extends StatelessWidget {
  const _Arsenal({
    required this.controller,
    required this.selected,
    required this.onSelect,
  });
  final BattleshipController controller;
  final ShipType selected;
  final ValueChanged<ShipType> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            for (final type in ShipType.values) ...[
              if (type != ShipType.values.first) const SizedBox(width: 8),
              Expanded(
                child: _ArsenalChip(
                  type: type,
                  remaining: controller.remainingToPlace(type),
                  selected: type == selected &&
                      controller.remainingToPlace(type) > 0,
                  onTap: controller.remainingToPlace(type) > 0
                      ? () => onSelect(type)
                      : null,
                ),
              ),
            ],
          ],
        ),
      );
}

class _ArsenalChip extends StatelessWidget {
  const _ArsenalChip({
    required this.type,
    required this.remaining,
    required this.selected,
    required this.onTap,
  });
  final ShipType type;
  final int remaining;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final total = type.count;
    final done = remaining == 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? purple
              : (done
                  ? const Color(0xFFE8F4E8)
                  : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? purple
                : (done
                    ? const Color(0xFFC8E6C9)
                    : const Color(0xFFE3D8F5)),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < type.size; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : (done ? const Color(0xFF4CAF50) : purple),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              type.russianLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: selected
                    ? Colors.white
                    : (done ? const Color(0xFF2E7D32) : ink),
              ),
            ),
            Text(
              '$remaining/$total',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.white.withValues(alpha: .85)
                    : (done ? const Color(0xFF2E7D32) : muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrientationToggle extends StatelessWidget {
  const _OrientationToggle({
    required this.orientation,
    required this.onChanged,
  });
  final Orientation orientation;
  final ValueChanged<Orientation> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleChip(
              label: 'Горизонтально',
              icon: Icons.arrow_right_rounded,
              selected: orientation == Orientation.horizontal,
              onTap: () => onChanged(Orientation.horizontal),
            ),
            const SizedBox(width: 6),
            _ToggleChip(
              label: 'Вертикально',
              icon: Icons.arrow_drop_down_rounded,
              selected: orientation == Orientation.vertical,
              onTap: () => onChanged(Orientation.vertical),
            ),
          ],
        ),
      );
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? purple : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? Colors.white : purple, size: 20),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : ink,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: purple, size: 20),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReadyButton extends StatelessWidget {
  const _ReadyButton({required this.controller, required this.onTap});
  final BattleshipController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final complete = controller.myFleetComplete;
    final ready = controller.myReady;
    final waiting = ready && !controller.enemyReady;
    final label = ready
        ? (controller.mode == BattleshipMode.network
            ? (waiting ? 'Ждём друга…' : 'В бой!')
            : 'В бой!')
        : 'В бой!';
    final enabled = complete && !ready;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        key: const Key('battleship-ready'),
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.sailing_rounded),
        label: Text(label),
      ),
    );
  }
}

/// Виджет одного поля 10×10 в расстановке: рисует флот, подсвечивает
/// предпросмотр выбранного корабля, обрабатывает тап.
class _SetupBoard extends StatelessWidget {
  const _SetupBoard({
    required this.fleet,
    required this.orientation,
    required this.selected,
    required this.canPlace,
    required this.onTap,
  });
  final Fleet fleet;
  final Orientation orientation;
  final ShipType selected;
  final bool Function(Square origin) canPlace;
  final void Function(Square cell) onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final maxSize = math.min(constraints.maxWidth, 360.0);
          return SizedBox(
            width: maxSize,
            height: maxSize,
            child: GestureDetector(
              onTapUp: (details) {
                final cellSize = maxSize / (boardSize + 1);
                final dx = details.localPosition.dx - cellSize;
                final dy = details.localPosition.dy - cellSize;
                final col = (dx / cellSize).floor();
                final row = (dy / cellSize).floor();
                if (row < 0 ||
                    row >= boardSize ||
                    col < 0 ||
                    col >= boardSize) {
                  return;
                }
                onTap(Square(row, col));
              },
              child: CustomPaint(

                painter: _BoardPainter(
                  size: maxSize,
                  ships: fleet.ships,
                  myShots: const {},
                  enemyShots: const {},
                  sunkOutlines: const [],
                  showShips: true,
                  unfiredHighlight: const {},
                  hintCell: null,
                  previewShip: _PreviewShip(
                    type: selected,
                    orientation: orientation,
                    canPlaceAt: canPlace,
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// Информация о предпросматриваемом корабле в расстановке.
class _PreviewShip {
  const _PreviewShip({
    required this.type,
    required this.orientation,
    required this.canPlaceAt,
  });
  final ShipType type;
  final Orientation orientation;
  final bool Function(Square origin) canPlaceAt;
}

/// Экран партии: два поля 10×10 (сверху — соперник, снизу — своё), строка
/// состояния, кнопки управления. Туман войны: на поле соперника кораблей не
/// видно, только промахи/попадания/обводки потопленных.
class BattleshipSessionPage extends StatefulWidget {
  const BattleshipSessionPage({
    super.key,
    required this.controller,
    required this.settings,
  });
  final BattleshipController controller;
  final SettingsController settings;

  @override
  State<BattleshipSessionPage> createState() => _BattleshipSessionPageState();
}

class _BattleshipSessionPageState extends State<BattleshipSessionPage> {
  bool _endShown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maybeShowEnd);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybeShowEnd);
    super.dispose();
  }

  void _maybeShowEnd() {
    if (!mounted) return;
    if (widget.controller.isOver && !_endShown) {
      _endShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
    }
  }

  void _showEndDialog() {
    if (!mounted) return;
    final controller = widget.controller;
    final iWon = controller.mode == BattleshipMode.network
        ? controller.winner == controller._mySideForWidget
        : (controller.mode == BattleshipMode.ai
            ? controller.winner == Side.me
            : true);
    final title = iWon
        ? (controller.mode == BattleshipMode.local
            ? 'Победа!'
            : 'Победа! Ты потопил весь флот!')
        : 'Партия окончена';
    final message = iWon
        ? 'Отличная партия! Так держать ✨'
        : 'Не беда — в следующий раз обязательно получится!';
    showDianaDialog<bool>(
      context: context,
      title: title,
      barrierDismissible: false,
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: [
        DianaDialogButton<bool>(
          label: 'Играть снова',
          key: const Key('battleship-play-again'),
          value: true,
          primary: true,
        ),
        const DianaDialogButton<bool>(label: 'В меню', value: false),
      ],
    ).then((again) {
      if (!mounted) return;
      if (again == true && widget.controller.mode != BattleshipMode.network) {
        // Офлайн: перезапускаем партию того же режима на свежем экране.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BattleshipSetupPage(
              settings: widget.settings,
              vsAi: widget.controller.mode == BattleshipMode.ai,
              difficulty: widget.controller.difficulty,
              meFirst: true,
            ),
          ),
        );
      } else {
        Navigator.of(context).maybePop();
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
            label: 'Не сдаваться', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) widget.controller.resign();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Морской бой для Дианы'),
        actions: [
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => IconButton(
              key: const Key('sound-toggle'),
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
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Сдаться',
            onPressed:
                controller.canResign ? _confirmResign : null,
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'В меню',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 510),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final topLabel = _topBoardLabel();
                  final bottomLabel = _bottomBoardLabel();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _statusLine(),
                        const SizedBox(height: 6),
                        _boardLabel(topLabel, true),
                        Expanded(
                          child: Center(child: _enemyBoard()),
                        ),
                        _boardLabel(bottomLabel, false),
                        Expanded(
                          child: Center(child: _myBoard()),
                        ),
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

  /// Подпись верхнего поля. В локальном режиме 2 на 1 — какой игрок сейчас
  /// соперник; в сети и против компьютера — «Поле соперника».
  String _topBoardLabel() {
    if (controller.mode == BattleshipMode.local) {
      return controller.turn == Side.me
          ? 'Поле игрока 2'
          : 'Поле игрока 1';
    }
    if (controller.mode == BattleshipMode.network) {
      return 'Поле друга';
    }
    return 'Поле соперника';
  }

  /// Подпись нижнего поля. В локальном режиме 2 на 1 — какой игрок сейчас
  /// расставляет/стреляет; в сети и против компьютера — «Моё поле».
  String _bottomBoardLabel() {
    if (controller.mode == BattleshipMode.local) {
      return controller.turn == Side.me
          ? 'Поле игрока 1'
          : 'Поле игрока 2';
    }
    return 'Моё поле';
  }

  Widget _statusLine() {
    final controller = widget.controller;
    final data = _perspective();
    // «Потоплено» — сколько кораблей соперника потопил текущий игрок (по
    // «sunk» в его выстрелах).
    final sunk = data.topShots.values
        .where((s) => s.result == ShotResult.sunk)
        .length;
    // «Потеряно» — сколько кораблей текущего игрока потопил соперник.
    final lost = data.bottomShots.values
        .where((s) => s.result == ShotResult.sunk)
        .length;
    return SizedBox(
      height: 44,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                controller.status ?? controller.turnLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: ink,
                ),
              ),
            ),
            _counter('Потоплено', sunk, totalShips),
            const SizedBox(width: 10),
            _counter('Потеряно', lost, totalShips, danger: true),
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
              fontSize: 15,
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

  /// Раскладка полей по «верхнему» (поле соперника — туда стреляет текущий
  /// игрок) и «нижнему» (моё поле — по нему стреляют по мне). В локальном
  /// режиме 2 на 1, когда ход перешёл ко второму игроку, поля меняются
  /// местами: верхним становится флот первого игрока (для второго — это
  /// соперник), нижним — флот второго игрока.
  _Perspective _perspective() {
    final controller = widget.controller;
    if (controller.mode == BattleshipMode.local &&
        controller.turn == Side.enemy) {
      return _Perspective(
        topFleet: controller.myFleet,
        topShots: controller.enemyShots,
        bottomFleet: controller.enemyFleet,
        bottomShots: controller.myShots,
      );
    }
    return _Perspective(
      topFleet: controller.enemyFleet,
      topShots: controller.myShots,
      bottomFleet: controller.myFleet,
      bottomShots: controller.enemyShots,
    );
  }

  Widget _enemyBoard() => LayoutBuilder(
        builder: (context, constraints) {
          final maxSize = math.min(
            math.min(constraints.maxWidth, constraints.maxHeight),
            240.0,
          );
          final data = _perspective();
          return SizedBox(
            width: maxSize,
            height: maxSize,
            child: GestureDetector(
              onTapUp: controller.canInteract
                  ? (details) {
                      final cellSize = maxSize / (boardSize + 1);
                      final dx = details.localPosition.dx - cellSize;
                      final dy = details.localPosition.dy - cellSize;
                      final col = (dx / cellSize).floor();
                      final row = (dy / cellSize).floor();
                      if (row < 0 ||
                          row >= boardSize ||
                          col < 0 ||
                          col >= boardSize) {
                        return;
                      }
                      final target = Square(row, col);
                      if (data.topShots.containsKey(target)) {
                        return;
                      }
                      controller.shoot(target);
                    }
                  : null,
              child: CustomPaint(

                painter: _BoardPainter(
                  size: maxSize,
                  ships: const [],
                  myShots: data.topShots,
                  enemyShots: const {},
                  sunkOutlines: _sunkOutlinesFromShots(data.topShots),
                  showShips: false,
                  unfiredHighlight: controller.hintsEnabled &&
                          controller.canInteract
                      ? _unfiredHighlight(data.topShots)
                      : const {},
                  hintCell: controller.hint,
                ),
              ),
            ),
          );
        },
      );

  Widget _myBoard() => LayoutBuilder(
        builder: (context, constraints) {
          final maxSize = math.min(
            math.min(constraints.maxWidth, constraints.maxHeight),
            240.0,
          );
          final data = _perspective();
          return SizedBox(
            width: maxSize,
            height: maxSize,
            child: CustomPaint(

              painter: _BoardPainter(
                size: maxSize,
                ships: data.bottomFleet.ships,
                myShots: const {},
                enemyShots: data.bottomShots,
                sunkOutlines: _sunkOutlinesFromFleet(
                  data.bottomFleet,
                  data.bottomShots,
                ),
                showShips: true,
                unfiredHighlight: const {},
                hintCell: null,
              ),
            ),
          );
        },
      );

  /// Обводки потопленных кораблей на поле соперника — восстанавливаем контур
  /// по смежным попаданиям. В сети мы не знаем тип потопленного корабля, но
  /// обводку по клеткам нарисуем.
  List<_SunkOutline> _sunkOutlinesFromShots(Map<Square, Shot> shots) {
    final outlines = <_SunkOutline>[];
    final done = <Square>{};
    for (final shot in shots.values) {
      if (shot.result != ShotResult.sunk) continue;
      if (done.contains(shot.square)) continue;
      final cells = _contiguousHits(shots, shot.square);
      done.addAll(cells);
      outlines.add(_SunkOutline(cells: cells.toList(), type: shot.sunkType));
    }
    return outlines;
  }

  /// Обводки потопленных кораблей на моём поле — я знаю свои корабли, поэтому
  /// просто прохожусь по потопленным.
  List<_SunkOutline> _sunkOutlinesFromFleet(
    Fleet fleet,
    Map<Square, Shot> shots,
  ) {
    final outlines = <_SunkOutline>[];
    for (final ship in fleet.ships) {
      final sunk = ship.cells.every((c) {
        final s = shots[c];
        return s != null && s.result != ShotResult.miss;
      });
      if (sunk) {
        outlines.add(_SunkOutline(cells: ship.cells, type: ship.type));
      }
    }
    return outlines;
  }

  /// Клетки, смежные с [anchor] по горизонтали и вертикали, в которых есть
  /// попадание (hit или sunk). Нужны для восстановления контура потопленного
  /// корабля на поле соперника.
  Set<Square> _contiguousHits(Map<Square, Shot> shots, Square anchor) {
    Set<Square> expand(Square from, int dr, int dc) {
      final result = <Square>{};
      var cur = from;
      while (true) {
        final next = Square(cur.row + dr, cur.col + dc);
        if (!next.inside) break;
        final s = shots[next];
        if (s == null || s.result == ShotResult.miss) break;
        result.add(next);
        cur = next;
      }
      return result;
    }

    final result = <Square>{anchor};
    result.addAll(expand(anchor, 0, 1));
    result.addAll(expand(anchor, 0, -1));
    result.addAll(expand(anchor, 1, 0));
    result.addAll(expand(anchor, -1, 0));
    return result;
  }

  Set<Square> _unfiredHighlight(Map<Square, Shot> shots) {
    final fired = shots.keys.toSet();
    final all = allSquares().toSet();
    return all.difference(fired);
  }

  BattleshipController get controller => widget.controller;

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: _CtrlButton(
                icon: Icons.lightbulb_rounded,
                label: 'Подсказка',
                enabled: controller.hintsEnabled &&
                    controller.canInteract &&
                    controller.hint == null,
                onTap: controller.showHint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CtrlButton(
                icon: Icons.undo_rounded,
                label: 'Отменить',
                enabled: controller.canUndo,
                onTap: controller.undo,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CtrlButton(
                icon: Icons.flag_outlined,
                label: 'Сдаться',
                enabled: controller.canResign,
                onTap: _confirmResign,
              ),
            ),
          ],
        ),
      );
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
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
              height: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: purple, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Обводка одного потопленного корабля для рисования контуром.
class _SunkOutline {
  const _SunkOutline({required this.cells, this.type});
  final List<Square> cells;
  final ShipType? type;
}

/// Раскладка полей для текущего игрока: какое поле рисовать сверху (поле
/// соперника — туда стреляет текущий игрок), какое снизу (своё поле). В
/// локальном режиме 2 на 1 раскладка меняется при смене хода.
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

/// Один painter для двух полей: рисует сетку, метки, корабли, выстрелы,
/// обводки, предпросмотр и подсказку. Что рисовать — определяется флагами.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.size,
    required this.ships,
    required this.myShots,
    required this.enemyShots,
    required this.sunkOutlines,
    required this.showShips,
    required this.unfiredHighlight,
    required this.hintCell,
    this.previewShip,
  });

  /// Размер квадратного поля в пикселях (включая метки).
  final double size;
  final List<Ship> ships;
  final Map<Square, Shot> myShots;
  final Map<Square, Shot> enemyShots;
  final List<_SunkOutline> sunkOutlines;
  final bool showShips;
  final Set<Square> unfiredHighlight;
  final Square? hintCell;
  final _PreviewShip? previewShip;

  static const _gridColor = Color(0xFFC9D6E8);
  static const _seaColor = Color(0xFFDDE7F3);
  static const _seaColorAlt = Color(0xFFCFDDEF);
  static const _shipColor = Color(0xFF4B6FB5);
  static const _shipBorderColor = Color(0xFF2E4985);
  static const _missColor = Color(0xFF8AA0BA);
  static const _hitColor = Color(0xFFE25757);
  static const _sunkOutlineColor = Color(0xFFC0392B);
  static const _labelColor = Color(0xFF6E7891);
  static const _previewOkColor = Color(0x554B6FB5);
  static const _hintColor = Color(0xFFF0BE48);
  static const _unfiredColor = Color(0x1A8266D5);

  double get cell => size / (boardSize + 1);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // Поле с метками: первая строка/столбец — подписи, остальное — клетки.
    final cellSize = cell;

    // Подписи столбцов (буквы РЕСПУБЛИКА) — верхняя строка.
    final labelPaint = Paint()
      ..color = _labelColor
      ..style = PaintingStyle.fill;
    for (var c = 0; c < boardSize; c++) {
      final letter = columnLetters[c];
      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: _labelColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cellSize + c * cellSize + (cellSize - tp.width) / 2,
          (cellSize - tp.height) / 2,
        ),
      );
    }
    // Подписи строк (1..10) — левый столбец.
    for (var r = 0; r < boardSize; r++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${r + 1}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: _labelColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (cellSize - tp.width) / 2,
          cellSize + r * cellSize + (cellSize - tp.height) / 2,
        ),
      );
    }
    // Заливка клеток морем.
    for (var r = 0; r < boardSize; r++) {
      for (var c = 0; c < boardSize; c++) {
        final rect = Rect.fromLTWH(
          cellSize + c * cellSize,
          cellSize + r * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = (r + c).isEven ? _seaColor : _seaColorAlt,
        );
      }
    }
    // Сетка.
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i <= boardSize; i++) {
      canvas.drawLine(
        Offset(cellSize + i * cellSize, cellSize),
        Offset(cellSize + i * cellSize, cellSize + boardSize * cellSize),
        gridPaint,
      );
      canvas.drawLine(
        Offset(cellSize, cellSize + i * cellSize),
        Offset(cellSize + boardSize * cellSize, cellSize + i * cellSize),
        gridPaint,
      );
    }
    // Подсветка необстрелянных клеток (если включены подсказки).
    if (unfiredHighlight.isNotEmpty) {
      final paint = Paint()..color = _unfiredColor;
      for (final s in unfiredHighlight) {
        final rect = Rect.fromLTWH(
          cellSize + s.col * cellSize + 2,
          cellSize + s.row * cellSize + 2,
          cellSize - 4,
          cellSize - 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );
      }
    }
    // Предпросмотр постановки корабля (только в расстановке).
    if (previewShip != null) {
      for (var r = 0; r < boardSize; r++) {
        for (var c = 0; c < boardSize; c++) {
          final origin = Square(r, c);
          final ok = previewShip!.canPlaceAt(origin);
          if (!ok) continue;
          final len = previewShip!.type.size;
          final orient = previewShip!.orientation;
          final rect = Rect.fromLTWH(
            cellSize + c * cellSize + 2,
            cellSize + r * cellSize + 2,
            (orient == Orientation.horizontal ? len * cellSize : cellSize) - 4,
            (orient == Orientation.vertical ? len * cellSize : cellSize) - 4,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = _previewOkColor,
          );
        }
      }
    }
    // Корабли (только на своём поле).
    if (showShips) {
      for (final ship in ships) {
        _drawShip(canvas, ship, cellSize);
      }
    }
    // Обводки потопленных кораблей.
    for (final outline in sunkOutlines) {
      _drawSunkOutline(canvas, outline, cellSize);
    }
    // Мои выстрелы по сопернику (на верхнем поле).
    for (final entry in myShots.entries) {
      _drawShot(canvas, entry.key, entry.value.result, cellSize);
    }
    // Выстрелы соперника по мне (на нижнем поле).
    for (final entry in enemyShots.entries) {
      _drawShot(canvas, entry.key, entry.value.result, cellSize);
    }
    // Подсказка.
    if (hintCell != null) {
      final rect = Rect.fromLTWH(
        cellSize + hintCell!.col * cellSize + 3,
        cellSize + hintCell!.row * cellSize + 3,
        cellSize - 6,
        cellSize - 6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = _hintColor.withValues(alpha: .55),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = _hintColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Подпись «подсказка» suppressed (игнорируем, чтобы не плодить мусор).
    labelPaint.toString(); // keep ref to silence unused warning
  }

  void _drawShip(Canvas canvas, Ship ship, double cellSize) {
    final cells = ship.cells;
    final first = cells.first;
    final last = cells.last;
    final rect = Rect.fromLTRB(
      cellSize + first.col * cellSize + 2,
      cellSize + first.row * cellSize + 2,
      cellSize + (last.col + 1) * cellSize - 2,
      cellSize + (last.row + 1) * cellSize - 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = _shipColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()
        ..color = _shipBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Нос корабля — кружок, чтобы он выглядел как кораблик.
    final dot = Rect.fromCenter(
      center: rect.center,
      width: rect.width * .25,
      height: rect.height * .25,
    );
    canvas.drawOval(dot, Paint()..color = _shipBorderColor);
  }

  void _drawSunkOutline(
    Canvas canvas,
    _SunkOutline outline,
    double cellSize,
  ) {
    if (outline.cells.isEmpty) return;
    final cells = outline.cells;
    final rows = cells.map((c) => c.row).toList();
    final cols = cells.map((c) => c.col).toList();
    final minR = rows.reduce(math.min);
    final maxR = rows.reduce(math.max);
    final minC = cols.reduce(math.min);
    final maxC = cols.reduce(math.max);
    final rect = Rect.fromLTRB(
      cellSize + minC * cellSize + 1,
      cellSize + minR * cellSize + 1,
      cellSize + (maxC + 1) * cellSize - 1,
      cellSize + (maxR + 1) * cellSize - 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = _sunkOutlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawShot(
    Canvas canvas,
    Square cell,
    ShotResult result,
    double cellSize,
  ) {
    final center = Offset(
      cellSize + cell.col * cellSize + cellSize / 2,
      cellSize + cell.row * cellSize + cellSize / 2,
    );
    switch (result) {
      case ShotResult.miss:
        // Точка — брызга от выстрела мимо.
        canvas.drawCircle(
          center,
          cellSize * 0.16,
          Paint()..color = _missColor,
        );
        break;
      case ShotResult.hit:
        // Крестик — попадание.
        final r = cellSize * 0.28;
        final paint = Paint()
          ..color = _hitColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - r, center.dy - r),
          Offset(center.dx + r, center.dy + r),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx - r, center.dy + r),
          Offset(center.dx + r, center.dy - r),
          paint,
        );
        break;
      case ShotResult.sunk:
        // Заполненная клетка — потоплена (контур рисуется отдельно).
        final rect = Rect.fromCenter(
          center: center,
          width: cellSize * 0.7,
          height: cellSize * 0.7,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = _hitColor,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.size != size ||
      oldDelegate.ships != ships ||
      oldDelegate.myShots != myShots ||
      oldDelegate.enemyShots != enemyShots ||
      oldDelegate.sunkOutlines != sunkOutlines ||
      oldDelegate.showShips != showShips ||
      oldDelegate.unfiredHighlight != unfiredHighlight ||
      oldDelegate.hintCell != hintCell ||
      oldDelegate.previewShip != previewShip;
}

/// Расширение, чтобы достать `_mySide` из контроллера для расчёта победителя
/// в сети. Внутренний метод контроллера не публичный, поэтому дублируем логику.
extension on BattleshipController {
  Side get _mySideForWidget =>
      mode == BattleshipMode.network ? (isHost ? Side.me : Side.enemy) : Side.me;
}
