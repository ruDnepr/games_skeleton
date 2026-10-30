import '../../app/settings.dart';

/// Identifier of the example game: the storage prefix of its settings and the
/// field both devices compare during the network handshake.
///
/// Latin letters only, no spaces. A real game picks its own and keeps it
/// forever, because stored switches and old invitations carry it.
const exampleGameId = 'example';

/// One square of the eight-by-eight board the example pretends to have.
final _squarePattern = RegExp(r'^[a-h][1-8]$');

/// What the example game tells the opponent about itself.
///
/// The framework only carries this map; the meaning belongs to the game. Here
/// it is exactly the two switches the game declares, so nothing is invented.
Map<String, Object?> exampleOptions(SettingsController settings) => {
  'reminder': settings.flag(exampleGameId, 'reminder'),
  'markers': settings.flag(exampleGameId, 'markers'),
};

/// The example game's own options, after a successful [exampleParseOptions].
class ExampleOptions {
  const ExampleOptions({required this.reminder, required this.markers});
  final bool reminder;
  final bool markers;
}

/// Reads the opponent's options and throws [FormatException] on anything this
/// game does not understand: unknown keys, missing keys, wrong types.
///
/// The transport calls this before the session starts, so a peer that speaks
/// about another game is refused at the door instead of mid-game.
ExampleOptions exampleParseOptions(Map<String, Object?> options) {
  const allowed = {'reminder', 'markers'};
  final unknown = options.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Чужие настройки игры: ${unknown.join(', ')}');
  }
  final reminder = options['reminder'];
  final markers = options['markers'];
  if (reminder is! bool || markers is! bool) {
    throw const FormatException('Настройки игры не распознаны');
  }
  return ExampleOptions(reminder: reminder, markers: markers);
}

/// Checks a move that arrived over the network.
///
/// There are no rules yet, so only the shape of the message is checked: two
/// squares of an eight-by-eight board that are not the same square. A real game
/// replaces this with its own rule check and throws [FormatException] for an
/// illegal move — the transport drops such a move and ends the session.
void exampleValidateMove(Map<String, Object?> move) {
  final from = move['from'];
  final to = move['to'];
  if (from is! String ||
      to is! String ||
      !_squarePattern.hasMatch(from) ||
      !_squarePattern.hasMatch(to) ||
      from == to) {
    throw const FormatException('Ход не распознан');
  }
}
