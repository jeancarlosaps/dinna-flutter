import 'package:flutter/material.dart';

import '../features/home/api_status_repository.dart';
import 'router/app_router.dart';
import 'theme/dinna_theme.dart';

class DinnaApp extends StatelessWidget {
  const DinnaApp({super.key, required this.apiStatusRepository});

  final ApiStatusRepository apiStatusRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dinna',
      debugShowCheckedModeBanner: false,
      theme: DinnaTheme.light(),
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter(apiStatusRepository: apiStatusRepository).onGenerateRoute,
    );
  }
}
