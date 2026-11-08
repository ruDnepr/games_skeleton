import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../app/sounds.dart';
import '../../presentation/games_page.dart' show popToGamesList;
import '../../presentation/theme.dart';
import '../definition.dart';
import 'car_painter.dart';
import 'car_style.dart';
import 'engine/levels.dart';
import 'engine/model.dart';
import 'lot_painter.dart';
import 'network.dart';
import 'progress.dart';
import 'push_hour_controller.dart';

/// Точка входа в партию: с сетевым соединением — сразу поле, без него — выбор
/// уровня. Логика маршрутизации одна, чтобы и карточка игры, и сетевое лобби
/// приходили в одно место.
class PushHourEntryPage extends StatelessWidget {
  const PushHourEntryPage({
    super.key,
    required this.settings,
    required this.progress,
    required this.level,
    this.network,
  });

  final SettingsController settings;
  final PushHourProgress progress;
  final Level level;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      return PushHourSessionPage(
        settings: settings,
        progress: progress,
        level: level,
        network: network,
      );
    }
    return PushHourLevelsPage(settings: settings, progress: progress);
  }
}

/// Сетка из ста уровней: наборы по десять, статусы «открыт/пройден» и звёзды.
class PushHourLevelsPage extends StatefulWidget {
  const PushHourLevelsPage({
    super.key,
    required this.settings,
    required this.progress,
  });

  final SettingsController settings;
  final PushHourProgress progress;

  @override
  State<PushHourLevelsPage> createState() => _PushHourLevelsPageState();
}

class _PushHourLevelsPageState extends State<PushHourLevelsPage> {
  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  void _openLevel(Level level) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PushHourSessionPage(
          settings: widget.settings,
          progress: widget.progress,
          level: level,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Push Hour',
    child: ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final showNumbers = widget.settings.flag(pushHourGameId, 'numbers');
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            const Intro(
              eyebrow: 'КАМПАНИЯ',
              title: '100 пробок',
              subtitle: 'Открывай уровни по очереди. Побей рекорд — получи '
                  'звёзды!',
            ),
            const SizedBox(height: 18),
            for (var setIndex = 0; setIndex < levelSets.length; setIndex++)
              _LevelSet(
                title: campaignSetTitles[setIndex],
                levels: levelSets[setIndex],
                progress: widget.progress,
                showNumbers: showNumbers,
                onOpen: _openLevel,
              ),
          ],
        );
      },
    ),
  );
}

class _LevelSet extends StatelessWidget {
  const _LevelSet({
    required this.title,
    required this.levels,
    required this.progress,
    required this.showNumbers,
    required this.onOpen,
  });

  final String title;
  final List<Level> levels;
  final PushHourProgress progress;
  final bool showNumbers;
  final ValueChanged<Level> onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Пять уровней в ряду — большие и удобные для пальца ребёнка.
            const columns = 5;
            const spacing = 10.0;
            // floors расчёт: запас в 1 пиксель гарантирует, что при любой
            // ширине пять плиток точно поместятся в ряд (иначе Wrap из-за
            // ошибок округления может упаковать по четыре).
            final side =
                ((constraints.maxWidth - spacing * (columns - 1)) / columns)
                    .floorToDouble();
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final level in levels)
                  _LevelTile(
                    level: level,
                    side: side,
                    open: progress.isOpen(level.number),
                    best: progress.bestFor(level.number),
                    stars: progress.bestFor(level.number) == null
                        ? 0
                        : progress.stars(
                            level.number,
                            progress.bestFor(level.number)!,
                          ),
                    showNumber: showNumbers,
                    onTap: () => onOpen(level),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.side,
    required this.open,
    required this.best,
    required this.stars,
    required this.showNumber,
    required this.onTap,
  });

  final Level level;
  final double side;
  final bool open;
  final int? best;
  final int stars;
  final bool showNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final solved = best != null;
    final color = !open
        ? const Color(0xFFE5E1EE)
        : solved
              ? const Color(0xFFDDF1DF)
              : const Color(0xFFFFE5A3);
    final icon = !open
        ? Icons.lock_rounded
        : solved
              ? Icons.check_circle_rounded
              : Icons.play_arrow_rounded;
    return SizedBox(
      width: side,
      height: side,
      key: Key('level-tile-${level.number}'),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: open ? onTap : null,
          child: Padding(
            padding: EdgeInsets.all(side * 0.10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: side * 0.36, color: ink.withValues(alpha: .8)),
                SizedBox(height: side * 0.04),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${level.number}',
                    style: TextStyle(
                      fontSize: side * 0.22,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ),
                if (showNumber && solved) ...[
                  SizedBox(height: side * 0.02),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$best ходов',
                      style: TextStyle(
                        fontSize: side * 0.13,
                        fontWeight: FontWeight.w800,
                        color: muted,
                      ),
                    ),
                  ),
                ],
                if (solved) ...[
                  SizedBox(height: side * 0.02),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Icon(
                          i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: side * 0.18,
                          color: const Color(0xFFFFB23E),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Экран партии: поле 6x6, ходы, подсказки, отмена и сетевая гонка.
class PushHourSessionPage extends StatefulWidget {
  const PushHourSessionPage({
    super.key,
    required this.settings,
    required this.progress,
    required this.level,
    this.network,
  });

  final SettingsController settings;
  final PushHourProgress progress;
  final Level level;
  final NetworkSession? network;

  @override
  State<PushHourSessionPage> createState() => _PushHourSessionPageState();
}

class _PushHourSessionPageState extends State<PushHourSessionPage> {
  late final GameSounds _sounds;
  late final PushHourController _controller;

  @override
  void initState() {
    super.initState();
    _sounds = GameSounds(widget.settings);
    _controller = PushHourController(
      settings: widget.settings,
      sounds: _sounds,
      progress: widget.progress,
      level: widget.level,
      network: widget.network,
    );
    _controller.addListener(_onController);
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    // Диалоги показываем после кадра: слушатель может сработать во время
    // построения, а showDialog нельзя звать из build.
    if (_controller.solved && !_winShown) {
      _winShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.solved) _showWinDialog();
      });
    }
    // Победа друга пришла по сети — показываем диалог, если сами ещё не выиграли.
    if (_controller.remoteSolved && !_controller.solved && !_remoteShown) {
      _remoteShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.remoteSolved && !_controller.solved) {
          _showRemoteWinDialog();
        }
      });
    }
  }

  bool _winShown = false;
  bool _remoteShown = false;

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    super.dispose();
  }

  /// Один свайп — один ход: машина едет сразу во время жеста, не дожидаясь
  /// отпускания пальца. Для теста достаточно сдвига в полклетки.
  void _dragCar(Car car, double delta) {
    // Знак дельты решает направление: вправо/вниз — +1, влево/вверх — -1.
    // Ось уже учтена при накоплении: горизонтальная копит dx, вертикальная dy.
    final step = delta > 0 ? 1 : -1;
    _controller.tryMove(car, step, quiet: true);
  }

  // ------------------------------------------------------------ диалоги

  Future<void> _showWinDialog() async {
    final moves = _controller.moves;
    final stars = widget.progress.stars(_controller.level.number, moves);
    final answer = await showDianaDialog<String>(
      context: context,
      title: 'Уровень пройден! 🎉',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Красная машина на свободе за $moves '
            '${_pluralMoves(moves)} и ${_formatTime(_controller.seconds)}.',
            textAlign: TextAlign.center,
            style: dialogTextStyle,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  i < stars
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 36,
                  color: const Color(0xFFFFB23E),
                ),
            ],
          ),
        ],
      ),
      actions: [
        DianaDialogButton<String>(
          label: _controller.hasNextLevel ? 'Следующий уровень' : 'В меню',
          value: 'next',
          primary: true,
          key: const Key('session-next'),
        ),
        DianaDialogButton<String>(
          label: 'В меню',
          value: 'menu',
          key: const Key('session-menu'),
        ),
      ],
    );
    if (!mounted) return;
    // Сбрасываем флаг: на следующем уровне диалог победы снова нужен.
    _winShown = false;
    if (answer == 'next') {
      if (_controller.hasNextLevel) {
        _controller.goToNextLevel();
      } else {
        popToGamesList(context);
      }
    } else {
      popToGamesList(context);
    }
  }

  Future<void> _showRemoteWinDialog() async {
    final answer = await showDianaDialog<String>(
      context: context,
      title: '${_controller.remoteName} уже выехал!',
      content: Text(
        '${_controller.remoteName} решил уровень за '
        '${_controller.remoteMoves} ${_pluralMoves(_controller.remoteMoves)}. '
        'Доиграешь свой уровень?',
        textAlign: TextAlign.center,
        style: dialogTextStyle,
      ),
      actions: [
        DianaDialogButton<String>(
          label: 'Играть дальше',
          value: 'continue',
          primary: true,
        ),
        DianaDialogButton<String>(
          label: 'В меню',
          value: 'menu',
        ),
      ],
    );
    if (!mounted) return;
    if (answer != 'continue') {
      popToGamesList(context);
    }
  }

  static String _pluralMoves(int moves) {
    final tail = moves % 100;
    if (tail >= 11 && tail <= 14) return 'ходов';
    switch (moves % 10) {
      case 1:
        return 'ход';
      case 2:
      case 3:
      case 4:
        return 'хода';
      default:
        return 'ходов';
    }
  }

  static String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  // ------------------------------------------------------------ отрисовка

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(_controller.level.title),
        ),
        actions: [
          IconButton(
            key: const Key('session-hint'),
            tooltip: 'Подсказка',
            onPressed: _controller.solved ? null : _onHint,
            icon: const Icon(Icons.lightbulb_rounded),
          ),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => IconButton(
              key: const Key('session-sound'),
              tooltip: widget.settings.sound
                  ? 'Звук включён'
                  : 'Звук выключен',
              onPressed: () =>
                  widget.settings.setSound(!widget.settings.sound),
              icon: Icon(
                widget.settings.sound
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
              ),
            ),
          ),
          IconButton(
            key: const Key('session-restart'),
            tooltip: 'Начать уровень заново',
            onPressed: _controller.restart,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Column(
                  children: [
                    _statusBar(),
                    const SizedBox(height: 10),
                    Expanded(child: RepaintBoundary(child: _board())),
                    const SizedBox(height: 10),
                    SizedBox(height: _hintLineHeight, child: _hintLine()),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('session-undo'),
                      onPressed:
                          _controller.history.isEmpty ? null : _controller.undo,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Отмена'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        foregroundColor: purple,
                        side: const BorderSide(color: Color(0xFFDAD0ED)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _onHint() {
    final result = _controller.requestHint();
    if (result == null) return;
    if (!result) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Подсказку здесь не найти — попробуй «Заново».',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Счётчики в одну строку: одинаковая ширина, текст никогда не переносится.
  Widget _statusBar() => SizedBox(
    height: _badgesHeight,
    child: Row(
      children: [
        Expanded(
          child: _Badge(
            icon: Icons.touch_app_rounded,
            text: 'Ходы: ${_controller.moves}',
            color: const Color(0xFFEDE6FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Badge(
            icon: Icons.timer_outlined,
            text: 'Время: ${_formatTime(_controller.seconds)}',
            color: const Color(0xFFFCE4D7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Badge(
            icon: Icons.flag_rounded,
            text: 'Минимум: ${_controller.level.minMoves}',
            color: const Color(0xFFDDF1DF),
          ),
        ),
        if (_controller.hasNetwork) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _Badge(
              icon: Icons.wifi_rounded,
              text: _controller.remoteSolved
                  ? '${_controller.remoteName}: выехал'
                  : '${_controller.remoteName}: ${_controller.remoteMoves}',
              color: const Color(0xFFFFE9A8),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _hintLine() {
    final hint = _controller.hint;
    final solved = _controller.solved;
    final active = hint != null && !solved;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFFFF1C9)
            : Colors.white.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? const Color(0xFFFFD873) : const Color(0xFFEDE6F5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.lightbulb_rounded
                : solved
                ? Icons.emoji_events_rounded
                : Icons.touch_app_rounded,
            size: 18,
            color: active
                ? const Color(0xFF9A6B00)
                : solved
                ? deepPurple
                : muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _hintText(hint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: active
                    ? const Color(0xFF7A5200)
                    : solved
                    ? deepPurple
                    : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hintText(Move? hint) {
    if (_controller.solved) {
      return 'Готово! Ходов: ${_controller.moves}, '
          'время: ${_formatTime(_controller.seconds)}';
    }
    if (hint != null) {
      return 'Подсказка: сдвинь ${_carName(hint)} ${_direction(hint)}.';
    }
    return '${levelDifficulty(_controller.level.minMoves)} · тяни машину или '
        'нажми на неё, чтобы сдвинуть на клетку.';
  }

  /// Название машины цветом: «красную машину», «жёлтую машину».
  String _carName(Move hint) {
    final car = _controller.grid.carById(hint.carId);
    if (car == null) return 'машину';
    if (car.isRed) return 'красную машину';
    return carColorAccusative(car.color);
  }

  static String _direction(Move hint) {
    if (hint.to.col != hint.from.col) {
      return hint.to.col > hint.from.col ? 'вправо' : 'влево';
    }
    return hint.to.row > hint.from.row ? 'вниз' : 'вверх';
  }

  Widget _board() => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, constraints.maxHeight);
      final cell = side / boardSize;
      final hint = _controller.hint;
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cell * 0.32),
              boxShadow: [
                BoxShadow(
                  color: ink.withValues(alpha: .30),
                  blurRadius: cell * 0.55,
                  offset: Offset(0, cell * 0.20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cell * 0.32),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: LotPainter(cell: cell)),
                  ),
                  for (final car in _controller.grid.cars)
                    AnimatedPositioned(
                      key: ValueKey<String>('car-${car.id}'),
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                      left: car.position.col * cell + cell * 0.03,
                      top: car.position.row * cell + cell * 0.03,
                      width:
                          (car.isHorizontal ? car.length : 1) * cell -
                          cell * 0.06,
                      height:
                          (car.isHorizontal ? 1 : car.length) * cell -
                          cell * 0.06,
                      child: _carWidget(car, cell),
                    ),
                  if (hint != null) ..._hintOverlay(hint, cell),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  /// Крупная пульсирующая стрелка в той клетке, куда поедет машина.
  List<Widget> _hintOverlay(Move hint, double cell) {
    final car = _controller.grid.carById(hint.carId);
    if (car == null) return const <Widget>[];
    final horizontal = car.isHorizontal;
    final step = horizontal
        ? hint.to.col - hint.from.col
        : hint.to.row - hint.from.row;
    final double left;
    final double top;
    if (horizontal) {
      left = (car.position.col + (step > 0 ? car.length : -1)) * cell;
      top = car.position.row * cell;
    } else {
      left = car.position.col * cell;
      top = (car.position.row + (step > 0 ? car.length : -1)) * cell;
    }
    final rotation = horizontal
        ? (step > 0 ? 0.0 : math.pi)
        : (step > 0 ? math.pi / 2 : -math.pi / 2);
    return <Widget>[
      Positioned(
        left: left,
        top: top,
        width: cell,
        height: cell,
        child: RepaintBoundary(
          child: IgnorePointer(child: _HintArrow(rotation: rotation, size: cell)),
        ),
      ),
    ];
  }

  Widget _carWidget(Car car, double cell) {
    final hint = _controller.hint;
    final hinted = hint != null && hint.carId == car.id;
    return GestureDetector(
      key: Key('car-tap-${car.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.tapCar(car),
      onPanStart: (_) {
        _dragDelta = 0;
        _dragMoved = false;
      },
      onPanUpdate: (details) {
        if (_dragMoved) return;
        _dragDelta += car.isHorizontal
            ? details.delta.dx
            : details.delta.dy;
        if (_dragDelta.abs() < cell * 0.25) return;
        _dragMoved = true;
        _dragCar(car, _dragDelta);
      },
      onPanEnd: (_) => _dragDelta = 0,
      onPanCancel: () => _dragDelta = 0,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: CarPainter(
            color: car.color,
            length: car.length,
            vertical: !car.isHorizontal,
            highlighted: hinted,
          ),
        ),
      ),
    );
  }

  /// Накопленное движение пальца по оси машины (один общий счётчик: жест
  /// в один момент времени только один).
  double _dragDelta = 0;

  /// Один свайп — один ход: дальше палец можно вести, но машина уже поехала.
  bool _dragMoved = false;
}

/// Высота строки-подсказки. Фиксирована, чтобы появление подсказки
/// не меняло размер поля: иначе машины «прыгают» на новое место.
const double _hintLineHeight = 54;

/// Высота полосы со счётчиками.
const double _badgesHeight = 44;

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, size: 14, color: ink.withValues(alpha: .75)),
        const SizedBox(width: 4),
        // FittedBox: текст счётчика всегда в одну строку, даже на узком экране.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Пульсирующая стрелка подсказки: показывает, куда поедет машина.
class _HintArrow extends StatefulWidget {
  const _HintArrow({required this.rotation, required this.size});

  final double rotation;
  final double size;

  @override
  State<_HintArrow> createState() => _HintArrowState();
}

class _HintArrowState extends State<_HintArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: .60 + .40 * _controller.value,
      child: Transform.scale(scale: .82 + .28 * _controller.value, child: child),
    ),
    child: Center(
      child: Container(
        padding: EdgeInsets.all(widget.size * 0.13),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFC53D).withValues(alpha: .75),
              blurRadius: widget.size * 0.45,
            ),
          ],
        ),
        child: Transform.rotate(
          angle: widget.rotation,
          child: Icon(
            Icons.arrow_forward_rounded,
            size: widget.size * 0.55,
            color: const Color(0xFFC78800),
          ),
        ),
      ),
    ),
  );
}
