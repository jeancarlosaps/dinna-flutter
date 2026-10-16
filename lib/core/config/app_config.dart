import 'package:flutter/foundation.dart';

/// Configuração por ambiente, lida de `--dart-define`.
///
/// `API_BASE_URL` sobrescreve o padrão. Sem ela, o app aponta para a API
/// local: `10.0.2.2` no Android Emulator (alias do host) e `localhost` no
/// iOS Simulator. Dispositivo físico sempre precisa de `API_BASE_URL`.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: resolveApiBaseUrl(
        override: const String.fromEnvironment('API_BASE_URL'),
        platform: defaultTargetPlatform,
      ),
    );
  }

  static const localApiPort = 3333;

  final Uri apiBaseUrl;

  @visibleForTesting
  static Uri resolveApiBaseUrl({required String override, required TargetPlatform platform}) {
    if (override.isNotEmpty) return Uri.parse(override);

    final host = platform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
    return Uri(scheme: 'http', host: host, port: localApiPort);
  }
}
