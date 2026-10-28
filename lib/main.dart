import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'features/home/http_api_status_repository.dart';
import 'features/restaurant/http_order_repository.dart';

void main() {
  final config = AppConfig.fromEnvironment();
  final apiClient = ApiClient(baseUrl: config.apiBaseUrl, httpClient: http.Client());

  runApp(
    DinnaApp(
      apiStatusRepository: HttpApiStatusRepository(apiClient),
      orderRepository: HttpOrderRepository(apiClient),
    ),
  );
}
