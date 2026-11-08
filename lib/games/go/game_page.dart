import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../presentation/games_page.dart' show popToGamesList;
import '../../presentation/theme.dart';
import 'board_game.dart';
import 'engine/model.dart';
import 'go_controller.dart';
import 'score_screen.dart';

class GoGamePage extends StatefulWidget {
  const GoGamePage({super.key, required this.settings, required this.setup});
  final SettingsController settings;
  final AppGameSetup setup;

  @override
  State<GoGamePage> createState() => _GoGamePageState();
}

class _GoGamePageState extends State<GoGamePage> {
  late final GoController _controller =
      GoController(widget.setup, widget.settings);
  Timer? _overTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.start());
    _controller.addListener(_checkOver);
  }

  void _checkOver() {
    if (!_controller.isOver && _controller.fatalMessage == null) return;
    if (_overTimer != null) return;
    _overTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GoScoreScreen(
            settings: widget.settings,
            controller: _controller,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _overTimer?.cancel();
    _controller.removeListener(_checkOver);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(_title()),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_rounded),
              onPressed: _confirmExit,
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: AppBackground(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.fatalMessage != null) {
                  return _FatalView(message: _controller.fatalMessage!);
                }
                return Column(
                  children: [
                    _StatusBar(controller: _controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: GoBoardView(controller: _controller),
                          ),
                        ),
                      ),
                    ),
                    // Слот под сообщения под доской зарезервирован всегда —
                    // даже когда ничего нет. Поле остаётся статичным, не «прыгает»
                    // при появлении/исчезновении пузыря. Показываем только одно
                    // сообщение по приоритету: запрос отмены > ожидание ответа
                    // > замечание > подсказка.
                    _NoticeSlot(controller: _controller),
                    _ActionBar(controller: _controller),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
          ),
        ),
      );

  String _title() => switch (widget.setup.mode) {
        GoMode.capture =>
          'Захват · ${widget.setup.boardSize}×${widget.setup.boardSize}',
        GoMode.classic =>
          'Классика · ${widget.setup.boardSize}×${widget.setup.boardSize}',
      };

  Future<void> _confirmExit() async {
    if (!mounted) return;
    final go = await showDianaDialog<bool>(
      context: context,
      title: 'Выйти в меню?',
      content: const Text(
        'Партия закончится. Всегда можно начать новую.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Остаться', value: false, primary: true),
        DianaDialogButton<bool>(label: 'В меню', value: true),
      ],
    );
    if (!mounted) return;
    if (go == true) {
      popToGamesList(context);
    }
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});
  final GoController controller;
  @override
  Widget build(BuildContext context) {
    final turn = controller.state.turn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: _PlayerCard(
              color: StoneColor.black,
              captures: controller.state.blackCaptured,
              active: turn == StoneColor.black,
              label: _labelFor(StoneColor.black),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PlayerCard(
              color: StoneColor.white,
              captures: controller.state.whiteCaptured,
              active: turn == StoneColor.white,
              label: _labelFor(StoneColor.white),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(StoneColor c) {
    final setup = controller.setup;
    if (setup.appMode == AppGameMode.local) return c.label;
    if (setup.appMode == AppGameMode.computer) {
      return c == setup.playerSide ? 'Ты' : 'Компьютер';
    }
    return c == setup.playerSide
        ? 'Ты'
        : controller.setup.network?.peerName ?? 'Друг';
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.color,
    required this.captures,
    required this.active,
    required this.label,
  });
  final StoneColor color;
  final int captures;
  final bool active;
  final String label;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
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
            StoneIcon(dark: color == StoneColor.black, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: ink,
                      ),
                    ),
                  ),
                  Text(
                    'Захвачено: $captures',
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});
  final GoController controller;
  @override
  Widget build(BuildContext context) {
    final thinking = controller.computerThinking || controller.hintThinking;
    final chips = <Widget>[
      if (controller.setup.appMode == AppGameMode.local ||
          controller.setup.appMode == AppGameMode.network)
        _ActionChip(
          icon: Icons.undo_rounded,
          label: 'Отменить',
          enabled: controller.canUndo,
          onTap: controller.undo,
        ),
      if (controller.hintButton)
        _ActionChip(
          icon: Icons.lightbulb_rounded,
          label: controller.hintThinking ? 'Думаю…' : 'Подсказка',
          enabled:
              controller.canInteract && !thinking && controller.hints,
          onTap: controller.showHint,
        ),
      _ActionChip(
        icon: Icons.block_rounded,
        label: 'Пас',
        enabled: controller.canPass,
        onTap: controller.pass,
      ),
      _ActionChip(
        icon: Icons.flag_rounded,
        label: 'Сдаться',
        enabled: !controller.isOver && controller.fatalMessage == null,
        onTap: () => _confirmResign(context),
        tone: _ChipTone.danger,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: chips[i],
              ),
            ),
            if (i < chips.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmResign(BuildContext context) async {
    final ok = await showDianaDialog<bool>(
      context: context,
      title: 'Сдаться?',
      content: const Text(
        'Партия закончится победой соперника.',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(
          label: 'Продолжить',
          value: false,
          primary: true,
        ),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    );
    if (ok == true) controller.resign();
  }
}

enum _ChipTone { normal, danger }

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.tone = _ChipTone.normal,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final _ChipTone tone;
  @override
  Widget build(BuildContext context) {
    final color =
        tone == _ChipTone.danger ? const Color(0xFFE5484D) : purple;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: enabled ? color : const Color(0xFFD8D2E0),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
              FilledButton.icon(
                onPressed: () => popToGamesList(context),
                icon: const Icon(Icons.home_rounded),
                label: const Text('В меню'),
              ),
            ],
          ),
        ),
      );
}

/// Фиксированный по высоте слот под сообщения под доской: замечание о тапе,
/// подсказка, запрос отмены хода или ожидание ответа. Слот всегда одного
/// размера — поле над ним не «прыгает» при появлении/исчезновении сообщения.
/// Показывается только одно сообщение по приоритету:
/// запрос отмены → ожидание ответа → замечание → подсказка.
class _NoticeSlot extends StatelessWidget {
  const _NoticeSlot({required this.controller});
  final GoController controller;

  @override
  Widget build(BuildContext context) {
    Widget? child;
    if (controller.incomingUndoPly != null) {
      child = _UndoRequest(controller: controller);
    } else if (controller.waitingForUndo) {
      child = const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Ждём ответа на запрос отмены хода…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else if (controller.notice != null) {
      child = _Bubble(
        text: controller.notice!,
        onClose: controller.clearNotice,
        color: const Color(0xFFFFF4D6),
      );
    } else if (controller.hintText != null) {
      child = _Bubble(
        text: controller.hintText!,
        onClose: controller.clearHint,
        color: const Color(0xFFE3F2DE),
      );
    }
    return SizedBox(
      height: 56,
      child: child ?? const SizedBox.shrink(),
    );
  }
}
