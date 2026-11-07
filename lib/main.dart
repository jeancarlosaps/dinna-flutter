import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'features/client/cart/cart_session.dart';
import 'features/client/cart/sqflite_cart_repository.dart';
import 'features/client/order/order_intent_store.dart';
import 'features/home/http_api_status_repository.dart';
import 'features/menu/http_product_repository.dart';
import 'features/recommendation/http_recommendation_repository.dart';
import 'features/restaurant/http_order_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final apiClient = ApiClient(baseUrl: config.apiBaseUrl, httpClient: http.Client());
  final intentStore = await openOrderIntentStore();

  runApp(
    DinnaApp(
      apiStatusRepository: HttpApiStatusRepository(apiClient),
      orderRepository: HttpOrderRepository(apiClient),
      productRepository: HttpProductRepository(apiClient),
      recommendationRepository: HttpRecommendationRepository(apiClient),
      cartSession: CartSession(SqfliteCartRepository()),
      orderIntentStore: intentStore,
    ),
  );
}
