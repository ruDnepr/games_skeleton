import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'rendzu_controller.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети, без него —
/// выбор режима (правила, размер доски, противник, уровень, цвет).
class RendzuEntryPage extends StatelessWidget {
  const RendzuEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      // В сети хост играет чёрными. Размер доски и набор правил в сети не
      // выбираются — берём классический рэндзю на 9×9 (быстрее и понятнее
      // ребёнку, как в исходной «Рэндзю для Дианы»).
      return RendzuSessionPage(
        settings: settings,
        network: network,
        ruleset: Ruleset.renju,
        boardSize: BoardSize.small9,
      );
    }
    return RendzuModePage(settings: settings);
  }
}

/// Выбор режима и параметров партии.
class RendzuModePage extends StatefulWidget {
  const RendzuModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<RendzuModePage> createState() => _RendzuModePageState();
}

class _RendzuModePageState extends State<RendzuModePage> {
  bool _vsAi = true;
  Ruleset _ruleset = Ruleset.renju;
  BoardSize _boardSize = BoardSize.small9;
  Difficulty _difficulty = Difficulty.easy;
  StoneColor _color = StoneColor.black;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Рэндзю',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
              title: 'Пять в ряд',
              subtitle:
                  'Выбери правила, доску и соперника — и собери пять камней в ряд.',
            ),
            const SizedBox(height: 18),
            const Text(
              'Правила',
              style: TextStyle(fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 8),
            _RulesetRow(
              value: _ruleset,
              onChanged: (r) => setState(() => _ruleset = r),
            ),
            const SizedBox(height: 16),
            const Text(
              'Доска',
              style: TextStyle(fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 8),
            _BoardSizeRow(
              value: _boardSize,
              onChanged: (b) => setState(() => _boardSize = b),
            ),
            const SizedBox(height: 18),
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
              subtitle: 'Ходы по очереди — чёрные начинают',
              icon: Icons.people_rounded,
              color: const Color(0xFFDDF1DF),
              selected: !_vsAi,
              onTap: () => setState(() => _vsAi = false),
            ),
            const SizedBox(height: 26),
            BigButton(
              key: const Key('rendzu-start'),
              title: 'Начать партию',
              subtitle: _vsAi
                  ? 'Против компьютера · ${_difficulty.russianName}'
                  : 'Двое на одном устройстве',
              icon: Icons.play_arrow_rounded,
              onPressed: () => _start(context),
            ),
          ],
        ),
      );

  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RendzuSessionPage(
          settings: widget.settings,
          vsAi: _vsAi,
          difficulty: _difficulty,
          humanColor: _color,
          ruleset: _ruleset,
          boardSize: _boardSize,
        ),
      ),
    );
  }
}

class _RulesetRow extends StatelessWidget {
  const _RulesetRow({required this.value, required this.onChanged});
  final Ruleset value;
  final ValueChanged<Ruleset> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: 'Гомоку',
              desc: 'Без запретов — проще',
              selected: value == Ruleset.gomoku,
              onTap: () => onChanged(Ruleset.gomoku),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: 'Рэндзю',
              desc: 'С запретами для чёрных',
              selected: value == Ruleset.renju,
              onTap: () => onChanged(Ruleset.renju),
            ),
          ),
        ],
      );
}

class _BoardSizeRow extends StatelessWidget {
  const _BoardSizeRow({required this.value, required this.onChanged});
  final BoardSize value;
  final ValueChanged<BoardSize> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: '9×9',
              desc: 'Быстрее и понятнее',
              selected: value == BoardSize.small9,
              onTap: () => onChanged(BoardSize.small9),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: '15×15',
              desc: 'Классический рэндзю',
              selected: value == BoardSize.standard15,
              onTap: () => onChanged(BoardSize.standard15),
            ),
          ),
        ],
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
  final StoneColor value;
  final ValueChanged<StoneColor> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: 'Чёрные',
              desc: 'Ходишь первым',
              selected: value == StoneColor.black,
              onTap: () => onChanged(StoneColor.black),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: 'Белые',
              desc: 'Компьютер ходит первым',
              selected: value == StoneColor.white,
              onTap: () => onChanged(StoneColor.white),
            ),
          ),
        ],
      );
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

/// Экран партии: доска (CustomPaint) посередине, сверху — чей ход и номер хода,
/// снизу — кнопки управления. Доска занимает максимум места, панели фиксированы.
class RendzuSessionPage extends StatefulWidget {
  const RendzuSessionPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.humanColor = StoneColor.black,
    this.ruleset = Ruleset.renju,
    this.boardSize = BoardSize.small9,
    this.network,
  });

  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final StoneColor humanColor;
  final Ruleset ruleset;
  final BoardSize boardSize;
  final NetworkSession? network;

  @override
  State<RendzuSessionPage> createState() => _RendzuSessionPageState();
}

class _RendzuSessionPageState extends State<RendzuSessionPage> {
  late final RendzuController _controller;
  bool _winShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = RendzuController(
      settings: widget.settings,
      sounds: sounds,
      ruleset: widget.ruleset,
      boardSize: widget.boardSize,
      network: widget.network,
    );
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

  void _maybeShowWin() {
    if (_controller.isOver && !_winShown) {
      _winShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
    }
  }

  void _showEndDialog() {
    if (!mounted) return;
    final isDraw = _controller.isDraw;
    final winner = _controller.winnerColor;
    final iWon = _controller.mode == RendzuMode.network
        ? winner == (_controller.isHost ? StoneColor.black : StoneColor.white)
        : (_controller.mode == RendzuMode.ai
            ? winner == widget.humanColor
            : true);
    final winnerName =
        winner == StoneColor.black ? 'Чёрные' : 'Белые';
    final title = isDraw
        ? 'Ничья!'
        : (iWon
            ? (_controller.mode == RendzuMode.local
                ? 'Победили $winnerName!'
                : 'Ты молодец!')
            : 'Партия окончена');
    final message = isDraw
        ? 'Доска заполнилась — никто не собрал пять. Сыграйте ещё раз!'
        : (iWon
            ? 'Отличная партия! Пять в ряд — так держать ✨'
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
      actions: [
        DianaDialogButton<bool>(
          label: 'Играть снова',
          key: const Key('rendzu-play-again'),
          value: true,
          primary: true,
        ),
        const DianaDialogButton<bool>(label: 'В меню', value: false),
      ],
    ).then((again) {
      if (!mounted) return;
      if (again == true && widget.network == null) {
        // Офлайн: перезапускаем партию того же режима.
        setState(() {
          _winShown = false;
          _controller.playAgain();
        });
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
        DianaDialogButton<bool>(label: 'Не сдаваться', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) _controller.resign();
    });
  }

  bool get _canResign => !_controller.isOver && _controller.mode != RendzuMode.local;

  @override
  Widget build(BuildContext context) {
    _maybeShowWin();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рэндзю для Дианы'),
        actions: [
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => IconButton(
              key: const Key('sound-toggle'),
              tooltip:
                  widget.settings.sound ? 'Выключить звук' : 'Включить звук',
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
                        _playersStrip(),
                        const SizedBox(height: 6),
                        _statusStrip(),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Center(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final boardPx = math
                                    .min(constraints.maxWidth,
                                        constraints.maxHeight)
                                    .clamp(220.0, 520.0);
                                return _BoardSurface(
                                  size: boardPx,
                                  controller: _controller,
                                  onTap: (p) => _controller.tap(p),
                                );
                              },
                            ),
                          ),
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

  /// Строка с двумя фишками игроков: чёрные и белые. Активный игрок подсвечен
  /// бейджем «ХОД». В локальном режиме обе фишки «человеческие», сверху чёрные,
  /// снизу белые — так двое на одном устройстве каждый видят свою сторону.
  Widget _playersStrip() => Row(
        children: [
          Expanded(
            child: _PlayerChip(
              color: StoneColor.black,
              name: _controller.playerName(StoneColor.black),
              active: _controller.currentColor == StoneColor.black &&
                  !_controller.isOver,
              moveCount: _controller.moveNumber,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PlayerChip(
              color: StoneColor.white,
              name: _controller.playerName(StoneColor.white),
              active: _controller.currentColor == StoneColor.white &&
                  !_controller.isOver,
              moveCount: _controller.moveNumber,
            ),
          ),
        ],
      );

  /// Подпись состояния: «Твой ход» / «Ходит друг…» / «Ход компьютера…» / текст
  /// предупреждения о запрещённом ходе.
  Widget _statusStrip() => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final warning = _controller.warning;
          final status = _controller.status;
          final busy = _controller.busy;
          String text;
          Color? bg;
          if (warning != null) {
            text = warning;
            bg = const Color(0xFFFCE3DA);
          } else if (status != null) {
            text = status;
            bg = const Color(0xFFEDE6FF);
          } else if (busy) {
            text = 'Компьютер думает…';
          } else {
            text = _controller.turnLabel;
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey('$text$bg'),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: bg ?? const Color(0xFFFFFCF6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: bg != null
                      ? const Color(0xFFE3C5B5)
                      : const Color(0xFFF1EAE5),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: bg != null ? const Color(0xFFB45B3A) : ink,
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
                    label: 'Подсказка',
                    enabled: _controller.hintsEnabled &&
                        _controller.canInteract,
                    onTap: _controller.showHint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CtrlButton(
                    icon: Icons.refresh_rounded,
                    label: 'Заново',
                    enabled: _controller.mode != RendzuMode.network,
                    onTap: _controller.playAgain,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Фишка игрока: цветной кружок, имя и бейдж «ХОД».
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.color,
    required this.name,
    required this.active,
    required this.moveCount,
  });
  final StoneColor color;
  final String name;
  final bool active;
  final int moveCount;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
            _SideDot(black: color == StoneColor.black),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  Text(
                    color == StoneColor.black ? 'Чёрные' : 'Белые',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              const Eyebrow(
                'ХОД',
                color: deepPurple,
                background: Color(0xFFDCCDF8),
                fontSize: 10,
              )
            else
              Text(
                'ход $moveCount',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
          ],
        ),
      );
}

class _SideDot extends StatelessWidget {
  const _SideDot({required this.black});
  final bool black;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: black
                ? [const Color(0xFF5A4E78), const Color(0xFF221B33)]
                : [Colors.white, const Color(0xFFEFE3C8)],
          ),
          border: Border.all(
            color: black ? const Color(0xFF221B33) : const Color(0xFFC9B68C),
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

/// Поверхность доски: CustomPaint с сеткой, камнями, подсветками. Тап
/// конвертируется в ближайшее пересечение и зовёт колбэк.
class _BoardSurface extends StatelessWidget {
  const _BoardSurface({
    required this.size,
    required this.controller,
    required this.onTap,
  });

  final double size;
  final RendzuController controller;
  final void Function(Point) onTap;

  @override
  Widget build(BuildContext context) {
    final cell = size / controller.board.size;
    return GestureDetector(
      onTapDown: (details) {
        final local = details.localPosition;
        final ix = ((local.dx / cell) - 0.5).round();
        final iy = ((local.dy / cell) - 0.5).round();
        final p = Point(ix, iy);
        if (p.inBounds(controller.board.size)) {
          onTap(p);
        }
      },
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _BoardPainter(
            board: controller.board,
            cell: cell,
            lastMove: controller.lastMove,
            winningLine: controller.winningLine,
            forbiddenHints: controller.forbiddenHints,
            patternThrees: controller.patternThrees,
            patternFours: controller.patternFours,
            hintPoint: controller.hintPoint,
          ),
        ),
      ),
    );
  }
}

/// Художник доски: деревянный фон, сетка пересечений, звёздные точки, камни с
/// радиальным градиентом, подсветка паттернов, запрещённых ходов, последнего
/// хода и победной линии.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.cell,
    required this.lastMove,
    required this.winningLine,
    required this.forbiddenHints,
    required this.patternThrees,
    required this.patternFours,
    required this.hintPoint,
  });

  final Board board;
  final double cell;
  final Point? lastMove;
  final List<Point> winningLine;
  final Set<Point> forbiddenHints;
  final List<List<Point>> patternThrees;
  final List<List<Point>> patternFours;
  final Point? hintPoint;

  // Деревянная палитра как в шашках и исходной «Рэндзю для Дианы».
  static const Color _woodLight = Color(0xFFE7C58E);
  static const Color _woodDark = Color(0xFFC99E63);
  static const Color _line = Color(0xFF7B4E2A);
  static const Color _blackHi = Color(0xFF6E5A8A);
  static const Color _black = Color(0xFF1B1530);
  static const Color _whiteEdge = Color(0xFFC9B68C);
  static const Color _threeHi = Color(0xFFFFD66D);
  static const Color _fourHi = Color(0xFFE27D60);

  static const double _stoneRadiusFactor = 0.42;

  Offset centerOf(Point p) => Offset(cell * (p.x + 0.5), cell * (p.y + 0.5));

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Деревянный фон.
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_woodLight, _woodDark],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // Лёгкая текстура-полосы.
    final grainPaint = Paint()
      ..color = Colors.black.withValues(alpha: .04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (i + 0.5) / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grainPaint);
    }

    // 2. Сетка пересечений.
    final linePaint = Paint()
      ..color = _line
      ..strokeWidth = board.size <= 9 ? 1.6 : 1.1
      ..style = PaintingStyle.stroke;
    final first = centerOf(const Point(0, 0));
    final last = centerOf(Point(board.size - 1, board.size - 1));
    for (var i = 0; i < board.size; i++) {
      final cx = centerOf(Point(i, 0)).dx;
      canvas.drawLine(Offset(cx, first.dy), Offset(cx, last.dy), linePaint);
      final ry = centerOf(Point(0, i)).dy;
      canvas.drawLine(Offset(first.dx, ry), Offset(last.dx, ry), linePaint);
    }

    // 3. Звёздные точки.
    final starPaint = Paint()..color = _line;
    for (final p in _starPoints(board.size)) {
      canvas.drawCircle(centerOf(p), board.size <= 9 ? 3.0 : 3.5, starPaint);
    }

    // 4. Подсветка паттернов: тройки (жёлтые), четвёрки (коралловые).
    if (patternThrees.isNotEmpty) {
      final p = Paint()..color = _threeHi.withValues(alpha: .35);
      for (final line in patternThrees) {
        for (final pt in line) {
          canvas.drawCircle(centerOf(pt), cell * 0.44, p);
        }
      }
    }
    if (patternFours.isNotEmpty) {
      final p = Paint()..color = _fourHi.withValues(alpha: .35);
      for (final line in patternFours) {
        for (final pt in line) {
          canvas.drawCircle(centerOf(pt), cell * 0.44, p);
        }
      }
    }

    // 5. Подсказка хода.
    if (hintPoint != null) {
      final p = Paint()..color = purple.withValues(alpha: .35);
      canvas.drawCircle(centerOf(hintPoint!), cell * 0.40, p);
      canvas.drawCircle(
        centerOf(hintPoint!),
        cell * 0.18,
        Paint()..color = purple,
      );
    }

    // 6. Камни.
    final stoneR = cell * _stoneRadiusFactor;
    for (final pt in board.occupiedPoints()) {
      _drawStone(canvas, centerOf(pt), stoneR, board.at(pt)!);
    }

    // 7. Маркеры запрещённых ходов (крестик).
    if (forbiddenHints.isNotEmpty) {
      final paint = Paint()
        ..color = _fourHi
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final r = cell * 0.20;
      for (final p in forbiddenHints) {
        final c = centerOf(p);
        canvas.drawLine(
          Offset(c.dx - r, c.dy - r),
          Offset(c.dx + r, c.dy + r),
          paint,
        );
        canvas.drawLine(
          Offset(c.dx - r, c.dy + r),
          Offset(c.dx + r, c.dy - r),
          paint,
        );
      }
    }

    // 8. Кольцо последнего хода.
    if (lastMove != null && !winningLine.contains(lastMove)) {
      final ring = Paint()
        ..color = yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(centerOf(lastMove!), cell * 0.46, ring);
    }

    // 9. Победная линия — подсветка.
    if (winningLine.length >= 2) {
      final winPaint = Paint()
        ..color = yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.16
        ..strokeCap = StrokeCap.round;
      final start = centerOf(winningLine.first);
      final end = centerOf(winningLine.last);
      canvas.drawLine(start, end, winPaint);
      final ring = Paint()
        ..color = yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (final p in winningLine) {
        canvas.drawCircle(centerOf(p), cell * 0.48, ring);
      }
    }
  }

  void _drawStone(
    Canvas canvas,
    Offset center,
    double radius,
    StoneColor color,
  ) {
    // Тень.
    canvas.drawCircle(
      center.translate(1.5, 2.5),
      radius,
      Paint()..color = Colors.black.withValues(alpha: .28),
    );

    // Тело камня с радиальным градиентом (блик сверху-слева).
    final grad = RadialGradient(
      center: const Alignment(-0.35, -0.35),
      radius: 0.95,
      colors: color == StoneColor.black
          ? const [_blackHi, _black]
          : const [Colors.white, Color(0xFFF1E6CC), _whiteEdge],
      stops: color == StoneColor.black ? const [0.0, 1.0] : const [0.0, 0.7, 1.0],
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..shader = grad.createShader(rect));

    // Маленький блик-точка.
    final hi = Paint()..color = Colors.white.withValues(alpha: .55);
    canvas.drawCircle(
      center.translate(-radius * 0.35, -radius * 0.35),
      radius * 0.18,
      hi,
    );
  }

  List<Point> _starPoints(int size) {
    if (size == 9) {
      return const [
        Point(2, 2),
        Point(6, 2),
        Point(4, 4),
        Point(2, 6),
        Point(6, 6),
      ];
    }
    if (size == 15) {
      return const [
        Point(3, 3),
        Point(11, 3),
        Point(7, 7),
        Point(3, 11),
        Point(11, 11),
      ];
    }
    return const [];
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.board != board ||
      old.lastMove != lastMove ||
      old.winningLine != winningLine ||
      old.forbiddenHints != forbiddenHints ||
      old.patternThrees != patternThrees ||
      old.patternFours != patternFours ||
      old.hintPoint != hintPoint;
}
