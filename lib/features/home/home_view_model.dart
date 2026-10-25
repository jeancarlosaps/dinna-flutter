import 'package:flutter/foundation.dart';

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

  bool _disposed = false;

  /// Mensagem de tela quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível verificar a API';

  Future<void> checkApi() async {
    if (_status == ApiStatus.checking) return;

    _status = ApiStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final availability = await _repository.checkHealth();
      _publish(
        status: availability.isOnline ? ApiStatus.online : ApiStatus.offline,
        message: availability.message,
      );
    } catch (error, stackTrace) {
      // ApiException já foi traduzida no repository. O que chega aqui é falha
      // inesperada: a tela sai de checking, sem o texto interno da exceção.
      _publish(status: ApiStatus.offline, message: unexpectedFailureMessage);
      if (!_disposed) {
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

  void _publish({required ApiStatus status, required String? message}) {
    if (_disposed) return;
    _status = status;
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
