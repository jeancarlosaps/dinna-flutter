import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'order_intent.dart';

/// Falha ao ler ou gravar a intenção. Não distingue um pedido já criado.
enum OrderIntentStoreProblem { corrupt, unreadable, unwritable }

/// Leitura ou gravação da intenção que não chegou a um estado utilizável.
class OrderIntentStoreException implements Exception {
  const OrderIntentStoreException(this.problem);

  final OrderIntentStoreProblem problem;

  @override
  String toString() => 'OrderIntentStoreException(${problem.name})';
}

/// Guarda uma única intenção de pedido.
///
/// [save] só termina depois da escrita que o armazenamento consegue garantir.
/// [load] devolve `null` só quando a ausência da intenção foi comprovada.
/// Falha de permissão, diretório ou sistema de arquivos lança
/// [OrderIntentStoreException] e não apaga o que estava no disco.
abstract interface class OrderIntentStore {
  Future<OrderIntent?> load();

  Future<void> save(OrderIntent intent);

  Future<void> clear();
}

/// Intenção só na memória. Testes e a sessão sem arquivo usam esta classe.
final class MemoryOrderIntentStore implements OrderIntentStore {
  OrderIntent? _intent;
  var _failSave = false;
  var _failLoad = false;

  /// A próxima gravação ou limpeza falha sem alterar o que já estava guardado.
  void failNextSave() => _failSave = true;

  /// A próxima leitura falha sem apagar a intenção.
  void failNextLoad() => _failLoad = true;

  @override
  Future<OrderIntent?> load() async {
    if (_failLoad) {
      _failLoad = false;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
    }
    final intent = _intent;
    if (intent == null) return null;
    return OrderIntent.fromJson(intent.toJson());
  }

  @override
  Future<void> save(OrderIntent intent) async {
    if (_failSave) {
      _failSave = false;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
    _intent = OrderIntent.fromJson(intent.toJson());
  }

  @override
  Future<void> clear() async {
    if (_failSave) {
      _failSave = false;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
    _intent = null;
  }
}

/// Um JSON no disco, trocado por arquivo temporário, flush e rename.
///
/// O rename não cobre falta de energia nem todo sistema de arquivos. Por isso
/// [load] trata arquivo parcial, corrompido ou impossível de ler como falha
/// e preserva os bytes. `null` só sai quando o diretório pai pôde ser listado
/// e o nome não estava lá. `File.exists` não entra nessa decisão: com o
/// diretório inacessível ele responde falso mesmo com o arquivo presente.
final class FileOrderIntentStore implements OrderIntentStore {
  FileOrderIntentStore(this._file);

  final File _file;

  File get _temp => File('${_file.path}.tmp');

  @override
  Future<OrderIntent?> load() async {
    final saved = await _contents(_file);
    final newer = await _contents(_temp);
    if (newer != null) {
      final recovered = _decode(newer);
      try {
        await _temp.rename(_file.path);
      } on FileSystemException {
        throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
      }
      return recovered;
    }
    if (saved != null) return _decode(saved);
    return null;
  }

  @override
  Future<void> save(OrderIntent intent) async {
    final encoded = jsonEncode(intent.toJson());
    final temp = _temp;
    try {
      await _file.parent.create(recursive: true);
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(_file.path);
      final written = await _file.readAsString();
      if (written != encoded) {
        throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
      }
    } on OrderIntentStoreException {
      rethrow;
    } on FileSystemException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
  }

  @override
  Future<void> clear() async {
    await _deleteIfPresent(_file);
    await _deleteIfPresent(_temp);
  }

  /// `null` quando este caminho não existe e o diretório pai pôde ser listado.
  Future<String?> _contents(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException catch (error) {
      if (_isCorruptEncoding(error)) {
        throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
      }
      if (await _provenAbsent(file, error)) return null;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      if (await _provenAbsent(file, error)) return;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
  }

  OrderIntent _decode(String raw) {
    try {
      return OrderIntent.fromJson(jsonDecode(raw));
    } on FormatException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    } on ArgumentError {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    } on TypeError {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    }
  }
}

/// Store de produção quando o diretório de suporte não pôde ser preparado.
///
/// Não guarda nada em memória. Toda operação falha e o envio fica bloqueado.
final class UnavailableOrderIntentStore implements OrderIntentStore {
  const UnavailableOrderIntentStore();

  @override
  Future<OrderIntent?> load() async {
    throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
  }

  @override
  Future<void> save(OrderIntent intent) async {
    throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
  }

  @override
  Future<void> clear() async {
    throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
  }
}

/// Abre o arquivo da intenção. Falha de diretório devolve
/// [UnavailableOrderIntentStore] para o app continuar e o POST ficar bloqueado.
Future<OrderIntentStore> openOrderIntentStore({
  Future<Directory> Function()? applicationSupportDirectory,
}) async {
  try {
    final support = await (applicationSupportDirectory ?? getApplicationSupportDirectory)();
    final directory = Directory(support.path);
    await directory.create(recursive: true);
    return FileOrderIntentStore(File('${directory.path}/order-intent.json'));
  } catch (error, stackTrace) {
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'order intent store',
          context: ErrorDescription('ao preparar o arquivo da intenção'),
        ),
      );
    }
    return const UnavailableOrderIntentStore();
  }
}

bool _isCorruptEncoding(FileSystemException error) {
  return error.osError == null && error.message.toLowerCase().contains('utf-8');
}

bool _isNotFound(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 2 || code == 3;
}

/// Ausência comprovada: o erro é de arquivo inexistente e um ancestral
/// listável não contém o nome. Permissão negada não passa por aqui.
Future<bool> _provenAbsent(FileSystemEntity entity, FileSystemException error) {
  if (!_isNotFound(error)) return Future<bool>.value(false);
  return _nameMissing(entity.parent, _baseName(entity.path));
}

Future<bool> _nameMissing(Directory directory, String name) async {
  if (name.isEmpty) return false;
  try {
    await for (final child in directory.list(followLinks: false)) {
      if (_baseName(child.path) == name) return false;
    }
    return true;
  } on FileSystemException catch (error) {
    if (!_isNotFound(error)) return false;
    if (directory.path == directory.parent.path) return false;
    return _nameMissing(directory.parent, _baseName(directory.path));
  }
}

String _baseName(String path) {
  final separator = Platform.pathSeparator;
  final trimmed = path.endsWith(separator) ? path.substring(0, path.length - 1) : path;
  final index = trimmed.lastIndexOf(separator);
  return index < 0 ? trimmed : trimmed.substring(index + 1);
}
