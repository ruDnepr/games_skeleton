import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import 'board_game.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'game_page.dart';
import 'go_controller.dart';
import 'network.dart';

/// Шаг 1 — режим правил: «Захват» или «Классическое го».
class GoModePage extends StatelessWidget {
  const GoModePage({super.key, required this.settings});
  final SettingsController settings;
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Режим игры',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ШАГ 1',
              title: 'Во что сыграем?',
              subtitle: 'Начни с «Захвата» — это самый мягкий вход в го.',
            ),
            const SizedBox(height: 25),
            ChoiceTile(
              title: 'Захват',
              subtitle: 'Первым снимешь камень соперника — и победа!',
              icon: Icons.bolt_rounded,
              color: const Color(0xFFFFE5A3),
              tag: 'просто',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GoBoardSizePage(
                    settings: settings,
                    mode: GoMode.capture,
                  ),
                ),
              ),
            ),
            ChoiceTile(
              title: 'Классическое го',
              subtitle: 'Территория и очки, как в настоящем го',
              icon: Icons.public_rounded,
              color: const Color(0xFFD9EFE4),
              tag: 'подробнее',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GoBoardSizePage(
                    settings: settings,
                    mode: GoMode.classic,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Шаг 2 — размер доски: 9×9, 13×13, 19×19.
class GoBoardSizePage extends StatelessWidget {
  const GoBoardSizePage({
    super.key,
    required this.settings,
    required this.mode,
  });
  final SettingsController settings;
  final GoMode mode;
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Размер доски',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ШАГ 2',
              title: 'Какая доска?',
              subtitle: '9×9 — основная для ребёнка. Больше — длиннее партия.',
            ),
            const SizedBox(height: 25),
            for (final s in const [9, 13, 19])
              ChoiceTile(
                title: '$s×$s',
                subtitle: s == 9
                    ? 'Короткая партия, удобно начать'
                    : (s == 13
                        ? 'Средняя — для продвинутых'
                        : 'Большая — как у мастеров'),
                icon: Icons.grid_on_rounded,
                color: s == 9
                    ? const Color(0xFFDDF1DF)
                    : (s == 13
                        ? const Color(0xFFFFE5A3)
                        : const Color(0xFFE8DDFB)),
                tag: s == 9 ? 'рекомендуем' : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GoDifficultyPage(
                      settings: settings,
                      mode: mode,
                      boardSize: s,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Шаг 3 — уровень сложности (только для игры с компьютером).
class GoDifficultyPage extends StatelessWidget {
  const GoDifficultyPage({
    super.key,
    required this.settings,
    required this.mode,
    required this.boardSize,
  });
  final SettingsController settings;
  final GoMode mode;
  final int boardSize;
  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Сложность',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ШАГ 3',
              title: 'С кем играем и какой уровень?',
              subtitle:
                  'Можно тренироваться с компьютером или вдвоём на одном устройстве.',
            ),
            const SizedBox(height: 18),
            const Text(
              'Против компьютера',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
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
                onTap: () => _chooseColor(
                  context,
                  AppGameMode.computer,
                  difficulty: difficulty,
                ),
              ),
            const SizedBox(height: 18),
            const Text(
              'Два игрока',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ChoiceTile(
              title: 'На одном устройстве',
              subtitle: 'Ходы по очереди, вдвоём',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFFFFE5A3),
              onTap: () => _chooseColor(context, AppGameMode.local),
            ),
            const SizedBox(height: 13),
            const _NetworkNote(),
          ],
        ),
      );

  Future<void> _chooseColor(
    BuildContext context,
    AppGameMode appMode, {
    Difficulty difficulty = Difficulty.easy,
  }) async {
    final side = await Navigator.push<StoneColor>(
      context,
      MaterialPageRoute(
        builder: (_) => GoColorGuessPage(settings: settings),
      ),
    );
    if (!context.mounted || side == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoGamePage(
          settings: settings,
          setup: AppGameSetup(
            mode: mode,
            boardSize: boardSize,
            playerSide: side,
            komi: GameSetup.defaultKomi(boardSize),
            appMode: appMode,
            difficulty: difficulty,
          ),
        ),
      ),
    );
  }
}

/// Подсказка про сетевую игру: она запускается с главной страницы.
class _NetworkNote extends StatelessWidget {
  const _NetworkNote();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0E9FC),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: purple, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Сетевая игра запускается с главной страницы — кнопка «Сетевая игра».',
                style: TextStyle(
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

/// Жеребьёвка цвета: в какой руке чёрный камень.
class GoColorGuessPage extends StatefulWidget {
  const GoColorGuessPage({
    super.key,
    required this.settings,
    this.random,
    this.revealDelay = const Duration(milliseconds: 1600),
  });
  final SettingsController settings;
  final Random? random;
  final Duration revealDelay;
  @override
  State<GoColorGuessPage> createState() => _GoColorGuessPageState();
}

class _GoColorGuessPageState extends State<GoColorGuessPage>
    with SingleTickerProviderStateMixin {
  late final int hiddenHand =
      (widget.random ?? Random.secure()).nextInt(2);
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);
  int? chosen;
  Timer? _timer;
  late final GameSounds _sounds = GameSounds(widget.settings);

  void _choose(int hand) {
    if (chosen != null) return;
    setState(() => chosen = hand);
    final guessed = hand == hiddenHand;
    _sounds.play(guessed ? GameSound.guess : GameSound.miss);
    _timer = Timer(widget.revealDelay, () {
      if (mounted) {
        // Угадал — чёрные (ходит первым), не угадал — белые.
        Navigator.pop(
          context,
          guessed ? StoneColor.black : StoneColor.white,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Выбираем цвет',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Intro(
                eyebrow: 'НЕБОЛЬШАЯ ЖЕРЕБЬЁВКА',
                title: 'В какой руке\nчёрный камень?',
                subtitle:
                    'Угадай — и будешь играть чёрными, ходить первым.',
              ),
              const SizedBox(height: 30),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: chosen == null
                      ? const Eyebrow(
                          'ВЫБЕРИ ОДНУ РУКУ',
                          background: Color(0xFFFFE8B2),
                          color: Color(0xFF9E7130),
                        )
                      : Eyebrow(
                          chosen == hiddenHand
                              ? 'УГАДАЛА! ТЫ ИГРАЕШЬ ЧЁРНЫМИ'
                              : 'ПОЧТИ! ТЫ ИГРАЕШЬ БЕЛЫМИ',
                          key: ValueKey(chosen == hiddenHand),
                          background: const Color(0xFFE3F2DE),
                          color: const Color(0xFF5C8559),
                        ),
                ),
              ),
              const SizedBox(height: 25),
              AnimatedBuilder(
                animation: _bounce,
                builder: (context, _) => Row(
                  children: [
                    Expanded(
                      child: _HandCard(
                        key: const Key('hand-left'),
                        label: 'Левая',
                        index: 0,
                        hiddenHand: hiddenHand,
                        chosen: chosen,
                        angle: -.05 + _bounce.value * .05,
                        onTap: () => _choose(0),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _HandCard(
                        key: const Key('hand-right'),
                        label: 'Правая',
                        index: 1,
                        hiddenHand: hiddenHand,
                        chosen: chosen,
                        angle: .05 - _bounce.value * .05,
                        onTap: () => _choose(1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: chosen == null
                      ? const Text(
                          'Готова? Доверься интуиции ✨',
                          key: ValueKey('waiting'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Text(
                          chosen == hiddenHand
                              ? 'Отличное начало!'
                              : 'Любым цветом можно победить!',
                          key: const ValueKey('revealed'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: purple,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    super.key,
    required this.label,
    required this.index,
    required this.hiddenHand,
    required this.chosen,
    required this.angle,
    required this.onTap,
  });
  final String label;
  final int index, hiddenHand;
  final int? chosen;
  final double angle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: chosen == null ? angle : 0,
        child: Material(
          color: index == 0
              ? const Color(0xFFFFE2C9)
              : const Color(0xFFE8DDFB),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 210,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedScale(
                          scale: chosen == null ? 1 : .85,
                          duration: const Duration(milliseconds: 350),
                          child: Text(
                            chosen == null ? '✊' : '🖐️',
                            style: const TextStyle(fontSize: 72),
                          ),
                        ),
                        if (chosen != null && index == hiddenHand)
                          const Positioned(
                            bottom: 0,
                            child: StoneIcon(dark: true, size: 42),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      color: ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Настройки хоста перед сетевой партией: режим, размер, цель, цвет.
class GoHostSetupPage extends StatefulWidget {
  const GoHostSetupPage({
    super.key,
    required this.settings,
  });
  final SettingsController settings;

  @override
  State<GoHostSetupPage> createState() => _GoHostSetupPageState();
}

class _GoHostSetupPageState extends State<GoHostSetupPage> {
  late GoMode mode =
      widget.settings.gameString(goGameId, goHostModeKey, 'capture') ==
              'classic'
          ? GoMode.classic
          : GoMode.capture;
  late int boardSize = int.parse(
    widget.settings.gameString(goGameId, goHostBoardKey, '9'),
  );
  late CaptureTarget target =
      int.parse(widget.settings.gameString(goGameId, goHostTargetKey, '1')) == 3
          ? CaptureTarget.three
          : CaptureTarget.one;
  late StoneColor side =
      widget.settings.gameString(goGameId, goHostSideKey, 'black') == 'white'
          ? StoneColor.white
          : StoneColor.black;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Создать игру',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ПАРАМЕТРЫ ПАРТИИ',
              title: 'Настрой сетевую игру',
              subtitle: 'Друг увидит эти параметры перед подключением.',
            ),
            const SizedBox(height: 22),
            const _SectionLabel('Режим'),
            Wrap(
              spacing: 10,
              children: [
                _Chip(
                  label: 'Захват',
                  selected: mode == GoMode.capture,
                  onTap: () => setState(() => mode = GoMode.capture),
                ),
                _Chip(
                  label: 'Классика',
                  selected: mode == GoMode.classic,
                  onTap: () => setState(() => mode = GoMode.classic),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Размер доски'),
            Wrap(
              spacing: 10,
              children: [
                for (final s in const [9, 13, 19])
                  _Chip(
                    label: '$s×$s',
                    selected: boardSize == s,
                    onTap: () => setState(() => boardSize = s),
                  ),
              ],
            ),
            if (mode == GoMode.capture) ...[
              const SizedBox(height: 16),
              const _SectionLabel('Цель захвата'),
              Wrap(
                spacing: 10,
                children: [
                  _Chip(
                    label: '1 камень',
                    selected: target == CaptureTarget.one,
                    onTap: () =>
                        setState(() => target = CaptureTarget.one),
                  ),
                  _Chip(
                    label: '3 камня',
                    selected: target == CaptureTarget.three,
                    onTap: () =>
                        setState(() => target = CaptureTarget.three),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const _SectionLabel('Твой цвет'),
            Wrap(
              spacing: 10,
              children: [
                _Chip(
                  label: 'Чёрные',
                  selected: side == StoneColor.black,
                  onTap: () => setState(() => side = StoneColor.black),
                ),
                _Chip(
                  label: 'Белые',
                  selected: side == StoneColor.white,
                  onTap: () => setState(() => side = StoneColor.white),
                ),
              ],
            ),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.wifi_rounded),
              label: const Text('К сетевому лобби'),
            ),
          ],
        ),
      );

  Future<void> _create(BuildContext context) async {
    await saveGoHostSetup(
      widget.settings,
      mode: mode,
      boardSize: boardSize,
      target: target,
      side: side,
    );
    if (!context.mounted) return;
    // Возвращаемся в сетевое лобби — выбор уже в настройках, и goOptions
    // прочитает его при создании лобби.
    Navigator.of(context).maybePop();
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
            fontSize: 14,
            color: ink,
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? purple : const Color(0xFFF1EAFB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : ink,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
}
