import 'dart:async';

import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../games/definition.dart';
import 'theme.dart';

/// Shared settings, plus the switches of one game when the page was opened
/// from that game's card.
///
/// The general block — sound, name and progress — is the same everywhere. The
/// game block is built from [GameDefinition.settings], so every game gets the
/// same rows as the sound switch without writing any UI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings, this.game});
  final SettingsController settings;

  /// Null when the page is opened from the main menu: only the general block.
  final GameDefinition? game;

  @override
  Widget build(BuildContext context) {
    final current = game;
    return PageFrame(
      title: 'Настройки',
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            const Intro(
              eyebrow: 'ВСЁ ПОД ТЕБЯ',
              title: 'Как тебе удобнее?',
              subtitle: 'Настрой игру так, чтобы она приносила радость.',
            ),
            const SizedBox(height: 26),
            if (current != null) ...[
              Text(
                current.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
              for (final setting in current.settings)
                _SettingsSwitch(
                  key: Key('game-flag-${current.id}-${setting.key}'),
                  icon: setting.icon,
                  title: setting.title,
                  subtitle: setting.subtitle,
                  value: settings.flag(current.id, setting.key),
                  onChanged: (value) =>
                      settings.setFlag(current.id, setting.key, value),
                ),
              const SizedBox(height: 10),
            ],
            _SettingsSwitch(
              icon: Icons.volume_up_rounded,
              title: 'Звуки игры',
              subtitle: 'Мягкие звуки и мелодии',
              value: settings.sound,
              onChanged: settings.setSound,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Твоё имя',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Так тебя увидит друг в сети',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NameField(settings: settings),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                final reset = await showDianaDialog<bool>(
                  context: context,
                  title: 'Сбросить прогресс?',
                  content: const Text(
                    'Счётчик партий и побед станет равен нулю. '
                    'Настройки останутся.',
                    textAlign: TextAlign.center,
                    style: dialogTextStyle,
                  ),
                  actions: const [
                    DianaDialogButton<bool>(
                      label: 'Не сейчас',
                      value: false,
                      primary: true,
                    ),
                    DianaDialogButton<bool>(label: 'Сбросить', value: true),
                  ],
                );
                if (reset == true) await settings.resetProgress();
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Сбросить прогресс'),
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
      ),
    );
  }
}

/// The player name.
///
/// The field keeps its own text while it is focused. Earlier the whole settings
/// page was rebuilt on every keystroke and the name was written back into the
/// field, so Android lost the text input connection and the keyboard closed —
/// the name could not be changed at all. Now the text is committed when the
/// child presses «Готово» or taps anywhere else.
class _NameField extends StatefulWidget {
  const _NameField({required this.settings});
  final SettingsController settings;
  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.settings.nickname,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  /// Keeps the field in sight when the keyboard pushes the page up.
  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _commit();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        alignment: .35,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  void _commit() {
    unawaited(widget.settings.setNickname(_text.text));
    // Show exactly what was stored: trimmed, and cut to twenty characters.
    final stored = widget.settings.nickname;
    if (_text.text != stored) {
      _text.value = TextEditingValue(
        text: stored,
        selection: TextSelection.collapsed(offset: stored.length),
      );
    }
  }

  @override
  void dispose() {
    // Leaving the page while the field is focused must not lose the name. The
    // write is deferred by a microtask, because a notification during the build
    // that removes this widget would rebuild a half-torn tree.
    final typed = _text.text;
    if (typed != widget.settings.nickname) {
      scheduleMicrotask(() => widget.settings.setNickname(typed));
    }
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('nickname-field'),
    controller: _text,
    focusNode: _focus,
    maxLength: 20,
    textCapitalization: TextCapitalization.words,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _focus.unfocus(),
    onTapOutside: (_) => _focus.unfocus(),
    decoration: InputDecoration(
      hintText: 'Например, Диана',
      counterText: '',
      filled: true,
      fillColor: cream,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  // A Material, not a decorated Container: a ListTile paints its background and
  // ink splashes on the nearest Material, so a coloured box in between hides
  // them — Flutter asserts about exactly that in debug builds.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: purple,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFF1EAFB),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: purple),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
