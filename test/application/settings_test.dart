import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings are stored on the device and must come back after a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('имя обрезается, пустое заменяется, повтор не уведомляет', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    var notified = 0;
    settings.addListener(() => notified++);

    // An empty name is the default one, and the default one is already there.
    await settings.setNickname('   ');
    expect(settings.nickname, 'Диана');
    expect(notified, 0);

    await settings.setNickname('  Алиса  ');
    expect(settings.nickname, 'Алиса');
    expect(notified, 1);

    // The same name again is silent: the field being typed into is not rebuilt.
    await settings.setNickname('Алиса');
    expect(notified, 1);

    await settings.setNickname('Диана-Василиса-Премудрая');
    expect(settings.nickname.runes.length, 20);
    expect(settings.nickname.startsWith('Диана-Василиса'), isTrue);
    expect(notified, 2);
  });

  test('настройки и прогресс восстанавливаются после load', () async {
    final settings = SettingsController();
    await settings.load();
    await settings.setSound(false);
    await settings.setNickname('Маша');
    await settings.recordGame(won: true);
    settings.dispose();

    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.sound, isFalse);
    expect(restored.nickname, 'Маша');
    expect(restored.gamesPlayed, 1);
    expect(restored.gamesWon, 1);
  });

  test('флаги разных игр не пересекаются', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    expect(
      SettingsController.flagKey('example', 'reminder'),
      'game.example.reminder',
    );

    // The defaults are the ones the games declared.
    expect(settings.flag('example', 'reminder'), isTrue);
    expect(settings.flag('example', 'markers'), isFalse);
    // An unknown game or key must not throw.
    expect(settings.flag('nope', 'nothing'), isFalse);

    var notified = 0;
    settings.addListener(() => notified++);

    // Writing the value that is already there changes nothing.
    await settings.setFlag('example', 'markers', false);
    expect(notified, 0);

    await settings.setFlag('example', 'reminder', false);
    await settings.setFlag('other', 'reminder', true);
    expect(notified, 2);

    expect(settings.flag('example', 'reminder'), isFalse);
    expect(settings.flag('other', 'reminder'), isTrue);
    expect(settings.flag('example', 'markers'), isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('game.example.reminder'), isFalse);
    expect(preferences.getBool('game.other.reminder'), isTrue);

    // And both come back after a restart, still separately.
    settings.dispose();
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.flag('example', 'reminder'), isFalse);
    expect(restored.flag('other', 'reminder'), isTrue);
    expect(restored.flag('example', 'markers'), isFalse);
  });

  test('сброс прогресса обнуляет счётчики и не трогает настройки', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    await settings.setSound(false);
    await settings.recordGame(won: true);
    await settings.recordGame(won: false);
    await settings.setFlag('example', 'markers', true);

    await settings.resetProgress();
    expect(settings.gamesPlayed, 0);
    expect(settings.gamesWon, 0);
    expect(settings.sound, isFalse);
    expect(settings.flag('example', 'markers'), isTrue);
  });
}
