import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/order.dart';
import 'last_order_store.dart';

/// Lê o número público de um pedido já existente. Não cria outro pedido.
typedef OrderNumberLookup = Future<int?> Function(String orderId);

/// Estado compartilhado do último pedido entre a confirmação e a tela inicial.
class LastOrderSession extends ChangeNotifier {
  LastOrderSession(this._store, {this.orderNumberLookup});

  final LastOrderStore _store;
  final OrderNumberLookup? orderNumberLookup;
  Future<void>? _restoreTask;
  Future<void>? _retryTask;
  Future<void> _operationTail = Future<void>.value();
  Order? _order;
  Order? _pendingSave;
  String? _errorMessage;
  var _restored = false;
  var _disposed = false;
  var _saving = false;
  var _loading = false;
  var _saveRevision = 0;

  static const saveFailureMessage = 'Não foi possível guardar o último pedido neste aparelho.';
  static const readFailureMessage = 'Não foi possível carregar o último pedido neste aparelho.';

  Order? get order => _order;
  String? get errorMessage => _errorMessage;
  bool get isRestored => _restored;
  bool get isSaving => _saving;
  bool get isLoading => _loading;

  bool isPersisted(Order order) {
    if (!_restored || _pendingSave != null || _errorMessage != null) return false;
    final current = _order;
    if (current == null) return false;
    if (current == order) return true;
    final number = current.orderNumber;
    if (order.orderNumber != null || number == null || current.id != order.id) return false;
    return current == order.withOrderNumber(number);
  }

  Future<void> restore() => _restoreTask ??= _enqueue(_load);

  /// Guarda a última confirmação. Falha local não invalida o sucesso da API;
  /// a ordem pendente fica disponível para retry na home.
  Future<void> record(Order order) async {
    await restore();
    if (_disposed) return;

    final snapshot = _preservingNumber(order);
    _pendingSave = snapshot;
    _order = snapshot;
    _errorMessage = null;
    final revision = ++_saveRevision;
    _saving = true;
    _notify();
    await _enqueue(() => _savePending(revision));
  }

  /// Repete a leitura ou a gravação que falhou. Leituras e gravações são
  /// serializadas para que uma resposta antiga não substitua um pedido novo.
  Future<void> retry() {
    final current = _retryTask;
    if (current != null) return current;
    final task = _retry();
    _retryTask = task;
    return task.whenComplete(() {
      if (identical(_retryTask, task)) _retryTask = null;
    });
  }

  Future<void> _retry() async {
    await restore();
    if (_disposed) return;

    final pending = _pendingSave;
    if (pending != null) {
      final revision = _saveRevision;
      _saving = true;
      _notify();
      await _enqueue(() => _savePending(revision));
      return;
    }

    _loading = true;
    _notify();
    await _enqueue(_load);
  }

  Future<void> _load() async {
    if (_disposed) return;
    _loading = true;
    _notify();
    try {
      final loaded = await _store.load();
      if (_disposed || _pendingSave != null) return;
      final enriched = await _enrich(loaded);
      if (_disposed || _pendingSave != null) return;
      // Uma gravação iniciada durante a consulta já voltou acima e manteve
      // a fotografia nova. Aqui só entra o registro lido, com o número se veio.
      _order = enriched;
      _errorMessage = null;
      await _persistRecoveredNumber(loaded, enriched);
    } on Object {
      if (_disposed) return;
      if (_pendingSave == null) _errorMessage = readFailureMessage;
    } finally {
      if (!_disposed) {
        _restored = true;
        _loading = false;
        _notify();
      }
    }
  }

  /// Um registro anterior a esta versão não tem número. A consulta só acontece
  /// nesse caso. Falha de leitura devolve a fotografia como estava.
  Future<Order?> _enrich(Order? loaded) async {
    if (loaded == null || loaded.orderNumber != null) return loaded;
    final lookup = orderNumberLookup;
    if (lookup == null) return loaded;
    try {
      final number = await lookup(loaded.id);
      if (number == null || number < 1) return loaded;
      return loaded.withOrderNumber(number);
    } on Object {
      return loaded;
    }
  }

  /// Grava o número uma vez. Não regrava quando ele já estava no JSON e não
  /// apaga a fotografia se o disco recusar a atualização.
  Future<void> _persistRecoveredNumber(Order? loaded, Order? enriched) async {
    if (loaded == null || enriched == null) return;
    if (loaded.orderNumber != null || enriched.orderNumber == null) return;
    if (_pendingSave != null) return;
    try {
      await _store.save(enriched);
    } on Object {
      // A linha antiga continua válida. O número fica disponível nesta execução.
    }
  }

  Order _preservingNumber(Order incoming) {
    if (incoming.orderNumber != null) return incoming;
    final current = _pendingSave ?? _order;
    final number = current?.orderNumber;
    if (current == null || number == null || current.id != incoming.id) return incoming;
    return incoming.withOrderNumber(number);
  }

  Future<void> _savePending(int revision) async {
    if (_disposed || revision != _saveRevision) return;
    final order = _pendingSave;
    if (order == null) return;
    _saving = true;
    _notify();
    try {
      await _store.save(order);
      if (_disposed || revision != _saveRevision) return;
      _order = order;
      _pendingSave = null;
      _errorMessage = null;
    } on Object {
      if (!_disposed && revision == _saveRevision) _errorMessage = saveFailureMessage;
    } finally {
      if (!_disposed && revision == _saveRevision) {
        _saving = false;
        _notify();
      }
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _operationTail;
    final finished = Completer<void>();
    _operationTail = finished.future;
    return _run(previous, finished, operation);
  }

  Future<void> _run(
    Future<void> previous,
    Completer<void> finished,
    Future<void> Function() operation,
  ) async {
    try {
      await previous;
      await operation();
    } finally {
      if (!finished.isCompleted) finished.complete();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
