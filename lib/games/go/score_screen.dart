import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../presentation/theme.dart';
import 'board_game.dart';
import 'engine/model.dart';
import 'engine/scoring.dart';
import 'game_page.dart';
import 'go_controller.dart';

class GoScoreScreen extends StatelessWidget {
  const GoScoreScreen({
    super.key,
    required this.settings,
    required this.controller,
  });
  final SettingsController settings;
  final GoController controller;

  @override
  Widget build(BuildContext context) {
    final w = controller.winner;
    final setup = controller.setup;
    final isLocal = setup.appMode == AppGameMode.local;
    final iWon = w == setup.playerSide;
    final title = _title(w, isLocal, iWon);
    final message = _message(w, isLocal, iWon);

    return PageFrame(
      title: 'Партия закончена',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          const SizedBox(height: 8),
          Center(child: _WinnerStone(winner: w)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: ink,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: muted,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (setup.mode == GoMode.classic)
            _ClassicScore(controller: controller),
          if (setup.mode == GoMode.capture)
            _CaptureScore(controller: controller),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    GoGamePage(settings: settings, setup: setup),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Играть снова'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.home_rounded),
            label: const Text('В меню'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 54),
              foregroundColor: purple,
              side: const BorderSide(color: Color(0xFFDAD0ED)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _title(StoneColor? w, bool isLocal, bool iWon) {
    if (w == null) return 'Ничья — отличная партия!';
    if (isLocal) return '${w.label} победили!';
    return iWon ? 'Ты выиграла!' : 'В этот раз соперник сильнее';
  }

  String _message(StoneColor? w, bool isLocal, bool iWon) {
    if (w == null) return 'Каждая партия делает тебя сильнее.';
    if (isLocal) return 'Отличная игра обоих!';
    if (iWon) {
      return 'Отлично сыграла! Го — это путь, и ты делаешь первые уверенные шаги.';
    }
    return 'Не беда — в го даже мастера проигрывают. Попробуй ещё раз!';
  }
}

class _WinnerStone extends StatelessWidget {
  const _WinnerStone({required this.winner});
  final StoneColor? winner;
  @override
  Widget build(BuildContext context) {
    if (winner == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoneIcon(size: 56),
          SizedBox(width: 12),
          StoneIcon(dark: true, size: 56),
        ],
      );
    }
    return StoneIcon(dark: winner == StoneColor.black, size: 80);
  }
}

class _CaptureScore extends StatelessWidget {
  const _CaptureScore({required this.controller});
  final GoController controller;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            _Row(
              label: 'Чёрные сняли',
              value: '${controller.state.blackCaptured}',
            ),
            const SizedBox(height: 8),
            _Row(
              label: 'Белые сняли',
              value: '${controller.state.whiteCaptured}',
            ),
            const SizedBox(height: 8),
            _Row(
              label: 'Цель',
              value:
                  '${controller.setup.captureTarget.count} ${controller.setup.captureTarget.count == 1 ? 'камень' : 'камня'}',
              emphasize: true,
            ),
          ],
        ),
      );
}

class _ClassicScore extends StatelessWidget {
  const _ClassicScore({required this.controller});
  final GoController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.rules.score(controller.state) ??
        controller.finalScore;
    if (s == null) {
      return const Text(
        'Счёт не подсчитан.',
        style: TextStyle(color: muted, fontWeight: FontWeight.w700),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Подсчёт очков',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _ScoreColumn(color: StoneColor.black, s: s),
          const Divider(height: 24),
          _ScoreColumn(color: StoneColor.white, s: s),
          const SizedBox(height: 12),
          _Row(
            label: 'Разница',
            value: (s.difference.abs() < 0.01
                ? '0'
                : (s.difference > 0
                    ? '+${s.difference.toStringAsFixed(1)} чёрным'
                    : '+${(-s.difference).toStringAsFixed(1)} белым')),
            emphasize: true,
          ),
        ],
      ),
    );
  }
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
            StoneIcon(dark: color == StoneColor.black, size: 26),
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
                fontSize: 22,
                color: purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Row(
          label: 'Территория',
          value:
              '${color == StoneColor.black ? s.blackTerritory : s.whiteTerritory}',
        ),
        const SizedBox(height: 6),
        _Row(
          label: 'Пленники',
          value:
              '${color == StoneColor.black ? s.blackCaptured : s.whiteCaptured}',
        ),
        if (color == StoneColor.white) ...[
          const SizedBox(height: 6),
          _Row(label: 'Коми', value: s.komi.toStringAsFixed(1)),
        ],
        if ((color == StoneColor.black ? s.deadWhite : s.deadBlack) > 0) ...[
          const SizedBox(height: 6),
          _Row(
            label: 'Мёртвые у соперника',
            value:
                '${color == StoneColor.black ? s.deadWhite : s.deadBlack}',
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});
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
