import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'domino_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'network.dart';
import 'table_view.dart';
import 'tile_view.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети, без него —
/// выбор режима (против компьютера или вдвоём на одном устройстве).
class DominoEntryPage extends StatelessWidget {
  const DominoEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return DominoSessionPage(settings: settings, network: network);
    }
    return DominoModePage(settings: settings);
  }
}

/// Выбор режима: против компьютера (с уровнем) или вдвоём на одном устройстве.
class DominoModePage extends StatelessWidget {
  const DominoModePage({super.key, required this.settings});
  final SettingsController settings;

  void _startLocal(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => DominoSessionPage(
        settings: settings,
        vsAi: false,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Режим игры',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 1',
          title: 'С кем играем?',
          subtitle: 'Можно тренироваться с компьютером, играть вдвоём '
              'или позвать друзей по сети.',
        ),
        const SizedBox(height: 25),
        ChoiceTile(
          title: 'Против компьютера',
          subtitle: 'Три уровня: от лёгкого до сложного',
          icon: Icons.smart_toy_rounded,
          color: const Color(0xFFE8E0FA),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DominoDifficultyPage(settings: settings),
            ),
          ),
        ),
        ChoiceTile(
          title: 'Два игрока',
          subtitle: 'Играйте по очереди на одном устройстве',
          icon: Icons.people_alt_rounded,
          color: const Color(0xFFFFE5A3),
          onTap: () => _startLocal(context),
        ),
        const SizedBox(height: 16),
        const _HintBox(
          text: 'Играть можно и в одиночку против компьютера: '
              'начни с лёгкого уровня.',
        ),
      ],
    ),
  );
}

/// Выбор сложности: Лёгкий / Средний / Сложный.
class DominoDifficultyPage extends StatelessWidget {
  const DominoDifficultyPage({super.key, required this.settings});
  final SettingsController settings;

  void _start(BuildContext context, Difficulty difficulty) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DominoSessionPage(
          settings: settings,
          vsAi: true,
          difficulty: difficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Сложность',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 2',
          title: 'Выбери уровень',
          subtitle: 'Начни с лёгкого — и расти с каждой партией!',
        ),
        const SizedBox(height: 25),
        for (final difficulty in Difficulty.values)
          ChoiceTile(
            title: difficulty.label,
            subtitle: difficulty.hint,
            icon: Icons.star_rounded,
            color: switch (difficulty) {
              Difficulty.easy => const Color(0xFFDDF1DF),
              Difficulty.medium => const Color(0xFFFFE5A3),
              Difficulty.hard => const Color(0xFFE8DDFB),
            },
            tag: '★' * (difficulty.index + 1),
            onTap: () => _start(context, difficulty),
          ),
      ],
    ),
  );
}

class _HintBox extends StatelessWidget {
  const _HintBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0E9FC),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: purple, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: ink,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Что игрок выбрал в диалоге итога партии.
enum _ResultChoice { again, undo, home }

/// Экран партии: сверху — заголовок и кнопки, посередине — стол с цепочкой и
/// базаром, снизу — рука игрока и кнопки действий.
class DominoSessionPage extends StatefulWidget {
  const DominoSessionPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.network,
    this.animationDuration = const Duration(milliseconds: 420),
    this.initialState,
  });
  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final NetworkSession? network;

  /// Длительность анимации выкладывания кости. В тестах — `Duration.zero`.
  final Duration animationDuration;

  /// Стартовая позиция для тестов; в игре всегда раздаётся новая.
  final GameState? initialState;

  @override
  State<DominoSessionPage> createState() => _DominoSessionPageState();
}

class _DominoSessionPageState extends State<DominoSessionPage> {
  late final DominoController _controller;
  bool _resultShown = false;
  bool _resultDialogOpen = false;
  bool _resultRecorded = false;
  bool _errorShown = false;
  bool _undoDialogShown = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = DominoController(
      settings: widget.settings,
      sounds: sounds,
      network: widget.network,
      animationDuration: widget.animationDuration,
    )..onUndoRequested = _showUndoRequest;
    _controller.addListener(_onGameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.network != null) {
          _controller.startNetwork();
        } else if (widget.initialState != null) {
          _controller.startLocalWithState(widget.initialState!);
        } else if (widget.vsAi) {
          _controller.startComputer(widget.difficulty);
        } else {
          _controller.startLocal();
        }
      }
    });
  }

  void _onGameChanged() {
    if (!mounted) return;
    if (_controller.fatalMessage != null && !_errorShown) {
      _errorShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showError();
      });
    } else if (_controller.incomingUndoPly != null && !_undoDialogShown) {
      _undoDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showUndoRequest();
      });
    } else if (_controller.isOver &&
        !_controller.isAnimating &&
        !_resultShown &&
        _controller.fatalMessage == null) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResult();
      });
    }
  }

  Future<void> _showError() async {
    await showDianaDialog<bool>(
      context: context,
      title: 'Ой, что-то случилось',
      barrierDismissible: false,
      content: Text(
        _controller.fatalMessage ?? 'Связь потеряна.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'В меню', value: true, primary: true),
      ],
    );
    if (mounted) _goHome();
  }

  Future<void> _showUndoRequest() async {
    final seat = _controller.incomingUndoSeat;
    final accepted = await showDianaDialog<bool>(
      context: context,
      title: 'Просят отменить ход',
      barrierDismissible: false,
      content: Text(
        seat == null
            ? 'Разрешить вернуться на один ход назад?'
            : '${_controller.nameFor(seat)} просит вернуть один ход назад. '
                  'Разрешить?',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Разрешить', value: true, primary: true),
        DianaDialogButton<bool>(label: 'Не сейчас', value: false),
      ],
    );
    if (!mounted) return;
    _undoDialogShown = false;
    if (accepted == true && _resultDialogOpen) {
      Navigator.of(context).pop();
      _resultDialogOpen = false;
      _resultShown = false;
    }
    _controller.respondUndo(accepted == true);
  }

  Future<void> _showResult() async {
    final winner = _controller.winner;
    // Без победителя партия могла закончиться только ничьей.
    final draw = winner == null;
    final mine = winner != null && winner == _controller.mySeat;
    final local = _controller.mode == DominoMode.local;
    _controller.sounds.play(
      resultSoundName(draw: draw, local: local, iWon: mine),
    );
    _resultDialogOpen = true;
    final choice = await showDianaDialog<_ResultChoice>(
      context: context,
      title: _resultTitle(winner, mine, local, draw),
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Celebration(calm: !mine && !local),
          const SizedBox(height: 14),
          Text(
            _resultText(winner, mine, local, draw),
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
          if (_controller.isFish) ...[
            const SizedBox(height: 12),
            _ScoreTable(
              names: [
                for (var seat = 0; seat < _controller.playerCount; seat++)
                  _controller.nameFor(seat),
              ],
              sums: _controller.result?.sums ?? const [],
              winner: winner,
            ),
          ],
        ],
      ),
      actions: [
        const DianaDialogButton<_ResultChoice>(
          label: 'Играть снова',
          value: _ResultChoice.again,
          primary: true,
        ),
        if (_controller.canUndo)
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
    _resultDialogOpen = false;
    if (!mounted) return;
    switch (choice) {
      case _ResultChoice.again:
        _recordResult(mine || local);
        await _playAgain();
      case _ResultChoice.home:
        _recordResult(mine || local);
        _goHome();
      case _ResultChoice.undo:
        _resultShown = false;
        _controller.undo();
      case null:
        _resultShown = false;
    }
  }

  String _resultTitle(int? winner, bool mine, bool local, bool draw) {
    if (draw) return _controller.isFish ? 'Рыба — ничья!' : 'Ничья!';
    if (_controller.isFish) {
      return local || mine
          ? 'Рыба! Победа!'
          : 'Рыба! В следующий раз получится!';
    }
    if (local) return '${_controller.nameFor(winner!)} победил!';
    return mine ? 'Ты выиграл! 🎉' : 'Отличная партия!';
  }

  String _resultText(int? winner, bool mine, bool local, bool draw) {
    if (draw) {
      return 'У всех поровну очков на руках. Сыграем ещё?';
    }
    if (_controller.isFish) {
      final sums = _controller.result?.sums ?? const [];
      final scores = winner != null && winner < sums.length
          ? 'Меньше всех очков на руках — ${sums[winner]}. '
          : '';
      return '$scoresНикто не смог походить, а базар пуст. '
          'Пусть победит тот, у кого легче руки!';
    }
    if (local) return 'Все кости на столе. Здорово сыграно!';
    return mine
        ? 'Здорово! Ты выложил все свои кости — это победа!'
        : 'Соперник выложил все свои кости. В следующий раз обязательно получится!';
  }

  void _recordResult(bool won) {
    if (_resultRecorded) return;
    _resultRecorded = true;
    unawaited(widget.settings.recordGame(won: won));
  }

  void _goHome() {
    if (_exiting || !mounted) return;
    _exiting = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _playAgain() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    _exiting = true;
    navigator.popUntil((route) => route.isFirst);
    if (_controller.mode == DominoMode.network) {
      // Сетевой рематч требует нового лобби: возвращаемся в меню.
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DominoSessionPage(
          settings: widget.settings,
          vsAi: widget.vsAi,
          difficulty: widget.difficulty,
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (_exiting) return;
    final yes = await showDianaDialog<bool>(
      context: context,
      title: 'Выйти из партии?',
      content: const Text(
        'Текущая партия закончится. Можно будет начать новую!',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Продолжить', value: false, primary: true),
        DianaDialogButton<bool>(label: 'В меню', value: true),
      ],
    );
    if (!mounted || yes != true) return;
    if (_controller.mode == DominoMode.network && !_controller.isOver) {
      _controller.resign();
    }
    _goHome();
  }

  Future<void> _confirmResign() async {
    final yes = await showDianaDialog<bool>(
      context: context,
      title: 'Закончить партию?',
      content: const Text(
        'Если сдашься, победа достанется сопернику.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Продолжить', value: false, primary: true),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    );
    if (mounted && yes == true) _controller.resign();
  }

  void _showHistory() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFCF7),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'История ходов',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            if (_controller.history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Пока ходов нет. Начинаем!',
                  style: TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _controller.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final record = _controller.history[index];
                    return ListTile(
                      leading: TileMark(size: 30),
                      title: Text(
                        record.text,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(_controller.nameFor(record.seat)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.removeListener(_onGameChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmExit();
    },
    child: Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 700;
                    final gap = compact ? 6.0 : 10.0;
                    // Поле больше не растягивается на весь экран: оно
                    // занимает свою полосу, а освободившееся место уходит
                    // руке и цепочке — так кости крупнее, а в цепочку
                    // помещается больше.
                    final fieldHeight =
                        (constraints.maxHeight *
                                (compact ? .26 : .24)).clamp(
                          122.0,
                          compact ? 190.0 : 232.0,
                        );
                    final handHeight =
                        (constraints.maxHeight *
                                (compact ? .18 : .20)).clamp(
                          92.0,
                          compact ? 124.0 : 158.0,
                        );
                    return Column(
                      children: [
                        _header(compact: compact),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              14,
                              2,
                              14,
                              compact ? 6 : 12,
                            ),
                            child: Column(
                              children: [
                                _players(compact: compact),
                                Expanded(
                                  flex: 5,
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: fieldHeight,
                                      ),
                                      child: _table(compact: compact),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: handHeight,
                                      ),
                                      child: _hand(compact: compact),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: compact ? 46 : 54,
                                  child: _message(compact: compact),
                                ),
                                SizedBox(height: gap),
                                SizedBox(
                                  height: compact ? 46 : 54,
                                  child: _actions(compact: compact),
                                ),
                                if (!compact) ..._secondaryActions(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _secondaryActions() => [
    const SizedBox(height: 2),
    SizedBox(
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _showHistory,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('История'),
          ),
          TextButton.icon(
            onPressed: _controller.isOver ? null : _confirmResign,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Сдаться'),
          ),
        ],
      ),
    ),
  ];

  Widget _header({bool compact = false}) => Padding(
    padding: EdgeInsets.fromLTRB(6, compact ? 0 : 4, 6, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: _confirmExit,
          tooltip: 'Назад в меню',
          visualDensity: compact ? VisualDensity.compact : null,
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
        ),
        Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Домино',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  switch (_controller.mode) {
                    DominoMode.computer =>
                      'Против компьютера · ${_controller.difficulty.label}',
                    DominoMode.local => 'Два игрока',
                    DominoMode.network => 'Сетевая игра',
                  },
                  style: const TextStyle(
                    fontSize: 10,
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: widget.settings,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('hint-toggle'),
                tooltip: _controller.hintsEnabled
                    ? 'Выключить подсказки'
                    : 'Включить подсказки',
                visualDensity: compact ? VisualDensity.compact : null,
                onPressed: () => widget.settings.setFlag(
                  dominoGameId,
                  'hints',
                  !_controller.hintsEnabled,
                ),
                icon: Icon(
                  _controller.hintsEnabled
                      ? Icons.lightbulb_rounded
                      : Icons.lightbulb_outline_rounded,
                  color: _controller.hintsEnabled
                      ? purple
                      : const Color(0xFFB4ACAF),
                ),
              ),
              IconButton(
                key: const Key('sound-toggle'),
                tooltip: widget.settings.sound
                    ? 'Выключить звук'
                    : 'Включить звук',
                visualDensity: compact ? VisualDensity.compact : null,
                onPressed: () =>
                    widget.settings.setSound(!widget.settings.sound),
                icon: Icon(
                  widget.settings.sound
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: purple,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _players({bool compact = false}) {
    if (!_controller.isReady) return const SizedBox.shrink();
    final state = _controller.state;
    final notes = <int, String>{};
    for (final seat in state.inactive) {
      notes[seat] = 'вышел из партии';
    }
    return PlayersStrip(
      names: [
        for (var seat = 0; seat < state.playerCount; seat++)
          _controller.nameFor(seat),
      ],
      handSizes: state.handSizes,
      activeSeat: state.turn,
      handSeat: _controller.handSeat,
      notes: notes,
      compact: compact,
    );
  }

  Widget _table({bool compact = false}) {
    if (!_controller.isReady) {
      return const TableSurface(
        child: Center(
          child: Text(
            'Готовим стол…',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }
    final state = _controller.state;
    final selected = _controller.selectedTile;
    final fitsLeft = selected != null &&
        state.board.sidesFor(selected).contains(ChainSide.left);
    final fitsRight = selected != null &&
        state.board.sidesFor(selected).contains(ChainSide.right);
    final suggestedSide = _controller.suggestedMove?.side;
    return TableSurface(
      child: Column(
        children: [
          Row(
            children: [
              EndChip(
                key: const Key('end-left'),
                value: state.board.leftEnd,
                side: ChainSide.left,
                highlighted: fitsLeft || suggestedSide == ChainSide.left,
                enabled: _controller.canInteract &&
                    (fitsLeft || suggestedSide == ChainSide.left),
                onTap: () => _controller.playAt(ChainSide.left),
              ),
              const Spacer(),
              BazaarStack(
                key: const Key('bazaar'),
                count: state.bazaarCount,
                enabled: _controller.canDraw,
                onTap: () => _controller.drawFromBazaar(),
              ),
              const Spacer(),
              EndChip(
                key: const Key('end-right'),
                value: state.board.rightEnd,
                side: ChainSide.right,
                highlighted: fitsRight || suggestedSide == ChainSide.right,
                enabled: _controller.canInteract &&
                    (fitsRight || suggestedSide == ChainSide.right),
                onTap: () => _controller.playAt(ChainSide.right),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          Expanded(
            child: ChainView(
              placed: state.board.chain,
              scrollToken: state.board.length,
              scrollTo: _controller.animation?.move?.side ?? ChainSide.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hand({bool compact = false}) {
    if (!_controller.isReady) return const SizedBox.shrink();
    return HandView(
      tiles: _controller.myHand,
      playable: _controller.playableTiles,
      selected: _controller.selectedTile,
      suggested: _controller.suggestedMove?.tile,
      hintsEnabled: _controller.hintsEnabled,
      reserved: !_controller.canInteract,
      onTap: _controller.tapTile,
    );
  }

  Widget _message({bool compact = false}) {
    var text = _controller.notice;
    var hint = false;
    if (text == null) {
      text = _controller.hintText;
      hint = text != null;
    }
    if (text == null && _controller.computerThinking) {
      text = 'Компьютер думает…';
    }
    if (text == null && _controller.isOver) {
      final winner = _controller.winner;
      text = winner == null
          ? 'Ничья — отличная партия!'
          : 'Партия закончена.';
    }
    if (text == null && _controller.isReady) {
      text = _turnText();
    }
    final label = text ?? 'Готовим стол…';
    final canDismiss = _controller.notice != null ||
        _controller.hintText != null;
    return Container(
      key: const Key('message-bubble'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
      decoration: BoxDecoration(
        color: hint ? const Color(0xFFFFE8A8) : const Color(0xFFFFF0CA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            hint ? Icons.lightbulb_rounded : Icons.auto_awesome_rounded,
            color: const Color(0xFFBA8940),
            size: compact ? 17 : 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                height: 1.25,
                color: const Color(0xFF795D38),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (canDismiss)
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                key: const Key('message-dismiss'),
                padding: EdgeInsets.zero,
                iconSize: 17,
                onPressed: _controller.hintText != null
                    ? _controller.clearHint
                    : _controller.clearNotice,
                tooltip: 'Скрыть',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: Color(0xFF9A8060),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _turnText() {
    if (!_controller.isReady) return 'Готовим стол…';
    if (_controller.mode == DominoMode.local) {
      // Вдвоём за одним устройством подсказка нужна не меньше: за столом
      // сидит ребёнок, и он не должен сам догадываться, что базар открыт.
      final name = _controller.nameFor(_controller.state.turn);
      if (_controller.legalMoves.isNotEmpty) {
        return 'Ход: $name — выбери кость.';
      }
      return _controller.canDraw
          ? 'Ход: $name — подходящей кости нет, возьми из базара.'
          : 'Ход: $name — ходов нет, пропускаем.';
    }
    if (_controller.activeSide == DominoActive.me) {
      if (_controller.legalMoves.isNotEmpty) return 'Твой ход — выбери кость.';
      return _controller.canDraw
          ? 'Подходящей кости нет — возьми из базара.'
          : 'Ходов нет — пропускаем.';
    }
    if (_controller.activeSide == DominoActive.friend) {
      return 'Ходит ${_controller.nameFor(_controller.state.turn)}…';
    }
    if (_controller.activeSide == DominoActive.computer) {
      return 'Компьютер думает…';
    }
    return '';
  }

  bool get _showHintButton =>
      _controller.hintsEnabled &&
      _controller.hintButtonEnabled &&
      _controller.canInteract;

  Widget _actions({bool compact = false}) {
    final height = compact ? 46.0 : 54.0;
    if (_controller.canDraw) {
      return _ActionButton(
        key: const Key('draw-button'),
        icon: Icons.download_rounded,
        label: 'Взять из базара',
        enabled: true,
        onTap: () => _controller.drawFromBazaar(),
        highlighted: true,
        height: height,
      );
    }
    final canUndo = _controller.canUndo;
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            key: const Key('undo-button'),
            icon: Icons.undo_rounded,
            label: 'Отменить ход',
            enabled: canUndo,
            onTap: _controller.undo,
            height: height,
          ),
        ),
        if (_showHintButton) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              key: const Key('hint-button'),
              icon: Icons.lightbulb_outline_rounded,
              label: 'Подсказка',
              enabled: true,
              onTap: _controller.showHint,
              highlighted: true,
              height: height,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.highlighted = false,
    this.height = 54,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool highlighted;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: FilledButton(
      onPressed: enabled ? onTap : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: highlighted ? purple : Colors.white,
        foregroundColor: highlighted ? Colors.white : ink,
        disabledBackgroundColor: const Color(0xFFEFE9E5),
        disabledForegroundColor: const Color(0xFFB4ACAF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: height >= 52 ? 21 : 18),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: height >= 52 ? 16 : 14.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Картинка над итогом: кости и звёздочки, если победа.
class _Celebration extends StatefulWidget {
  const _Celebration({this.calm = false});

  final bool calm;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, _) => SizedBox(
      width: 150,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: .95 + animation.value * (widget.calm ? .04 : .08),
            child: const TileMark(size: 62),
          ),
          if (!widget.calm) ...[
            Positioned(
              top: 4 + animation.value * 5,
              left: 6,
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFF5C254),
                size: 26,
              ),
            ),
            Positioned(
              top: 2,
              right: 4,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: purple.withValues(alpha: .7),
                size: 24,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Очки на руках при «рыбе».
class _ScoreTable extends StatelessWidget {
  const _ScoreTable({
    required this.names,
    required this.sums,
    required this.winner,
  });

  final List<String> names;
  final List<int> sums;
  final int? winner;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF3EDE2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var seat = 0; seat < names.length; seat++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  winner == seat ? Icons.emoji_events_rounded : null,
                  color: const Color(0xFFE0B23A),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    names[seat],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
                Text(
                  seat < sums.length ? '${sums[seat]}' : '–',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: deepPurple,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
