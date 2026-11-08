import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/order.dart';
import 'last_order_store.dart';

/// Estado compartilhado do último pedido entre a confirmação e a tela inicial.
class LastOrderSession extends ChangeNotifier {
  LastOrderSession(this._store);

  final LastOrderStore _store;
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

  bool isPersisted(Order order) =>
      _restored && _pendingSave == null && _errorMessage == null && _order == order;

  Future<void> restore() => _restoreTask ??= _enqueue(_load);

  /// Guarda a última confirmação. Falha local não invalida o sucesso da API;
  /// a ordem pendente fica disponível para retry na home.
  Future<void> record(Order order) async {
    await restore();
    if (_disposed) return;

    _pendingSave = order;
    _order = order;
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
      if (_disposed) return;
      // A save may have been requested while the query was in flight. Keep
      // its in-memory snapshot; the queued write will persist it next.
      if (_pendingSave == null) {
        _order = loaded;
        _errorMessage = null;
      }
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
