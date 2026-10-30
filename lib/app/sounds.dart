import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// Every short sound of the game, one per file in `assets/audio`.
enum GameSound {
  move(volume: .38),
  capture(volume: .45),
  crown(volume: .48),
  guess(volume: .45),
  miss(volume: .40),
  win(volume: .50),
  lose(volume: .46),
  draw(volume: .46);

  const GameSound({required this.volume});

  /// File name inside `assets/audio`. The audio cache already prefixes
  /// `assets/audio/`, so the name is passed to it without the folder.
  String get fileName => '$name.wav';

  /// Full asset path, as declared in `pubspec.yaml`.
  String get path => 'assets/audio/$fileName';

  /// Sound of a move that is being played: these must never pile up. An
  /// ending sound may follow a move sound, so it is not one of them.
  bool get isMoveSound =>
      this != GameSound.win &&
      this != GameSound.lose &&
      this != GameSound.draw;

  /// Quiet enough for a child to play for a long time without being startled.
  final double volume;
}

/// The sound that ends the game for this player. A draw has its own calm tone;
/// otherwise the winner hears the win sound and the loser a softer falling one.
/// In a two-player game on one device somebody always won, so it is a win.
GameSound resultSoundName({
  required bool draw,
  required bool local,
  required bool iWon,
}) => draw ? GameSound.draw : (local || iWon ? GameSound.win : GameSound.lose);

/// Plays the samples. The seam exists so tests can watch what would be played
/// without touching a real audio device.
abstract class SfxBackend {
  Future<void> play(GameSound sound);
}

/// Preloaded players, one pool per sample.
///
/// The obvious `FlameAudio.play` creates a new native player for every sound
/// and never releases it. After a few dozen moves the platform runs out of
/// players: effects arrive late, repeat on their own and burst out together
/// when the app comes back to the foreground. A pool keeps the players and
/// reuses them, so one sample sounds at most [maxVoices] times at once.
class PoolsSfxBackend extends SfxBackend with WidgetsBindingObserver {
  PoolsSfxBackend();

  /// Shared by the whole app: the pools are created once.
  static final PoolsSfxBackend instance = PoolsSfxBackend();

  /// How many copies of one sample may overlap. Two is enough for a board game
  /// and guarantees that a double event never turns into a pile of noise.
  static const maxVoices = 2;

  final Map<GameSound, AudioPool> _pools = {};
  bool _foreground = true;
  Future<void>? _loading;

  /// Creates the pools. Safe to call more than once; a failure is reported but
  /// never stops the game, because a device without audio must stay playable.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    // The pools live as long as the process, so the observer stays as well.
    WidgetsBinding.instance.addObserver(this);
    for (final sound in GameSound.values) {
      try {
        _pools[sound] = await FlameAudio.createPool(
          sound.fileName,
          minPlayers: 1,
          maxPlayers: maxVoices,
        );
      } catch (error, stack) {
        // One broken sample must not remove the others.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'sounds',
            context: ErrorDescription('подготовка звука ${sound.path}'),
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sounds queued while the app was hidden would all fire on return.
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  Future<void> play(GameSound sound) async {
    final pool = _pools[sound];
    if (pool == null || !_foreground) return;
    try {
      await pool.start(volume: sound.volume);
    } catch (_) {
      // An interrupted or missing output device is not a game error.
    }
  }
}

/// Plays game effects, respecting the sound switch and never repeating the same
/// event several times in a row.
class GameSounds {
  GameSounds(
    this.settings, {
    SfxBackend? backend,
    DateTime Function()? clock,
  }) : _backend = backend ?? PoolsSfxBackend.instance,
       _clock = clock ?? DateTime.now;

  /// Two move sounds closer than this mean one event reported twice, not two
  /// things happening: the second one is dropped. A whole move, a capture and
  /// a promotion of one tap happen at the same instant, so the gap is short.
  static const repeatGap = Duration(milliseconds: 90);

  final SettingsController settings;
  final SfxBackend _backend;
  final DateTime Function() _clock;
  GameSound? _lastSound;
  DateTime? _lastAt;
  DateTime? _lastMoveAt;

  /// Whether sound is on right now.
  bool get enabled => settings.sound;

  /// The last sound that was let through. Exposed for tests; the game itself
  /// never reads it.
  @visibleForTesting
  GameSound? get lastSound => _lastSound;

  void play(GameSound sound) {
    if (!enabled) return;
    final now = _clock();
    final last = _lastAt;
    final lastMove = _lastMoveAt;
    final repeated = sound == _lastSound &&
        last != null &&
        now.difference(last) < repeatGap;
    final crowded = sound.isMoveSound &&
        lastMove != null &&
        now.difference(lastMove) < repeatGap;
    if (repeated || crowded) return;
    _lastSound = sound;
    _lastAt = now;
    if (sound.isMoveSound) _lastMoveAt = now;
    unawaited(_backend.play(sound));
  }
}
