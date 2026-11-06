import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'engine/scoring.dart';
import 'go_controller.dart';

// Тёплые тона деревянной доски го. Те же, что в оригинальной игре «Го для
// Дианы» — чтобы у ребёнка знакомая картинка.
const _woodLight = Color(0xFFE7B677);
const _woodMid = Color(0xFFD39A52);
const _woodDark = Color(0xFFB97A39);
const _woodLine = Color(0xFF6E4422);
const _blackStoneDark = Color(0xFF1B1A22);
const _blackStoneLight = Color(0xFF5A5764);
const _whiteStoneDark = Color(0xFFE2D6BE);
const _whiteStoneLight = Color(0xFFFFFFFF);

/// Точка входа в партию: с сетевым соединением — сразу партия по сети, без
/// него — выбор режима (против компьютера или вдвоём на одном устройстве).
class GoEntryPage extends StatelessWidget {
  const GoEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      // В сети хост выбрал режим и размер доски заранее — клиент открывает
      // ту же конфигурацию. Для упрощения берём значения по умолчанию: 9×9
      // «Захват». Хост играет чёрными и ходит первым.
      return GoSessionPage(
        settings: settings,
        network: network,
        setup: const GameSetup(mode: GoMode.capture, boardSize: 9),
      );
    }
    return GoModePage(settings: settings);
  }
}

/// Выбор режима партии: размер доски, режим правил, соперник, цвет.
class GoModePage extends StatefulWidget {
  const GoModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<GoModePage> createState() => _GoModePageState();
}

class _GoModePageState extends State<GoModePage> {
  int _boardSize = 9;
  GoMode _mode = GoMode.capture;
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;
  StoneColor _color = StoneColor.black;
  CaptureTarget _captureTarget = CaptureTarget.one;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Го для Дианы',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
              title: 'С кем и где сыграем?',
              subtitle: 'Начни с «Захвата» и доски 9×9 — это самый мягкий вход в го.',
            ),
            const SizedBox(height: 22),
            const _SectionLabel('Размер доски'),
            _SizeRow(value: _boardSize, onChanged: (s) => setState(() => _boardSize = s)),
            const SizedBox(height: 16),
            const _SectionLabel('Режим'),
            _ModeRow(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            if (_mode == GoMode.capture) ...[
              const SizedBox(height: 12),
              const _SectionLabel('Цель'),
              _TargetRow(
                value: _captureTarget,
                onChanged: (t) => setState(() => _captureTarget = t),
              ),
            ],
            const SizedBox(height: 16),
            const _SectionLabel('Соперник'),
            _OpponentRow(
              vsAi: _vsAi,
              onChanged: (v) => setState(() => _vsAi = v),
            ),
            if (_vsAi) ...[
              const SizedBox(height: 12),
              const _SectionLabel('Уровень'),
              _DifficultyRow(
                value: _difficulty,
                onChanged: (d) => setState(() => _difficulty = d),
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Твой цвет'),
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
                key: const Key('go-start'),
                onPressed: () => _start(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Начать партию'),
              ),
            ),
          ],
        ),
      );

  void _start(BuildContext context) {
    final setup = GameSetup(
      mode: _mode,
      boardSize: _boardSize,
      captureTarget: _captureTarget,
      komi: GameSetup.defaultKomi(_boardSize),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoSessionPage(
          settings: widget.settings,
          vsAi: _vsAi,
          difficulty: _difficulty,
          humanColor: _color,
          setup: setup,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: ink,
            fontSize: 14,
          ),
        ),
      );
}

class _SizeRow extends StatelessWidget {
  const _SizeRow({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const sizes = [9, 13, 19];
    const descs = {
      9: 'Короткая, удобно начать',
      13: 'Средняя — для продвинутых',
      19: 'Большая — как у мастеров',
    };
    return Row(
      children: [
        for (var i = 0; i < sizes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: '${sizes[i]}×${sizes[i]}',
              desc: descs[sizes[i]]!,
              selected: value == sizes[i],
              onTap: () => onChanged(sizes[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.value, required this.onChanged});
  final GoMode value;
  final ValueChanged<GoMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: 'Захват',
              desc: 'Первым снимешь камень — победа',
              selected: value == GoMode.capture,
              onTap: () => onChanged(GoMode.capture),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: 'Классика',
              desc: 'Территория и очки',
              selected: value == GoMode.classic,
              onTap: () => onChanged(GoMode.classic),
            ),
          ),
        ],
      );
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.value, required this.onChanged});
  final CaptureTarget value;
  final ValueChanged<CaptureTarget> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: '1 камень',
              desc: 'Совсем короткая партия',
              selected: value == CaptureTarget.one,
              onTap: () => onChanged(CaptureTarget.one),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: '3 камня',
              desc: 'Чуть подлиннее',
              selected: value == CaptureTarget.three,
              onTap: () => onChanged(CaptureTarget.three),
            ),
          ),
        ],
      );
}

class _OpponentRow extends StatelessWidget {
  const _OpponentRow({required this.vsAi, required this.onChanged});
  final bool vsAi;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ChoiceChip(
              label: 'Против компьютера',
              desc: 'Три уровня сложности',
              selected: vsAi,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: 'Вдвоём',
              desc: 'На одном устройстве',
              selected: !vsAi,
              onTap: () => onChanged(false),
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
    const descs = ['Часто уступает', 'Играет ровно', 'Думает 1–2 секунды'];
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
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
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

/// Экран партии: доска посередине, сверху — чей ход и счёт захватов, снизу —
/// кнопки управления. Всё, кроме поля, фиксированной высоты; поле — остаток.
class GoSessionPage extends StatefulWidget {
  const GoSessionPage({
    super.key,
    required this.settings,
    required this.setup,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.humanColor = StoneColor.black,
    this.network,
  });
  final SettingsController settings;
  final GameSetup setup;
  final bool vsAi;
  final Difficulty difficulty;
  final StoneColor humanColor;
  final NetworkSession? network;

  @override
  State<GoSessionPage> createState() => _GoSessionPageState();
}

class _GoSessionPageState extends State<GoSessionPage> {
  late final GoController _controller;
  bool _winShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = GoController(
      settings: widget.settings,
      sounds: sounds,
      setup: widget.setup,
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWinDialog());
    }
  }

  void _showWinDialog() {
    if (!mounted) return;
    final isLocal = _controller.mode == GoGameMode.local;
    final w = _controller.winner;
    final mine = _controller.mode == GoGameMode.network
        ? (_controller.isHost ? StoneColor.black : StoneColor.white)
        : widget.humanColor;
    final iWon = w == null
        ? false
        : (isLocal || w == mine);
    final winnerName = w == null ? '' : (w == StoneColor.black ? 'Чёрные' : 'Белые');
    final title = w == null
        ? 'Ничья — отличная партия!'
        : (isLocal
            ? '$winnerName победили!'
            : (iWon ? 'Ты молодец!' : 'В этот раз соперник сильнее'));
    final message = w == null
        ? 'Каждая партия делает тебя сильнее.'
        : (isLocal
            ? 'Отличная игра обоих!'
            : (iWon
                ? 'Отличная партия! Так держать ✨'
                : 'Не беда — в следующий раз обязательно получится!'));

    // Контент диалога: если классика и есть счёт — показываем таблицу очков.
    Widget? content;
    if (widget.setup.mode == GoMode.classic) {
      final score =
          _controller.rules.score(_controller.state) ?? _controller.finalScore;
      if (score != null) {
        content = _ScoreTable(score: score);
      }
    } else if (widget.setup.mode == GoMode.capture && w != null) {
      content = _CaptureTable(
        blackCaptured: _controller.state.blackCaptured,
        whiteCaptured: _controller.state.whiteCaptured,
        target: widget.setup.captureTarget.count,
      );
    }

    showDianaDialog<bool>(
      context: context,
      title: title,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
          if (content != null) ...[const SizedBox(height: 16), content],
        ],
      ),
      actions: [
        DianaDialogButton<bool>(
          label: 'Играть снова',
          key: const Key('go-play-again'),
          value: true,
          primary: true,
        ),
        const DianaDialogButton<bool>(label: 'В меню', value: false),
      ],
    ).then((again) {
      if (!mounted) return;
      if (again == true) {
        if (widget.network == null) {
          // Офлайн: перезапускаем партию того же режима на свежем экране.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => GoSessionPage(
                settings: widget.settings,
                vsAi: widget.vsAi,
                difficulty: widget.difficulty,
                humanColor: widget.humanColor,
                setup: widget.setup,
                network: widget.network,
              ),
            ),
          );
        } else {
          // Сетевой рематч требует новой комнаты.
          Navigator.of(context).maybePop();
        }
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
        'Партия закончится победой соперника.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Продолжить', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    ).then((resign) {
      if (resign == true) _controller.resign();
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeShowWin();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
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
            onPressed: _controller.canResign ? _confirmResign : null,
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
                  if (_controller.fatalMessage != null) {
                    return _FatalView(message: _controller.fatalMessage!);
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _StatusBar(controller: _controller),
                        const SizedBox(height: 6),
                        if (_controller.turnLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _controller.turnLabel,
                              style: const TextStyle(
                                color: muted,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: GoBoardView(controller: _controller),
                              ),
                            ),
                          ),
                        ),
                        if (_controller.notice != null)
                          _Bubble(
                            text: _controller.notice!,
                            onClose: _controller.clearNotice,
                            color: const Color(0xFFFFF4D6),
                          ),
                        if (_controller.hintText != null)
                          _Bubble(
                            text: _controller.hintText!,
                            onClose: _controller.clearHint,
                            color: const Color(0xFFE3F2DE),
                          ),
                        if (_controller.incomingUndoPly != null)
                          _UndoRequest(controller: _controller),
                        if (_controller.waitingForUndo)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Ждём ответа друга на отмену хода…',
                              style: TextStyle(
                                color: muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        _ActionBar(controller: _controller),
                        const SizedBox(height: 6),
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

  String _title() => switch (widget.setup.mode) {
        GoMode.capture =>
          'Захват · ${widget.setup.boardSize}×${widget.setup.boardSize}',
        GoMode.classic =>
          'Классика · ${widget.setup.boardSize}×${widget.setup.boardSize}',
      };
}

/// Строка статуса: две карточки игроков с числом захватов.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});
  final GoController controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: Row(
          children: [
            Expanded(
              child: _PlayerCard(
                color: StoneColor.black,
                captures: controller.state.blackCaptured,
                active: controller.state.turn == StoneColor.black &&
                    !controller.isOver,
                label: controller.playerName(StoneColor.black),
                setup: controller.setup,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PlayerCard(
                color: StoneColor.white,
                captures: controller.state.whiteCaptured,
                active: controller.state.turn == StoneColor.white &&
                    !controller.isOver,
                label: controller.playerName(StoneColor.white),
                setup: controller.setup,
              ),
            ),
          ],
        ),
      );
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.color,
    required this.captures,
    required this.active,
    required this.label,
    required this.setup,
  });
  final StoneColor color;
  final int captures;
  final bool active;
  final String label;
  final GameSetup setup;

  @override
  Widget build(BuildContext context) {
    final captureText = setup.mode == GoMode.capture
        ? 'Снято: $captures / ${setup.captureTarget.count}'
        : 'Снято: $captures';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? purple.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? purple : const Color(0xFFEDE4F0),
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          _StoneDot(dark: color == StoneColor.black, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: ink,
                  ),
                ),
                Text(
                  captureText,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: purple,
              ),
            ),
        ],
      ),
    );
  }
}

class _StoneDot extends StatelessWidget {
  const _StoneDot({required this.dark, required this.size});
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.35),
            radius: 0.9,
            colors: dark
                ? const [_blackStoneLight, _blackStoneDark]
                : const [_whiteStoneLight, _whiteStoneDark],
          ),
          border: Border.all(
            color: dark ? _blackStoneDark : _whiteStoneDark,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: .25),
              blurRadius: size * 0.08,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
      );
}

/// Доска го с объёмными камнями, подсказками и анимациями.
class GoBoardView extends StatefulWidget {
  const GoBoardView({super.key, required this.controller});
  final GoController controller;

  @override
  State<GoBoardView> createState() => _GoBoardViewState();
}

class _GoBoardViewState extends State<GoBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant GoBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  void _onChange() {
    // Анимация появления последнего камня играется от смены отпечатка.
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _anim.dispose();
    super.dispose();
  }

  Point? _pointFromLocal(Offset local, double boardSizePx, int n, double margin) {
    final usable = boardSizePx - margin * 2;
    final cell = usable / (n - 1);
    final dx = local.dx - margin;
    final dy = local.dy - margin;
    final x = (dx / cell).round();
    final y = (dy / cell).round();
    if (x < 0 || y < 0 || x >= n || y >= n) return null;
    // Точность попадания — в радиусе половины клетки.
    final dxp = dx - x * cell;
    final dyp = dy - y * cell;
    if (math.sqrt(dxp * dxp + dyp * dyp) > cell * 0.45) {
      return null;
    }
    return Point(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return GestureDetector(
          onTapDown: (details) {
            final p = _pointFromLocal(
              details.localPosition,
              size,
              c.state.board.size,
              size * 0.06,
            );
            if (p != null) c.tap(p);
          },
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _GoBoardPainter(
                state: c.state,
                legal: c.legalPlacements,
                atari: c.atariPoints,
                suggested: c.suggestedMove,
                hintsOn: c.hintsEnabled,
                isMyTurn: c.canInteract,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoBoardPainter extends CustomPainter {
  _GoBoardPainter({
    required this.state,
    required this.legal,
    required this.atari,
    required this.suggested,
    required this.hintsOn,
    required this.isMyTurn,
  });

  final GameState state;
  final List<Point> legal;
  final Set<Point> atari;
  final Point? suggested;
  final bool hintsOn;
  final bool isMyTurn;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final size = canvasSize.shortestSide;
    final margin = size * 0.06;
    final n = state.board.size;
    final usable = size - margin * 2;
    final cell = usable / (n - 1);

    Offset centerOf(Point p) => Offset(margin + p.x * cell, margin + p.y * cell);

    // Деревянная доска.
    final boardRect = Rect.fromLTWH(0, 0, size, size);
    canvas.drawRect(
      boardRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_woodLight, _woodMid, _woodDark],
        ).createShader(boardRect),
    );
    // Внутренняя рамка.
    canvas.drawRect(
      boardRect,
      Paint()
        ..color = _woodLine.withValues(alpha: .25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.012,
    );

    // Линии сетки.
    final linePaint = Paint()
      ..color = _woodLine
      ..strokeWidth = math.max(1.2, size * 0.004)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
        Offset(margin + i * cell, margin),
        Offset(margin + i * cell, margin + (n - 1) * cell),
        linePaint,
      );
      canvas.drawLine(
        Offset(margin, margin + i * cell),
        Offset(margin + (n - 1) * cell, margin + i * cell),
        linePaint,
      );
    }

    // Звёздные точки (хоси).
    final starPaint = Paint()..color = _woodLine;
    for (final p in state.board.starPoints()) {
      canvas.drawCircle(centerOf(p), size * 0.006, starPaint);
    }

    // Подсказки: допустимые ходы (мягкие точки) — только в мой ход.
    if (hintsOn && isMyTurn) {
      final hintPaint = Paint()..color = purple.withValues(alpha: .25);
      for (final p in legal) {
        canvas.drawCircle(centerOf(p), cell * 0.12, hintPaint);
      }
    }

    // Все стоящие камни.
    for (final entry in state.board.stones.entries) {
      final p = entry.key;
      final color = entry.value;
      _drawStone(canvas, centerOf(p), cell * 0.46, color, 1);

      // Маркер последнего хода — кольцо на камне.
      if (state.lastMove?.point == p) {
        final ringPaint = Paint()
          ..color = color == StoneColor.black
              ? Colors.white.withValues(alpha: .85)
              : ink.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size * 0.005);
        canvas.drawCircle(centerOf(p), cell * 0.18, ringPaint);
      }

      // Группы в атари — красное кольцо (подсказка под угрозой).
      if (hintsOn && atari.contains(p)) {
        final danger = Paint()
          ..color = const Color(0xFFE5484D).withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size * 0.006);
        canvas.drawCircle(centerOf(p), cell * 0.40, danger);
      }
    }

    // Запрещённая точка ко — маленький красный крестик.
    if (state.koPoint != null && hintsOn) {
      final c = centerOf(state.koPoint!);
      final crossPaint = Paint()
        ..color = const Color(0xFFE5484D).withValues(alpha: .6)
        ..strokeWidth = math.max(1.5, size * 0.006)
        ..strokeCap = StrokeCap.round;
      final r = cell * 0.18;
      canvas.drawLine(
          Offset(c.dx - r, c.dy - r), Offset(c.dx + r, c.dy + r), crossPaint);
      canvas.drawLine(
          Offset(c.dx - r, c.dy + r), Offset(c.dx + r, c.dy - r), crossPaint);
    }

    // Предложенный ход — зелёное кольцо.
    if (hintsOn && suggested != null) {
      final suggest = Paint()
        ..color = const Color(0xFF34C759).withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size * 0.007);
      canvas.drawCircle(centerOf(suggested!), cell * 0.42, suggest);
    }
  }

  void _drawStone(
    Canvas canvas,
    Offset center,
    double radius,
    StoneColor color, [
    double opacity = 1,
  ]) {
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Тень под камнем.
    canvas.drawCircle(
      Offset(center.dx, center.dy + radius * 0.12),
      radius * 0.96,
      Paint()
        ..color = ink.withValues(alpha: 0.28 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.18),
    );
    // Тело камня — радиальный градиент для объёма.
    final colors = color == StoneColor.black
        ? const [_blackStoneLight, _blackStoneDark]
        : const [_whiteStoneLight, _whiteStoneDark];
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          radius: 0.9,
          colors: colors.map((c) => c.withValues(alpha: opacity)).toList(),
        ).createShader(rect),
    );
    // Блик.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx - radius * 0.32,
          center.dy - radius * 0.38,
        ),
        width: radius * 0.55,
        height: radius * 0.34,
      ),
      Paint()
        ..color = Colors.white.withValues(
          alpha: (color == StoneColor.black ? 0.30 : 0.80) * opacity,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _GoBoardPainter old) =>
      old.state.fingerprint != state.fingerprint ||
      old.suggested != suggested ||
      old.hintsOn != hintsOn ||
      old.isMyTurn != isMyTurn;
}

/// Панель действий: Пас, Отменить, Подсказка, Сдаться.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});
  final GoController controller;

  @override
  Widget build(BuildContext context) {
    final thinking = controller.computerThinking || controller.hintThinking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          _ActionChip(
            icon: Icons.undo_rounded,
            label: 'Отменить',
            enabled: controller.canUndo,
            onTap: controller.undo,
          ),
          if (controller.hintButtonEnabled)
            _ActionChip(
              icon: Icons.lightbulb_rounded,
              label: controller.hintThinking ? 'Думаю…' : 'Подсказка',
              enabled: controller.canInteract &&
                  !thinking &&
                  controller.hintsEnabled,
              onTap: controller.showHint,
            ),
          _ActionChip(
            icon: Icons.block_rounded,
            label: 'Пас',
            enabled: controller.canPass,
            onTap: controller.pass,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
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
  Widget build(BuildContext context) {
    const color = purple;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: enabled ? color : const Color(0xFFD8D2E0),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
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

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.onClose,
    required this.color,
  });
  final String text;
  final VoidCallback onClose;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
}

class _UndoRequest extends StatelessWidget {
  const _UndoRequest({required this.controller});
  final GoController controller;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0E9FC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Друг просит отменить последний ход. Разрешить?',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
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
}

class _FatalView extends StatelessWidget {
  const _FatalView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 64, color: muted),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              BigButton(
                title: 'В меню',
                icon: Icons.home_rounded,
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ],
          ),
        ),
      );
}

/// Таблица очков для классического режима в диалоге завершения.
class _ScoreTable extends StatelessWidget {
  const _ScoreTable({required this.score});
  final ScoreSummary score;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScoreColumn(color: StoneColor.black, s: score),
            const Divider(height: 20),
            _ScoreColumn(color: StoneColor.white, s: score),
            const SizedBox(height: 8),
            _ScoreRow(
              label: 'Разница',
              value: score.difference.abs() < 0.01
                  ? '0'
                  : (score.difference > 0
                      ? '+${score.difference.toStringAsFixed(1)} чёрным'
                      : '+${(-score.difference).toStringAsFixed(1)} белым'),
              emphasize: true,
            ),
          ],
        ),
      );
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({required this.color, required this.s});
  final StoneColor color;
  final ScoreSummary s;

  @override
  Widget build(BuildContext context) {
    final score = color == StoneColor.black ? s.blackScore : s.whiteScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StoneDot(dark: color == StoneColor.black, size: 24),
            const SizedBox(width: 8),
            Text(
              color.label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: ink,
              ),
            ),
            const Spacer(),
            Text(
              score.toStringAsFixed(1),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ScoreRow(
          label: 'Территория',
          value:
              '${color == StoneColor.black ? s.blackTerritory : s.whiteTerritory}',
        ),
        const SizedBox(height: 4),
        _ScoreRow(
          label: 'Пленники',
          value:
              '${color == StoneColor.black ? s.blackCaptured : s.whiteCaptured}',
        ),
        if (color == StoneColor.white) ...[
          const SizedBox(height: 4),
          _ScoreRow(label: 'Коми', value: s.komi.toStringAsFixed(1)),
        ],
        if ((color == StoneColor.black ? s.deadWhite : s.deadBlack) > 0) ...[
          const SizedBox(height: 4),
          _ScoreRow(
            label: 'Мёртвые у соперника',
            value:
                '${color == StoneColor.black ? s.deadWhite : s.deadBlack}',
          ),
        ],
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w700,
              fontSize: emphasize ? 15 : 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: emphasize ? 17 : 14,
              color: emphasize ? purple : ink,
            ),
          ),
        ],
      );
}

/// Таблица результата в режиме «Захват»: счёт снятых камней и цель.
class _CaptureTable extends StatelessWidget {
  const _CaptureTable({
    required this.blackCaptured,
    required this.whiteCaptured,
    required this.target,
  });
  final int blackCaptured;
  final int whiteCaptured;
  final int target;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            _ScoreRow(label: 'Чёрные сняли', value: '$blackCaptured'),
            const SizedBox(height: 6),
            _ScoreRow(label: 'Белые сняли', value: '$whiteCaptured'),
            const SizedBox(height: 6),
            _ScoreRow(
              label: 'Цель',
              value: '$target ${target == 1 ? 'камень' : 'камня'}',
              emphasize: true,
            ),
          ],
        ),
      );
}
