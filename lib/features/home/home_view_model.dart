import 'package:flutter/foundation.dart';

import '../../core/network/api_exception.dart';
import 'api_status_repository.dart';

enum ApiStatus { unknown, checking, online, offline }

/// Fluxo de referência MVVM: View → ViewModel → Repository → ApiClient.
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

    try {
      _status = await _repository.isApiOnline() ? ApiStatus.online : ApiStatus.offline;
    } on ApiException catch (error) {
      _status = ApiStatus.offline;
      _errorMessage = error.message;
    }
    // A tela pode ter sido fechada enquanto a requisição estava em andamento.
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
