import 'package:flutter/material.dart';

import '../../features/home/api_status_repository.dart';
import '../../features/home/home_view.dart';
import '../../features/home/home_view_model.dart';

/// Nomes de rota centralizados. As rotas do cliente e do restaurante
/// entram aqui na Task de navegação base (SCRUM-23).
abstract final class AppRoutes {
  static const home = '/';
}

class AppRouter {
  AppRouter({required this.apiStatusRepository});

  final ApiStatusRepository apiStatusRepository;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return switch (settings.name) {
      AppRoutes.home => MaterialPageRoute(
        settings: settings,
        builder: (_) => HomeView(createViewModel: () => HomeViewModel(apiStatusRepository)),
      ),
      _ => MaterialPageRoute(
        settings: settings,
        builder: (_) => const Scaffold(body: Center(child: Text('Página não encontrada'))),
      ),
    };
  }
}
