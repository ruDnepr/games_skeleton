import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки хранятся на устройстве и возвращаются после перезапуска.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('имя обрезается, пустое заменяется, повтор не уведомляет', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    var notified = 0;
    settings.addListener(() => notified++);

    // Пустое имя — это имя по умолчанию, оно уже там.
    await settings.setNickname('   ');
    expect(settings.nickname, 'Диана');
    expect(notified, 0);

    await settings.setNickname('  Алиса  ');
    expect(settings.nickname, 'Алиса');
    expect(notified, 1);

    // То же имя снова — тихо: поле ввода не перестраивается.
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
      SettingsController.flagKey('backgammon', 'hints'),
      'game.backgammon.hints',
    );

    // Значения по умолчанию — те, что объявила игра.
    expect(settings.flag('backgammon', 'hints'), isTrue);
    expect(settings.flag('backgammon', 'numbers'), isFalse);
    // Неизвестная игра или ключ не бросают.
    expect(settings.flag('nope', 'nothing'), isFalse);

    var notified = 0;
    settings.addListener(() => notified++);

    // Запись того же значения ничего не меняет.
    await settings.setFlag('backgammon', 'numbers', false);
    expect(notified, 0);

    await settings.setFlag('backgammon', 'hints', false);
    await settings.setFlag('other', 'hints', true);
    expect(notified, 2);

    expect(settings.flag('backgammon', 'hints'), isFalse);
    expect(settings.flag('other', 'hints'), isTrue);
    expect(settings.flag('backgammon', 'numbers'), isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('game.backgammon.hints'), isFalse);
    expect(preferences.getBool('game.other.hints'), isTrue);

    // После перезапуска — те же значения, по-прежнему раздельно.
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.flag('backgammon', 'hints'), isFalse);
    expect(restored.flag('other', 'hints'), isTrue);
    expect(restored.flag('backgammon', 'numbers'), isFalse);
  });

  test('сброс прогресса обнуляет счётчики и не трогает настройки', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    await settings.setSound(false);
    await settings.recordGame(won: true);
    await settings.recordGame(won: false);
    await settings.setFlag('backgammon', 'numbers', true);

    await settings.resetProgress();
    expect(settings.gamesPlayed, 0);
    expect(settings.gamesWon, 0);
    expect(settings.sound, isFalse);
    expect(settings.flag('backgammon', 'numbers'), isTrue);
  });
}
