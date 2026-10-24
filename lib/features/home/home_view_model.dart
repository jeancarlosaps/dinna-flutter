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

  Future<void> checkApi() async {
    if (_status == ApiStatus.checking) return;

    _status = ApiStatus.checking;
    _errorMessage = null;
    notifyListeners();

    final availability = await _repository.checkHealth();
    _status = availability.isOnline ? ApiStatus.online : ApiStatus.offline;
    _errorMessage = availability.message;
    // A tela pode ter sido fechada enquanto a requisição estava em andamento.
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
