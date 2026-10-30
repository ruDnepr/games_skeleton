import 'dart:convert';

import '../app/catalog.dart';

// v1 — первый общий протокол каркаса. Номер растёт, когда меняется смысл
// сообщений: устройства с разными версиями отказываются от партии до её
// начала, а не расходятся посреди игры.
const protocolVersion = 1;

/// mDNS-служба, по которой игры находят друг друга в одной сети.
const serviceType = '_diana-games._tcp';

/// Без похожих символов: 0/O, 1/I/L. Код диктуют вслух, поэтому их нет.
const codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _codePattern = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');

bool isGameCode(String value) => _codePattern.hasMatch(value);

final _gameIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

/// Идентификатор игры из [GameCatalog]: латиница, цифры и подчёркивание.
bool isGameId(String value) => _gameIdPattern.hasMatch(value);

/// Общий лобби-конверт: всё, о чём устройства договариваются до партии.
///
/// Раньше здесь лежали шашечные вариант и цвет. Теперь выбор игры — это
/// [gameId], а всё, что игра хочет сказать о себе, лежит в непрозрачной
/// карте [options]: разбирать её умеет только сама игра.
class LobbyConfig {
  const LobbyConfig({
    required this.gameId,
    required this.hostSide,
    required this.code,
    this.version = protocolVersion,
    this.hostName = 'Друг',
    this.options = const {},
  });

  final int version;
  final String gameId;
  final String hostSide;
  final String code;
  final String hostName;
  final Map<String, Object?> options;

  Map<String, Object?> toJson() => {
    'version': version,
    'gameId': gameId,
    'hostSide': hostSide,
    'code': code,
    'hostName': hostName,
    'options': options,
  };

  /// Разбирает лобби и отказывается от чужого сразу: другая версия протокола,
  /// игры нет в каталоге, опции не разобрались — всё это [FormatException] до
  /// начала партии.
  factory LobbyConfig.fromJson(Object? data) {
    if (data is! Map) {
      throw const FormatException('Настройки сетевой игры не распознаны');
    }
    if (data['version'] != protocolVersion) {
      throw const FormatException('У вас разные версии игры');
    }
    final gameId = data['gameId'];
    final hostSide = data['hostSide'];
    final code = data['code'];
    final hostName = data['hostName'];
    final options = data['options'];
    if (code is! String ||
        !isGameCode(code) ||
        gameId is! String ||
        !isGameId(gameId) ||
        hostSide is! String ||
        hostSide.trim().isEmpty ||
        hostSide.length > 20 ||
        hostName is! String ||
        hostName.length > 40 ||
        options is! Map) {
      throw const FormatException('Настройки сетевой игры не распознаны');
    }
    final game = GameCatalog.byId(gameId);
    if (game == null) {
      throw const FormatException('Такой игры нет в этой версии приложения');
    }
    final parsed = Map<String, Object?>.from(options);
    // Разбор опций — работа игры: чужие данные она отвергает сама.
    game.parseOptions(parsed);
    return LobbyConfig(
      version: protocolVersion,
      gameId: gameId,
      hostSide: hostSide,
      code: code,
      hostName: hostName,
      options: parsed,
    );
  }
}

class NetworkMessage {
  const NetworkMessage(this.type, [this.data = const {}]);
  final String type;
  final Map<String, Object?> data;

  /// Всё, что транспорт пропускает. Сообщение с другим типом — ошибка.
  static const types = {
    'hello',
    'gameConfig',
    'move',
    'undoRequest',
    'undoResponse',
    'resign',
    'ping',
    'pong',
    'desync',
    'error',
    'connected',
    'disconnected',
  };

  /// Больше этого сообщение не бывает: доска и история целиком не пересылаются.
  static const maxLength = 16384;

  String encode() => jsonEncode({'type': type, 'data': data});

  factory NetworkMessage.decode(Object? text) {
    if (text is! String || text.length > maxLength) {
      throw const FormatException('Некорректное сообщение');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['type'] is! String ||
        !types.contains(decoded['type']) ||
        decoded['data'] is! Map) {
      throw const FormatException('Неизвестное сообщение');
    }
    return NetworkMessage(
      decoded['type'] as String,
      Map<String, Object?>.from(decoded['data'] as Map),
    );
  }
}
