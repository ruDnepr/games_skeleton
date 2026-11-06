import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/app/sounds.dart';
import 'package:games_for_diana/games/backgammon/backgammon_controller.dart';
import 'package:games_for_diana/games/backgammon/engine/model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Логика подсветки ходов, применения шага, пошаговой отмены и победы — без
/// Flame и без виджетов: контроллер сам по себе ведёт партию.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SettingsController settings;
  late BackgammonController controller;

  setUp(() async {
    settings = SettingsController();
    await settings.load();
    settings.sound = false;
    final sounds = GameSounds(settings);
    controller = BackgammonController(settings: settings, sounds: sounds);
  });
  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  /// Ставит детерминированное состояние (без случайного броска).
  void setState(Board board, {Player turn = Player.white, List<int> dice = const []}) {
    controller.state = GameState(
      board: board,
      turn: turn,
      rolled: dice,
      available: dice,
    );
  }

  test('подсветка: при выборе шашки видны допустимые пункты', () {
    setState(Board.initial(), dice: const [3, 1]);
    controller.selectPoint(23);
    expect(controller.selectedPoint, 23);
    // С 23 ходим на 20 (кость 3) или на 22 (кость 1).
    expect(controller.highlightedDestinations, containsAll([20, 22]));
  });

  test('ход шашкой применяется, кость тратится', () {
    setState(Board.initial(), dice: const [3, 1]);
    controller.selectPoint(23);
    controller.selectPoint(20); // адресат → ход 23→20 костью 3
    expect(controller.state.board.at(23, Player.white), 1);
    expect(controller.state.board.at(20, Player.white), 1);
    expect(controller.state.available, [1]); // кость 3 потрачена
  });

  test('пошаговая отмена возвращает шашку назад', () {
    setState(Board.initial(), dice: const [3, 1]);
    controller.selectPoint(23);
    controller.selectPoint(20);
    expect(controller.state.board.at(20, Player.white), 1);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.state.board.at(23, Player.white), 2);
    expect(controller.state.board.at(20, Player.white), 0);
    expect(controller.state.available, [3, 1]);
  });

  test('ход с бара: выбирается только вход, другие шашки недоступны', () {
    final b = Board(points: List.filled(24, 0), whiteBar: 1);
    setState(b, dice: const [3, 5]);
    controller.selectBar();
    expect(controller.selectedBar, isTrue);
    // Вход костью 3 → пункт 21, костью 5 → пункт 19.
    expect(controller.highlightedDestinations, containsAll([21, 19]));
    // Выбор обычного пункта при шашке на баре ничего не даёт.
    controller.selectPoint(5);
    expect(controller.selectedBar, isFalse);
    expect(controller.selectedPoint, isNull);
  });

  test('вынос последней шашки — победа', () {
    final b = Board(
      points: List.filled(24, 0)..[0] = 1,
      whiteOff: 14,
    );
    setState(b, dice: const [1]);
    controller.selectPoint(0);
    controller.selectOff();
    expect(controller.state.winner, Player.white);
    expect(controller.state.board.whiteOff, 15);
  });

  test('подсказка выбирает шашку хорошего хода', () {
    setState(Board.initial(), dice: const [3, 1]);
    controller.hint();
    // После подсказки что-то выбрано (пункт или бар) и есть адресаты.
    expect(
      controller.selectedPoint != null || controller.selectedBar,
      isTrue,
    );
    expect(controller.legalForSelected, isNotEmpty);
  });
}
