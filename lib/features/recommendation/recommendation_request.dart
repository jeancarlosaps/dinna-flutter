import '../../core/domain/json_values.dart';
import 'recommendation_preferences.dart';

const _requestKeys = {'table', 'preferences', 'limit'};

/// Mesa opcional: 1–40 caracteres, sem espaço nas pontas e com algum
/// caractere que não seja espaço.
final _tableValue = RegExp(r'^\S(?:.*\S)?$');

/// Body de `POST /ai/recommendation`.
///
/// [limit] ausente no JSON de leitura vale 3. `null` não é aceito.
/// Não envia campo fora do contrato.
final class RecommendationRequest {
  RecommendationRequest({required this.preferences, this.table, this.limit = 3}) {
    _requireLimit(limit);
    _requireTable(table);
  }

  factory RecommendationRequest.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'RecommendationRequest');
      _rejectUnknownKeys(map, _requestKeys, 'RecommendationRequest');
      if (map.containsKey('limit') && map['limit'] == null) {
        throw ArgumentError.value(null, 'limit', 'limit nulo');
      }
      return RecommendationRequest(
        table: map.containsKey('table') ? readRequiredString(map, 'table', maxLength: 40) : null,
        preferences: RecommendationPreferences.fromJson(map['preferences']),
        limit: map.containsKey('limit') ? readRequiredInt(map, 'limit', min: 1) : 3,
      );
    });
  }

  final String? table;
  final RecommendationPreferences preferences;
  final int limit;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'preferences': preferences.toJson(), 'limit': limit};
    if (table != null) json['table'] = table;
    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecommendationRequest &&
        other.table == table &&
        other.preferences == preferences &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(table, preferences, limit);

  @override
  String toString() => 'RecommendationRequest(table: $table, limit: $limit, $preferences)';
}

void _requireLimit(int limit) {
  if (limit < 1 || limit > 3) {
    throw ArgumentError.value(limit, 'limit', 'limit deve ser inteiro de 1 a 3');
  }
}

void _requireTable(String? table) {
  if (table == null) return;
  if (table.length > 40 || !_tableValue.hasMatch(table)) {
    throw ArgumentError.value(
      table,
      'table',
      'table deve ter de 1 a 40 caracteres, sem espaço nas pontas',
    );
  }
}

void _rejectUnknownKeys(Map<String, Object?> json, Set<String> allowed, String name) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw ArgumentError.value(key, name, 'campo desconhecido');
    }
  }
}
