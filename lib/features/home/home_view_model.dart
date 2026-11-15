import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import 'api_status_repository.dart';

enum ApiStatus { unknown, checking, online, offline }

/// Fluxo de referência MVVM: View → ViewModel → Repository → Service.
///
/// Depende só de [ApiStatusRepository]. Não conhece HTTP.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this._repository);

  final ApiStatusRepository _repository;

  ApiStatus _status = ApiStatus.unknown;
  ApiStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DataFailure? _failure;
  DataFailure? get failure => _failure;

  bool _disposed = false;

  /// Mensagem de tela quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível verificar a API';

  Future<void> checkApi() async {
    if (_disposed || _status == ApiStatus.checking) return;

    _status = ApiStatus.checking;
    _errorMessage = null;
    _failure = null;
    _notify();

    try {
      final availability = await _repository.checkHealth();
      _publish(
        status: availability.isOnline ? ApiStatus.online : ApiStatus.offline,
        message: availability.message,
        failure: availability.failure,
      );
    } catch (error, stackTrace) {
      // ApiException já foi traduzida no repository. O que chega aqui é falha
      // inesperada: a tela sai de checking, sem o texto interno da exceção.
      _publish(
        status: ApiStatus.offline,
        message: unexpectedFailureMessage,
        failure: DataFailure.unavailable,
      );
      // Debug apenas: em release o presentError imprime exception.toString(),
      // que pode incluir a URL. A tela continua só com a mensagem genérica.
      if (kDebugMode && !_disposed) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'home view model',
            context: ErrorDescription('ao verificar a API'),
          ),
        );
      }
    }
  }

  void _publish({required ApiStatus status, required String? message, DataFailure? failure}) {
    if (_disposed) return;
    _status = status;
    _errorMessage = message;
    _failure = failure;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
