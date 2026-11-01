import 'dart:convert';
import 'dart:io';

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
/// [load] devolve `null` quando ainda não há intenção. Arquivo corrompido,
/// leitura impossível ou sobra ilegível lançam [OrderIntentStoreException]
/// e não apagam o que estava no disco.
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
  Future<OrderIntent?> load() {
    if (_failLoad) {
      _failLoad = false;
      return Future<OrderIntent?>.error(
        const OrderIntentStoreException(OrderIntentStoreProblem.unreadable),
      );
    }
    final intent = _intent;
    if (intent == null) return Future<OrderIntent?>.value();
    return Future<OrderIntent?>.value(OrderIntent.fromJson(intent.toJson()));
  }

  @override
  Future<void> save(OrderIntent intent) {
    if (_failSave) {
      _failSave = false;
      return Future<void>.error(
        const OrderIntentStoreException(OrderIntentStoreProblem.unwritable),
      );
    }
    _intent = OrderIntent.fromJson(intent.toJson());
    return Future<void>.value();
  }

  @override
  Future<void> clear() {
    if (_failSave) {
      _failSave = false;
      return Future<void>.error(
        const OrderIntentStoreException(OrderIntentStoreProblem.unwritable),
      );
    }
    _intent = null;
    return Future<void>.value();
  }
}

/// Um JSON no disco, trocado por arquivo temporário, flush e rename.
///
/// O rename não cobre falta de energia nem todo sistema de arquivos. Por isso
/// [load] trata arquivo parcial, corrompido ou impossível de ler como falha
/// e preserva os bytes.
final class FileOrderIntentStore implements OrderIntentStore {
  FileOrderIntentStore(this._file);

  final File _file;

  File get _temp => File('${_file.path}.tmp');

  @override
  Future<OrderIntent?> load() async {
    try {
      if (await _file.exists()) {
        final intent = await _read(_file);
        await _deleteQuietly(_temp);
        return intent;
      }
      if (!await _temp.exists()) return null;
      final recovered = await _read(_temp);
      try {
        await _temp.rename(_file.path);
      } on FileSystemException {
        // Os bytes já foram lidos. O próximo save tenta o arquivo final.
      }
      return recovered;
    } on OrderIntentStoreException {
      rethrow;
    } on FileSystemException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unreadable);
    }
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
    try {
      if (await _file.exists()) await _file.delete();
      if (await _temp.exists()) await _temp.delete();
    } on FileSystemException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
  }

  Future<OrderIntent> _read(File file) async {
    final raw = await file.readAsString();
    try {
      return OrderIntent.fromJson(jsonDecode(raw));
    } on FormatException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    } on TypeError {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A sobra não autoriza outro POST. O arquivo final continua valendo.
    }
  }
}
