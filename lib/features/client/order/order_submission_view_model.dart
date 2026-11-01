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
/// não liberam outra chave. Um 201 ou bloqueio que não couber no arquivo
/// continua valendo nesta execução e não volta a ser reenvio. Reiniciar o
/// processo não recupera esse desfecho: o arquivo antigo segue com a mesma
/// chave e o mesmo body.
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

  /// O 201 ou o bloqueio já é conhecido, mas não ficou no arquivo.
  ///
  /// Vale só nesta execução. Reiniciar o processo não recupera esse desfecho.
  static const terminalNotRecordedMessage =
      'O resultado deste envio não ficou gravado neste aparelho. Esta tela não reenvia nem começa outro pedido.';

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

  /// Desfecho já decidido neste processo. Não volta para pending nem uncertain.
  OrderIntent? _terminal;

  /// O [_terminal] foi lido ou gravado no arquivo. Sem isso, outro ciclo é inseguro.
  bool _terminalStored = false;

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

  /// O 201 foi gravado e a confirmação ainda está neste processo.
  ///
  /// Intenção incerta, bloqueada ou só conhecida em memória não entra. O
  /// próximo POST só existe depois que [beginAnotherOrder] apagar o arquivo.
  bool get canBeginAnotherOrder {
    final terminal = _terminal;
    return !_disposed &&
        _restored &&
        !_storeBlocked &&
        _terminalStored &&
        !_gate &&
        !isSubmitting &&
        _status == OrderSubmissionStatus.succeeded &&
        terminal != null &&
        terminal.phase == OrderIntentPhase.succeeded &&
        terminal.order != null;
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

  /// Envia um pedido novo com [items] na mesa [table].
  ///
  /// Não retoma intenção. Se já existe uma gravada, publica o estado dela e
  /// não cria chave. Ignora a chamada durante um envio, depois do sucesso,
  /// com o reenvio bloqueado ou após o [dispose].
  Future<void> submit({required String table, required List<CartItem> items}) async {
    if (_disposed || _gate || _status == OrderSubmissionStatus.submitting) return;
    if (_terminal != null) return;
    if (_restored &&
        (_storeBlocked || _resendBlocked || _status == OrderSubmissionStatus.succeeded)) {
      return;
    }

    // A lista pode ser uma vista do carrinho. A cópia sai antes da notificação
    // e do primeiro await; uma edição nesse intervalo não entra nesta chave.
    final snapshot = List<CartItem>.unmodifiable(List<CartItem>.of(items));
    _gate = true;
    _enterSubmitting();
    try {
      await restore();
      if (_disposed || _terminal != null) return;
      if (_storeBlocked) {
        _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
        return;
      }
      final intent = _intent;
      if (intent != null) {
        await _holdStored(intent);
        return;
      }
      await _startNew(table, snapshot);
    } finally {
      _gate = false;
    }
  }

  /// Repete a intenção [intentId] que o diálogo mostrou ao abrir.
  ///
  /// Só há POST quando esse ID é o da intenção ainda persistida, em fase
  /// pendente ou incerta, e dentro da folga. Confirmação antiga, duplicada,
  /// de intenção encerrada ou ausente não cria chave e não chama o envio novo.
  Future<void> resume(String intentId) async {
    if (_disposed || _gate || isSubmitting || _postDenied(intentId)) return;
    _gate = true;
    try {
      if (_postDenied(intentId)) return;
      final OrderIntent? persisted;
      try {
        persisted = await _store.load();
      } on OrderIntentStoreException {
        if (_disposed) return;
        _restored = true;
        _storeBlocked = true;
        if (_terminal != null) return;
        _publishBlocked(unreadableIntentMessage, DataFailure.unavailable);
        return;
      }
      if (_disposed || _postDenied(intentId)) return;
      _restored = true;
      if (persisted == null || persisted.id != intentId) return;
      if (_replaysTerminal(persisted)) return;
      if (persisted.phase == OrderIntentPhase.succeeded) {
        _rememberTerminal(persisted, persisted: true);
        _publishSuccess(persisted);
        return;
      }
      if (persisted.phase == OrderIntentPhase.blocked || !persisted.allowsResume(_now())) {
        if (persisted.phase == OrderIntentPhase.blocked) {
          _rememberTerminal(persisted, persisted: true);
          _publishBlocked(_blockedMessage(persisted.block), _blockedFailure(persisted.block));
          return;
        }
        await _persistBlock(persisted, OrderIntentBlock.expired);
        return;
      }
      if (_postDenied(intentId)) return;
      _intent = persisted;
      _enterSubmitting();
      if (_postDenied(intentId)) return;
      await _dispatch(persisted);
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
      _terminal = null;
      _terminalStored = false;
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

  bool _postDenied(String intentId) {
    if (_terminal != null || _storeBlocked || _resendBlocked) return true;
    if (_status == OrderSubmissionStatus.succeeded) return true;
    final known = _intent;
    return known != null &&
        known.id == intentId &&
        (known.phase == OrderIntentPhase.succeeded || known.phase == OrderIntentPhase.blocked);
  }

  /// O arquivo está atrás de um desfecho que esta execução já conhece.
  bool _replaysTerminal(OrderIntent incoming) {
    final terminal = _terminal;
    if (terminal == null) return false;
    if (terminal.id != incoming.id) return true;
    return incoming.phase == OrderIntentPhase.pending ||
        incoming.phase == OrderIntentPhase.uncertain;
  }

  void _rememberTerminal(OrderIntent intent, {required bool persisted}) {
    final current = _terminal;
    if (current != null) {
      if (persisted && current.id == intent.id) _terminalStored = true;
      return;
    }
    _terminal = intent;
    _intent = intent;
    _terminalStored = persisted;
  }

  void _keepUnrecordedTerminal() {
    _storeBlocked = true;
    _resendBlocked = true;
    _errorMessage = terminalNotRecordedMessage;
    _failure = DataFailure.unavailable;
    _notify();
  }

  void _reportTerminalWrite(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'order submission view model',
        context: ErrorDescription('ao gravar o desfecho da intenção'),
      ),
    );
  }

  Future<void> _readStore() async {
    try {
      final intent = await _store.load();
      if (_disposed) return;
      _restored = true;
      if (_terminal != null) return;
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
    if (_replaysTerminal(intent)) return;
    _intent = intent;
    if (intent.phase == OrderIntentPhase.succeeded) {
      _rememberTerminal(intent, persisted: true);
      _publishSuccess(intent);
      return;
    }
    if (intent.phase == OrderIntentPhase.blocked) {
      _rememberTerminal(intent, persisted: true);
      _publishBlocked(_blockedMessage(intent.block), _blockedFailure(intent.block));
      return;
    }
    if (!intent.allowsResume(_now())) {
      await _persistBlock(intent, intent.block ?? OrderIntentBlock.expired);
      return;
    }
    if (_terminal != null) return;
    _publishUncertain(OrderSubmission.uncertainOutcomeMessage);
  }

  Future<void> _startNew(String table, List<CartItem> items) async {
    if (_terminal != null || _storeBlocked || _resendBlocked) return;
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

  Future<void> _dispatch(OrderIntent intent) async {
    if (_postDenied(intent.id)) return;
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
      _rememberTerminal(done, persisted: false);
      try {
        await _store.save(done);
        _terminalStored = true;
      } on OrderIntentStoreException catch (error, stackTrace) {
        _terminalStored = false;
        _storeBlocked = true;
        _reportTerminalWrite(error, stackTrace);
      }
      if (_disposed) return;
      _publishSuccess(done);
      if (!_terminalStored) _keepUnrecordedTerminal();
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
    if (_terminal != null) return;
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
    _rememberTerminal(blocked, persisted: false);
    try {
      await _store.save(blocked);
      _terminalStored = true;
    } on OrderIntentStoreException catch (error, stackTrace) {
      _terminalStored = false;
      _storeBlocked = true;
      _reportTerminalWrite(error, stackTrace);
    }
    if (_disposed) return;
    _publishBlocked(message ?? _blockedMessage(reason), _blockedFailure(reason));
  }

  Future<void> _onSaveFailed() async {
    if (_terminal != null) return;
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
    if (_terminal != null) return;
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
    final terminal = _terminal;
    if (terminal != null) {
      final reaffirmsSuccess =
          terminal.phase == OrderIntentPhase.succeeded && status == OrderSubmissionStatus.succeeded;
      final reaffirmsBlock = terminal.phase == OrderIntentPhase.blocked && resendBlocked;
      if (!reaffirmsSuccess && !reaffirmsBlock) return;
    }
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
