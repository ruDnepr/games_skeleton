import '../definition.dart';
import 'network.dart';

/// Rules of the example game.
///
/// There is no real game behind this scaffold yet, so the cards explain what
/// the example stands for instead of inventing rules. A real game replaces
/// this list with its own and the shared rules screen draws it as is.
const exampleRules = [
  RuleCard(
    number: 1,
    title: 'Это не игра, а заготовка',
    text:
        'Настоящих правил здесь нет. Игра-пример показывает, куда их положить: '
        'список карточек приходит из файла rules.dart этой игры.',
  ),
  RuleCard(
    number: 2,
    title: 'Правила — это данные',
    text:
        'Экран правил общий: он рисует карточки по порядку, от первой до '
        'последней. Чтобы у игры появились свои правила, заполни этот список.',
  ),
  RuleCard(
    number: 3,
    title: 'Свои настройки',
    text:
        'Переключатели объявляет сама игра. Каждый хранится под ключом '
        'game.<id>.<key>, поэтому игры не мешают друг другу.',
  ),
  RuleCard(
    number: 4,
    title: 'Своя партия',
    text:
        'Кнопка «Играть» открывает session_page.dart. В заготовке там вежливое '
        '«Здесь будет партия» и кнопка «Понятно».',
  ),
  RuleCard(
    number: 5,
    title: 'Сеть уже готова',
    text:
        'Поиск в Wi-Fi, код из шести символов и адрес IP:порт общие. Игра '
        'добавляет только разбор своих настроек и проверку своих ходов.',
  ),
  RuleCard(
    number: 6,
    title: 'Идентификатор игры',
    text:
        'У игры есть латинский id — «$exampleGameId». Он попадает в ключи '
        'хранения и в рукопожатие по сети, поэтому после первых партий его '
        'не меняют.',
  ),
];
