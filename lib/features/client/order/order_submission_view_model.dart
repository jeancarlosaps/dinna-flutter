import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../../core/domain/data_failure.dart';
import '../../../core/domain/order.dart';
import '../../restaurant/order_repository.dart';
import 'order_intent.dart';
import 'order_intent_id.dart';
import 'order_intent_store.dart';

/// Estado do envio para a View. Ela não lê HTTP.
enum OrderSubmissionStatus { idle, submitting, succeeded, failed }

/// Envio do pedido: ViewModel → [OrderRepository.create].
///
/// Cada intenção nova ganha um UUID e um body imutável, gravados antes do
/// POST. Timeout, queda e reinício reutilizam essa intenção. O sucesso
/// confirmado permanece no disco até a tela pedir outro pedido. Falha
/// confirmada de validação ou ausência encerra a intenção; a tentativa
/// seguinte, pedida pela tela, recebe outra chave e o carrinho daquele
/// momento. Conflito de payload, chave órfã, expiração e arquivo ilegível
/// não liberam outra chave.
///
/// Não há retry automático. [shouldClearCart] fica verdadeiro só depois que a
/// API confirma o pedido. Esta classe não apaga item.
class OrderSubmissionViewModel extends ChangeNotifier {
  OrderSubmissionViewModel(
    this._repository, {
    OrderIntentStore? intentStore,
    DateTime Function()? now,
    String Function()? newIntentId,
  }) : _store = intentStore ?? MemoryOrderIntentStore(),
       _now = now ?? DateTime.now,
       _newIntentId = newIntentId ?? newOrderIntentId;

  final OrderRepository _repository;
  final OrderIntentStore _store;
  final DateTime Function() _now;
  final String Function() _newIntentId;

  /// Mensagem quando uma falha confirmada chega sem texto utilizável.
  static const unexpectedFailureMessage = 'Não foi possível enviar o pedido';

  /// Orientação junto do resultado incerto. Não afirma que o pedido falhou.
  static const verifyBeforeRetryGuidance =
      'Confira com o restaurante se o pedido chegou antes de tentar de novo.';

  /// A gravação falhou e a leitura seguinte não achou intenção. Nada foi enviado.
  static const persistFailureMessage =
      'Não foi possível guardar o envio neste aparelho. O pedido não foi enviado.';

  /// O arquivo não pode ser lido. Outro POST poderia duplicar um pedido já feito.
  static const unreadableIntentMessage =
      'Não foi possível ler o envio guardado neste aparelho. O pedido pode ter sido registrado. Confira com o restaurante antes de enviar outro.';

  /// A folga de 23 horas acabou, ou o relógio local não é confiável.
  ///
  /// Expirar a proteção não significa que o pedido deixou de existir.
  static const expiredIntentMessage =
      'O prazo de proteção desta tentativa terminou. Isso não significa que o pedido deixou de existir. Confira com o restaurante.';

  OrderSubmissionStatus _status = OrderSubmissionStatus.idle;
  Order? _order;
  String? _errorMessage;
  DataFailure? _failure;
  bool _outcomeUncertain = false;
  bool _resendBlocked = false;
  bool _storeBlocked = false;
  List<CartItem>? _confirmedItems;
  String? _confirmedTable;
  OrderIntent? _intent;
  Future<void>? _restoreTask;
  bool _restored = false;
  bool _gate = false;
  bool _disposed = false;

  OrderSubmissionStatus get status => _status;

  /// Pedido devolvido pela API. Preenchido só em [OrderSubmissionStatus.succeeded].
  Order? get order => _order;

  /// Preenchida só quando o envio falha ou fica bloqueado.
  String? get errorMessage => _errorMessage;

  /// Nula enquanto não houve falha.
  DataFailure? get failure => _failure;

  /// Verdadeiro quando o POST pode ter sido aplicado sem confirmação.
  bool get outcomeUncertain => _outcomeUncertain;

  /// Conflito, chave órfã, expiração ou arquivo ilegível. Não há reenvio seguro.
  bool get resendBlocked => _resendBlocked;

  /// Erro com resposta que prova que o pedido não foi criado.
  bool get isDefiniteFailure =>
      _status == OrderSubmissionStatus.failed && !_outcomeUncertain && !_resendBlocked;

  bool get isSubmitting => _status == OrderSubmissionStatus.submitting;

  /// Itens da fotografia que a API confirmou. Nulo sem sucesso.
  List<CartItem>? get confirmedItems => _confirmedItems;

  /// Mesa da mesma fotografia. Nula sem sucesso.
  String? get confirmedTable => _confirmedTable;

  /// Chave da intenção ainda em aberto. Nula sem intenção guardada.
  String? get intentId => _intent?.id;

  /// Só a confirmação da API liga este sinal. Esta classe não apaga item.
  bool get shouldClearCart =>
      _status == OrderSubmissionStatus.succeeded && _order != null && _confirmedItems != null;

  /// Primeiro envio, ou nova intenção depois de uma rejeição que não reteve a chave.
  ///
  /// Sucesso confirmado não entra aqui. O próximo pedido passa por
  /// [beginAnotherOrder].
  bool get canRequestSubmit =>
      !_disposed &&
      !_storeBlocked &&
      !_resendBlocked &&
      !_outcomeUncertain &&
      (_status == OrderSubmissionStatus.idle || isDefiniteFailure);

  /// Reenvio manual da mesma chave, dentro da folga de segurança.
  bool get canResumeSameIntent {
    final intent = _intent;
    return !_disposed &&
        _restored &&
        !_storeBlocked &&
        !_resendBlocked &&
        _outcomeUncertain &&
        intent != null &&
        _status != OrderSubmissionStatus.submitting &&
        intent.allowsResume(_now());
  }

  /// O 201 já foi mostrado e a intenção confirmada ainda está no disco.
  ///
  /// Intenção incerta ou bloqueada não entra. O próximo POST só existe depois
  /// que [beginAnotherOrder] conseguir apagar esta intenção.
  bool get canBeginAnotherOrder {
    final intent = _intent;
    return !_disposed &&
        _restored &&
        !_storeBlocked &&
        !_gate &&
        !isSubmitting &&
        _status == OrderSubmissionStatus.succeeded &&
        intent != null &&
        intent.phase == OrderIntentPhase.succeeded &&
        intent.order != null;
  }

  /// Lê a intenção gravada. Não envia nada.
  ///
  /// Pode ser chamada mais de uma vez. Chamadas concorrentes esperam a mesma leitura.
  Future<void> restore() {
    final current = _restoreTask;
    if (current != null) return current;
    final task = _readStore();
    _restoreTask = task;
    return task;
  }

  /// Envia [items] para a mesa [table], ou retoma a intenção ainda aberta.
  ///
  /// Ignora a chamada durante um envio, depois do sucesso, com o reenvio
  /// bloqueado ou após o [dispose]. [confirmedResume] é a confirmação explícita
  /// do diálogo. Sem ela, uma intenção achada na leitura não gera POST. No
  /// reenvio confirmado, a chave e o body guardados se repetem. O carrinho
  /// vivo fica de fora. Não repete o POST sozinho.
  Future<void> submit({
    required String table,
    required List<CartItem> items,
    bool confirmedResume = false,
  }) async {
    if (_disposed || _gate || _status == OrderSubmissionStatus.submitting) return;
    if (_restored &&
        (_storeBlocked || _resendBlocked || _status == OrderSubmissionStatus.succeeded)) {
      return;
    }

    final open = _intent;
    if (confirmedResume && open != null && !open.allowsResume(_now())) {
      _gate = true;
      try {
        await _persistBlock(open, OrderIntentBlock.expired);
      } finally {
        _gate = false;
      }
      return;
    }

    // A lista pode ser uma vista do carrinho. A cópia sai antes da notificação
    // e do primeiro await; uma edição nesse intervalo não entra nesta chave.
    final snapshot = List<CartItem>.unmodifiable(List<CartItem>.of(items));
    _gate = true;
    _enterSubmitting();
    try {
      await restore();
      if (_disposed) return;
      if (_storeBlocked) {
        _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
        return;
      }
      final intent = _intent;
      if (intent != null && !confirmedResume) {
        await _holdStored(intent);
        return;
      }
      if (intent != null && intent.phase == OrderIntentPhase.blocked) {
        _publishBlocked(_blockedMessage(intent.block), _blockedFailure(intent.block));
        return;
      }
      if (intent != null && intent.phase == OrderIntentPhase.succeeded) {
        _publishSuccess(intent);
        return;
      }
      if (intent != null) {
        await _resume(intent);
        return;
      }
      await _startNew(table, snapshot);
    } finally {
      _gate = false;
    }
  }

  /// Encerra a intenção confirmada para um pedido seguinte poder nascer.
  ///
  /// Não envia nada e não usa o carrinho. Se a limpeza do arquivo falha, a
  /// confirmação permanece e outro POST fica bloqueado.
  Future<void> beginAnotherOrder() async {
    if (!canBeginAnotherOrder) return;
    _gate = true;
    try {
      await _store.clear();
      if (_disposed) return;
      _intent = null;
      _publish(status: OrderSubmissionStatus.idle);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _storeBlocked = true;
      _resendBlocked = true;
      _errorMessage = unreadableIntentMessage;
      _failure = DataFailure.unavailable;
      _notify();
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order submission view model',
            context: ErrorDescription('ao encerrar o pedido confirmado'),
          ),
        );
      }
    } finally {
      _gate = false;
    }
  }

  Future<void> _readStore() async {
    try {
      final intent = await _store.load();
      if (_disposed) return;
      _restored = true;
      if (intent == null) return;
      await _holdStored(intent);
    } on OrderIntentStoreException {
      if (_disposed) return;
      _restored = true;
      _storeBlocked = true;
      _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
    }
  }

  Future<void> _holdStored(OrderIntent intent) async {
    _intent = intent;
    if (intent.phase == OrderIntentPhase.succeeded) {
      _publishSuccess(intent);
      return;
    }
    if (intent.phase == OrderIntentPhase.blocked || !intent.allowsResume(_now())) {
      final reason = intent.block ?? OrderIntentBlock.expired;
      await _persistBlock(intent, reason);
      return;
    }
    _publishUncertain(OrderSubmission.uncertainOutcomeMessage);
  }

  Future<void> _startNew(String table, List<CartItem> items) async {
    final rejected = OrderRequest.rejection(table: table, items: items);
    if (rejected != null) {
      _publishFailure(rejected);
      return;
    }

    final intent = OrderIntent.pending(
      id: _newIntentId(),
      createdAt: _now().toUtc(),
      table: table,
      items: OrderRequest.itemMaps(items),
    );
    _intent = intent;
    try {
      await _store.save(intent);
    } on OrderIntentStoreException {
      await _onSaveFailed();
      return;
    }
    if (_disposed) return;
    await _dispatch(intent);
  }

  Future<void> _resume(OrderIntent intent) async {
    if (!intent.allowsResume(_now())) {
      await _persistBlock(intent, OrderIntentBlock.expired);
      return;
    }
    await _dispatch(intent);
  }

  Future<void> _dispatch(OrderIntent intent) async {
    final OrderSubmission result;
    try {
      result = await _repository.create(
        table: intent.table,
        items: intent.cartItems,
        idempotencyKey: intent.id,
        body: intent.body,
      );
    } catch (error, stackTrace) {
      if (_disposed) return;
      await _markUncertain(intent);
      _publishUncertain(OrderSubmission.uncertainOutcomeMessage);
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order submission view model',
            context: ErrorDescription('ao enviar o pedido'),
          ),
        );
      }
      return;
    }
    if (_disposed) return;
    await _apply(intent, result);
  }

  Future<void> _apply(OrderIntent intent, OrderSubmission result) async {
    if (result.resendBlocked) {
      final reason = result.failure == DataFailure.conflict
          ? OrderIntentBlock.conflict
          : OrderIntentBlock.invalidState;
      await _persistBlock(intent, reason, message: result.message);
      return;
    }

    final order = result.order;
    if (order != null) {
      final done = intent.succeeded(order);
      _intent = done;
      try {
        await _store.save(done);
      } on OrderIntentStoreException {
        // O 201 já chegou. Se o processo cair, a leitura trata a intenção
        // pendente como incerta e o reenvio recebe o mesmo pedido.
      }
      if (_disposed) return;
      _publishSuccess(done);
      return;
    }

    if (result.outcomeUncertain || result.failure == DataFailure.uncertain) {
      await _markUncertain(intent);
      if (_disposed) return;
      _publishUncertain(_visibleMessage(result.message, uncertain: true));
      return;
    }

    try {
      await _store.clear();
      _intent = null;
    } on OrderIntentStoreException {
      if (_disposed) return;
      _storeBlocked = true;
      _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
      return;
    }
    if (_disposed) return;
    _publishFailure(result);
  }

  Future<void> _markUncertain(OrderIntent intent) async {
    final uncertain = intent.uncertain();
    _intent = uncertain;
    try {
      await _store.save(uncertain);
    } on OrderIntentStoreException {
      // O arquivo anterior continua pendente. A próxima leitura não cria chave.
    }
  }

  Future<void> _persistBlock(OrderIntent intent, OrderIntentBlock reason, {String? message}) async {
    final blocked = intent.blocked(reason);
    _intent = blocked;
    try {
      await _store.save(blocked);
    } on OrderIntentStoreException {
      _storeBlocked = true;
    }
    if (_disposed) return;
    _publishBlocked(message ?? _blockedMessage(reason), _blockedFailure(reason));
  }

  Future<void> _onSaveFailed() async {
    try {
      final stored = await _store.load();
      if (_disposed) return;
      if (stored == null) {
        _intent = null;
        _publish(
          status: OrderSubmissionStatus.failed,
          message: persistFailureMessage,
          failure: DataFailure.unavailable,
        );
        return;
      }
      _intent = stored;
      _publishUncertain(OrderSubmission.uncertainOutcomeMessage);
    } on OrderIntentStoreException {
      if (_disposed) return;
      _storeBlocked = true;
      _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
    }
  }

  void _enterSubmitting() {
    _status = OrderSubmissionStatus.submitting;
    _order = null;
    _errorMessage = null;
    _failure = null;
    _outcomeUncertain = false;
    _resendBlocked = false;
    _confirmedItems = null;
    _confirmedTable = null;
    _notify();
  }

  void _publishSuccess(OrderIntent intent) {
    final order = intent.order;
    _publish(
      status: OrderSubmissionStatus.succeeded,
      order: order,
      confirmedItems: order == null ? null : intent.cartItems,
      confirmedTable: order == null ? null : intent.table,
    );
  }

  void _publishUncertain(String message) {
    _publish(
      status: OrderSubmissionStatus.failed,
      message: message,
      failure: DataFailure.uncertain,
      outcomeUncertain: true,
    );
  }

  void _publishFailure(OrderSubmission result) {
    final uncertain = result.outcomeUncertain || result.failure == DataFailure.uncertain;
    _publish(
      status: OrderSubmissionStatus.failed,
      message: _visibleMessage(result.message, uncertain: uncertain),
      failure: result.failure ?? (uncertain ? DataFailure.uncertain : DataFailure.unavailable),
      outcomeUncertain: uncertain,
    );
  }

  void _publishBlocked(String message, DataFailure failure) {
    _publish(
      status: OrderSubmissionStatus.failed,
      message: message,
      failure: failure,
      resendBlocked: true,
    );
  }

  String _blockedMessage(OrderIntentBlock? reason) => switch (reason) {
    OrderIntentBlock.conflict => OrderSubmission.idempotencyConflictMessage,
    OrderIntentBlock.expired => expiredIntentMessage,
    _ => OrderSubmission.idempotencyInvalidMessage,
  };

  DataFailure _blockedFailure(OrderIntentBlock? reason) => switch (reason) {
    OrderIntentBlock.conflict => DataFailure.conflict,
    _ => DataFailure.unavailable,
  };

  String _visibleMessage(String? message, {required bool uncertain}) {
    if (message != null && message.trim().isNotEmpty) return message;
    if (uncertain) return OrderSubmission.uncertainOutcomeMessage;
    return unexpectedFailureMessage;
  }

  void _publish({
    required OrderSubmissionStatus status,
    Order? order,
    String? message,
    DataFailure? failure,
    bool outcomeUncertain = false,
    bool resendBlocked = false,
    List<CartItem>? confirmedItems,
    String? confirmedTable,
  }) {
    if (_disposed) return;
    _status = status;
    _order = order;
    _errorMessage = message;
    _failure = failure;
    _outcomeUncertain = outcomeUncertain;
    _resendBlocked = resendBlocked;
    _confirmedItems = confirmedItems;
    _confirmedTable = confirmedTable;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
