import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../presentation/theme.dart';
import '../definition.dart';
import 'engine/model.dart';
import 'network.dart';
import 'rules.dart';
import 'session_page.dart';
import 'settings.dart';

/// Игра «Лото» в каталоге. Карточка, правила, настройки и точка входа в
/// партию — всё здесь; главное окно, список игр, лобби и звук общие.
final lotoGame = GameDefinition(
  id: lotoGameId,
  title: 'Лото',
  tagline: 'Закрывай числа и собирай строку',
  icon: Icons.bubble_chart_rounded,
  accent: yellow,
  rules: lotoRules,
  settings: lotoSettings,
  // Кнопка «Играть» на карточке и сетевое лобби ведут сюда. Когда друг уже
  // подключился, [network] заполнен и партия сразу открывается по сети.
  start: (context, settings, {network}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LotoEntryPage(settings: settings, network: network),
      ),
    );
  },
  options: lotoOptions,
  parseOptions: lotoParseOptions,
  validateMove: lotoValidateMove,
  // Хост — ведущий: он тянет бочонки и объявляет их. Просто и предсказуемо.
  hostSide: (_) => 'host',
  // Перед сетевой игрой хост выбирает, как побеждать: по строке или по всей
  // карточке. Выбор хранится в настройках и уходит в рукопожатие — клиент
  // получит то же правило.
  preNetwork: lotoPreNetwork,
);

/// Экран выбора режима победы перед сетевым лобби. Открывается только у хоста:
/// именно он решает, по каким правилам будет идти партия.
Future<void> lotoPreNetwork(
  BuildContext context,
  SettingsController settings,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LotoWinModePage(settings: settings),
    ),
  );
}

/// Экран выбора режима победы для сетевой партии. Тот же выбор, что и на
/// странице начала партии на одном устройстве, но без выбора режима игры —
/// режим всегда сетевой.
class LotoWinModePage extends StatefulWidget {
  const LotoWinModePage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<LotoWinModePage> createState() => _LotoWinModePageState();
}

class _LotoWinModePageState extends State<LotoWinModePage> {
  late WinMode _winMode = WinMode.fromName(
    widget.settings.gameString(lotoGameId, lotoWinModeKey, WinMode.row.name),
  );

  Future<void> _choose(WinMode mode) async {
    setState(() => _winMode = mode);
    await widget.settings
        .setGameString(lotoGameId, lotoWinModeKey, mode.name);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Лото',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Intro(
          eyebrow: 'ДО СЕТЕВОЙ ПАРТИИ',
          title: 'Как побеждаем?',
          subtitle: 'Хост решает правило победы для всех игроков.',
        ),
        const SizedBox(height: 22),
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
            onTap: () => _choose(mode),
            tag: mode == WinMode.row ? '5 чисел' : '15 чисел',
          ),
        const SizedBox(height: 22),
        BigButton(
          key: const Key('loto-win-next'),
          title: 'Дальше',
          subtitle: 'Открыть сетевое лобби',
          icon: Icons.play_arrow_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}
