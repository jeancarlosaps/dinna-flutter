import 'package:flutter/foundation.dart';

/// Configuração por ambiente, lida de `--dart-define`.
///
/// `API_BASE_URL` sobrescreve o padrão. Sem ela, o app aponta para a API
/// local: `10.0.2.2` no Android Emulator (alias do host) e `localhost` no
/// iOS Simulator. Dispositivo físico sempre precisa de `API_BASE_URL`.
///
/// `API_TOKEN` é opcional. Ausente ou em branco deixa a API local sem o
/// header de acesso. O valor é configuração de execução: não é preferência,
/// não vai para o SQLite e não deve aparecer em log.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.apiToken});

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: resolveApiBaseUrl(
        override: const String.fromEnvironment('API_BASE_URL'),
        platform: defaultTargetPlatform,
      ),
      apiToken: resolveApiToken(const String.fromEnvironment('API_TOKEN')),
    );
  }

  static const localApiPort = 3333;

  final Uri apiBaseUrl;

  /// Token de `API_TOKEN`, ou nulo quando o define não autentica a chamada.
  final String? apiToken;

  @visibleForTesting
  static Uri resolveApiBaseUrl({required String override, required TargetPlatform platform}) {
    if (override.isNotEmpty) return Uri.parse(override);

    final host = platform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
    return Uri(scheme: 'http', host: host, port: localApiPort);
  }

  /// Ausente ou só com espaço significa execução local sem autenticação.
  @visibleForTesting
  static String? resolveApiToken(String raw) {
    final token = raw.trim();
    if (token.isEmpty) return null;
    return token;
  }
}
