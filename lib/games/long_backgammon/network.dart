import '../../app/settings.dart';
import '../backgammon/network.dart' as bg;

/// Идентификатор длинных нард. Отдельный от коротких: ключи хранения и
/// рукопожатие по сети не пересекаются.
const longBackgammonGameId = 'long_backgammon';

/// Опции длинных нард для соперника — те же три переключателя, что и у
/// коротких, но читаются под своим gameId.
Map<String, Object?> longBackgammonOptions(SettingsController settings) => {
  'hints': settings.flag(longBackgammonGameId, 'hints'),
  'numbers': settings.flag(longBackgammonGameId, 'numbers'),
  'autoRoll': settings.flag(longBackgammonGameId, 'autoRoll'),
};

/// Разбор опций длинных нард — общий с короткими: форма карты та же.
typedef LongBackgammonOptions = bg.BackgammonOptions;
LongBackgammonOptions longBackgammonParseOptions(Map<String, Object?> options) =>
    bg.backgammonParseOptions(options);

/// Проверка хода — общий формат с короткими нардами: цвет, кости, шаги.
void longBackgammonValidateMove(Map<String, Object?> move) =>
    bg.backgammonValidateMove(move);
