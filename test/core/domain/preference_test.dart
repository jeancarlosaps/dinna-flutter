import 'dart:convert';

import 'package:dinna/core/domain/preference.dart';
import 'package:flutter_test/flutter_test.dart';

/// O valor é o exemplo de `preferences` no contrato da recomendação.
/// Aqui ele fica no JSON local `{ "text": "..." }`, não no body do endpoint.
const _filled = '{"text":"sem glúten, leve"}';

void main() {
  group('Preference', () {
    test('lê, grava e faz round-trip do texto preenchido', () {
      final preference = Preference.fromJson(jsonDecode(_filled) as Object);

      expect(preference.text, 'sem glúten, leve');
      expect(preference.toJson(), jsonDecode(_filled));
      expect(
        Preference.fromJson(jsonDecode(jsonEncode(preference.toJson())) as Object),
        preference,
      );
    });

    test('texto preenchido alimenta o campo opcional preferences', () {
      final preference = Preference.fromJson(jsonDecode(_filled) as Object);

      expect(preference.recommendationPreferences, 'sem glúten, leve');
      expect(preference.toJson().keys, ['text']);
      expect(preference.toJson().containsKey('preferences'), isFalse);
    });

    test('texto vazio permanece no JSON local e omite o campo da API', () {
      final preference = Preference.fromJson(jsonDecode('{"text":""}') as Object);

      expect(preference.text, isEmpty);
      expect(preference.recommendationPreferences, isNull);
      expect(preference.toJson(), {'text': ''});
      expect(Preference.fromJson(preference.toJson()), preference);
    });

    test('rejeita JSON incompatível com o contrato local', () {
      final cases = <String, Object?>{
        'não é objeto': jsonDecode('[]'),
        'text ausente': <String, Object?>{},
        'text nulo': {'text': null},
        'text numérico': {'text': 1},
      };

      for (final entry in cases.entries) {
        expect(() => Preference.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });
  });
}
