import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'domino_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';

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
class DominoModePage extends StatefulWidget {
  const DominoModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<DominoModePage> createState() => _DominoModePageState();
}

class _DominoModePageState extends State<DominoModePage> {
  bool _vsAi = true;
  Difficulty _difficulty = Difficulty.easy;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Домино',
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
          subtitle: 'Ходы по очереди — кости внизу у того, чья очередь',
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
            key: const Key('domino-start'),
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
        builder: (_) => DominoSessionPage(
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
        border: Border.all(color: selected ? purple : const Color(0xFFE3D8F5)),
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

/// Экран партии: сверху — соперник, посередине — стол с цепочкой и базаром,
/// снизу — моя рука и кнопки.
class DominoSessionPage extends StatefulWidget {
  const DominoSessionPage({
    super.key,
    required this.settings,
    this.vsAi = false,
    this.difficulty = Difficulty.easy,
    this.network,
  });
  final SettingsController settings;
  final bool vsAi;
  final Difficulty difficulty;
  final NetworkSession? network;

  @override
  State<DominoSessionPage> createState() => _DominoSessionPageState();
}

class _DominoSessionPageState extends State<DominoSessionPage> {
  late final DominoController _controller;
  bool _overShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = DominoController(
      settings: widget.settings,
      sounds: sounds,
      network: widget.network,
    );
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
    _controller.dispose();
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
  }

  void _showOverDialog() {
    if (!mounted) return;
    final draw = _controller.isDraw;
    final iWon = _controller.mode == DominoMode.local
        ? true
        : _controller.winner == _controller.mySeat;
    final winner = _controller.winner;
    final isFish = _controller.isFish;
    String title;
    if (draw) {
      title = isFish ? 'Рыба — ничья!' : 'Ничья!';
    } else if (isFish) {
      title = iWon ? 'Рыба! Победа!' : 'Рыба! В следующий раз получится!';
    } else if (_controller.mode == DominoMode.local) {
      title = winner != null
          ? '${_controller.nameFor(winner)} победил!'
          : 'Партия окончена';
    } else {
      title = iWon ? 'Ты выиграл! 🎉' : 'Партия окончена';
    }
    String message;
    if (draw) {
      message = 'У обоих поровну очков на руках. Сыграем ещё?';
    } else if (isFish) {
      final sums = _controller.result?.sums ?? const <int>[];
      final score = winner != null && winner < sums.length
          ? 'Меньше всех очков на руках — ${sums[winner]}. '
          : '';
      message = '$scoreНикто не смог походить, а базар пуст.';
    } else if (_controller.mode == DominoMode.local) {
      message = 'Все кости на столе. Здорово сыграно!';
    } else if (iWon) {
      message = 'Здорово! Ты выложил все свои кости — это победа!';
    } else {
      message = 'Соперник выложил все свои кости. В следующий раз обязательно!';
    }
    final result = _controller.result;
    showDianaDialog<_OverChoice>(
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
          if (isFish && result != null && result.sums.length >= 2) ...[
            const SizedBox(height: 14),
            _ScoreTable(
              names: [
                _controller.nameFor(0),
                _controller.nameFor(1),
              ],
              sums: result.sums,
              winner: winner,
            ),
          ],
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
            builder: (_) => DominoSessionPage(
              settings: widget.settings,
              vsAi: widget.vsAi,
              difficulty: widget.difficulty,
            ),
          ),
        );
      } else if (choice == _OverChoice.home || widget.network != null) {
        Navigator.of(context).maybePop();
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
      if (mounted) Navigator.of(context).maybePop();
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

  @override
  Widget build(BuildContext context) {
    _maybeShowOver();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Домино для Дианы'),
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
          if (_controller.mode != DominoMode.local)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Сдаться',
              onPressed: _controller.isOver ? null : _confirmResign,
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
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Column(
                      children: [
                        _opponentPanel(),
                        const SizedBox(height: 6),
                        _turnStrip(),
                        const SizedBox(height: 6),
                        Expanded(child: _boardArea()),
                        const SizedBox(height: 6),
                        if (_controller.notice != null) _noticeBubble(),
                        if (_controller.notice != null)
                          const SizedBox(height: 6),
                        _handRow(),
                        const SizedBox(height: 8),
                        _actionBar(),
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

  Widget _opponentPanel() {
    final active = _controller.turn == _controller.opponentSeat &&
        !_controller.isOver;
    final name = _controller.nameFor(_controller.opponentSeat);
    final size = _controller.opponentHandSize;
    return Container(
      height: 54,
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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: peach,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_rounded, color: ink, size: 22),
          ),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                Text(
                  'Костей на руке: $size',
                  style: const TextStyle(
                    fontSize: 11,
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
            ),
        ],
      ),
    );
  }

  Widget _turnStrip() {
    return SizedBox(
      height: 28,
      child: Center(
        child: Text(
          _controller.turnLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: _controller.activeSide == DominoActive.me
                ? deepPurple
                : muted,
          ),
        ),
      ),
    );
  }

  Widget _boardArea() {
    if (!_controller.isReady) {
      return const Center(child: Text('Готовим стол…'));
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE7DBC2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC9B68C), width: 2),
        boxShadow: [
          BoxShadow(
            color: ink.withValues(alpha: .12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Верхняя строка: левый конец, базар, правый конец.
          SizedBox(
            height: 56,
            child: Row(
              children: [
                _EndChip(
                  value: _controller.leftEnd,
                  side: ChainSide.left,
                  highlighted: _controller.selectedTile != null &&
                      _controller.board
                          .sidesFor(_controller.selectedTile!)
                          .contains(ChainSide.left),
                  enabled: _controller.canInteract &&
                      _controller.selectedTile != null &&
                      _controller.board
                          .sidesFor(_controller.selectedTile!)
                          .contains(ChainSide.left),
                  onTap: () => _controller.selectSide(ChainSide.left),
                ),
                const Spacer(),
                _BazaarStack(
                  count: _controller.bazaarCount,
                  enabled: _controller.canDraw,
                  onTap: () => _controller.drawFromBazaar(),
                ),
                const Spacer(),
                _EndChip(
                  value: _controller.rightEnd,
                  side: ChainSide.right,
                  highlighted: _controller.selectedTile != null &&
                      _controller.board
                          .sidesFor(_controller.selectedTile!)
                          .contains(ChainSide.right),
                  enabled: _controller.canInteract &&
                      _controller.selectedTile != null &&
                      _controller.board
                          .sidesFor(_controller.selectedTile!)
                          .contains(ChainSide.right),
                  onTap: () => _controller.selectSide(ChainSide.right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _ChainView(placed: _controller.board.chain)),
        ],
      ),
    );
  }

  Widget _noticeBubble() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6C5F2)),
      ),
      child: Text(
        _controller.notice!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: deepPurple,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _handRow() {
    final hand = _controller.myHand;
    if (hand.isEmpty) {
      return const SizedBox(
        height: 96,
        child: Center(child: Text('Рука пуста')),
      );
    }
    final playable = _controller.playableTiles;
    final selected = _controller.selectedTile;
    final suggested = _controller.suggestedMove?.tile;
    final hintsOn = _controller.hintsEnabled;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: hand.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final tile = hand[index];
          final canTap = _controller.canInteract &&
              _controller.board.canPlace(tile);
          final isPlayable = hintsOn && playable.contains(tile);
          final isSelected = selected == tile;
          final isSuggested = suggested == tile;
          return _DominoTileView(
            tile: tile,
            width: 44,
            selected: isSelected,
            highlighted: isPlayable || isSuggested,
            dimmed: hintsOn && !playable.contains(tile) && !canTap,
            onTap: canTap || isSelected
                ? () => _controller.tapTile(tile)
                : null,
          );
        },
      ),
    );
  }

  Widget _actionBar() {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          if (_controller.canDraw)
            Expanded(
              child: _CtrlButton(
                icon: Icons.casino_rounded,
                label: 'Взять из базара',
                color: const Color(0xFFFFD9C7),
                onTap: () => _controller.drawFromBazaar(),
              ),
            )
          else if (_controller.canPass)
            Expanded(
              child: _CtrlButton(
                icon: Icons.skip_next_rounded,
                label: 'Пропустить',
                color: const Color(0xFFFFE5A3),
                onTap: () => _controller.pass(),
              ),
            )
          else
            const Expanded(child: SizedBox()),
          const SizedBox(width: 8),
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
              enabled: _controller.canShowHint,
              onTap: _controller.showHint,
            ),
          ),
        ],
      ),
    );
  }
}

enum _OverChoice { again, home }

/// Таблица очков на руках при «рыбе».
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
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F2FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        for (var i = 0; i < names.length && i < sums.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                winner == i ? Icons.emoji_events_rounded : null,
                color: const Color(0xFFE0B23A),
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  names[i],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              Text(
                '${sums[i]} оч.',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: deepPurple,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Костяшка домино: объёмная, с точками.
///
/// [width] — короткая сторона. В руке кость стоит вертикально (`width × 2·width`).
/// В цепочке — лежит вдоль неё: `2·width × width`, половинки смотрят влево и
/// вправо. Дубли в цепочке остаются вертикальными — они лежат поперёк.
class _DominoTileView extends StatelessWidget {
  const _DominoTileView({
    required this.tile,
    required this.width,
    this.selected = false,
    this.highlighted = false,
    this.dimmed = false,
    this.horizontal = false,
    this.onTap,
  });

  final DominoTile tile;
  final double width;
  final bool selected;
  final bool highlighted;
  final bool dimmed;
  final bool horizontal;
  final VoidCallback? onTap;

  double get _height => width * 2;

  @override
  Widget build(BuildContext context) {
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      height: _height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * .17),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFDF8), Color(0xFFF6EAD2), Color(0xFFEADBBE)],
          stops: [0, .55, 1],
        ),
        border: Border.all(
          color: selected
              ? deepPurple
              : (highlighted ? purple : const Color(0xFFD3BF98)),
          width: selected || highlighted ? 2.4 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted ? purple : ink).withValues(alpha: .22),
            offset: Offset(0, selected ? 2 : 4),
            blurRadius: selected ? 4 : 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? .30 : .20),
            offset: Offset(0, selected ? 7 : 6),
            blurRadius: selected ? 12 : 6,
          ),
          if (highlighted)
            BoxShadow(
              color: purple.withValues(alpha: .45),
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: width * .13,
        vertical: width * .12,
      ),
      child: Column(
        children: [
          Expanded(child: _PipHalf(value: tile.a, side: width)),
          Container(
            height: 1.6,
            margin: EdgeInsets.symmetric(vertical: width * .05),
            decoration: BoxDecoration(
              color: const Color(0xFFC4AE86),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(child: _PipHalf(value: tile.b, side: width)),
        ],
      ),
    );

    final rotated = horizontal ? RotatedBox(quarterTurns: 3, child: face) : face;

    return Semantics(
      label: 'Кость ${tile.label}',
      button: onTap != null,
      child: Opacity(
        opacity: dimmed ? .45 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: rotated,
        ),
      ),
    );
  }
}

/// Половинка кости с точками от 0 до 6.
class _PipHalf extends StatelessWidget {
  const _PipHalf({required this.value, required this.side});
  final int value;
  final double side;

  static const _patterns = <int, List<int>>{
    0: [],
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final cells = _patterns[value] ?? const <int>[];
    final dot = side * .19;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          children: [
            for (final cell in cells)
              Positioned(
                left: (cell % 3) * (width / 3) + (width / 3 - dot) / 2,
                top: (cell ~/ 3) * (height / 3) + (height / 3 - dot) / 2,
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-.3, -.4),
                      colors: [Color(0xFF6B5540), Color(0xFF3B2C1F)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: .5),
                        offset: const Offset(0, 1),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Обратная сторона кости — так лежит базар.
class _DominoTileBack extends StatelessWidget {
  const _DominoTileBack({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 2,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(width * .17),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9C6B41), Color(0xFF7A4E2C)],
      ),
      border: Border.all(color: const Color(0xFF5E3A1F), width: 1.4),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .25),
          offset: const Offset(0, 4),
          blurRadius: 4,
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: width * .46,
        height: width * .46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * .1),
          border: Border.all(
            color: const Color(0xFFFFE8B8).withValues(alpha: .55),
          ),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          size: width * .3,
          color: const Color(0xFFFFE8B8).withValues(alpha: .85),
        ),
      ),
    ),
  );
}

/// Цепочка костей на столе. Прокручивается к тому концу, куда только что
/// поставили кость.
class _ChainView extends StatefulWidget {
  const _ChainView({required this.placed});
  final List<PlacedTile> placed;

  @override
  State<_ChainView> createState() => _ChainViewState();
}

class _ChainViewState extends State<_ChainView> {
  final ScrollController _controller = ScrollController();
  int _lastLength = 0;

  @override
  void didUpdateWidget(covariant _ChainView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.placed.length != _lastLength) {
      _lastLength = widget.placed.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    _controller.animateTo(
      max,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.placed.isEmpty) {
      return const Center(
        child: Text(
          'Партия скоро начнётся…',
          style: TextStyle(
            color: Color(0xFF8A6E3D),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.placed.length; i++) ...[
              if (i > 0) const SizedBox(width: 1),
              _ChainTileView(placed: widget.placed[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Кость в цепочке: лежит вдоль цепочки, дубль — поперёк.
class _ChainTileView extends StatelessWidget {
  const _ChainTileView({required this.placed});
  final PlacedTile placed;

  @override
  Widget build(BuildContext context) {
    final tile = placed.tile;
    final across = placed.isAcross;
    final width = 26.0;
    if (across) {
      // Дубль: вертикальная кость в горизонтальной цепочке.
      return _DominoTileView(tile: tile, width: width);
    }
    return _DominoTileView(
      tile: tile,
      width: width,
      horizontal: true,
    );
  }
}

/// Стопка базара: лицевой стороной вниз, с числом оставшихся костей.
class _BazaarStack extends StatelessWidget {
  const _BazaarStack({
    required this.count,
    required this.enabled,
    required this.onTap,
  });
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Базар: $count костей',
      button: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .55,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 38,
                height: 60,
                child: Stack(
                  children: [
                    for (var i = 0; i < count.clamp(0, 3); i++)
                      Transform.translate(
                        offset: Offset(i * 2.0, i * 2.0),
                        child: const _DominoTileBack(width: 26),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Базар: $count',
                style: const TextStyle(
                  fontSize: 10.5,
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
}

/// Открытый конец цепочки: тапабельная кнопка со значением.
class _EndChip extends StatelessWidget {
  const _EndChip({
    required this.value,
    required this.side,
    required this.highlighted,
    required this.enabled,
    required this.onTap,
  });
  final int? value;
  final ChainSide side;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null ? '—' : '$value';
    return Opacity(
      opacity: enabled || highlighted ? 1 : .5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 58,
          height: 50,
          decoration: BoxDecoration(
            color: highlighted
                ? purple
                : (enabled ? const Color(0xFFFFF3D6) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? deepPurple
                  : const Color(0xFFE2C97A),
              width: highlighted ? 2.4 : 1.4,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: purple.withValues(alpha: .35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                side == ChainSide.left
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: highlighted ? Colors.white : const Color(0xFFB58A1F),
                size: 18,
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: highlighted ? Colors.white : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка панели действий.
class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.color = const Color(0xFFF1EAFB),
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color color;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: Material(
      color: color,
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
              Icon(icon, color: deepPurple, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
