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
      final hasFile = await _file.exists();
      final hasTemp = await _temp.exists();
      if (!hasFile && !hasTemp) return null;

      // O temporário é a escrita mais nova. Ele prevalece sobre o arquivo
      // final e só sai do disco depois que o rename conclui.
      if (hasTemp) {
        final recovered = await _read(_temp);
        await _temp.rename(_file.path);
        return recovered;
      }
      return await _read(_file);
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
    try {
      final raw = await file.readAsString();
      return OrderIntent.fromJson(jsonDecode(raw));
    } on FormatException {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    } on ArgumentError {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    } on FileSystemException catch (error) {
      if (error.osError == null && error.message.toLowerCase().contains('utf-8')) {
        throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
      }
      rethrow;
    } on TypeError {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.corrupt);
    }
  }
}
