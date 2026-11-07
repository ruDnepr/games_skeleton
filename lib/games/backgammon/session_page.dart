import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'backgammon_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'network.dart';
import 'ui/backgammon_game.dart';
import 'ui/dice_widget.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети тем
/// вариантом, который выбрал хост, без него — выбор варианта, потом режима.
class BackgammonEntryPage extends StatelessWidget {
  const BackgammonEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      // Вариант выбирает хост до создания сетевой игры; клиент принимает тот,
      // что пришёл в рукопожатии.
      final variantStr =
          network!.lobby.options['variant'] as String? ?? 'short';
      final variant = variantStr == 'long'
          ? BackgammonVariant.long
          : BackgammonVariant.short;
      return BackgammonSessionPage(
        settings: settings,
        network: network,
        variant: variant,
      );
    }
    return BackgammonVariantPage(settings: settings);
  }
}

/// Выбор варианта нард: короткие или длинные. Показывается перед выбором
/// режима (для локальной партии) или перед сетевым лобби (тогда [forNetwork]
/// true, и выбор сохраняется в настройках, чтобы уехать в рукопожатие через
/// [backgammonOptions]).
class BackgammonVariantPage extends StatefulWidget {
  const BackgammonVariantPage({
    super.key,
    required this.settings,
    this.forNetwork = false,
  });
  final SettingsController settings;
  final bool forNetwork;

  @override
  State<BackgammonVariantPage> createState() => _BackgammonVariantPageState();
}

class _BackgammonVariantPageState extends State<BackgammonVariantPage> {
  late BackgammonVariant _variant;

  @override
  void initState() {
    super.initState();
    final stored = widget.settings.gameString(
      backgammonGameId,
      backgammonVariantKey,
      'short',
    );
    _variant =
        stored == 'long' ? BackgammonVariant.long : BackgammonVariant.short;
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Нарды',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ВЫБЕРИ ВАРИАНТ',
          title: 'Какие нарды?',
          subtitle: 'Короткие — с выбиванием шашек. Длинные — гонка без '
              'выбивания, все шашки на «голове».',
        ),
        const SizedBox(height: 22),
        _ModeTile(
          title: 'Короткие нарды',
          subtitle: 'Выбиваешь шашки соперника и спешишь домой',
          icon: Icons.casino_rounded,
          color: const Color(0xFFFCE4D7),
          selected: _variant == BackgammonVariant.short,
          onTap: () => setState(() => _variant = BackgammonVariant.short),
        ),
        const SizedBox(height: 14),
        _ModeTile(
          title: 'Длинные нарды',
          subtitle: 'Гонка без выбивания: строй блоки и спеши домой',
          icon: Icons.donut_large_rounded,
          color: const Color(0xFFEDE6FF),
          selected: _variant == BackgammonVariant.long,
          onTap: () => setState(() => _variant = BackgammonVariant.long),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            key: const Key('backgammon-variant-next'),
            onPressed: () => _next(context),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(widget.forNetwork ? 'К сетевой игре' : 'Дальше'),
          ),
        ),
      ],
    ),
  );

  Future<void> _next(BuildContext context) async {
    await widget.settings.setGameString(
      backgammonGameId,
      backgammonVariantKey,
      _variant == BackgammonVariant.long ? 'long' : 'short',
    );
    if (!mounted) return;
    if (widget.forNetwork) {
      // Выбор сделан — возвращаемся, чтобы открылось сетевое лобби.
      Navigator.of(context).maybePop();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackgammonModePage(
          settings: widget.settings,
          variant: _variant,
        ),
      ),
    );
  }
}

/// Выбор режима: против компьютера (с уровнем и цветом) или вдвоём.
class BackgammonModePage extends StatefulWidget {
  const BackgammonModePage({
    super.key,
    required this.settings,
    this.variant = BackgammonVariant.short,
  });
  final SettingsController settings;
  final BackgammonVariant variant;

  @override
  State<BackgammonModePage> createState() => _BackgammonModePageState();
}

class _BackgammonModePageState extends State<BackgammonModePage> {
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;
  Player _color = Player.white;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.variant == BackgammonVariant.long
        ? 'Длинные нарды'
        : 'Короткие нарды',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
          title: 'С кем сыграем?',
          subtitle: 'Выбери режим — против компьютера или вдвоём на одном устройстве.',
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
            'Твой цвет',
            style: TextStyle(fontWeight: FontWeight.w900, color: ink),
          ),
          const SizedBox(height: 8),
          _ColorRow(
            value: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
        ],
        const SizedBox(height: 14),
        _ModeTile(
          title: 'Двое на одном устройстве',
          subtitle: 'Ходы по очереди — белые снизу, чёрные сверху',
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
            key: const Key('backgammon-start'),
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
        builder: (_) => BackgammonSessionPage(
          settings: widget.settings,
          vsAi: _vsAi,
          difficulty: _difficulty,
          humanColor: _color,
          variant: widget.variant,
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
    const labels = ['Лёгкий', 'Средний', 'Сложный'];
    const descs = ['Часто уступает', 'Играет ровно', 'Думает на ход вперёд'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: labels[i],
              desc: descs[i],
              selected: value.index == i,
              onTap: () => onChanged(Difficulty.values[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.value, required this.onChanged});
  final Player value;
  final ValueChanged<Player> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ChoiceChip(
          label: 'Белые',
          desc: 'Ходишь первым',
          selected: value == Player.white,
          onTap: () => onChanged(Player.white),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ChoiceChip(
          label: 'Чёрные',
          desc: 'Компьютер ходит первым',
          selected: value == Player.black,
          onTap: () => onChanged(Player.black),
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
              color: selected ? Colors.white.withValues(alpha: .85) : muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Экран партии: доска (Flame) посередине, сверху — чей ход и кости, снизу —
/// кнопки управления. Всё, кроме поля, фиксированной высоты; поле — остаток.
class BackgammonSessionPage extends StatefulWidget {
  const BackgammonSessionPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.humanColor = Player.white,
    this.network,
    this.variant = BackgammonVariant.short,
  });
  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final Player humanColor;
  final NetworkSession? network;
  final BackgammonVariant variant;

  @override
  State<BackgammonSessionPage> createState() => _BackgammonSessionPageState();
}

class _BackgammonSessionPageState extends State<BackgammonSessionPage> {
  late final BackgammonController _controller;
  late final BackgammonGame _game;
  bool _winShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = BackgammonController(
      settings: widget.settings,
      sounds: sounds,
      network: widget.network,
      variant: widget.variant,
    )..onUndoRequested = _showUndoRequest;
    if (widget.network != null) {
      _controller.startNetwork();
    } else if (widget.vsAi) {
      _controller.startAi(widget.difficulty, widget.humanColor);
    } else {
      _controller.startLocal();
    }
    _game = BackgammonGame(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showUndoRequest() {
    if (!mounted) return;
    showDianaDialog<bool>(
      context: context,
      title: 'Отменить ход?',
      content: const Text(
        'Друг просит отменить последний ход. Разрешить?',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Разрешить', value: true, primary: true),
        DianaDialogButton<bool>(label: 'Не сейчас', value: false),
      ],
    ).then((accepted) {
      if (accepted == true) {
        _controller.respondUndo(true);
      } else {
        _controller.respondUndo(false);
      }
    });
  }

  void _maybeShowWin() {
    if (_controller.phase == GamePhase.over && !_winShown) {
      _winShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWinDialog());
    }
  }

  void _showWinDialog() {
    if (!mounted) return;
    final iWon = _controller.mode == GameMode.network
        ? _controller.state.winner ==
            (_controller.isHost ? Player.white : Player.black)
        : (_controller.mode == GameMode.ai
            ? _controller.state.winner == widget.humanColor
            : true);
    final winnerName = _controller.state.winner == Player.white
        ? 'Белые'
        : 'Чёрные';
    final title = iWon
        ? (_controller.mode == GameMode.local ? 'Победили $winnerName!' : 'Ты молодец!')
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
          key: const Key('backgammon-play-again'),
          value: true,
          primary: true,
        ),
        const DianaDialogButton<bool>(label: 'В меню', value: false),
      ],
    ).then((again) {
      if (!mounted) return;
      if (again == true && widget.network == null) {
        // Офлайн: перезапускаем партию того же режима на свежем экране.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BackgammonSessionPage(
              settings: widget.settings,
              vsAi: widget.vsAi,
              difficulty: widget.difficulty,
              humanColor: widget.humanColor,
              network: widget.network,
              variant: widget.variant,
            ),
          ),
        );
      } else {
        // В меню/лобби: сетевой рематч требует новой комнаты.
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowWin();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Нарды для Дианы'),
        actions: [
          // Звук можно выключить прямо в игре — как в шашках.
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
            onPressed: _canResign ? _confirmResign : null,
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
                listenable: _controller,
                builder: (context, _) {
                  // Панели зафиксированы: белые всегда сверху, чёрные всегда
                  // снизу — как в реальных нардах. Бейдж «ХОД» показывает, чья
                  // очередь; панели не «прыгают» при смене хода. В локальном
                  // режиме верхняя панель повёрнута на 180°, чтобы игрок по ту
                  // сторону стола читал имя нормально.
                  const topSide = Player.white;
                  const bottomSide = Player.black;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _playerPanel(topSide, top: true),
                        const SizedBox(height: 6),
                        _diceStrip(),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 0.84,
                              child: RepaintBoundary(
                                child: GameWidget(game: _game),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _playerPanel(bottomSide, top: false),
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

  bool get _canResign =>
      _controller.phase == GamePhase.playing &&
      _controller.mode != GameMode.local;

  /// Панель игрока: имя, цвет, бейдж «ХОД» когда его очередь. В локальном
  /// режиме верхняя панель повёрнута — так два игрока на одном устройстве
  /// каждый видят свою сторону.
  Widget _playerPanel(Player side, {required bool top}) {
    final active = _controller.currentTurn == side &&
        _controller.phase == GamePhase.playing;
    final isWhite = side == Player.white;
    final name = _controller.playerName(side);
    final panel = Container(
      key: Key(top ? 'top-player-panel' : 'bottom-player-panel'),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
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
          _SideDot(white: isWhite),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          if (active)
            const Eyebrow(
              'ХОД',
              color: deepPurple,
              background: Color(0xFFDCCDF8),
              fontSize: 10,
            ),
        ],
      ),
    );
    // В локальном режиме верхнюю панель поворачиваем — игрок по ту сторону
    // стола читает её нормально.
    if (top && _controller.mode == GameMode.local) {
      return RotatedBox(quarterTurns: 2, child: panel);
    }
    return panel;
  }

  /// Отдельная строка для кубиков на всю ширину — дубль из четырёх кубиков
  /// помещается без труда, текст сверху не выдавливается. В ход человека
  /// кнопка броска пульсирует, чтобы ребёнок точно заметил свою очередь.
  Widget _diceStrip() => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rolled = _controller.state.rolled;
      final showRoll = rolled.isEmpty &&
          _controller.activeSide == ActiveSide.me &&
          _controller.phase == GamePhase.playing;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
        child: SizedBox(
          height: 60,
          child: Center(
            child: showRoll
                ? _PulseRollButton(onTap: _controller.rollDice)
                : rolled.isEmpty
                ? const Text(
                    '—',
                    style: TextStyle(color: muted, fontSize: 22),
                  )
                : DiceWidget(
                    rolled: rolled,
                    available: _controller.state.available,
                    canRoll: false,
                  ),
          ),
        ),
      );
    },
  );

  Widget _bottomBar() => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _CtrlButton(
                icon: Icons.undo_rounded,
                label: 'Отменить',
                enabled: _controller.canUndo,
                onTap: _controller.undo,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CtrlButton(
                icon: Icons.lightbulb_rounded,
                label: 'Подсказать',
                enabled: _controller.hintsEnabled &&
                    _controller.activeSide == ActiveSide.me &&
                    _controller.state.rolled.isNotEmpty &&
                    _controller.phase == GamePhase.playing,
                onTap: _controller.hint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CtrlButton(
                icon: Icons.check_circle_rounded,
                label: 'Завершить',
                enabled: _controller.canEndTurn,
                onTap: _controller.endTurn,
              ),
            ),
          ],
        ),
      );
    },
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
        DianaDialogButton<bool>(label: 'Не сдаваться', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) _controller.resign();
    });
  }
}

/// Маленький кружок-индикатор цвета игрока (белый/чёрный) для панели.
class _SideDot extends StatelessWidget {
  const _SideDot({required this.white});
  final bool white;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: white
            ? [Colors.white, const Color(0xFFEFE3C8)]
            : [const Color(0xFF5A4E78), const Color(0xFF221B33)],
      ),
      border: Border.all(
        color: white ? const Color(0xFFC9B68C) : const Color(0xFF221B33),
        width: 1.5,
      ),
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
          height: 54,
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

/// Большая пульсирующая кнопка «Бросить кости» — чтобы ребёнок точно заметил,
/// что наступила его очередь. Пульсация — мягкое увеличение/уменьшение.
class _PulseRollButton extends StatefulWidget {
  const _PulseRollButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_PulseRollButton> createState() => _PulseRollButtonState();
}

class _PulseRollButtonState extends State<_PulseRollButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, child) {
      final scale = 1 + 0.06 * _anim.value;
      return Transform.scale(scale: scale, child: child);
    },
    child: SizedBox(
      height: 50,
      child: FilledButton.icon(
        key: const Key('backgammon-roll'),
        onPressed: widget.onTap,
        icon: const Icon(Icons.casino_rounded, size: 24),
        label: const Text('Бросить кости', style: TextStyle(fontSize: 16)),
      ),
    ),
  );
}
