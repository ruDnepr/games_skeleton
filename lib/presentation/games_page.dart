import 'package:flutter/material.dart';

import '../app/catalog.dart';
import '../app/settings.dart';
import '../games/definition.dart';
import 'network_page.dart';
import 'rules_page.dart';
import 'settings_page.dart';
import 'theme.dart';

/// Why the game list was opened.
enum GamesPurpose {
  /// «Играть» — the card starts the game on this device.
  play,

  /// «Сетевая игра» — the card opens the lobby for that game.
  network,
}

/// The list of games from [GameCatalog].
///
/// It never mentions a particular game: every card is built from its
/// [GameDefinition], and tapping it asks the game where to go.
class GamesPage extends StatelessWidget {
  const GamesPage({
    super.key,
    required this.settings,
    this.purpose = GamesPurpose.play,
  });
  final SettingsController settings;
  final GamesPurpose purpose;

  bool get _forNetwork => purpose == GamesPurpose.network;

  Future<void> _open(BuildContext context, GameDefinition game) async {
    if (_forNetwork) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NetworkPage(settings: settings, game: game),
        ),
      );
      return;
    }
    await game.start(context, settings);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: _forNetwork ? 'Сетевая игра' : 'Играть',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Intro(
          eyebrow: _forNetwork ? 'ИГРАЙ С ДРУГОМ' : 'ВЫБЕРИ ИГРУ',
          title: 'Во что сыграем?',
          subtitle: _forNetwork
              ? 'Выбери игру, а потом создай её или подключись к другу по коду.'
              : 'У каждой игры свои правила, настройки и партия.',
        ),
        const SizedBox(height: 25),
        for (final game in GameCatalog.games)
          _GameCard(
            game: game,
            onPlay: () => _open(context, game),
            onRules: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RulesPage(game: game),
              ),
            ),
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(settings: settings, game: game),
              ),
            ),
          ),
      ],
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.onPlay,
    required this.onRules,
    required this.onSettings,
  });
  final GameDefinition game;
  final VoidCallback onPlay;
  final VoidCallback onRules;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF2EAE3)),
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
      child: Column(
        children: [
          InkWell(
            key: Key('game-card-${game.id}'),
            onTap: onPlay,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: game.accent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      game.icon,
                      color: ink.withValues(alpha: .8),
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          game.tagline,
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
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: purple,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF2EAE3)),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: Key('game-rules-${game.id}'),
                  onPressed: onRules,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('Правила'),
                  style: _cardActionStyle(),
                ),
              ),
              const SizedBox(
                width: 1,
                height: 26,
                child: ColoredBox(color: Color(0xFFF2EAE3)),
              ),
              Expanded(
                child: TextButton.icon(
                  key: Key('game-settings-${game.id}'),
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Настройки'),
                  style: _cardActionStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  static ButtonStyle _cardActionStyle() => TextButton.styleFrom(
    foregroundColor: purple,
    minimumSize: const Size(48, 48),
    textStyle: const TextStyle(
      fontFamily: 'Nunito',
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  );
}
