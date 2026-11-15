import 'json_values.dart';

/// Preferência textual do cliente, local ao app.
///
/// O JSON local é `{ "text": "..." }`. Não é o body de
/// `POST /ai/recommendation` e não define categorias alimentares.
final class Preference {
  Preference({required this.text});

  factory Preference.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'Preference');
      return Preference(text: readRequiredString(map, 'text', minLength: 0));
    });
  }

  /// Texto livre. Vazio é válido e significa que não há preferência a enviar.
  final String text;

  /// Valor do campo opcional `preferences` em `POST /ai/recommendation`.
  ///
  /// Texto vazio devolve `null`, para o chamador omitir o campo. Não monta
  /// o body do endpoint.
  String? get recommendationPreferences => text.isEmpty ? null : text;

  Map<String, Object?> toJson() => {'text': text};

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Preference && other.text == text;
  }

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Preference(text: $text)';
}
