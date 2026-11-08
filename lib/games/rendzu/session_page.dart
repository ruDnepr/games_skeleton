import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/games_page.dart' show popToGamesList;
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'network.dart';
import 'rendzu_controller.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети тем
/// набором правил и размером доски, что выбрал хост до лобби; без соединения —
/// экран выбора режима и параметров партии.
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
      // В сети хост играет чёрными. Набор правил и размер доски хост выбирает
      // до создания сетевой игры; клиент принимает тот, что пришёл в
      // рукопожатии.
      final options = network!.lobby.options;
      final rulesetStr = options['ruleset'] as String? ?? rendzuDefaultRuleset;
      final boardSizeStr =
          options['boardSize'] as String? ?? rendzuDefaultBoardSize;
      final ruleset =
          rulesetStr == 'renju' ? Ruleset.renju : Ruleset.gomoku;
      final boardSize = boardSizeStr == 'standard15'
          ? BoardSize.standard15
          : BoardSize.small9;
      return RendzuSessionPage(
        settings: settings,
        network: network,
        ruleset: ruleset,
        boardSize: boardSize,
      );
    }
    return RendzuModePage(settings: settings);
  }
}

/// Экран выбора набора правил и размера доски перед сетевым лобби. Хост
/// выбирает, выбор сохраняется в настройках и уезжает в рукопожатие через
/// [rendzuOptions]. После нажатия «К сетевой игре» экран закрывается —
/// открывается общее лобби каркаса.
class RendzuNetworkSetupPage extends StatefulWidget {
  const RendzuNetworkSetupPage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<RendzuNetworkSetupPage> createState() => _RendzuNetworkSetupPageState();
}

class _RendzuNetworkSetupPageState extends State<RendzuNetworkSetupPage> {
  late Ruleset _ruleset;
  late BoardSize _boardSize;

  @override
  void initState() {
    super.initState();
    final storedRuleset = widget.settings
        .gameString(rendzuGameId, rendzuRulesetKey, rendzuDefaultRuleset);
    final storedBoard = widget.settings
        .gameString(rendzuGameId, rendzuBoardSizeKey, rendzuDefaultBoardSize);
    _ruleset = storedRuleset == 'renju' ? Ruleset.renju : Ruleset.gomoku;
    _boardSize = storedBoard == 'standard15'
        ? BoardSize.standard15
        : BoardSize.small9;
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Рэндзю',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'СЕТЕВАЯ ПАРТИЯ',
              title: 'Пять в ряд по сети',
              subtitle:
                  'Выбери правила и доску — друг увидит те же настройки в лобби.',
            ),
            const SizedBox(height: 18),
            const Text(
              'Набор правил',
              style: TextStyle(fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 8),
            _RulesetRow(
              value: _ruleset,
              onChanged: (r) => setState(() => _ruleset = r),
            ),
            const SizedBox(height: 14),
            const Text(
              'Размер доски',
              style: TextStyle(fontWeight: FontWeight.w900, color: ink),
            ),
            const SizedBox(height: 8),
            _BoardSizeRow(
              value: _boardSize,
              onChanged: (b) => setState(() => _boardSize = b),
            ),
            const SizedBox(height: 26),
            BigButton(
              key: const Key('rendzu-network-next'),
              title: 'К сетевой игре',
              subtitle: 'Хост играет чёрными и ходит первым',
              icon: Icons.wifi_rounded,
              onPressed: () => _next(context),
            ),
          ],
        ),
      );

  Future<void> _next(BuildContext context) async {
    await widget.settings.setGameString(
      rendzuGameId,
      rendzuRulesetKey,
      _ruleset == Ruleset.renju ? 'renju' : 'gomoku',
    );
    await widget.settings.setGameString(
      rendzuGameId,
      rendzuBoardSizeKey,
      _boardSize == BoardSize.standard15 ? 'standard15' : 'small9',
    );
    if (!context.mounted) return;
    // Выбор сделан — возвращаемся, чтобы открылось сетевое лобби.
    Navigator.of(context).maybePop();
  }
}

/// Выбор режима и параметров локальной партии.
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
            const SizedBox(height: 6),
            _Hint(_ruleset.russianDescription),
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
              const SizedBox(height: 6),
              _Hint(_difficulty.russianDescription),
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
      );
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
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceChip(
              label: labels[i],
              desc: '',
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : ink,
                    fontSize: 14,
                  ),
                ),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.white.withValues(alpha: .85)
                          : muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Экран партии: доска (CustomPaint) посередине, сверху — HUD с фишками
/// игроков и номером хода, снизу — кнопки «Отменить» и «Сдаться». AppBar
/// показывает набор правил и размер доски, а также кнопки «Подсказка» и
/// «Заново».
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
  bool _hintVisible = false;

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
    _controller.addListener(_onControllerChanged);
    if (widget.network != null) {
      _controller.startNetwork();
    } else if (widget.vsAi) {
      _controller.startAi(widget.difficulty, widget.humanColor);
    } else {
      _controller.startLocal();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final warning = _controller.warning;
    if (warning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warning),
            backgroundColor: const Color(0xFFE27D60),
            duration: const Duration(seconds: 4),
          ),
        );
        _controller.clearWarning();
      });
    }
    // Перестраиваем виджет — иначе _maybeShowWin() в build() не вызовется
    // после победы, и диалог результата не появится.
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _maybeShowWin() {
    if (_controller.isOver && !_winShown) {
      _winShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showEndDialog());
    }
  }

  void _showHint() {
    if (_controller.isOver || !_controller.canInteract) return;
    _controller.showHint();
    if (_controller.hintPoint == null) return;
    setState(() => _hintVisible = true);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  /// Диалог результата: показывает, каким ходом и кто победил. Кнопки «Играть
  /// снова», «Отменить ход» (только офлайн, если есть что отменять) и «В меню».
  Future<void> _showEndDialog() async {
    if (!mounted) return;
    final isDraw = _controller.isDraw;
    final winner = _controller.winnerColor;
    final iWon = _controller.mode == RendzuMode.network
        ? winner == (_controller.isHost ? StoneColor.black : StoneColor.white)
        : (_controller.mode == RendzuMode.ai
            ? winner == widget.humanColor
            : true);
    final winnerName = winner == StoneColor.black ? 'Чёрные' : 'Белые';
    final cfg = _controller;
    final moveNo = cfg.moveNumber;
    final lastMove = cfg.lastMove;
    final line = cfg.winningLine;

    String title;
    String message;
    bool calm = false;
    if (isDraw) {
      title = 'Ничья!';
      message = 'Доска заполнена, никто не собрал пять. Попробуем ещё раз?';
      calm = true;
    } else {
      if (_controller.mode == RendzuMode.ai) {
        title = iWon ? 'Ты молодец!' : 'Отличная партия!';
      } else {
        title = '$winnerName победили!';
      }
      final direction = _describeDirection(line);
      final pointStr = lastMove != null
          ? 'ходом №$moveNo в клетку (${lastMove.x + 1}, ${lastMove.y + 1})'
          : 'последним ходом';
      if (_controller.mode == RendzuMode.ai && iWon) {
        message =
            'Ты собрал пять в ряд — $direction, $pointStr. Так держать!';
      } else if (_controller.mode == RendzuMode.ai && !iWon) {
        message = 'Компьютер собрал пять в ряд — $direction, $pointStr. '
            'В следующий раз обязательно получится!';
      } else {
        message = '$winnerName собрали пять в ряд — $direction, '
            '$pointStr. Здорово сыграно!';
      }
    }

    final canUndoOffline = _controller.mode != RendzuMode.network &&
        _controller.moveNumber > 0;

    final choice = await showDianaDialog<_ResultChoice>(
      context: context,
      title: title,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Celebration(calm: calm),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
        ],
      ),
      actions: [
        const DianaDialogButton<_ResultChoice>(
          label: 'Играть снова',
          value: _ResultChoice.again,
          primary: true,
        ),
        if (canUndoOffline)
          const DianaDialogButton<_ResultChoice>(
            label: 'Отменить ход',
            value: _ResultChoice.undo,
          ),
        const DianaDialogButton<_ResultChoice>(
          label: 'В меню',
          value: _ResultChoice.home,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _ResultChoice.again:
        setState(() => _winShown = false);
        _controller.playAgain();
      case _ResultChoice.undo:
        setState(() => _winShown = false);
        _controller.undo();
      case _ResultChoice.home:
        popToGamesList(context);
      case null:
        break;
    }
  }

  /// Человеческое описание направления победной линии.
  String _describeDirection(List<Point> line) {
    if (line.length < 2) return 'пять в ряд';
    final a = line.first;
    final b = line.last;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    if (dy == 0) return 'по горизонтали';
    if (dx == 0) return 'по вертикали';
    if ((dx > 0 && dy > 0) || (dx < 0 && dy < 0)) return 'по диагонали ↘';
    return 'по диагонали ↗';
  }

  void _confirmRestart() {
    showDianaDialog<bool>(
      context: context,
      title: 'Начать заново?',
      content: const Text(
        'Текущая партия будет потеряна.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Отмена', value: false),
        DianaDialogButton<bool>(label: 'Заново', value: true, primary: true),
      ],
    ).then((ok) {
      if (ok == true) {
        setState(() => _winShown = false);
        _controller.playAgain();
      }
    });
  }

  void _confirmResign() {
    showDianaDialog<bool>(
      context: context,
      title: 'Сдаться?',
      content: const Text(
        'Ты проиграешь эту партию.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Отмена', value: false),
        DianaDialogButton<bool>(label: 'Сдаюсь', value: true, primary: true),
      ],
    ).then((ok) {
      if (ok == true) _controller.resign();
    });
  }

  bool get _canResign => !_controller.isOver;

  @override
  Widget build(BuildContext context) {
    _maybeShowWin();
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${widget.ruleset.russianName} · ${widget.boardSize.russianName}',
            style: const TextStyle(fontSize: 17),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Подсказка',
            icon: const Icon(Icons.lightbulb_outline_rounded),
            onPressed: (_controller.isOver ||
                    !_controller.hintsEnabled ||
                    !_controller.canInteract)
                ? null
                : _showHint,
          ),
          IconButton(
            tooltip: 'Заново',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _controller.mode == RendzuMode.network
                ? null
                : _confirmRestart,
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
                        _Hud(controller: _controller),
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
                                  board: _controller.board,
                                  lastMove: _controller.lastMove,
                                  winningLine: _controller.winningLine,
                                  forbiddenHints:
                                      _controller.hintsEnabled &&
                                              widget.ruleset == Ruleset.renju
                                          ? _controller.forbiddenHints
                                          : const <Point>{},
                                  patternThrees:
                                      _controller.patternHighlightEnabled
                                          ? _controller.patternThrees
                                          : const <List<Point>>[],
                                  patternFours:
                                      _controller.patternHighlightEnabled
                                          ? _controller.patternFours
                                          : const <List<Point>>[],
                                  hintPoint:
                                      _hintVisible ? _controller.hintPoint : null,
                                  onTap: (p) {
                                    _controller.tap(p);
                                    if (_hintVisible) {
                                      setState(() => _hintVisible = false);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        _Controls(
                          canUndo: _controller.canUndo,
                          canResign: _canResign,
                          onUndo: _controller.undo,
                          onResign: _confirmResign,
                        ),
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
}

enum _ResultChoice { again, undo, home }

/// Верхний HUD: две фишки игроков по краям, в центре — номер хода и подпись
/// «чей ход». Активный игрок подсвечен жёлтой рамкой.
class _Hud extends StatelessWidget {
  const _Hud({required this.controller});
  final RendzuController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.currentColor;
    final isBlack = current == StoneColor.black;
    final isVsComputer = controller.mode == RendzuMode.ai;
    final humanTurn = controller.canInteract;
    final moveNo = controller.moveNumber + (controller.isOver ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _PlayerChip(color: StoneColor.black, active: isBlack && !controller.isOver),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ход $moveNo',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: muted)),
              if (isVsComputer && !controller.isOver)
                Text(
                  humanTurn ? 'Твой ход' : 'Думает компьютер…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: humanTurn ? purple : const Color(0xFFE27D60),
                  ),
                ),
            ],
          ),
          const Spacer(),
          _PlayerChip(color: StoneColor.white, active: !isBlack && !controller.isOver),
        ],
      ),
    );
  }
}

/// Фишка игрока: цветной кружок и подпись «Чёрные»/«Белые». Как в оригинале —
/// без имени игрока и без бейджа «ХОД».
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.color, required this.active});
  final StoneColor color;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? yellow.withValues(alpha: .30)
              : Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? yellow : const Color(0xFFE3D8F5),
            width: active ? 2.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  colors: color == StoneColor.black
                      ? const [Color(0xFF5A5764), Color(0xFF1B1A22)]
                      : const [Colors.white, Color(0xFFE2D6BE)],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              color == StoneColor.black ? 'Чёрные' : 'Белые',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: ink),
            ),
          ],
        ),
      );
}


class _Controls extends StatelessWidget {
  const _Controls({
    required this.canUndo,
    required this.canResign,
    required this.onUndo,
    required this.onResign,
  });
  final bool canUndo;
  final bool canResign;
  final VoidCallback onUndo;
  final VoidCallback onResign;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Отменить'),
            ),
            TextButton.icon(
              onPressed: canResign ? onResign : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Сдаться'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE27D60),
              ),
            ),
          ],
        ),
      );
}

/// Поверхность доски: CustomPaint с сеткой, камнями, подсветками. Тап
/// конвертируется в ближайшее пересечение и зовёт колбэк.
class _BoardSurface extends StatelessWidget {
  const _BoardSurface({
    required this.size,
    required this.board,
    required this.lastMove,
    required this.winningLine,
    required this.forbiddenHints,
    required this.patternThrees,
    required this.patternFours,
    required this.hintPoint,
    required this.onTap,
  });

  final double size;
  final Board board;
  final Point? lastMove;
  final List<Point> winningLine;
  final Set<Point> forbiddenHints;
  final List<List<Point>> patternThrees;
  final List<List<Point>> patternFours;
  final Point? hintPoint;
  final void Function(Point) onTap;

  @override
  Widget build(BuildContext context) {
    final cell = size / board.size;
    return GestureDetector(
      onTapDown: (details) {
        final local = details.localPosition;
        final ix = ((local.dx / cell) - 0.5).round();
        final iy = ((local.dy / cell) - 0.5).round();
        final p = Point(ix, iy);
        if (p.inBounds(board.size)) {
          onTap(p);
        }
      },
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _BoardPainter(
            board: board,
            cell: cell,
            lastMove: lastMove,
            winningLine: winningLine,
            forbiddenHints: forbiddenHints,
            patternThrees: patternThrees,
            patternFours: patternFours,
            hintPoint: hintPoint,
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
  static const Color _woodLight = Color(0xFFB07A45);
  static const Color _woodDark = Color(0xFF8C5831);
  static const Color _line = Color(0xFFF0D9A8);
  static const Color _blackHi = Color(0xFF6A6677);
  static const Color _black = Color(0xFF2A2733);
  static const Color _white = Color(0xFFFBFBF6);
  static const Color _whiteEdge = Color(0xFFCEB998);
  static const Color _threeHi = Color(0xFFFFD66D);
  static const Color _fourHi = Color(0xFFE27D60);

  // Радиус камня — строго меньше половины клетки, чтобы соседние камни
  // не перекрывали друг друга.
  static const double _stoneRadiusFactor = 0.40;

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

    // 3. Звёздные точки (как в го).
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
          : const [_white, _white, _whiteEdge],
      stops: color == StoneColor.black
          ? const [0.0, 1.0]
          : const [0.0, 0.7, 1.0],
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

/// Конфетти-празднование в диалоге победы — дословно из оригинала.
class _Celebration extends StatefulWidget {
  const _Celebration({this.calm = false});
  final bool calm;
  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.calm) {
      return Icon(
        Icons.handshake_rounded,
        size: 56,
        color: muted.withValues(alpha: .5),
      );
    }
    return ScaleTransition(
      scale: Tween(begin: .85, end: 1.1).animate(
        CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      ),
      child: const Icon(Icons.celebration_rounded, size: 56, color: yellow),
    );
  }
}
