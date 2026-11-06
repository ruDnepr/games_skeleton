import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'engine/rules.dart';
import 'loto_controller.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети, без
/// него — выбор режима (против компьютера или вдвоём на одном устройстве).
class LotoEntryPage extends StatelessWidget {
  const LotoEntryPage({
    super.key,
    required this.settings,
    this.network,
  });

  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return LotoSessionPage(settings: settings, network: network);
    }
    return LotoModePage(settings: settings);
  }
}

/// Выбор режима: против компьютера или вдвоём на одном устройстве, плюс режим
/// победы (по строке или по всей карточке).
class LotoModePage extends StatefulWidget {
  const LotoModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<LotoModePage> createState() => _LotoModePageState();
}

class _LotoModePageState extends State<LotoModePage> {
  bool _vsComputer = true;
  WinMode _winMode = WinMode.row;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Лото',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'НАЧИНАЕМ ПАРТИЮ',
          title: 'С кем сыграем?',
          subtitle: 'Выбери режим — против компьютера или вдвоём на одном '
              'устройстве. Не забудь решить, как выигрывать.',
        ),
        const SizedBox(height: 22),
        _ModeTile(
          title: 'Против компьютера',
          subtitle: 'Ты тянешь бочонки, компьютер закрывает числа сам',
          icon: Icons.smart_toy_rounded,
          color: const Color(0xFFEDE6FF),
          selected: _vsComputer,
          onTap: () => setState(() => _vsComputer = true),
        ),
        const SizedBox(height: 14),
        _ModeTile(
          title: 'Двое на одном устройстве',
          subtitle: 'Две карточки рядом, тянете по очереди',
          icon: Icons.people_rounded,
          color: const Color(0xFFDDF1DF),
          selected: !_vsComputer,
          onTap: () => setState(() => _vsComputer = false),
        ),
        const SizedBox(height: 22),
        const Text(
          'Как выигрывать',
          style: TextStyle(fontWeight: FontWeight.w900, color: ink),
        ),
        const SizedBox(height: 8),
        _WinModeRow(value: _winMode, onChanged: (m) => setState(() => _winMode = m)),
        const SizedBox(height: 26),
        BigButton(
          key: const Key('loto-start'),
          title: 'Начать партию',
          subtitle: _winMode == WinMode.row
              ? 'Победа по строке'
              : 'Победа по всей карточке',
          icon: Icons.play_arrow_rounded,
          color: purple,
          onPressed: () => _start(context),
        ),
      ],
    ),
  );

  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LotoSessionPage(
          settings: widget.settings,
          vsComputer: _vsComputer,
          winMode: _winMode,
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

class _WinModeRow extends StatelessWidget {
  const _WinModeRow({required this.value, required this.onChanged});
  final WinMode value;
  final ValueChanged<WinMode> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ChoiceChip(
          label: 'По строке',
          desc: 'Пять чисел подряд',
          selected: value == WinMode.row,
          onTap: () => onChanged(WinMode.row),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ChoiceChip(
          label: 'Вся карточка',
          desc: 'Все 15 чисел',
          selected: value == WinMode.fullCard,
          onTap: () => onChanged(WinMode.fullCard),
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

/// Экран партии: бочонок и объявление сверху, история под ним, карточки
/// игроков в середине, кнопка «Вытянуть бочонок» и панель действий снизу.
class LotoSessionPage extends StatefulWidget {
  const LotoSessionPage({
    super.key,
    required this.settings,
    this.vsComputer = true,
    this.winMode = WinMode.row,
    this.network,
  });

  final SettingsController settings;
  final bool vsComputer;
  final WinMode winMode;
  final NetworkSession? network;

  @override
  State<LotoSessionPage> createState() => _LotoSessionPageState();
}

class _LotoSessionPageState extends State<LotoSessionPage> {
  late final LotoController _controller;
  bool _winShown = false;

  @override
  void initState() {
    super.initState();
    final sounds = GameSounds(widget.settings);
    _controller = LotoController(
      settings: widget.settings,
      sounds: sounds,
      network: widget.network,
    );
    _controller.addListener(_onControllerChanged);
    if (widget.network != null) {
      _controller.startNetwork(mode: widget.winMode);
    } else if (widget.vsComputer) {
      _controller.startComputer(mode: widget.winMode);
    } else {
      _controller.startTwoPlayers(mode: widget.winMode);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _maybeShowWin();
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWinDialog());
    }
  }

  void _showWinDialog() {
    if (!mounted) return;
    final winner = _controller.winner;
    final noWinner = winner == null;
    final iWon = noWinner
        ? false
        : (_controller.mode == LotoMode.network
              ? winner.id == _controller.myPlayerId
              : (_controller.mode == LotoMode.twoPlayers
                    ? true
                    : winner.id == _controller.myPlayerId));
    final winnerName = winner?.name ?? '';
    final title = noWinner
        ? 'Партия окончена'
        : (iWon
              ? (_controller.mode == LotoMode.twoPlayers
                    ? 'Победили — $winnerName!'
                    : 'Победа!')
              : 'Победитель — $winnerName');
    final message = noWinner
        ? 'Связь прервалась или партия закончилась иначе. Попробуй сыграть '
              'ещё раз!'
        : (iWon
              ? (_controller.winMode == WinMode.row
                    ? 'Ты закрыл строку первым. Отличная игра!'
                    : 'Ты закрыл всю карточку. Это очень здорово!')
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
          key: const Key('loto-play-again'),
          value: true,
          primary: true,
        ),
        const DianaDialogButton<bool>(label: 'В меню', value: false),
      ],
    ).then((again) {
      if (!mounted) return;
      if (again == true && widget.network == null) {
        _winShown = false;
        _controller.playAgain();
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
    _maybeShowWin();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лото для Дианы'),
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
            icon: const Icon(Icons.home_rounded),
            tooltip: 'В меню',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Сдаться',
              onPressed: _controller.canResign ? _confirmResign : null,
            ),
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
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      children: [
                        _barrelStage(),
                        const SizedBox(height: 8),
                        _historyStrip(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _cardsArea(),
                        ),
                        const SizedBox(height: 8),
                        if (_controller.status != null)
                          _statusBubble(),
                        if (_controller.status != null)
                          const SizedBox(height: 8),
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

  /// Сцена ведущего: мешок, последний бочонок и объявление.
  Widget _barrelStage() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .06),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        _BagView(
          width: 58,
          waiting: _controller.lastBarrel == null &&
              _controller.canDraw &&
              _controller.game.players.isNotEmpty,
        ),
        const SizedBox(width: 8),
        _AnimatedBarrel(barrel: _controller.lastBarrel),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Eyebrow(
                _controller.mode == LotoMode.network
                    ? (_controller.isHost ? 'ВЕДУЩИЙ — ТЫ' : 'ВЕДУЩИЙ — ДРУГ')
                    : 'ВЕДУЩИЙ',
                color: deepPurple,
                background: const Color(0xFFEDE6FF),
                fontSize: 10,
              ),
              const SizedBox(height: 6),
              Text(
                _controller.lastBarrel == null
                    ? (_controller.game.players.isEmpty
                          ? 'Ждём раздачи карточек…'
                          : 'Доставай первый бочонок!')
                    : _controller.lastBarrel!.announcement,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'В мешке: ${_controller.barrelsLeft}',
                style: const TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Полоса истории: вытянутые бочонки в обратном порядке.
  Widget _historyStrip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF1E7DA)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, size: 15, color: purple),
            const SizedBox(width: 5),
            const Text(
              'История',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: purple,
                letterSpacing: .4,
              ),
            ),
            const Spacer(),
            Text(
              _controller.drawn.isEmpty
                  ? 'пока пусто'
                  : 'вытянуто ${_controller.drawn.length}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: _controller.drawn.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Здесь появятся все бочонки по порядку',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const Key('loto-history'),
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: _controller.drawn.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 5),
                  itemBuilder: (context, index) {
                    final number = _controller.drawn[
                        _controller.drawn.length - 1 - index];
                    return Center(
                      child: _BarrelCap(
                        number: number,
                        size: 34,
                        dimmed: index > 2,
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  /// Карточки игроков. В режиме двух игроков обе большие и тапаются; против
  /// компьютера своя — большая, соперника — поменьше; в сети своя большая,
  /// соперника — компактная.
  Widget _cardsArea() {
    if (_controller.game.players.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Ведущий раздаёт карточки…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    switch (_controller.mode) {
      case LotoMode.computer:
        final me = _controller.me;
        final rival = _controller.others.firstOrNull;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (me != null)
              _PlayerCard(
                player: me,
                winMode: _controller.winMode,
                highlight: _highlightFor(me.id),
                chipColor: chipGreen,
                compact: false,
                onTap: _controller.canInteract
                    ? (n) => _controller.closeNumber(n, playerId: me.id)
                    : null,
              ),
            if (rival != null) ...[
              const SizedBox(height: 10),
              _PlayerCard(
                player: rival,
                winMode: _controller.winMode,
                highlight: const <int>{},
                chipColor: chipBlue,
                compact: true,
                onTap: null,
              ),
            ],
          ],
        );
      case LotoMode.twoPlayers:
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final player in _controller.game.players) ...[
              if (player.id != _controller.game.players.first.id)
                const SizedBox(height: 10),
              _PlayerCard(
                player: player,
                winMode: _controller.winMode,
                highlight: _highlightFor(player.id),
                chipColor: _controller.game.players.indexOf(player) == 0
                    ? chipGreen
                    : chipBlue,
                compact: false,
                onTap: _controller.canInteract
                    ? (n) => _controller.closeNumber(n, playerId: player.id)
                    : null,
              ),
            ],
          ],
        );
      case LotoMode.network:
        final me = _controller.me;
        final rival = _controller.others.firstOrNull;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (me != null)
              _PlayerCard(
                player: me,
                winMode: _controller.winMode,
                highlight: _highlightFor(me.id),
                chipColor: chipGreen,
                compact: false,
                onTap: _controller.canInteract
                    ? (n) => _controller.closeNumber(n, playerId: me.id)
                    : null,
              ),
            if (rival != null) ...[
              const SizedBox(height: 10),
              _PlayerCard(
                player: rival,
                winMode: _controller.winMode,
                highlight: const <int>{},
                chipColor: chipBlue,
                compact: true,
                onTap: null,
              ),
            ],
          ],
        );
    }
  }

  /// Подсветка для карточки игрока: либо кнопка-подсказка (только числа,
  /// которые есть у этого игрока), либо (если включено `hints`) клетка, на
  /// которую пришёл последний бочонок.
  Set<int> _highlightFor(String playerId) {
    final player = _controller.game.playerById(playerId);
    if (player == null) return const <int>{};
    final hint = <int>{
      for (final n in _controller.hintHighlight)
        if (player.card.contains(n)) n,
    };
    if (_controller.hintsEnabled) {
      final barrel = _controller.lastBarrel;
      if (barrel != null &&
          LotoRules.canClose(
            card: player.card,
            closed: player.closed,
            drawn: _controller.game.drawn,
            number: barrel.number,
          )) {
        hint.add(barrel.number);
      }
    }
    return hint;
  }

  Widget _statusBubble() => Align(
    alignment: Alignment.center,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFC6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2A21B), width: 1.5),
      ),
      child: Text(
        _controller.status!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Color(0xFF8A6A1F),
        ),
      ),
    ),
  );

  Widget _bottomBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    child: Column(
      children: [
        if (_controller.canDraw)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                key: const Key('loto-draw'),
                onPressed: _controller.drawBarrel,
                icon: const Icon(Icons.casino_rounded),
                label: const Text('Вытянуть бочонок'),
              ),
            ),
          ),
        Row(
          children: [
            if (_controller.hintButtonEnabled)
              Expanded(
                child: _CtrlButton(
                  icon: Icons.lightbulb_rounded,
                  label: 'Подсказка',
                  enabled: _controller.canInteract,
                  onTap: () => _controller.showHint(),
                ),
              ),
            if (_controller.hintButtonEnabled) const SizedBox(width: 8),
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
                icon: Icons.flag_rounded,
                label: 'Сдаться',
                enabled: _controller.canResign,
                onTap: _confirmResign,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ---- Игровая карточка -----------------------------------------------------

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    required this.winMode,
    required this.highlight,
    required this.chipColor,
    required this.compact,
    required this.onTap,
  });

  final LotoPlayer player;
  final WinMode winMode;
  final Set<int> highlight;
  final Color chipColor;
  final bool compact;
  final void Function(int number)? onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: compact ? const Color(0xFFF1E7DA) : purple.withValues(alpha: .35),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Avatar(player: player),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (player.hasWon(winMode))
              const _Badge(
                label: 'победа!',
                background: Color(0xFFDFF3E5),
                color: Color(0xFF2F7D52),
              )
            else
              _Badge(
                label:
                    '${player.closedCount}/${winMode == WinMode.row ? 5 : 15}',
                background: const Color(0xFFEFE8FB),
                color: purple,
              ),
          ],
        ),
        const SizedBox(height: 7),
        LotoCardView(
          card: player.card,
          closed: player.closed,
          highlight: highlight,
          chipColor: chipColor,
          compact: compact,
          onTap: onTap,
        ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.player});
  final LotoPlayer player;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      color: player.isComputer
          ? const Color(0xFFE6DEF9)
          : const Color(0xFFFFE5A3),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(
      player.isComputer
          ? Icons.smart_toy_rounded
          : (player.isHost
                ? Icons.star_rounded
                : Icons.person_rounded),
      size: 16,
      color: ink.withValues(alpha: .7),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.color,
  });
  final String label;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    ),
  );
}

// ---- Карточка 3×9 ---------------------------------------------------------

/// Карточка лото: три строки по девять клеток, пять чисел в строке.
class LotoCardView extends StatelessWidget {
  const LotoCardView({
    super.key,
    required this.card,
    required this.closed,
    this.highlight = const <int>{},
    this.chipColor = chipGreen,
    this.compact = false,
    this.onTap,
  });

  final LotoCard card;
  final Set<int> closed;
  final Set<int> highlight;
  final Color chipColor;
  final bool compact;
  final void Function(int number)? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cell = constraints.maxWidth / LotoCard.columnCount;
      final cellHeight = cell * (compact ? .86 : .98);
      return Container(
        padding: EdgeInsets.all(compact ? 4 : 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 12 : 20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFDF7), Color(0xFFFFF1DC)],
          ),
          border: Border.all(
            color: woodMid.withValues(alpha: .55),
            width: compact ? 1 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: woodDark.withValues(alpha: .30),
              offset: Offset(0, compact ? 2 : 5),
              blurRadius: 0,
            ),
            BoxShadow(
              color: ink.withValues(alpha: .10),
              offset: Offset(0, compact ? 3 : 8),
              blurRadius: compact ? 4 : 12,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < LotoCard.rowCount; row++)
              SizedBox(
                height: cellHeight,
                child: Row(
                  children: [
                    for (var column = 0;
                        column < LotoCard.columnCount;
                        column++)
                      Expanded(
                        child: _Cell(
                          number: card.rows[row][column],
                          closed: closed,
                          highlight: highlight,
                          rowClosed: LotoRules.isRowClosed(
                            card: card,
                            closed: closed,
                            row: row,
                          ),
                          onTap: onTap,
                          compact: compact,
                          chipColor: chipColor,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.number,
    required this.closed,
    required this.highlight,
    required this.rowClosed,
    required this.onTap,
    required this.compact,
    required this.chipColor,
  });

  final int? number;
  final Set<int> closed;
  final Set<int> highlight;
  final bool rowClosed;
  final void Function(int number)? onTap;
  final bool compact;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    final value = number;
    if (value == null) {
      return const SizedBox.expand();
    }
    final isClosed = closed.contains(value);
    final isHinted = !isClosed && highlight.contains(value);
    final tappable = onTap != null && !isClosed;
    final radius = compact ? 5.0 : 9.0;
    return Semantics(
      button: tappable,
      label: isClosed ? 'Число $value, закрыто' : 'Число $value',
      child: GestureDetector(
        key: Key('loto-cell-$value'),
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => onTap!(value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          margin: EdgeInsets.all(compact ? .7 : 1.6),
          decoration: BoxDecoration(
            color: isClosed
                ? chipColor.withValues(alpha: .16)
                : (isHinted
                      ? yellow.withValues(alpha: .55)
                      : (rowClosed
                            ? chipGreen.withValues(alpha: .14)
                            : Colors.white.withValues(alpha: .72))),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isHinted
                  ? const Color(0xFFE2A21B)
                  : const Color(0xFFEADFCB),
              width: isHinted ? 2.2 : 1,
            ),
            boxShadow: isHinted
                ? [
                    BoxShadow(
                      color: yellow.withValues(alpha: .55),
                      blurRadius: compact ? 4 : 9,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isClosed
                ? _Chip(compact: compact, color: chipColor)
                : Text(
                    '$value',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 8.5 : 19,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.compact, required this.color});
  final bool compact;
  final Color color;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: .82,
    heightFactor: .82,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .35)!,
            color,
            Color.lerp(color, Colors.black, .18)!,
          ],
        ),
        border: Border.all(
          color: Color.lerp(color, Colors.black, .35)!,
          width: compact ? .8 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .45),
            offset: Offset(0, compact ? 1 : 2),
            blurRadius: compact ? 1 : 3,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.check_rounded,
          size: compact ? 8 : 15,
          color: Colors.white,
        ),
      ),
    ),
  );
}

// ---- Бочонок и мешок (CustomPaint) ----------------------------------------

/// Бочонок лото с деревянным корпусом и круглым торцом, на котором написано
/// число. Бочонок «выезжает» из мешка на каждом новом числе.
class _AnimatedBarrel extends StatefulWidget {
  const _AnimatedBarrel({required this.barrel});
  final Barrel? barrel;

  @override
  State<_AnimatedBarrel> createState() => _AnimatedBarrelState();
}

class _AnimatedBarrelState extends State<_AnimatedBarrel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );
  int? _shown;

  @override
  void didUpdateWidget(covariant _AnimatedBarrel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barrel?.number != widget.barrel?.number) {
      _shown = widget.barrel?.number;
      if (widget.barrel != null) _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barrel = widget.barrel;
    final width = 110.0;
    return AnimatedBuilder(
      animation: _draw,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_draw.value.clamp(0.0, 1.0));
        final fade = _draw.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(-22 * (1 - t), 0),
            child: Transform.rotate(
              angle: (1 - t) * -.45,
              child: Transform.scale(scale: .72 + .28 * t, child: child),
            ),
          ),
        );
      },
      child: barrel == null
          ? SizedBox(
              width: width,
              height: width * .72,
              child: Center(
                child: _BarrelCap(
                  number: _shown ?? 7,
                  size: width * .42,
                  dimmed: true,
                ),
              ),
            )
          : _BarrelView(
              number: barrel.number,
              width: width,
              glow: _draw.value < 1,
            ),
    );
  }
}

class _BarrelView extends StatelessWidget {
  const _BarrelView({required this.number, required this.width, this.glow = false});
  final int number;
  final double width;
  final bool glow;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Бочонок $number',
    child: SizedBox(
      width: width,
      height: width * .72,
      child: CustomPaint(
        painter: _BarrelPainter(number: number, glow: glow),
      ),
    ),
  );
}

class _BarrelPainter extends CustomPainter {
  _BarrelPainter({required this.number, required this.glow});
  final int number;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height;
    final capRadius = height * .34;
    final capCenter = Offset(
      size.width - capRadius - height * .03,
      height * .47,
    );
    final body = Rect.fromLTRB(
      size.width * .03,
      capCenter.dy - capRadius * .97,
      capCenter.dx,
      capCenter.dy + capRadius * .97,
    );

    // Тень под бочонком: без неё он «висит» в воздухе.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .5, height * .93),
        width: size.width * .78,
        height: height * .13,
      ),
      Paint()
        ..color = ink.withValues(alpha: .15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );

    // Корпус: деревянный цилиндр со скруглениями.
    final bodyShape = RRect.fromRectAndRadius(
      body,
      Radius.circular(capRadius * .5),
    );
    canvas.drawRRect(
      bodyShape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [woodLight, woodMid, woodDark],
          stops: [.0, .52, 1],
        ).createShader(body),
    );

    canvas.save();
    canvas.clipRRect(bodyShape);
    _paintGrain(canvas, body, seed: number);
    _paintHoops(canvas, body);
    canvas.restore();

    // Дальний торец — тёмный полумесяц слева: видно, что бочонок круглый.
    canvas.drawOval(
      Rect.fromLTRB(
        body.left - capRadius * .10,
        body.top + capRadius * .02,
        body.left + capRadius * .34,
        body.bottom - capRadius * .02,
      ),
      Paint()..color = woodEdge.withValues(alpha: .85),
    );

    if (glow) {
      canvas.drawCircle(
        capCenter,
        capRadius * 1.15,
        Paint()
          ..color = yellow.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Ближний торец: круг с числом.
    canvas.drawCircle(
      capCenter,
      capRadius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.45),
          colors: [Color(0xFFFFE9C2), woodLight, woodMid],
          stops: [.0, .5, 1],
        ).createShader(
          Rect.fromCircle(center: capCenter, radius: capRadius),
        ),
    );
    canvas.drawCircle(
      capCenter,
      capRadius * .95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = capRadius * .13
        ..color = woodDark,
    );
    canvas.drawCircle(
      capCenter,
      capRadius * .84,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = capRadius * .045
        ..color = woodEdge.withValues(alpha: .4),
    );
    _paintNumber(canvas, capCenter, capRadius);
  }

  void _paintNumber(Canvas canvas, Offset center, double radius) {
    final text = '$number';
    var fontSize = radius * (text.length == 1 ? 1.02 : .86);
    TextPainter layout(double size) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: ink,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var painter = layout(fontSize);
    while (painter.width > radius * 1.3 && fontSize > 4) {
      fontSize *= .93;
      painter = layout(fontSize);
    }
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintGrain(Canvas canvas, Rect rect, {required int seed}) {
    final random = math.Random(seed * 7 + 3);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.height * .03
      ..color = woodDark.withValues(alpha: .20);
    for (var i = 0; i < 5; i++) {
      final y = rect.top + rect.height * (.19 + .16 * i);
      final path = Path()..moveTo(rect.left + rect.width * .10, y);
      path.quadraticBezierTo(
        rect.center.dx + (random.nextDouble() - .5) * rect.width * .3,
        y + (random.nextDouble() - .5) * rect.height * .10,
        rect.right - rect.width * .06,
        y + (random.nextDouble() - .5) * rect.height * .08,
      );
      canvas.drawPath(path, paint);
    }
    canvas.drawOval(
      Rect.fromLTRB(
        rect.left + rect.width * .12,
        rect.top + rect.height * .07,
        rect.right - rect.width * .10,
        rect.top + rect.height * .27,
      ),
      Paint()..color = Colors.white.withValues(alpha: .13),
    );
    canvas.drawOval(
      Rect.fromLTRB(
        rect.left + rect.width * .12,
        rect.bottom - rect.height * .26,
        rect.right - rect.width * .06,
        rect.bottom - rect.height * .02,
      ),
      Paint()..color = woodDark.withValues(alpha: .18),
    );
  }

  void _paintHoops(Canvas canvas, Rect rect) {
    for (final position in const [.13, .80]) {
      final left = rect.left + rect.width * position;
      final hoop = Rect.fromLTRB(
        left,
        rect.top + rect.height * .04,
        left + rect.width * .05,
        rect.bottom - rect.height * .04,
      );
      canvas.drawRect(
        hoop,
        Paint()..color = woodEdge.withValues(alpha: .20),
      );
      canvas.drawLine(
        Offset(hoop.left, hoop.top),
        Offset(hoop.left, hoop.bottom),
        Paint()
          ..color = Colors.white.withValues(alpha: .16)
          ..strokeWidth = rect.width * .008,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarrelPainter oldDelegate) =>
      oldDelegate.number != number || oldDelegate.glow != glow;
}

/// Торец бочонка без корпуса — маленький кружок с числом. Так выглядят
/// вытянутые бочонки в истории и бочонки в мешке: у них видно только торец.
class _BarrelCap extends StatelessWidget {
  const _BarrelCap({
    required this.number,
    required this.size,
    this.dimmed = false,
  });
  final int number;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Бочонок $number',
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CapPainter(number: number, dimmed: dimmed),
      ),
    ),
  );
}

class _CapPainter extends CustomPainter {
  _CapPainter({required this.number, required this.dimmed});
  final int number;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final opacity = dimmed ? .55 : 1.0;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.25, -.3),
          colors: [
            const Color(0xFFFFE7BE).withValues(alpha: opacity),
            woodLight.withValues(alpha: opacity),
            woodMid.withValues(alpha: opacity),
          ],
          stops: const [.0, .55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius - radius * .07,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .16
        ..color = woodDark.withValues(alpha: opacity),
    );
    final two = number >= 10;
    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: radius * (two ? .95 : 1.15),
          fontWeight: FontWeight.w900,
          color: ink.withValues(alpha: opacity),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CapPainter oldDelegate) =>
      oldDelegate.number != number || oldDelegate.dimmed != dimmed;
}

/// Мешок с бочонками.
class _BagView extends StatelessWidget {
  const _BagView({required this.width, this.waiting = false});
  final double width;
  final bool waiting;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Мешок с бочонками',
    child: SizedBox(
      width: width,
      height: width * .96,
      child: CustomPaint(painter: _BagPainter(waiting: waiting)),
    ),
  );
}

class _BagPainter extends CustomPainter {
  _BagPainter({required this.waiting});
  final bool waiting;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTRB(
      size.width * .12,
      size.height * .34,
      size.width * .88,
      size.height * .95,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .96),
        width: size.width * .72,
        height: size.height * .1,
      ),
      Paint()
        ..color = ink.withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final path = Path()
      ..moveTo(size.width * .3, size.height * .36)
      ..quadraticBezierTo(
        size.width * .04,
        size.height * .66,
        size.width * .2,
        size.height * .93,
      )
      ..lineTo(size.width * .8, size.height * .93)
      ..quadraticBezierTo(
        size.width * .96,
        size.height * .66,
        size.width * .7,
        size.height * .36,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA88BE0), deepPurple, Color(0xFF4A3585)],
        ).createShader(body),
    );
    for (final (index, dx) in [.34, .5, .66].indexed) {
      canvas.drawCircle(
        Offset(size.width * dx, size.height * (.33 - index % 2 * .03)),
        size.width * .11,
        Paint()..color = woodLight,
      );
      canvas.drawCircle(
        Offset(size.width * dx, size.height * (.33 - index % 2 * .03)),
        size.width * .11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .035
          ..color = woodDark,
      );
    }
    canvas.drawLine(
      Offset(size.width * .28, size.height * .36),
      Offset(size.width * .72, size.height * .36),
      Paint()
        ..color = const Color(0xFF6B4CA8)
        ..strokeWidth = size.height * .06
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .36),
      size.height * .05,
      Paint()..color = yellow,
    );
    if (waiting) {
      canvas.drawCircle(
        Offset(size.width * .5, size.height * .52),
        size.width * .26,
        Paint()..color = Colors.white.withValues(alpha: .06),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BagPainter oldDelegate) =>
      oldDelegate.waiting != waiting;
}

// ---- Кнопки панели управления ---------------------------------------------

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

// ---- Палитра лото (взята из оригинала; общие цвета — в theme.dart) --------

const woodLight = Color(0xFFF4CE93);
const woodMid = Color(0xFFD79A55);
const woodDark = Color(0xFF9A6330);
const woodEdge = Color(0xFF7A4A22);

const chipGreen = Color(0xFF4CAF7D);
const chipBlue = Color(0xFF4B8FD8);
