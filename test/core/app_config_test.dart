import 'package:dinna/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.resolveApiBaseUrl', () {
    test('usa 10.0.2.2 no Android Emulator', () {
      final url = AppConfig.resolveApiBaseUrl(override: '', platform: TargetPlatform.android);

      expect(url.toString(), 'http://10.0.2.2:3333');
    });

    test('usa localhost no iOS Simulator', () {
      final url = AppConfig.resolveApiBaseUrl(override: '', platform: TargetPlatform.iOS);

      expect(url.toString(), 'http://localhost:3333');
    });

    test('API_BASE_URL tem prioridade sobre o padrão da plataforma', () {
      final url = AppConfig.resolveApiBaseUrl(
        override: 'http://192.168.0.10:3333',
        platform: TargetPlatform.android,
      );

      expect(url.toString(), 'http://192.168.0.10:3333');
    });
  });
}
