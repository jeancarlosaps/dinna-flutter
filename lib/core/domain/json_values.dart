/// Leitura estrita do JSON da dinna-api.
///
/// Não completa campo obrigatório ausente e não converte número fracionário
/// em inteiro. Models de domínio usam estas funções; elas não chamam HTTP.
library;

Map<String, Object?> readJsonObject(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path deve ser um objeto JSON');
  }

  final mapped = <String, Object?>{};
  for (final key in value.keys) {
    if (key is! String) {
      throw FormatException('$path deve ter chaves string');
    }
    mapped[key] = value[key] as Object?;
  }
  return mapped;
}

String readRequiredString(
  Map<String, Object?> json,
  String key, {
  int minLength = 1,
  int? maxLength,
}) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Campo $key é obrigatório');
  }

  final value = json[key];
  if (value is! String) {
    throw FormatException('Campo $key deve ser string');
  }
  if (maxLength != null && value.length > maxLength) {
    throw FormatException('Campo $key deve ter no máximo $maxLength caracteres');
  }
  if (value.length < minLength) {
    throw FormatException(
      minLength == 1
          ? 'Campo $key deve ter ao menos 1 caractere'
          : 'Campo $key deve ter ao menos $minLength caracteres',
    );
  }
  return value;
}

/// Ausente e `null` viram `null`. Outro tipo é erro: não há coerção.
String? readOptionalString(Map<String, Object?> json, String key, {int? maxLength}) {
  if (!json.containsKey(key) || json[key] == null) return null;

  final value = json[key];
  if (value is! String) {
    throw FormatException('Campo $key deve ser string');
  }
  if (maxLength != null && value.length > maxLength) {
    throw FormatException('Campo $key deve ter no máximo $maxLength caracteres');
  }
  return value;
}

/// Inteiro JSON. `double` (mesmo `3290.0`) não é centavo do contrato.
int readRequiredInt(Map<String, Object?> json, String key, {required int min}) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Campo $key é obrigatório');
  }

  final value = json[key];
  if (value is! int) {
    throw FormatException('Campo $key deve ser inteiro');
  }
  if (value < min) {
    throw FormatException('Campo $key deve ser >= $min');
  }
  return value;
}

bool readRequiredBool(Map<String, Object?> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Campo $key é obrigatório');
  }

  final value = json[key];
  if (value is! bool) {
    throw FormatException('Campo $key deve ser booleano');
  }
  return value;
}

/// ISO-8601 UTC no formato do contrato: sufixo `Z` maiúsculo.
///
/// O exemplo aceito é `"2026-10-16T18:00:00Z"`. `z` minúsculo, offset e
/// horário sem fuso não entram.
DateTime readRequiredUtc(Map<String, Object?> json, String key) {
  final raw = readRequiredString(json, key);
  if (!raw.contains('T') || !raw.endsWith('Z')) {
    throw FormatException('Campo $key deve ser ISO-8601 UTC');
  }

  final DateTime parsed;
  try {
    parsed = DateTime.parse(raw);
  } on FormatException catch (error) {
    throw FormatException('Campo $key deve ser ISO-8601 UTC (${error.message})');
  }
  if (!parsed.isUtc) {
    throw FormatException('Campo $key deve ser ISO-8601 UTC');
  }
  return parsed;
}

/// Escrita canônica. Fração `.000` sai para coincidir com o exemplo do contrato.
String writeUtcIso8601(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'value', 'data deve estar em UTC');
  }

  final iso = value.toIso8601String();
  if (iso.endsWith('.000Z')) return iso.replaceFirst('.000Z', 'Z');
  return iso;
}

List<T> readRequiredList<T>(
  Map<String, Object?> json,
  String key,
  T Function(Object? value) readItem, {
  int minLength = 1,
}) {
  if (!json.containsKey(key) || json[key] == null) {
    throw FormatException('Campo $key é obrigatório');
  }

  final value = json[key];
  if (value is! List) {
    throw FormatException('Campo $key deve ser uma lista');
  }
  if (value.length < minLength) {
    throw FormatException(
      minLength == 1
          ? 'Campo $key deve ter ao menos 1 item'
          : 'Campo $key deve ter ao menos $minLength itens',
    );
  }

  final items = <T>[];
  for (var index = 0; index < value.length; index++) {
    items.add(readItem(value[index] as Object?));
  }
  return items;
}

T parseModel<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError catch (error) {
    final message = error.message;
    throw FormatException(message is String && message.isNotEmpty ? message : 'JSON inválido');
  }
}
