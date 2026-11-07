import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'game_page.dart';
import 'go_controller.dart';
import 'network.dart';
import 'setup_pages.dart';

/// Точка входа в партию: с сетевым соединением — сразу партия по сети тем
/// режимом и размером доски, которые выбрал хост до лобби; без него —
/// пошаговый выбор (режим → размер → сложность → жеребьёвка цвета).
class GoEntryPage extends StatelessWidget {
  const GoEntryPage({
    super.key,
    required this.settings,
    this.network,
  });
  final SettingsController settings;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    if (network != null) {
      // Хост выбрал режим, размер, цель и сторону до создания сетевой игры;
      // клиент принимает то, что пришло в рукопожатии. Хост играет выбранной
      // стороной и ходит первым, если выбрал чёрных.
      final options = optionsFromLobby(network!);
      final mySide = network!.isHost
          ? options.hostSide
          : options.hostSide.opponent;
      final setup = AppGameSetup(
        mode: options.mode,
        boardSize: options.boardSize,
        playerSide: mySide,
        captureTarget: options.captureTarget,
        komi: GameSetup.defaultKomi(options.boardSize),
        appMode: AppGameMode.network,
        network: network,
      );
      return GoGamePage(settings: settings, setup: setup);
    }
    return GoModePage(settings: settings);
  }
}
