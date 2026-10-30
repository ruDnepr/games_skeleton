import 'package:flutter/material.dart';

import 'theme.dart';

/// A polite placeholder: the game is in the catalogue, but its session screen
/// does not exist yet.
///
/// It promises nothing. The child sees that the frame is ready and that the
/// game itself is still to come, and closes the screen with one big button.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    this.note,
    this.buttonKey = const Key('coming-soon-ok'),
  });
  final String title;
  final String? note;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: title,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Intro(
          eyebrow: 'ПАРТИИ ПОКА НЕТ',
          title: 'Здесь будет партия',
          subtitle:
              note ??
              'Каркас готов: правила, настройки и сетевая игра уже работают. '
                  'Сама партия появится вместе с игрой.',
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            key: buttonKey,
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Понятно'),
          ),
        ),
      ],
    ),
  );
}
