import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_for_diana/app/settings.dart';
import 'package:games_for_diana/games/domino/engine/model.dart';
import 'package:games_for_diana/games/domino/session_page.dart';
import 'package:games_for_diana/games/domino/table_view.dart';
import 'package:games_for_diana/games/domino/tile_view.dart';
import 'package:games_for_diana/presentation/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameState table({
  required List<List<String>> hands,
  List<String> board = const [],
  int turn = 0,
  List<String> bazaar = const [],
}) {
  var chain = const Board.empty();
  for (final label in board) {
    chain = chain.place(DominoTile.parse(label), ChainSide.right);
  }
  return GameState(
    playerCount: hands.length,
    hands: [
      for (final hand in hands)
        [for (final label in hand) DominoTile.parse(label)],
    ],
    bazaar: [for (final label in bazaar) DominoTile.parse(label)],
    board: chain,
    turn: turn,
  );
}

/// Партия вдвоём за одним устройством: ходит первый игрок, у второго есть
/// подходящая кость, поэтому ход не проваливается в пропуски.
GameState twoPlayers() => table(
      hands: [
        ['1:2', '0:0'],
        ['1:4'],
      ],
      board: ['2:5'],
      turn: 0,
      bazaar: ['6:6', '3:3'],
    );

Widget wrap(Widget child) => MaterialApp(
      theme: dianaTheme(),
      home: Scaffold(body: Center(child: child)),
    );

List<PlacedTile> chainOf(List<String> labels) => [
      for (final label in labels) PlacedTile.parse(label),
    ];

Future<SettingsController> pumpGame(
  WidgetTester tester,
  GameState state, {
  SettingsController? settings,
  Size size = const Size(430, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final s = settings ?? SettingsController()..sound = false;
  addTearDown(s.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: dianaTheme(),
      home: DominoSessionPage(
        settings: s,
        initialState: state,
        animationDuration: Duration.zero,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('отдельные виджеты', () {
    testWidgets('цепочка рисует все кости по порядку', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 360,
            height: 120,
            child: ChainView(placed: chainOf(['1:2', '2:2', '2:5'])),
          ),
        ),
      );
      expect(find.byKey(const Key('chain')), findsOneWidget);
      for (var index = 0; index < 3; index++) {
        expect(find.byKey(Key('chain-tile-$index')), findsOneWidget);
      }
    });

    testWidgets('пустая цепочка просит выложить первую кость', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            height: 120,
            child: ChainView(placed: []),
          ),
        ),
      );
      expect(find.text('Цепочка пока пустая'), findsOneWidget);
    });

    testWidgets('рука подсвечивает подходящие кости и отмечает совет', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 120,
            child: HandView(
              tiles: const [DominoTile(1, 2), DominoTile(4, 4)],
              playable: {const DominoTile(1, 2)},
              selected: null,
              hintsEnabled: true,
              suggested: const DominoTile(4, 4),
              onTap: (_) {},
            ),
          ),
        ),
      );
      final views = tester
          .widgetList<DominoTileView>(find.byType(DominoTileView))
          .toList();
      expect(views, hasLength(2));
      final playable = views.firstWhere((view) => view.tile.label == '1:2');
      final suggested = views.firstWhere((view) => view.tile.label == '4:4');
      expect(playable.highlighted, isTrue);
      expect(suggested.selected, isTrue);
    });

    testWidgets('кость держит пропорцию 2:1', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 120,
            child: HandView(
              tiles: const [DominoTile(1, 2), DominoTile(4, 4)],
              playable: const {},
              selected: null,
              hintsEnabled: false,
              onTap: (_) {},
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const Key('hand-tile-1:2')));
      expect(
        size.height / size.width,
        closeTo(DominoTileView.heightRatio, .001),
        reason: 'у костяшки две ширины на одну длину',
      );
    });

    testWidgets('без подсказок подсветки нет', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 120,
            child: HandView(
              tiles: const [DominoTile(1, 2)],
              playable: {const DominoTile(1, 2)},
              selected: null,
              hintsEnabled: false,
              onTap: (_) {},
            ),
          ),
        ),
      );
      final view = tester.widget<DominoTileView>(find.byType(DominoTileView));
      expect(view.highlighted, isFalse);
    });

    testWidgets('нажатие на кость в руке сообщает о выборе', (tester) async {
      DominoTile? tapped;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 120,
            child: HandView(
              tiles: const [DominoTile(3, 5)],
              playable: {const DominoTile(3, 5)},
              selected: null,
              hintsEnabled: true,
              onTap: (tile) => tapped = tile,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hand-tile-3:5')));
      expect(tapped?.label, '3:5');
    });

    testWidgets('чужой ход не даёт нажимать на кости', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 120,
            child: HandView(
              tiles: const [DominoTile(3, 5)],
              playable: {const DominoTile(3, 5)},
              selected: null,
              hintsEnabled: true,
              reserved: true,
              onTap: (_) => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('hand-tile-3:5')));
      expect(taps, 0);
    });

    testWidgets('базар показывает число костей и нажимается, когда можно взять', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          BazaarStack(
            key: const Key('bazaar'),
            count: 7,
            enabled: true,
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.text('7'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bazaar')));
      expect(taps, 1);
    });

    testWidgets('пустой базар не нажимается', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          BazaarStack(
            key: const Key('bazaar'),
            count: 0,
            enabled: false,
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('bazaar')), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('конец цепочки показывает число и срабатывает по нажатию', (
      tester,
    ) async {
      ChainSide? side;
      await tester.pumpWidget(
        wrap(
          EndChip(
            key: const Key('end-right'),
            value: 5,
            side: ChainSide.right,
            highlighted: true,
            onTap: () => side = ChainSide.right,
          ),
        ),
      );
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('end-right')));
      expect(side, ChainSide.right);
    });

    testWidgets('панель игрока показывает имя и количество костей', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PlayerPanel(seat: 1, name: 'Петя', tiles: 5, active: true),
        ),
      );
      expect(find.text('Петя'), findsOneWidget);
      expect(find.text('5 костей'), findsOneWidget);
      expect(find.text('ХОД'), findsOneWidget);
    });

    testWidgets('полоса игроков прячет того, чья рука внизу', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            height: 80,
            child: PlayersStrip(
              names: const ['Диана', 'Петя', 'Маша'],
              handSizes: const [7, 6, 5],
              activeSeat: 1,
              handSeat: 0,
              notes: const {2: 'ждём возвращения'},
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('player-panel-0')), findsNothing);
      expect(find.byKey(const Key('player-panel-1')), findsOneWidget);
      expect(find.byKey(const Key('player-panel-2')), findsOneWidget);
      expect(find.text('ждём возвращения'), findsOneWidget);
    });
  });

  group('экран партии', () {
    testWidgets('показывает стол, руку и открытые концы', (tester) async {
      await pumpGame(tester, twoPlayers());
      expect(find.byKey(const Key('hand')), findsOneWidget);
      expect(find.byKey(const Key('bazaar')), findsOneWidget);
      expect(find.byKey(const Key('end-left')), findsOneWidget);
      expect(find.byKey(const Key('end-right')), findsOneWidget);
      expect(find.byKey(const Key('hand-tile-1:2')), findsOneWidget);
      expect(find.byKey(const Key('chain-tile-0')), findsOneWidget);
    });

    testWidgets('нажатие на подходящую кость выкладывает её в цепочку', (
      tester,
    ) async {
      await pumpGame(tester, twoPlayers());
      await tester.tap(find.byKey(const Key('hand-tile-1:2')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('chain-tile-1')), findsOneWidget);
      // Ход перешёл второму игроку — в руке теперь его кость.
      expect(find.byKey(const Key('hand-tile-1:4')), findsOneWidget);
    });

    testWidgets('кнопка «Подсказка» показывает совет', (tester) async {
      await pumpGame(tester, twoPlayers());
      expect(find.byKey(const Key('hint-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hint-button')));
      await tester.pump();
      expect(find.textContaining('Поставь'), findsOneWidget);
      await tester.tap(find.byKey(const Key('message-dismiss')));
      await tester.pump();
      expect(find.textContaining('Поставь'), findsNothing);
    });

    testWidgets('на небольшом экране стол, рука и кнопки помещаются', (
      tester,
    ) async {
      await pumpGame(tester, twoPlayers(), size: const Size(360, 640));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('hand')), findsOneWidget);
      expect(find.byKey(const Key('bazaar')), findsOneWidget);
      expect(find.byKey(const Key('hint-toggle')), findsOneWidget);
    });

    testWidgets('когда подходящих костей нет, экран предлагает взять из базара', (
      tester,
    ) async {
      await pumpGame(
        tester,
        table(
          hands: [
            ['0:0'],
            ['1:4'],
          ],
          board: ['6:6'],
          bazaar: ['6:5', '3:3'],
        ),
      );
      expect(find.byKey(const Key('draw-button')), findsOneWidget);
      expect(find.textContaining('возьми'), findsWidgets);
    });

    testWidgets('взятая из базара кость появляется в руке', (tester) async {
      await pumpGame(
        tester,
        table(
          hands: [
            ['0:0'],
            ['1:4'],
          ],
          board: ['6:6'],
          bazaar: ['6:5', '3:3'],
          turn: 0,
        ),
      );
      await tester.tap(find.byKey(const Key('draw-button')));
      await tester.pump();
      await tester.pump();
      // Кость 6:5 подписана как 5:6: у костяшки нет направления, порядок чисел
      // на экране всегда от меньшего к большему.
      expect(find.byKey(const Key('hand-tile-5:6')), findsOneWidget);
      expect(find.textContaining('подошла'), findsWidgets);
    });

    testWidgets('кнопка «Отменить ход» возвращает прежнюю цепочку', (
      tester,
    ) async {
      await pumpGame(tester, twoPlayers());
      expect(find.byKey(const Key('chain-tile-1')), findsNothing);
      await tester.tap(find.byKey(const Key('hand-tile-1:2')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('chain-tile-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('chain-tile-1')), findsNothing);
      expect(find.byKey(const Key('hand-tile-1:2')), findsOneWidget);
    });
  });

  group('стартовые экраны', () {
    testWidgets('ModePage показывает три варианта', (tester) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DominoModePage(settings: settings)),
      );
      expect(find.text('Против компьютера'), findsOneWidget);
      expect(find.text('Два игрока'), findsOneWidget);
      expect(find.textContaining('тренироваться с компьютером'), findsOneWidget);
    });

    testWidgets('DifficultyPage показывает три уровня с подзаголовками', (
      tester,
    ) async {
      final settings = SettingsController()..sound = false;
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(home: DominoDifficultyPage(settings: settings)),
      );
      expect(find.text('Лёгкий'), findsOneWidget);
      expect(find.text('Средний'), findsOneWidget);
      expect(find.text('Сложный'), findsOneWidget);
      expect(
        find.text('Компьютер ходит первой подходящей костью'),
        findsOneWidget,
      );
      expect(
        find.text('Компьютер оставляет себе больше вариантов'),
        findsOneWidget,
      );
      expect(
        find.text('Компьютер следит за твоими костями'),
        findsOneWidget,
      );
    });
  });
}
