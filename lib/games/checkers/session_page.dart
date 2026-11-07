import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'checkers_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети (русские
/// шашки по умолчанию, как договаривались в `hostSide`), без него — выбор
/// варианта и режима.
class CheckersEntryPage extends StatelessWidget {
  const CheckersEntryPage({
    super.key,
    required this.settings,
    this.network,
    this.variant = GameVariant.russian,
  });
  final SettingsController settings;
  final NetworkSession? network;
  final GameVariant variant;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return CheckersSessionPage(
        settings: settings,
        network: network,
        variant: variant,
      );
    }
    return CheckersModePage(settings: settings);
  }
}

/// Выбор режима: вариант, противник (компьютер / вдвоём), уровень и цвет.
class CheckersModePage extends StatefulWidget {
  const CheckersModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<CheckersModePage> createState() => _CheckersModePageState();
}

class _CheckersModePageState extends State<CheckersModePage> {
  GameVariant _variant = GameVariant.russian;
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;
  Side _color = Side.white;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Шашки',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
          title: 'Выбери свои шашки',
          subtitle: 'Вариант, соперник и цвет — всё можно поменять перед стартом.',
        ),
        const SizedBox(height: 22),
        const Text(
          'Вариант',
          style: TextStyle(fontWeight: FontWeight.w900, color: ink),
        ),
        const SizedBox(height: 8),
        _VariantPicker(value: _variant, onChanged: (v) => setState(() => _variant = v)),
        const SizedBox(height: 18),
        const Text(
          'Соперник',
          style: TextStyle(fontWeight: FontWeight.w900, color: ink),
        ),
        const SizedBox(height: 8),
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
          subtitle: 'Ходы по очереди — белые снизу, чёрные сверху',
          icon: Icons.people_rounded,
          color: const Color(0xFFDDF1DF),
          selected: !_vsAi,
          onTap: () => setState(() => _vsAi = false),
        ),
        if (_vsAi) ...[
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
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            key: const Key('checkers-start'),
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
        builder: (_) => CheckersSessionPage(
          settings: widget.settings,
          variant: _variant,
          vsAi: _vsAi,
          difficulty: _difficulty,
          humanColor: _color,
        ),
      ),
    );
  }
}

class _VariantPicker extends StatelessWidget {
  const _VariantPicker({required this.value, required this.onChanged});
  final GameVariant value;
  final ValueChanged<GameVariant> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (GameVariant.russian, 'Русские', 'Дамка летает, бьём назад'),
      (GameVariant.american, 'Классические', 'Дамка на одну клетку'),
      (GameVariant.international, 'Международные', 'Доска 10×10, брать много'),
      (GameVariant.giveaway, 'Поддавки', 'Отдай все шашки — победил'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _ChoiceChip(
            label: item.$2,
            desc: item.$3,
            selected: value == item.$1,
            onTap: () => onChanged(item.$1),
          ),
      ],
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
    const items = [
      (Difficulty.easy, 'Лёгкий', 'Часто уступает'),
      (Difficulty.medium, 'Средний', 'Играет ровно'),
      (Difficulty.hard, 'Сложный', 'Думает глубоко'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: items[i].$2,
              desc: items[i].$3,
              selected: value == items[i].$1,
              onTap: () => onChanged(items[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.value, required this.onChanged});
  final Side value;
  final ValueChanged<Side> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ChoiceChip(
          label: 'Белые',
          desc: 'Ходишь первым',
          selected: value == Side.white,
          onTap: () => onChanged(Side.white),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ChoiceChip(
          label: 'Чёрные',
          desc: 'Компьютер ходит первым',
          selected: value == Side.black,
          onTap: () => onChanged(Side.black),
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

/// Экран партии: доска посередине, сверху и снизу — панели игроков, под доской —
/// кнопки управления. По сети и против компьютера доска разворачивается так,
/// чтобы шашки человека были снизу.
class CheckersSessionPage extends StatefulWidget {
  const CheckersSessionPage({
    super.key,
    required this.settings,
    this.variant = GameVariant.russian,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.humanColor = Side.white,
    this.network,
  });
  final SettingsController settings;
  final GameVariant variant;
  final bool vsAi;
  final Difficulty difficulty;
  final Side humanColor;
  final NetworkSession? network;

  @override
  State<CheckersSessionPage> createState() => _CheckersSessionPageState();
}

class _CheckersSessionPageState extends State<CheckersSessionPage> {
  late final CheckersController _controller;
  bool _winShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = CheckersController(
      settings: widget.settings,
      sounds: sounds,
      variant: widget.variant,
      network: widget.network,
    )..onUndoRequested = _showUndoRequest;
    if (widget.network != null) {
      _controller.startNetwork();
    } else if (widget.vsAi) {
      _controller.startAi(widget.difficulty, widget.humanColor);
    } else {
      _controller.startLocal();
    }
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
    if (_controller.isOver && !_winShown) {
      _winShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
    }
  }

  void _showEndDialog() {
    if (!mounted) return;
    final result = _controller.result;
    if (result == null) return;
    final isDraw = result == GameResult.draw;
    final iWon = _controller.mode == GameMode.network
        ? _controller.winner == (_controller.isHost ? Side.white : Side.black)
        : (_controller.mode == GameMode.ai
            ? _controller.winner == widget.humanColor
            : true);
    final title = isDraw
        ? 'Ничья!'
        : (_controller.mode == GameMode.local
            ? 'Победили ${_controller.winner == Side.white ? 'белые' : 'чёрные'}!'
            : (iWon ? 'Ты молодец!' : 'Партия окончена'));
    final message = isDraw
        ? 'Позиция повторилась — честная ничья.'
        : (iWon
            ? 'Отличная партия! Так держать ✨'
            : 'Не беда — в следующий раз обязательно получится!');
    showDianaDialog<bool>(
      context: context,
      title: title,
      barrierDismissible: false,
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: widget.network == null
          ? const [
              DianaDialogButton<bool>(
                label: 'Играть снова',
                key: Key('checkers-play-again'),
                value: true,
                primary: true,
              ),
              DianaDialogButton<bool>(label: 'В меню', value: false),
            ]
          : const [
              DianaDialogButton<bool>(
                label: 'В меню',
                value: true,
                primary: true,
              ),
            ],
    ).then((again) {
      if (!mounted) return;
      if (again == true && widget.network == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CheckersSessionPage(
              settings: widget.settings,
              variant: widget.variant,
              vsAi: widget.vsAi,
              difficulty: widget.difficulty,
              humanColor: widget.humanColor,
              network: widget.network,
            ),
          ),
        );
      } else {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowWin();
    final flipped = (widget.network != null || widget.vsAi) &&
        widget.humanColor == Side.black;
    final bottomSide = flipped
        ? (widget.humanColor)
        : (widget.network != null || widget.vsAi
              ? widget.humanColor
              : Side.white);
    final topSide = bottomSide.opponent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Шашки для Дианы'),
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
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _playerPanel(topSide, top: true),
                        const SizedBox(height: 6),
                        _statusStrip(),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: RepaintBoundary(
                                child: _BoardView(
                                  controller: _controller,
                                  flipped: flipped,
                                ),
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

  Widget _playerPanel(Side side, {required bool top}) {
    final active = _controller.currentTurn == side &&
        _controller.phase == GamePhase.playing;
    final isWhite = side == Side.white;
    final name = _controller.playerName(side);
    final captured = _capturedBy(side);
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
          if (captured > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '×$captured',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: muted,
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

  /// Сколько шашек соперника этого цвета уже снято с доски.
  int _capturedBy(Side side) {
    final variant = _controller.variant;
    final start = variant.initialRows * (variant.boardSize / 2).floor();
    return (start - _controller.state.board.count(side.opponent)).clamp(0, start);
  }

  Widget _statusStrip() {
    final text = _controller.status ?? _controller.turnLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: SizedBox(
        height: 32,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              text,
              key: ValueKey(text),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _controller.busy ? purple : muted,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() => Padding(
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
        if (_controller.hintButtonEnabled) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _CtrlButton(
              icon: Icons.lightbulb_rounded,
              label: 'Подсказать',
              enabled: _controller.canInteract,
              onTap: _controller.showHint,
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: _CtrlButton(
            icon: Icons.refresh_rounded,
            label: 'Сбросить выбор',
            enabled: _controller.selected != null,
            onTap: _controller.clearSelection,
          ),
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

/// Доска: CustomPaint с тапами. Все подсветки (выбор, адресаты, подсказка,
/// подсказанные шашки) рисуются здесь. Тап переводится в клетку с учётом
/// переворота доски для чёрных.
class _BoardView extends StatelessWidget {
  const _BoardView({required this.controller, required this.flipped});
  final CheckersController controller;
  final bool flipped;

  int get _size => controller.state.board.size;

  void _onTapUp(TapUpDetails details, BuildContext context) {
    if (!controller.canInteract) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final cell = renderObject.size.width / _size;
    var col = (details.localPosition.dx / cell).floor();
    var row = (details.localPosition.dy / cell).floor();
    if (row < 0 || row >= _size || col < 0 || col >= _size) return;
    if (flipped) {
      row = _size - 1 - row;
      col = _size - 1 - col;
    }
    controller.tap(Square(row, col));
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (details) => _onTapUp(details, context),
    child: CustomPaint(
      painter: _BoardPainter(controller: controller, flipped: flipped),
    ),
  );
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({required this.controller, required this.flipped});
  final CheckersController controller;
  final bool flipped;

  static const _light = Color(0xFFF6E2B3);
  static const _dark = Color(0xFF8B5A2B);
  static const _whitePiece = Color(0xFFF8EED1);
  static const _whiteEdge = Color(0xFFC9B68C);
  static const _blackPiece = Color(0xFF3A2C4F);
  static const _blackEdge = Color(0xFF1B1328);
  static const _selectedRing = Color(0xFF8266D5);
  static const _destDot = Color(0xFF8266D5);
  static const _movableDot = Color(0x558266D5);
  static const _suggestRing = Color(0xFFFFD66D);

  @override
  void paint(Canvas canvas, Size size) {
    final board = controller.state.board;
    final n = board.size;
    final cell = size.width / n;
    // Рамка.
    final framePaint = Paint()..color = const Color(0xFF6B4322);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      framePaint,
    );
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final (r, c) = flipped ? (n - 1 - row, n - 1 - col) : (row, col);
        final dark = (r + c).isOdd;
        final rect = Rect.fromLTWH(
          col * cell,
          row * cell,
          cell,
          cell,
        );
        canvas.drawRect(rect, Paint()..color = dark ? _dark : _light);
      }
    }

    final selected = controller.selected;
    final destinations = controller.destinations;
    final movable = controller.movablePieces;
    final suggested = controller.suggestedMove;

    // Подсветка «шашки, которыми можно ходить» — когда ничего не выбрано.
    if (movable.isNotEmpty && selected == null) {
      for (final square in movable) {
        final (row, col) = _display(square, n);
        final center = Offset((col + 0.5) * cell, (row + 0.5) * cell);
        canvas.drawCircle(
          center,
          cell * 0.18,
          Paint()..color = _movableDot,
        );
      }
    }

    // Подсветка выбранной шашки.
    if (selected != null) {
      final (row, col) = _display(selected, n);
      final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
      canvas.drawRect(
        rect,
        Paint()
          ..color = _selectedRing.withValues(alpha: .25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect.deflate(2),
        Paint()
          ..color = _selectedRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Подсветка адресатов.
    for (final dest in destinations) {
      final (row, col) = _display(dest, n);
      final center = Offset((col + 0.5) * cell, (row + 0.5) * cell);
      canvas.drawCircle(
        center,
        cell * 0.22,
        Paint()
          ..color = _destDot.withValues(alpha: .35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        cell * 0.22,
        Paint()
          ..color = _destDot
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Рисуем шашки.
    for (final entry in board.pieces.entries) {
      final piece = entry.value;
      final (row, col) = _display(entry.key, n);
      final center = Offset((col + 0.5) * cell, (row + 0.5) * cell);
      _drawPiece(canvas, center, cell * 0.42, piece);
    }

    // Подсвечиваем подсказанный ход: рамки на from и to.
    if (suggested != null) {
      final fromDisp = _display(suggested.from, n);
      final toDisp = _display(suggested.to, n);
      for (final (row, col) in [fromDisp, toDisp]) {
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        canvas.drawRect(
          rect.deflate(2),
          Paint()
            ..color = _suggestRing
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
    }
  }

  (int, int) _display(Square square, int n) =>
      flipped ? (n - 1 - square.row, n - 1 - square.col) : (square.row, square.col);

  void _drawPiece(
    Canvas canvas,
    Offset center,
    double radius,
    Piece piece,
  ) {
    final isWhite = piece.side == Side.white;
    final base = isWhite ? _whitePiece : _blackPiece;
    final edge = isWhite ? _whiteEdge : _blackEdge;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(
      center + Offset(0, radius * 0.12),
      radius,
      shadow,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-.3, -.4),
          colors: [
            isWhite ? Colors.white : const Color(0xFF5C4A78),
            base,
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12,
    );
    // Внутреннее кольцо, как у настоящей шашки.
    canvas.drawCircle(
      center,
      radius * 0.62,
      Paint()
        ..color = edge.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.07,
    );
    if (piece.king) {
      _drawCrown(canvas, center, radius * 0.5, isWhite);
    }
  }

  void _drawCrown(Canvas canvas, Offset center, double r, bool isWhite) {
    // Маленькая корона: три зубца, нарисованные как путь.
    final paint = Paint()
      ..color = isWhite ? const Color(0xFFB98A2E) : const Color(0xFFFFD66D)
      ..style = PaintingStyle.fill;
    final path = Path();
    final left = center + Offset(-r, r * 0.6);
    final right = center + Offset(r, r * 0.6);
    final midLeft = center + Offset(-r * 0.55, -r * 0.7);
    final midRight = center + Offset(r * 0.55, -r * 0.7);
    final top = center + Offset(0, -r * 0.3);
    path
      ..moveTo(left.dx, left.dy)
      ..lineTo(midLeft.dx, midLeft.dy)
      ..lineTo(top.dx, top.dy)
      ..lineTo(midRight.dx, midRight.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(right.dx, right.dy - r * 0.25)
      ..lineTo(left.dx, left.dy - r * 0.25)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.flipped != flipped ||
      old.controller.state.fingerprint != controller.state.fingerprint ||
      old.controller.selected != controller.selected ||
      old.controller.suggestedMove != controller.suggestedMove;
}
