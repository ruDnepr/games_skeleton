import 'package:flutter/material.dart';

import '../../presentation/coming_soon_page.dart';
import '../definition.dart';

/// Entry point of the example game's session.
///
/// A real game opens its board here and, when [network] is not null, reads the
/// opponent's moves from `network.service.events`, checking each one with the
/// game's own rule check. The example has no board yet, so it says so honestly
/// and closes with one button.
class ExampleSessionPage extends StatelessWidget {
  const ExampleSessionPage({super.key, this.network});
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) => ComingSoonPage(
    title: 'Игра-пример',
    note: network == null
        ? null
        : 'С другом по сети соединение уже есть, но партии пока нет: '
              'она появится вместе с самой игрой.',
  );
}
