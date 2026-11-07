import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'checkers_controller.dart';
import 'engine/ai.dart';
import 'engine/model.dart';
import 'network.dart';

/// Точка входа в шашки: с сетевым соединением — сразу партия по сети тем
/// вариантом, который выбрал хост, без него — пошаговый выбор варианта, режима,
/// сложности и цвета.
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
      // Вариант выбирает хост до создания сетевой игры; клиент принимает тот,
      // что пришёл в рукопожатии.
      final variantStr =
          network!.lobby.options['variant'] as String? ?? 'russian';
      return CheckersSessionPage(
        settings: settings,
        network: network,
        variant: parseVariant(variantStr),
      );
    }
    return CheckersVariantPage(settings: settings);
  }
}

/// Шаг 1: выбор варианта шашек — русские, классические, международные, поддавки.
class CheckersVariantPage extends StatelessWidget {
  const CheckersVariantPage({
    super.key,
    required this.settings,
    this.forNetwork = false,
  });
  final SettingsController settings;
  final bool forNetwork;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Вариант игры',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 1',
          title: 'Во что сыграем?',
          subtitle: 'У каждой игры свой характер. Выбирай любую!',
        ),
        const SizedBox(height: 25),
        for (final variant in GameVariant.values)
          ChoiceTile(
            title: variant.label,
            subtitle: switch (variant) {
              GameVariant.russian => 'Знакомые правила и летающие дамки',
              GameVariant.american => 'Короткие ходы и классический бой',
              GameVariant.international =>
                'Большая доска и максимальное взятие',
              GameVariant.giveaway => 'Побеждает тот, кто отдаст свои шашки',
            },
            icon: switch (variant) {
              GameVariant.russian => Icons.auto_awesome_rounded,
              GameVariant.american => Icons.extension_rounded,
              GameVariant.international => Icons.public_rounded,
              GameVariant.giveaway => Icons.favorite_rounded,
            },
            color: switch (variant) {
              GameVariant.russian => const Color(0xFFFFE5A3),
              GameVariant.american => const Color(0xFFE6DEF9),
              GameVariant.international => const Color(0xFFD9EFE4),
              GameVariant.giveaway => const Color(0xFFFFDDD3),
            },
            tag: '${variant.boardSize}×${variant.boardSize}',
            onTap: () => _open(context, variant),
          ),
      ],
    ),
  );

  Future<void> _open(BuildContext context, GameVariant variant) async {
    if (forNetwork) {
      // Сохраним выбор хоста — он уедет в рукопожатие через checkersOptions.
      await settings.setGameString(
        checkersGameId,
        checkersVariantKey,
        variantKey(variant),
      );
      if (!context.mounted) return;
      Navigator.of(context).maybePop();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CheckersModePage(settings: settings, variant: variant),
      ),
    );
  }
}

/// Шаг 2: режим — против компьютера или вдвоём на одном устройстве.
class CheckersModePage extends StatelessWidget {
  const CheckersModePage({
    super.key,
    required this.settings,
    required this.variant,
  });
  final SettingsController settings;
  final GameVariant variant;

  Future<void> _startLocal(BuildContext context) async {
    final side = await Navigator.push<Side>(
      context,
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!context.mounted || side == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckersSessionPage(
          settings: settings,
          variant: variant,
          mode: GameMode.local,
          humanColor: side,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Режим игры',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ШАГ 2',
          title: 'С кем играем?',
          subtitle: 'Можно тренироваться одному или пригласить друга.',
        ),
        const SizedBox(height: 25),
        ChoiceTile(
          title: 'Против компьютера',
          subtitle: 'Выбери уровень и начни приключение',
          icon: Icons.smart_toy_rounded,
          color: const Color(0xFFE8E0FA),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CheckersDifficultyPage(settings: settings, variant: variant),
            ),
          ),
        ),
        ChoiceTile(
          title: 'Два игрока',
          subtitle: 'Играйте вместе на одном устройстве',
          icon: Icons.people_alt_rounded,
          color: const Color(0xFFFFE5A3),
          onTap: () => _startLocal(context),
        ),
      ],
    ),
  );
}

/// Шаг 3 (для игры против компьютера): уровень сложности.
class CheckersDifficultyPage extends StatelessWidget {
  const CheckersDifficultyPage({
    super.key,
    required this.settings,
    required this.variant,
  });
  final SettingsController settings;
  final GameVariant variant;

  Future<void> _start(BuildContext context, Difficulty difficulty) async {
    final side = await Navigator.push<Side>(
      context,
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!context.mounted || side == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckersSessionPage(
          settings: settings,
          variant: variant,
          mode: GameMode.computer,
          difficulty: difficulty,
          humanColor: side,
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
          eyebrow: 'ШАГ 3',
          title: 'Выбери уровень',
          subtitle: 'Начни с лёгкого — и расти с каждой партией!',
        ),
        const SizedBox(height: 25),
        for (final difficulty in Difficulty.values)
          ChoiceTile(
            title: difficulty.label,
            subtitle: switch (difficulty) {
              Difficulty.easy => 'Учимся и пробуем без спешки',
              Difficulty.medium => 'Немного больше размышлений',
              Difficulty.hard => 'Для настоящих искателей задач',
            },
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

/// Жеребьёвка цвета: ребёнок угадывает, в какой руке спряталась белая шашка.
/// Угадал — играет белыми, не угадал — чёрными. Так цвет выбирает не родитель,
/// а сама судьба, и проигрыш не обидный: «любым цветом можно победить».
class GuessPage extends StatefulWidget {
  const GuessPage({
    super.key,
    required this.settings,
    this.random,
    this.revealDelay = const Duration(milliseconds: 1600),
  });
  final SettingsController settings;
  final Random? random;
  final Duration revealDelay;

  @override
  State<GuessPage> createState() => _GuessPageState();
}

class _GuessPageState extends State<GuessPage>
    with SingleTickerProviderStateMixin {
  late final int hiddenHand =
      (widget.random ?? Random.secure()).nextInt(2);
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);
  int? chosen;
  Timer? _timer;

  /// Один экземпляр для страницы, чтобы guard от повторного звука работал.
  late final GameSounds _sounds = GameSounds(widget.settings);

  void _choose(int hand) {
    if (chosen != null) return;
    setState(() => chosen = hand);
    final guessed = hand == hiddenHand;
    _sounds.play(guessed ? GameSound.guess : GameSound.miss);
    _timer = Timer(widget.revealDelay, () {
      if (mounted) Navigator.pop(context, guessed ? Side.white : Side.black);
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
            title: 'В какой руке\nшашка?',
            subtitle: 'Угадай, где спряталась белая шашка. Нажми на ладошку!',
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
                          ? 'УГАДАЛА! ТЫ ИГРАЕШЬ БЕЛЫМИ'
                          : 'ПОЧТИ! ТЫ ИГРАЕШЬ ЧЁРНЫМИ',
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

/// Одна карточка-ладонь в жеребьёвке. Покачивается, пока не выбрана, и
/// раскрывается после тапа: эмодзи ✊ сменяется на 🖐️, угаданная рука
/// показывает белую шашку.
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
      color: index == 0 ? const Color(0xFFFFE2C9) : const Color(0xFFE8DDFB),
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
                        child: CheckerIcon(size: 42),
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

/// Что выбрал ребёнок в диалоге результата.
enum _ResultChoice { again, undo, home }

/// Экран партии: доска посередине, сверху и снизу — панели игроков, под доской —
/// сообщение и кнопки. По сети и против компьютера доска разворачивается так,
/// чтобы шашки человека были снизу. На коротких экранах включается компактный
/// режим, на совсем маленьких — вертикальный скролл.
class CheckersSessionPage extends StatefulWidget {
  const CheckersSessionPage({
    super.key,
    required this.settings,
    this.variant = GameVariant.russian,
    this.mode = GameMode.local,
    this.difficulty = Difficulty.easy,
    this.humanColor = Side.white,
    this.network,
    this.animationPerLanding = const Duration(milliseconds: 350),
    this.initialState,
  });
  final SettingsController settings;
  final GameVariant variant;
  final GameMode mode;
  final Difficulty difficulty;
  final Side humanColor;
  final NetworkSession? network;

  /// Короче в тестах — партия идёт быстрее. Сама игра использует 350 мс.
  final Duration animationPerLanding;

  /// Стартовая позиция — для тестов и подсадок (жеребьёвка, серия взятий).
  final GameState? initialState;

  @override
  State<CheckersSessionPage> createState() => _CheckersSessionPageState();
}

class _CheckersSessionPageState extends State<CheckersSessionPage>
    with SingleTickerProviderStateMixin {
  late final CheckersController controller;
  late final Ticker _ticker;
  Duration _tickerElapsed = Duration.zero;
  Duration _animStart = Duration.zero;
  MoveAnimation? _lastAnimation;

  bool resultShown = false;
  bool resultDialogOpen = false;
  bool resultRecorded = false;
  bool errorShown = false;
  bool undoDialogShown = false;
  bool exiting = false;

  @override
  void initState() {
    super.initState();
    controller = CheckersController(
      settings: widget.settings,
      sounds: GameSounds(widget.settings),
      variant: widget.variant,
      mode: widget.mode,
      difficulty: widget.difficulty,
      humanColor: widget.humanColor,
      animationPerLanding: widget.animationPerLanding,
      network: widget.network,
      initialState: widget.initialState,
    );
    controller.addListener(_onGameChanged);
    _ticker = createTicker(_onTick);
    // Запускаем ИИ в посткадровом колбэке — к этому моменту слушатель уже
    // подключён, и ход ИИ не потеряется.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.start();
    });
  }

  void _onTick(Duration elapsed) {
    _tickerElapsed = elapsed;
    // Перерисовку доски гоняет AnimatedBuilder на тикере в [_board].
  }

  void _onGameChanged() {
    if (!mounted) return;
    final anim = controller.animation;
    if (anim != null && !identical(anim, _lastAnimation)) {
      _lastAnimation = anim;
      // Тикер при перезапуске сбрасывает elapsed в ноль — учитываем это.
      if (_ticker.active) {
        _animStart = _tickerElapsed;
      } else {
        _animStart = Duration.zero;
        _ticker.start();
      }
    } else if (anim == null && controller.suggestedMove == null &&
        _ticker.active) {
      _ticker.stop();
    } else if (controller.suggestedMove != null && !_ticker.active) {
      _ticker.start();
    }
    if (controller.fatalMessage != null && !errorShown) {
      errorShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showError();
      });
    } else if (controller.incomingUndoPly != null && !undoDialogShown) {
      undoDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showUndoRequest();
      });
    } else if (controller.isOver &&
        !controller.isAnimating &&
        !resultShown &&
        !controller.waitingForUndo &&
        controller.incomingUndoPly == null &&
        controller.fatalMessage == null) {
      resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResult();
      });
    }
  }

  bool get flipped =>
      widget.mode != GameMode.local && controller.humanColor == Side.black;

  Future<void> _showError() async {
    await showDianaDialog<bool>(
      context: context,
      title: 'Ой, что-то случилось',
      barrierDismissible: false,
      content: Text(
        controller.fatalMessage ?? 'Связь потеряна.',
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
    final accepted = await showDianaDialog<bool>(
      context: context,
      title: 'Друг просит отменить ход',
      barrierDismissible: false,
      content: const Text(
        'Разрешить вернуться на один ход назад?',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(label: 'Разрешить', value: true, primary: true),
        DianaDialogButton<bool>(label: 'Не сейчас', value: false),
      ],
    );
    if (!mounted) return;
    undoDialogShown = false;
    if (accepted == true && resultDialogOpen) {
      Navigator.of(context).pop();
      resultDialogOpen = false;
      resultShown = false;
    }
    controller.respondToUndo(accepted == true);
  }

  Future<void> _showResult() async {
    final winner = controller.winner;
    final draw = winner == null && controller.isDraw;
    if (winner == null && !draw) {
      resultShown = false;
      return;
    }
    final mine = winner != null && winner == controller.humanColor;
    // У каждого конца — свой звук: победа, мягкий проигрыш и спокойная ничья.
    // Вдвоём на одном устройстве кто-то всегда победил — играем победный звук.
    controller.sounds.play(
      resultSoundName(
        draw: draw,
        local: widget.mode == GameMode.local,
        iWon: mine,
      ),
    );
    resultDialogOpen = true;
    final choice = await showDianaDialog<_ResultChoice>(
      context: context,
      title: draw
          ? 'Ничья!'
          : (widget.mode == GameMode.local
                ? '${winner!.label} победили!'
                : (mine ? 'Ты молодец!' : 'Отличная партия!')),
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Celebration(calm: !mine),
          const SizedBox(height: 14),
          Text(
            draw
                ? 'Никто не уступил: позиция повторилась или давно не было '
                      'взятий. Сыграем ещё?'
                : (mine || widget.mode == GameMode.local
                      ? 'Здорово сыграно! Каждый ход был важен.'
                      : 'В следующий раз обязательно получится!'),
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
        if (controller.canUndo)
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
    resultDialogOpen = false;
    if (!mounted) return;
    switch (choice) {
      case _ResultChoice.again:
        _recordResult(mine);
        await _playAgain();
      case _ResultChoice.home:
        _recordResult(mine);
        _goHome();
      case _ResultChoice.undo:
        resultShown = false;
        controller.undo();
      case null:
        // Диалог нельзя закрыть барьером, сюда попадаем только при уходе
        // страницы.
        resultShown = false;
    }
  }

  void _recordResult(bool won) {
    if (resultRecorded) return;
    resultRecorded = true;
    unawaited(widget.settings.recordGame(won: won));
  }

  void _goHome() {
    if (exiting || !mounted) return;
    exiting = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _playAgain() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final mode = widget.mode;
    final variant = widget.variant;
    final settings = widget.settings;
    final difficulty = widget.difficulty;
    exiting = true;
    navigator.popUntil((route) => route.isFirst);
    if (mode == GameMode.network) {
      // Сетевой рематч требует новой комнаты — вернёмся в меню.
      return;
    }
    final side = await navigator.push<Side>(
      MaterialPageRoute(builder: (_) => GuessPage(settings: settings)),
    );
    if (!navigator.mounted || side == null) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => CheckersSessionPage(
          settings: settings,
          variant: variant,
          mode: mode,
          difficulty: difficulty,
          humanColor: side,
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    if (exiting) return;
    final yes = await showDianaDialog<bool>(
      context: context,
      title: 'Выйти из партии?',
      content: const Text(
        'Текущая партия закончится. Можно будет начать новую!',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: const [
        DianaDialogButton<bool>(
          label: 'Продолжить',
          value: false,
          primary: true,
        ),
        DianaDialogButton<bool>(label: 'В меню', value: true),
      ],
    );
    if (!mounted || yes != true) return;
    if (widget.mode == GameMode.network && !controller.isOver) {
      controller.resign();
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
        DianaDialogButton<bool>(
          label: 'Продолжить',
          value: false,
          primary: true,
        ),
        DianaDialogButton<bool>(label: 'Сдаться', value: true),
      ],
    );
    if (mounted && yes == true) controller.resign();
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
            if (controller.history.isEmpty)
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
                  itemCount: controller.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final record = controller.history[index];
                    return ListTile(
                      leading: CheckerIcon(
                        size: 32,
                        dark: record.side == Side.black,
                      ),
                      title: Text(
                        '${index + 1}. ${record.move}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(record.side.label),
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
    _ticker.dispose();
    controller.removeListener(_onGameChanged);
    controller.dispose();
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
              constraints: const BoxConstraints(maxWidth: 510),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final topSide = flipped ? Side.white : Side.black;
                  final bottomSide = topSide.opponent;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 700;
                      final tiny = constraints.maxHeight < 470;
                      final gap = compact ? 8.0 : 12.0;
                      final panels = <Widget>[
                        _playerPanel(topSide, top: true, compact: compact),
                        SizedBox(height: gap),
                        if (tiny)
                          AspectRatio(
                            aspectRatio: 1,
                            child: _board(compact: compact),
                          )
                        else
                          Expanded(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: _board(compact: compact),
                              ),
                            ),
                          ),
                        SizedBox(height: gap),
                        _playerPanel(
                          bottomSide,
                          top: false,
                          compact: compact,
                        ),
                        SizedBox(height: gap),
                        SizedBox(
                          height: compact ? 58 : 66,
                          child: _message(compact: compact),
                        ),
                        SizedBox(height: gap),
                        SizedBox(
                          height: _actionHeight(compact),
                          child: _actions(compact: compact),
                        ),
                        if (!compact) ..._secondaryActions(),
                      ];
                      return Column(
                        children: [
                          _header(compact: compact),
                          Expanded(
                            child: tiny
                                ? SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      2,
                                      16,
                                      10,
                                    ),
                                    child: Column(children: panels),
                                  )
                                : Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      2,
                                      16,
                                      compact ? 8 : 14,
                                    ),
                                    child: Column(children: panels),
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  double _actionHeight(bool compact) => compact ? 46 : 54;

  Widget _board({bool compact = false}) => RepaintBoundary(
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF8B552E),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFB77A3D), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xFF613D23), offset: Offset(0, 6)),
          BoxShadow(
            color: Color(0x446B492D),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) => CheckersBoardView(
          controller: controller,
          flipped: flipped,
          elapsed: _tickerElapsed,
          animStart: _animStart,
        ),
      ),
    ),
  );

  List<Widget> _secondaryActions() => [
    const SizedBox(height: 2),
    SizedBox(
      height: 38,
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
            onPressed: controller.isOver ? null : _confirmResign,
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
              Text(
                widget.variant.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                widget.mode == GameMode.network
                    ? 'Сетевая игра'
                    : (widget.mode == GameMode.local
                          ? 'Два игрока'
                          : 'Против компьютера'),
                style: const TextStyle(
                  fontSize: 10,
                  color: muted,
                  fontWeight: FontWeight.w800,
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
              if (controller.hintsEnabled)
                IconButton(
                  key: const Key('hint-toggle'),
                  tooltip: controller.hintButtonEnabled
                      ? 'Скрыть кнопку «Подсказка»'
                      : 'Показать кнопку «Подсказка»',
                  visualDensity: compact ? VisualDensity.compact : null,
                  onPressed: () => widget.settings.setFlag(
                    checkersGameId,
                    'hintButton',
                    !controller.hintButtonEnabled,
                  ),
                  icon: Icon(
                    controller.hintButtonEnabled
                        ? Icons.lightbulb_rounded
                        : Icons.lightbulb_outline_rounded,
                    color: controller.hintButtonEnabled
                        ? purple
                        : const Color(0xFFB4ACAF),
                  ),
                ),
              IconButton(
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

  Widget _playerPanel(Side side, {required bool top, bool compact = false}) {
    final active = controller.currentTurn == side && !controller.isOver;
    final title = compact
        ? '${controller.playerName(side)} · ${controller.state.board.count(side)}'
        : controller.playerName(side);
    Widget panel = Container(
      key: Key(top ? 'top-player-panel' : 'bottom-player-panel'),
      height: compact ? 44 : 60,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEDE5FD)
            : Colors.white.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(compact ? 15 : 19),
        border: Border.all(
          color: active ? const Color(0xFFB9A3EF) : const Color(0xFFF1EAE5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          CheckerIcon(size: compact ? 26 : 36, dark: side == Side.black),
          SizedBox(width: compact ? 9 : 12),
          Expanded(
            child: compact
                ? Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${side.label} · '
                        '${controller.state.board.count(side)} шашек',
                        style: const TextStyle(
                          fontSize: 11,
                          color: muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
          if (active)
            Eyebrow(
              'ХОД',
              color: deepPurple,
              background: const Color(0xFFDCCDF8),
              fontSize: compact ? 9 : 10,
            ),
        ],
      ),
    );
    // В локальном режиме верхнюю панель поворачиваем — игрок по ту сторону
    // стола читает её нормально.
    if (top && widget.mode == GameMode.local) {
      panel = RotatedBox(quarterTurns: 2, child: panel);
    }
    return panel;
  }

  /// Жёлтый пузырь под доской: сначала пояснение неудачного тапа, потом текст
  /// подсказки, потом особые состояния (ждём ответа, ИИ думает), и только в
  /// конце — чей ход.
  Widget _message({bool compact = false}) {
    var text = controller.notice;
    var hint = false;
    if (text == null) {
      text = controller.hintText;
      hint = text != null;
    }
    if (text == null && controller.waitingForUndo) text = 'Ждём ответа друга…';
    if (text == null && controller.computerThinking) {
      text = 'Компьютер думает…';
    }
    if (text == null && controller.isDraw) text = 'Ничья — отличная партия!';
    if (text == null &&
        controller.hintsEnabled &&
        widget.variant == GameVariant.giveaway) {
      text = 'В поддавках выгодно отдавать шашки!';
    }
    if (text == null && widget.mode == GameMode.network) {
      text = controller.isMyTurn ? 'Твой ход' : 'Ходит друг…';
    }
    text ??= 'Ходят ${controller.currentTurn == Side.white
        ? 'белые'
        : 'чёрные'}';
    final canDismiss =
        controller.notice != null || controller.hintText != null;
    return Container(
      key: const Key('message-bubble'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
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
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12,
                height: 1.25,
                color: const Color(0xFF795D38),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (canDismiss)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                key: const Key('message-dismiss'),
                padding: EdgeInsets.zero,
                iconSize: 18,
                onPressed: controller.hintText != null
                    ? controller.clearHint
                    : controller.clearNotice,
                tooltip: 'Скрыть',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF9A8060),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Кнопка «Подсказка» видна только тогда, когда её можно нажать: серой её не
  /// показываем. Во время серии взятия «Отменить ход» сменяется на «Закончить
  /// бой»: отменять половину серии — это незаметно откатить ход соперника.
  bool get _showHintButton =>
      controller.hintsEnabled &&
      controller.hintButtonEnabled &&
      (controller.hintThinking || controller.canInteract);

  Widget _actions({bool compact = false}) {
    final height = _actionHeight(compact);
    Widget? firstButton;
    if (controller.canFinishCapture) {
      firstButton = _ActionButton(
        key: const Key('finish-capture-button'),
        icon: Icons.done_all_rounded,
        label: 'Закончить бой',
        enabled: controller.canInteract,
        onTap: controller.finishCapture,
        highlighted: true,
        height: height,
      );
    } else if (controller.selectedPath.isEmpty) {
      firstButton = _ActionButton(
        key: const Key('undo-button'),
        icon: Icons.undo_rounded,
        label: 'Отменить ход',
        enabled: controller.canUndo,
        onTap: controller.undo,
        height: height,
      );
    }
    return Row(
      children: [
        if (firstButton != null) Expanded(child: firstButton),
        if (firstButton != null && _showHintButton) const SizedBox(width: 10),
        if (_showHintButton)
          Expanded(
            child: _ActionButton(
              key: const Key('hint-button'),
              icon: Icons.lightbulb_outline_rounded,
              label: controller.hintThinking ? 'Думаю…' : 'Подсказка',
              enabled: true,
              onTap: controller.showHint,
              highlighted: true,
              height: height,
            ),
          ),
      ],
    );
  }
}

/// Кнопка главного действия. Подпись всегда полноразмерная и не переносится:
/// `FittedBox(fit: BoxFit.scaleDown)` аккуратно уменьшает её на узком экране,
/// а не обрезает.
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
  final bool enabled, highlighted;
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: height >= 52 ? 16 : 15,
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

/// Картинка над текстом результата: корона со звёздами для победы, спокойная
/// шашка для ничьей или проигрыша.
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

  Widget _star({
    required double? top,
    required double? bottom,
    required double? left,
    required double? right,
    required Color color,
    required double size,
  }) => Positioned(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    child: Icon(Icons.star_rounded, color: color, size: size),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (_, _) => SizedBox(
      width: 150,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: .95 + animation.value * (widget.calm ? .04 : .1),
            child: CheckerIcon(size: 76, crown: !widget.calm),
          ),
          if (!widget.calm) ...[
            Positioned(
              top: 5 + animation.value * 5,
              left: 10,
              child: const Icon(
                Icons.star_rounded,
                color: Color(0xFFF5C254),
                size: 27,
              ),
            ),
            Positioned(
              top: 4,
              right: 8,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: purple.withValues(alpha: .7),
                size: 25,
              ),
            ),
            _star(
              top: null,
              bottom: 0,
              left: 22,
              right: null,
              color: const Color(0xFFFFB39D),
              size: 20,
            ),
            _star(
              top: null,
              bottom: 6,
              left: null,
              right: 18,
              color: const Color(0xFFB7DDAF),
              size: 19,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Доска: CustomPaint с тапами. Все подсветки (выбор, адресаты, подсказанные
/// шашки, лучший ход, движущаяся шашка) рисуются здесь. Анимацию хода и
/// пульсацию подсказки гоняет родительский `AnimatedBuilder` на тикере — он
/// обновляет [elapsed] и [animStart] на каждом кадре.
class CheckersBoardView extends StatelessWidget {
  const CheckersBoardView({
    super.key,
    required this.controller,
    required this.flipped,
    required this.elapsed,
    required this.animStart,
  });
  final CheckersController controller;
  final bool flipped;
  final Duration elapsed;
  final Duration animStart;

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
    child: Semantics(
      label: 'Игровая доска $_size на $_size',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          painter: _BoardPainter(
            controller: controller,
            flipped: flipped,
            elapsed: elapsed,
            animStart: animStart,
          ),
        ),
      ),
    ),
  );
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.controller,
    required this.flipped,
    required this.elapsed,
    required this.animStart,
  });
  final CheckersController controller;
  final bool flipped;
  final Duration elapsed;
  final Duration animStart;

  Offset _center(Square square, int n, double cell) {
    final row = flipped ? n - 1 - square.row : square.row;
    final col = flipped ? n - 1 - square.col : square.col;
    return Offset((col + .5) * cell, (row + .5) * cell);
  }

  void _ring(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double width,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  void _piece(
    Canvas canvas,
    Offset center,
    double cell,
    Piece piece, {
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final radius = cell * .37;
    final dark = piece.side == Side.black;
    canvas.saveLayer(
      Rect.fromCircle(center: center, radius: cell * .65),
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    // Тень от шашки — мягкий овал снизу.
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, cell * .18),
        width: radius * 2.05,
        height: radius * .8,
      ),
      Paint()
        ..color = const Color(0x660F0807)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Тёмная подложка по краю.
    canvas.drawCircle(
      center + Offset(0, cell * .065),
      radius,
      Paint()..color = dark ? const Color(0xFF1F1D26) : const Color(0xFFBCA985),
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Радиальный градиент тела шашки.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-.35, -.45),
          radius: 1.55,
          colors: dark
              ? const [
                  Color(0xFF777781),
                  Color(0xFF41414C),
                  Color(0xFF24232D),
                ]
              : const [
                  Color(0xFFFFFEF7),
                  Color(0xFFFFF2D9),
                  Color(0xFFCFBE9C),
                ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
    // Дамке — золотой ободок; у белой он темнее, чтобы был виден на светлом.
    final king = piece.king;
    if (king && !dark) {
      canvas.drawCircle(
        center,
        radius * .74,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, cell * .078)
          ..color = const Color(0xFF4A2F04),
      );
      canvas.drawCircle(
        center,
        radius * .74,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, cell * .042)
          ..color = const Color(0xFFF7B722),
      );
    } else {
      canvas.drawCircle(
        center,
        radius * .74,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, cell * .035)
          ..color = king
              ? const Color(0xFFFFDB6C)
              : (dark
                    ? const Color(0xFF73717A)
                    : const Color(0xFFD5C3A0)),
      );
    }
    // Световой блик сверху.
    canvas.drawArc(
      rect.deflate(radius * .18),
      math.pi * 1.12,
      math.pi * .62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, cell * .025)
        ..color = Colors.white.withValues(alpha: dark ? .3 : .72),
    );
    // Звезда для дамки.
    if (piece.king) {
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final r = radius * (i.isEven ? .42 : .20);
        final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          star.moveTo(p.dx, p.dy);
        } else {
          star.lineTo(p.dx, p.dy);
        }
      }
      star.close();
      if (!dark) {
        canvas.drawPath(
          star,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, cell * .03)
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF4A2F04),
        );
      }
      canvas.drawPath(
        star,
        Paint()
          ..color = dark
              ? const Color(0xFFF4C755)
              : const Color(0xFFF2AE12),
      );
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final board = controller.state.board;
    final n = board.size;
    final cell = size.width / n;

    // Клетки: градиент по диагонали, светлые и тёмные.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        final dark = (r + c).isOdd;
        final colors = dark
            ? [const Color(0xFF8C5A2C), const Color(0xFF69401F)]
            : [const Color(0xFFFFD65E), const Color(0xFFEFB94A)];
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ).createShader(rect),
        );
        canvas.drawRect(
          rect.deflate(.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .55
            ..color = Colors.white.withValues(alpha: dark ? .05 : .12),
        );
      }
    }

    // Подсветки видны только с включёнными подсказками.
    if (controller.hintsEnabled) {
      // Шашки, которыми можно начать ход, — когда ничего не выбрано.
      if (controller.selected == null && controller.selectedPath.isEmpty) {
        for (final square in controller.movablePieces) {
          final center = _center(square, n, cell);
          canvas.drawCircle(
            center,
            cell * .12,
            Paint()..color = const Color(0x558266D5),
          );
        }
      }
      // Выбранная шашка и клетки-адресаты.
      if (controller.selected != null || controller.selectedPath.isNotEmpty) {
        final selectedLocation = controller.selectedPath.isEmpty
            ? controller.selected!
            : controller.selectedPath.last;
        _ring(
          canvas,
          _center(selectedLocation, n, cell),
          cell * .44,
          const Color(0xFFFFF5B7),
          3,
        );
        for (final destination in controller.suggestedDestinations) {
          final center = _center(destination, n, cell);
          canvas.drawCircle(
            center,
            cell * .23,
            Paint()..color = const Color(0xAAFFF5BF),
          );
          canvas.drawCircle(
            center,
            cell * .11,
            Paint()..color = const Color(0xFFFCF6CE),
          );
        }
      }
      // Лучший ход — пульсирующее кольцо на from и двойной круг на to.
      final hint = controller.suggestedMove;
      if (hint != null) {
        final pulseTime = elapsed.inMicroseconds / 1000000.0;
        final pulse = 1.0 + .035 * math.sin(pulseTime * 5);
        _ring(
          canvas,
          _center(hint.from, n, cell),
          cell * .44 * pulse,
          const Color(0xFFFFEF9A),
          3.5,
        );
        final dest = _center(hint.landings.first, n, cell);
        canvas.drawCircle(
          dest,
          cell * .25 * pulse,
          Paint()..color = const Color(0xCCFFF2A3),
        );
        canvas.drawCircle(
          dest,
          cell * .12,
          Paint()..color = const Color(0xFFFFFCDF),
        );
      }
    }

    // Анимация хода: шашка скользит по landings, поднимаясь по синусоиде.
    final animation = controller.animation;
    if (animation != null) {
      final path = [animation.move.from, ...animation.move.landings];
      final totalMicros = math.max(
        1,
        animation.duration.inMicroseconds,
      );
      final elapsedMicros = (elapsed - animStart).inMicroseconds;
      final progress = (elapsedMicros / totalMicros *
              animation.move.landings.length)
          .clamp(0.0, animation.move.landings.length.toDouble());
      final segment = progress.floor().clamp(
        0,
        animation.move.landings.length - 1,
      );
      final t = (progress - segment).clamp(0.0, 1.0);
      final eased = Curves.easeInOut.transform(t);
      final from = _center(path[segment], n, cell);
      final to = _center(path[segment + 1], n, cell);
      // Все шашки, кроме движущейся и уже снятых в этой серии.
      for (final entry in animation.before.board.pieces.entries) {
        if (entry.key == animation.move.from) continue;
        final captureIndex = animation.move.captures.indexOf(entry.key);
        if (captureIndex >= 0 && captureIndex < segment) continue;
        final opacity = captureIndex == segment
            ? (1 - (t * 1.5).clamp(0.0, 1.0))
            : 1.0;
        _piece(
          canvas,
          _center(entry.key, n, cell),
          cell,
          entry.value,
          opacity: opacity,
        );
      }
      // Движущаяся шашка — становится дамкой, если серия прошла через край.
      var moving = animation.before.board.at(animation.move.from)!;
      if (!moving.king &&
          (controller.variant == GameVariant.russian ||
              controller.variant == GameVariant.giveaway) &&
          path
              .take(segment + 1)
              .any((p) => p.row == (moving.side == Side.white ? 0 : n - 1))) {
        moving = moving.crown();
      }
      final point = Offset.lerp(from, to, eased)! +
          Offset(0, -math.sin(math.pi * eased) * cell * .10);
      _piece(canvas, point, cell, moving);
      return;
    }

    // Статичная позиция — все шашки на своих местах, плюс «превью» серии.
    final preview = controller.selectedPath.isNotEmpty
        ? controller.selectedCandidates.firstOrNull
        : null;
    for (final entry in board.pieces.entries) {
      if (preview != null &&
          (entry.key == preview.from ||
              preview.captures
                  .take(controller.selectedPath.length)
                  .contains(entry.key))) {
        continue;
      }
      _piece(canvas, _center(entry.key, n, cell), cell, entry.value);
    }
    if (preview != null) {
      var moving = board.at(preview.from)!;
      if (!moving.king &&
          (controller.variant == GameVariant.russian ||
              controller.variant == GameVariant.giveaway) &&
          controller.selectedPath.any(
            (p) => p.row == (moving.side == Side.white ? 0 : n - 1),
          )) {
        moving = moving.crown();
      }
      _piece(
        canvas,
        _center(controller.selectedPath.last, n, cell),
        cell,
        moving,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      // Перерисовываем на каждом перестроении: доска читает состояние напрямую
      // из контроллера, а сравнение полей одного и того же контроллера в old и
      // new всегда даст равенство. Перестроение происходит только по тику
      // тикера или по уведомлению контроллера, так что лишних перерисовок нет.
      true;
}
