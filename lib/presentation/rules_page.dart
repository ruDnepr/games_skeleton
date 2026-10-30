import 'package:flutter/material.dart';

import '../games/definition.dart';
import 'theme.dart';

/// Rules of one game, drawn from the cards the game declares.
///
/// The screen itself knows nothing about any particular game: it walks the list
/// the game gave it, in the order the game gave it.
class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.game});
  final GameDefinition game;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Правила',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Intro(
          eyebrow: 'УЧИМСЯ ИГРАЯ',
          title: 'Это просто!',
          subtitle: game.tagline,
        ),
        const SizedBox(height: 24),
        for (final card in game.rules)
          _RuleCard(key: Key('rule-card-${card.number}'), card: card),
        const SizedBox(height: 14),
        const Text(
          'Ошибаться и пробовать снова — это нормально! ✨',
          style: TextStyle(
            color: purple,
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({super.key, required this.card});
  final RuleCard card;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFF4E7C4),
          child: Text(
            '${card.number}',
            style: const TextStyle(color: ink, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                card.text,
                style: const TextStyle(
                  fontSize: 13,
                  color: muted,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
