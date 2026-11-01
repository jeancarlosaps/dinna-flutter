import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'features/client/cart/cart_lines.dart';
import 'features/client/order/order_intent_store.dart';
import 'features/home/http_api_status_repository.dart';
import 'features/menu/http_product_repository.dart';
import 'features/restaurant/http_order_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final apiClient = ApiClient(baseUrl: config.apiBaseUrl, httpClient: http.Client());
  final support = await getApplicationSupportDirectory();
  final intentStore = FileOrderIntentStore(File('${support.path}/order-intent.json'));

  runApp(
    DinnaApp(
      apiStatusRepository: HttpApiStatusRepository(apiClient),
      orderRepository: HttpOrderRepository(apiClient),
      productRepository: HttpProductRepository(apiClient),
      cartLines: ProcessCartLines(),
      orderIntentStore: intentStore,
    ),
  );
}
