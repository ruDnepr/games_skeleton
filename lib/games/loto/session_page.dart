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
/// него — выбор режима (против компьютера, вдвоём или с ведущим-человеком).
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

/// Один экран вместо трёх шагов: с кем играем и как побеждаем. Повторяет
/// оригинальный `PlaySetupPage`: три режима (компьютер-ведущий, два игрока,
/// ведущий-человек) и выбор режима победы в одном списке.
class LotoModePage extends StatefulWidget {
  const LotoModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<LotoModePage> createState() => _LotoModePageState();
}

class _LotoModePageState extends State<LotoModePage> {
  LotoMode _mode = LotoMode.computerHost;
  WinMode _winMode = WinMode.row;

  void _start() {
    final setup = GameSetup(
      mode: _mode,
      winMode: _winMode,
      playerName: widget.settings.nickname,
      opponentName: _mode.hasComputerRival ? 'Компьютер' : 'Друг',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LotoSessionPage(settings: widget.settings, setup: setup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Новая партия',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
      children: [
        const Intro(
          eyebrow: 'ШАГ 1',
          title: 'С кем играем?',
          subtitle: 'Выбери, кто будет ведущим и сколько будет карточек.',
        ),
        const SizedBox(height: 20),
        for (final mode in const [
          LotoMode.computerHost,
          LotoMode.twoPlayers,
          LotoMode.humanHost,
        ])
          LotoSelectTile(
            key: Key('mode-${mode.name}'),
            title: mode.title,
            subtitle: mode.subtitle,
            icon: switch (mode) {
              LotoMode.computerHost => Icons.smart_toy_rounded,
              LotoMode.twoPlayers => Icons.people_alt_rounded,
              LotoMode.humanHost => Icons.record_voice_over_rounded,
              LotoMode.network => Icons.wifi_rounded,
            },
            color: switch (mode) {
              LotoMode.computerHost => const Color(0xFFE8E0FA),
              LotoMode.twoPlayers => const Color(0xFFFFE5A3),
              LotoMode.humanHost => const Color(0xFFDDF1DF),
              LotoMode.network => const Color(0xFFEDE6FF),
            },
            selected: _mode == mode,
            onTap: () => setState(() => _mode = mode),
          ),
        const SizedBox(height: 18),
        const Intro(
          eyebrow: 'ШАГ 2',
          title: 'Как побеждаем?',
          subtitle: 'Строка — быстрая победа. Вся карточка — для смелых.',
        ),
        const SizedBox(height: 20),
        for (final mode in WinMode.values)
          LotoSelectTile(
            key: Key('win-${mode.name}'),
            title: mode.label,
            subtitle: mode.description,
            icon: mode == WinMode.row
                ? Icons.horizontal_rule_rounded
                : Icons.grid_view_rounded,
            color: mode == WinMode.row
                ? const Color(0xFFFFE5A3)
                : const Color(0xFFE6DEF9),
            selected: _winMode == mode,
            onTap: () => setState(() => _winMode = mode),
            tag: mode == WinMode.row ? '5 чисел' : '15 чисел',
          ),
        const SizedBox(height: 22),
        BigButton(
          key: const Key('start-game'),
          title: 'Начать игру',
          subtitle: 'Раздаём карточки и мешаем мешок',
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
        const SizedBox(height: 18),
        const _SetupHint(),
      ],
    ),
  );
}

/// Карточка выбора с подсветкой: как `ChoiceTile` из каркаса, но с индикатором
/// «выбрано». Используется на экране старта для режима игры и режима победы,
/// а также на экране выбора режима победы перед сетевой игрой.
class LotoSelectTile extends StatelessWidget {
  const LotoSelectTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.tag,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? tag;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: selected ? purple : const Color(0xFFF2EAE3),
        width: selected ? 2 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .05),
          blurRadius: 18,
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
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: ink.withValues(alpha: .8), size: 29),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
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
              if (tag != null) ...[
                const SizedBox(width: 7),
                Text(
                  tag!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: purple,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(width: 6),
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

class _SetupHint extends StatelessWidget {
  const _SetupHint();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF0E9FC),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const BarrelCap(number: 11, size: 38),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Ведущий объявляет число вместе с прибауткой: «11 — барабанные '
            'палочки». Так числа запоминаются сами.',
            style: TextStyle(
              color: ink,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Экран партии: бочонок и объявление сверху, история под ним, карточки
/// игроков в середине, кнопка «Вытянуть бочонок» и панель действий снизу.
class LotoSessionPage extends StatefulWidget {
  const LotoSessionPage({
    super.key,
    required this.settings,
    this.setup,
    this.network,
    this.controller,
  });

  final SettingsController settings;
  final GameSetup? setup;
  final NetworkSession? network;

  /// Контроллер партии. Если не передан, страница создаст свой; в тестах
  /// удобно передать готовый, чтобы проверять состояние напрямую.
  final LotoController? controller;

  @override
  State<LotoSessionPage> createState() => _LotoSessionPageState();
}

class _LotoSessionPageState extends State<LotoSessionPage> {
  late final LotoController _controller;
  bool _ownedController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownedController = false;
    } else {
      final sounds = GameSounds(widget.settings);
      _controller = LotoController(
        settings: widget.settings,
        sounds: sounds,
        network: widget.network,
      );
      _ownedController = true;
      if (widget.network != null) {
        final winMode = WinMode.fromName(
          widget.network!.lobby.options['winMode'] ?? WinMode.row.name,
        );
        _controller.startNetwork(mode: winMode);
      } else if (widget.setup != null) {
        _controller.start(widget.setup!);
      }
    }
  }

  @override
  void dispose() {
    // Таймеры отменяем всегда: даже если контроллер внешний, страница
    // закрывается и таймеры не должны оставаться «висеть».
    _controller.stop();
    if (_ownedController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _exit() async {
    if (widget.network != null) {
      final leave = await showDianaDialog<bool>(
        context: context,
        title: 'Выйти из партии?',
        content: const Text(
          'Игра закончится для всех. Собраться снова можно через «Сетевую игру».',
          textAlign: TextAlign.center,
          style: dialogTextStyle,
        ),
        actions: const [
          DianaDialogButton<bool>(
            label: 'Остаться',
            value: false,
            primary: true,
          ),
          DianaDialogButton<bool>(label: 'Выйти', value: true),
        ],
      );
      if (leave != true || !mounted) return;
      await widget.network!.service.close();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    Navigator.of(context).maybePop();
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
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return Stack(
                    children: [
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                            child: GameHeader(
                              title: _controller.mode.title,
                              subtitle: _controller.winMode.label,
                              onExit: _exit,
                              soundOn: widget.settings.sound,
                              onToggleSound: () => widget.settings
                                  .setSound(!widget.settings.sound),
                              badge: widget.network?.lobby.code == null
                                  ? null
                                  : Eyebrow(
                                      widget.network!.lobby.code,
                                      fontSize: 9,
                                      background: const Color(0xFFEDE6FF),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: GameBody(
                              game: _controller.game,
                              cards: _myCards(),
                              others: _otherCards(),
                              othersAfterActions:
                                  _controller.mode == LotoMode.computerHost,
                              showOthersTitle: false,
                              notice: _controller.notice,
                              noticeTone: _controller.noticeWarning
                                  ? NoticeTone.warning
                                  : NoticeTone.info,
                              actions: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_controller.canDrawManually)
                                    ActionPill(
                                      key: const Key('draw-barrel'),
                                      label: 'Вытянуть бочонок',
                                      icon: Icons.casino_rounded,
                                      onPressed: _controller.drawBarrel,
                                    ),
                                  if (_controller.hintButtonEnabled)
                                    ActionPill(
                                      key: const Key('hint-button'),
                                      label: 'Подсказка',
                                      icon: Icons.lightbulb_outline_rounded,
                                      color: deepPurple,
                                      filled: false,
                                      onPressed: _controller.canInteract
                                          ? _controller.toggleHint
                                          : null,
                                    ),
                                  if (_controller.canUndo)
                                    ActionPill(
                                      key: const Key('undo-button'),
                                      label: 'Отменить ход',
                                      icon: Icons.undo_rounded,
                                      color: deepPurple,
                                      filled: false,
                                      onPressed: _controller.undo,
                                    ),
                                  if (_controller.canResign)
                                    ActionPill(
                                      key: const Key('resign-button'),
                                      label: 'Сдаться',
                                      icon: Icons.flag_outlined,
                                      color: deepPurple,
                                      filled: false,
                                      onPressed: _confirmResign,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_controller.isOver && _controller.winner != null)
                        CelebrationOverlay(
                          title: _controller.iWon
                              ? 'Победа!'
                              : 'Победитель — ${_controller.winner!.name}',
                          subtitle: _resultText(),
                          stars: _controller.iWon ? 3 : 2,
                          onAgain: () {
                            if (widget.network != null &&
                                !_controller.isHost) {
                              Navigator.of(context).maybePop();
                            } else {
                              _controller.playAgain();
                            }
                          },
                          onExit: _exit,
                          againLabel: widget.network != null
                              ? (_controller.isHost
                                    ? 'Ещё партия'
                                    : 'К лобби')
                              : 'Играть снова',
                        ),
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

  String _resultText() {
    final winner = _controller.winner;
    if (winner == null) return '';
    if (_controller.iWon) {
      return _controller.winMode == WinMode.row
          ? 'Ты закрыла строку первой. Отличная игра!'
          : 'Ты закрыла всю карточку. Это очень здорово!';
    }
    if (winner.isComputer) {
      return 'Компьютер закрыл первым, но ты почти победила. Сыграем ещё?';
    }
    return '${winner.name} закрыл(а) первым. Ты почти победила — сыграем ещё?';
  }

  /// Большие карточки этого устройства.
  List<Widget> _myCards() {
    final me = _controller.me;
    if (me == null) {
      if (_controller.mode == LotoMode.network && _controller.isHost) {
        return const [_HostNote()];
      }
      return const [_WaitingDeal()];
    }
    final cards = <Widget>[
      _BigCard(
        player: me,
        winMode: _controller.winMode,
        highlight: _highlightFor(me.id),
        chipColor: chipGreen,
        onTap: _controller.canInteract
            ? (number) =>
                _controller.close(playerId: me.id, number: number)
            : null,
      ),
    ];
    if (_controller.mode == LotoMode.twoPlayers) {
      for (final other in _controller.others) {
        cards.add(_BigCard(
          player: other,
          winMode: _controller.winMode,
          highlight: _highlightFor(other.id),
          chipColor: chipBlue,
          onTap: _controller.canInteract
              ? (number) =>
                  _controller.close(playerId: other.id, number: number)
              : null,
        ));
      }
    }
    return cards;
  }

  /// Панели остальных игроков.
  List<Widget> _otherCards() {
    if (_controller.mode == LotoMode.computerHost) {
      return [
        for (final other in _controller.others)
          _BigCard(
            player: other,
            winMode: _controller.winMode,
            highlight: _highlightFor(other.id),
            chipColor: chipBlue,
            onTap: null,
            compact: true,
          ),
      ];
    }
    if (_controller.mode == LotoMode.network) {
      return [
        for (final other in _controller.others)
          PlayerPanel(
            player: other,
            winMode: _controller.winMode,
            highlight: _highlightFor(other.id),
          ),
      ];
    }
    return const [];
  }

  /// Подсветка для карточки игрока: кнопка-подсказка (только числа этого
  /// игрока) и, если включено `hints`, клетка последнего бочонка.
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
}

/// «Ведущий раздаёт карточки…» — заглушка, пока хост в сети не пришёл снимок.
class _WaitingDeal extends StatelessWidget {
  const _WaitingDeal();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(
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

/// «Ты ведущий: доставай бочонки…» — подсказка хосту в сети без своей карточки.
class _HostNote extends StatelessWidget {
  const _HostNote();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: NoticeBar(
      text:
          'Ты ведущий: доставай бочонки и объявляй числа. '
          'Карточки игроков — ниже.',
    ),
  );
}

// ---- Верхняя строка экрана партии -----------------------------------------

class GameHeader extends StatelessWidget {
  const GameHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onExit,
    required this.soundOn,
    required this.onToggleSound,
    this.badge,
  });

  final String title;
  final String subtitle;
  final VoidCallback onExit;
  final bool soundOn;
  final VoidCallback onToggleSound;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _RoundButton(
        key: const Key('game-exit'),
        icon: Icons.arrow_back_rounded,
        label: 'В меню',
        onTap: onExit,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ],
        ),
      ),
      if (badge != null) ...[badge!, const SizedBox(width: 6)],
      _RoundButton(
        key: const Key('sound-toggle'),
        icon: soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        label: soundOn ? 'Выключить звук' : 'Включить звук',
        onTap: onToggleSound,
      ),
    ],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Colors.white.withValues(alpha: .85),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(child: Icon(icon, size: 21, color: ink)),
        ),
      ),
    ),
  );
}

// ---- Подсказка под карточкой ----------------------------------------------

class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.text,
    this.tone = NoticeTone.info,
  });

  final String text;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, color, icon) = switch (tone) {
      NoticeTone.info => (
        const Color(0xFFF0E9FC),
        purple,
        Icons.lightbulb_rounded,
      ),
      NoticeTone.warning => (
        const Color(0xFFFFF0D2),
        const Color(0xFF8A6A1F),
        Icons.info_outline_rounded,
      ),
      NoticeTone.good => (
        const Color(0xFFDFF3E5),
        const Color(0xFF2F7D52),
        Icons.check_circle_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, good }

// ---- Кнопка действия ------------------------------------------------------

class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = purple,
    this.foreground = Colors.white,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  final bool filled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .45 : 1,
    child: Material(
      color: filled ? color : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: filled
                ? null
                : Border.all(color: const Color(0xFFE3D8F5), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: filled ? foreground : color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: filled ? foreground : ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---- Раскладка экрана партии ----------------------------------------------

class GameBody extends StatelessWidget {
  const GameBody({
    super.key,
    required this.game,
    required this.cards,
    required this.others,
    required this.actions,
    this.banner,
    this.notice,
    this.noticeTone = NoticeTone.info,
    this.showOthersTitle = true,
    this.othersAfterActions = false,
  });

  final LotoGame game;
  final List<Widget> cards;
  final List<Widget> others;
  final Widget actions;
  final Widget? banner;
  final String? notice;
  final NoticeTone noticeTone;
  final bool showOthersTitle;
  final bool othersAfterActions;

  @override
  Widget build(BuildContext context) {
    final othersBlock = <Widget>[
      if (others.isNotEmpty && showOthersTitle)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            others.length == 1 ? 'Другой игрок' : 'Другие игроки',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: purple,
              letterSpacing: .8,
            ),
          ),
        ),
      if (others.isNotEmpty) ...others,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
      children: [
        if (banner != null) ...[banner!, const SizedBox(height: 10)],
        BarrelStage(
          barrel: game.lastBarrel,
          barrelsLeft: game.barrelsLeft,
          waitingFor: [
            for (final player in game.pendingClosers)
              if (!player.isComputer) player.name,
          ],
        ),
        const SizedBox(height: 10),
        HistoryPanel(drawn: game.drawn),
        const SizedBox(height: 12),
        ...cards,
        if (notice != null) ...[
          const SizedBox(height: 10),
          NoticeBar(text: notice!, tone: noticeTone),
        ],
        const SizedBox(height: 14),
        actions,
        if (!othersAfterActions && othersBlock.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...othersBlock,
        ],
        if (othersAfterActions && othersBlock.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...othersBlock,
        ],
      ],
    );
  }
}

// ---- Заголовок над карточкой ----------------------------------------------

class CardTitle extends StatelessWidget {
  const CardTitle({
    super.key,
    required this.name,
    required this.closed,
    required this.total,
    this.color = purple,
    this.hint,
  });

  final String name;
  final int closed;
  final int total;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7, left: 2, right: 2),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
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
        if (hint != null)
          Text(
            hint!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          )
        else
          Text(
            'закрыто $closed из $total',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
      ],
    ),
  );
}

// ---- Большая карточка игрока ----------------------------------------------

class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.player,
    required this.winMode,
    required this.highlight,
    required this.chipColor,
    required this.onTap,
    this.compact = false,
  });

  final LotoPlayer player;
  final WinMode winMode;
  final Set<int> highlight;
  final Color chipColor;
  final void Function(int number)? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final won = player.hasWon(winMode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            name: player.name,
            closed: player.closedCount,
            total: 15,
            color: chipColor,
            hint: won ? 'это победа!' : null,
          ),
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
}

// ---- Панель другого игрока (сеть) -----------------------------------------

class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.winMode,
    this.highlight = const <int>{},
    this.isMe = false,
  });

  final LotoPlayer player;
  final WinMode winMode;
  final Set<int> highlight;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final won = player.hasWon(winMode);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMe
              ? purple.withValues(alpha: .45)
              : const Color(0xFFF1E7DA),
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
              if (!player.connected)
                const _Badge(
                  label: 'вне игры',
                  background: Color(0xFFEDE9F2),
                  color: muted,
                )
              else if (won)
                _Badge(
                  label: winMode == WinMode.row
                      ? 'закрыл строку'
                      : 'закрыл всё',
                  background: const Color(0xFFDFF3E5),
                  color: const Color(0xFF2F7D52),
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
          IgnorePointer(
            child: LotoCardView(
              card: player.card,
              closed: player.closed,
              highlight: highlight,
              compact: true,
              chipColor: isMe ? chipGreen : chipBlue,
            ),
          ),
        ],
      ),
    );
  }
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
          : (player.isHost ? Icons.star_rounded : Icons.person_rounded),
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

class LotoCardView extends StatelessWidget {
  const LotoCardView({
    super.key,
    required this.card,
    required this.closed,
    this.highlight = const <int>{},
    this.chipColor = chipGreen,
    this.hintColor = yellow,
    this.compact = false,
    this.onTap,
  });

  final LotoCard card;
  final Set<int> closed;
  final Set<int> highlight;
  final Color chipColor;
  final Color hintColor;
  final bool compact;
  final void Function(int number)? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cell = constraints.maxWidth / LotoCard.columnCount;
      final cellHeight = cell * (compact ? .86 : .98);
      final radius = compact ? 8.0 : 16.0;
      return Container(
        padding: EdgeInsets.all(compact ? 4 : 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius + 4),
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
                          hintColor: hintColor,
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
    required this.hintColor,
  });

  final int? number;
  final Set<int> closed;
  final Set<int> highlight;
  final bool rowClosed;
  final void Function(int number)? onTap;
  final bool compact;
  final Color chipColor;
  final Color hintColor;

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
        key: Key('card-cell-$value'),
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
                      ? hintColor.withValues(alpha: .55)
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
                      color: hintColor.withValues(alpha: .55),
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

// ---- Панель истории -------------------------------------------------------

class HistoryPanel extends StatelessWidget {
  const HistoryPanel({
    super.key,
    required this.drawn,
    this.height = 62,
  });

  final List<int> drawn;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              drawn.isEmpty ? 'пока пусто' : 'вытянуто ${drawn.length}',
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
          height: height - 32,
          child: drawn.isEmpty
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
                  key: const Key('history-list'),
                  scrollDirection: Axis.horizontal,
                  itemCount: drawn.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 5),
                  itemBuilder: (context, index) {
                    final number = drawn[drawn.length - 1 - index];
                    return Center(
                      child: BarrelCap(
                        number: number,
                        size: (height - 32) * .92,
                        dimmed: index > 2,
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

// ---- Бочонок и мешок (CustomPaint) ----------------------------------------

class BarrelView extends StatelessWidget {
  const BarrelView({
    super.key,
    required this.number,
    this.width = 150,
    this.glow = false,
  });

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

class BarrelCap extends StatelessWidget {
  const BarrelCap({
    super.key,
    required this.number,
    this.size = 34,
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

class BagView extends StatelessWidget {
  const BagView({super.key, this.width = 96, this.waiting = false});

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

// ---- Сцена ведущего -------------------------------------------------------

class BarrelStage extends StatefulWidget {
  const BarrelStage({
    super.key,
    required this.barrel,
    required this.barrelsLeft,
    this.waitingFor = const <String>[],
    this.announce = true,
  });

  final Barrel? barrel;
  final int barrelsLeft;
  final List<String> waitingFor;
  final bool announce;

  @override
  State<BarrelStage> createState() => _BarrelStageState();
}

class _BarrelStageState extends State<BarrelStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant BarrelStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barrel?.number != widget.barrel?.number) {
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final barrelWidth = (width * .40).clamp(104.0, 168.0);
      final bagWidth = (width * .21).clamp(58.0, 92.0);
      final barrel = widget.barrel;
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: .06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            BagView(width: bagWidth, waiting: barrel == null),
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _draw,
              builder: (context, child) {
                final t = Curves.easeOutBack.transform(
                  _draw.value.clamp(0.0, 1.0),
                );
                final fade = _draw.value.clamp(0.0, 1.0);
                return Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(-26 * (1 - t), 0),
                    child: Transform.rotate(
                      angle: (1 - t) * -.45,
                      child: Transform.scale(
                        scale: .72 + .28 * t,
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: barrel == null
                  ? SizedBox(
                      width: barrelWidth,
                      height: barrelWidth * .74,
                      child: Center(
                        child: BarrelCap(
                          number: 7,
                          size: barrelWidth * .42,
                          dimmed: true,
                        ),
                      ),
                    )
                  : BarrelView(
                      number: barrel.number,
                      width: barrelWidth,
                      glow: _draw.value < 1,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _announcement(barrel)),
          ],
        ),
      );
    },
  );

  Widget _announcement(Barrel? barrel) {
    final waiting = widget.waitingFor;
    final text = barrel == null
        ? 'Мешок размешивают…'
        : (widget.announce
              ? barrel.announcement
              : 'Бочонок ${barrel.number}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
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
        if (waiting.isNotEmpty)
          Eyebrow(
            'Ждём: ${waiting.join(', ')}',
            background: const Color(0xFFFFEFC6),
            color: const Color(0xFF8A6A1F),
            fontSize: 9,
          )
        else
          Text(
            'В мешке: ${widget.barrelsLeft}',
            style: const TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    );
  }
}

// ---- Поздравление в конце партии -----------------------------------------

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onAgain,
    required this.onExit,
    this.againLabel = 'Играть снова',
    this.exitLabel = 'В меню',
    this.stars = 3,
  });

  final String title;
  final String subtitle;
  final VoidCallback onAgain;
  final VoidCallback onExit;
  final String againLabel;
  final String exitLabel;
  final int stars;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fireworks = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();
  late final List<_Confetti> _pieces = List<_Confetti>.generate(
    48,
    (index) => _Confetti.random(math.Random(index * 31 + 5)),
  );

  @override
  void dispose() {
    _fireworks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Container(
      color: ink.withValues(alpha: .38),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _fireworks,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(
                    pieces: _pieces,
                    progress: _fireworks.value,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF6),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: ink.withValues(alpha: .18),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                i < widget.stars
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 34,
                                color: const Color(0xFFF0BE48),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: dialogTextStyle,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          key: const Key('celebration-again'),
                          onPressed: widget.onAgain,
                          child: Text(widget.againLabel),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          key: const Key('celebration-exit'),
                          onPressed: widget.onExit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFE3D8F5)),
                            textStyle: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(widget.exitLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Confetti {
  _Confetti({
    required this.startX,
    required this.drift,
    required this.delay,
    required this.spin,
    required this.size,
    required this.color,
    required this.rounded,
  });

  factory _Confetti.random(math.Random random) => _Confetti(
    startX: random.nextDouble(),
    drift: (random.nextDouble() - .5) * .3,
    delay: random.nextDouble() * .35,
    spin: 1 + random.nextDouble() * 3,
    size: 6 + random.nextDouble() * 8,
    color: _colors[random.nextInt(_colors.length)],
    rounded: random.nextBool(),
  );

  static const _colors = [
    purple,
    yellow,
    peach,
    chipGreen,
    chipBlue,
    chipPink,
    deepPurple,
  ];

  final double startX;
  final double drift;
  final double delay;
  final double spin;
  final double size;
  final Color color;
  final bool rounded;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.progress});

  final List<_Confetti> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final t = ((progress - piece.delay) / (1 - piece.delay))
          .clamp(0.0, 1.0);
      if (t <= 0) continue;
      final x = (piece.startX + piece.drift * t) * size.width;
      final y = -20 + t * (size.height + 60);
      final opacity = t > .8 ? (1 - t) / .2 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * t * 2 * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.size,
            height: piece.size * .62,
          ),
          Radius.circular(piece.rounded ? piece.size : 1.5),
        ),
        Paint()
          ..color = piece.color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ---- Палитра лото (взята из оригинала; общие цвета — в theme.dart) --------

const woodLight = Color(0xFFF4CE93);
const woodMid = Color(0xFFD79A55);
const woodDark = Color(0xFF9A6330);
const woodEdge = Color(0xFF7A4A22);

const chipGreen = Color(0xFF4CAF7D);
const chipBlue = Color(0xFF4B8FD8);
const chipPink = Color(0xFFE68AB6);
