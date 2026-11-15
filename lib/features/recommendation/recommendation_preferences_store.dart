import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'recommendation_preferences.dart';

/// Falha ao preparar, ler ou gravar as preferências locais.
enum RecommendationPreferencesStoreProblem { unreadable, unwritable }

/// A leitura ou a gravação não chegou a um estado utilizável.
class RecommendationPreferencesStoreException implements Exception {
  const RecommendationPreferencesStoreException(this.problem);

  final RecommendationPreferencesStoreProblem problem;

  @override
  String toString() => 'RecommendationPreferencesStoreException(${problem.name})';
}

/// Formulário local de "Me ajuda a escolher".
///
/// Não é o body de `POST /ai/recommendation`. Os enums são os de
/// [RecommendationPreferences]; o que falta continua nulo. [restrictions]
/// segue a ordem do contrato e ignora repetição.
final class RecommendationSelection {
  RecommendationSelection({
    this.budget,
    this.hunger,
    this.protein,
    this.style,
    this.taste,
    List<DietaryRestriction> restrictions = const [],
  }) : restrictions = List<DietaryRestriction>.unmodifiable(_ordered(restrictions));

  /// JSON local. Valor desconhecido ou de tipo errado sai da seleção;
  /// o restante permanece. `null` quando [json] não é um objeto.
  static RecommendationSelection? fromStoredJson(Object? json) {
    if (json is! Map) return null;
    final values = <String, Object?>{};
    for (final key in json.keys) {
      if (key is! String) continue;
      values[key] = json[key] as Object?;
    }
    return RecommendationSelection(
      budget: _match(values['budget'], MealBudget.values, (budget) => budget.value),
      hunger: _match(values['hunger'], MealHunger.values, (hunger) => hunger.value),
      protein: _match(values['protein'], MealProtein.values, (protein) => protein.value),
      style: _match(values['style'], MealStyle.values, (style) => style.value),
      taste: _match(values['taste'], MealTaste.values, (taste) => taste.value),
      restrictions: _restrictions(values['restrictions']),
    );
  }

  final MealBudget? budget;
  final MealHunger? hunger;
  final MealProtein? protein;
  final MealStyle? style;
  final MealTaste? taste;
  final List<DietaryRestriction> restrictions;

  bool get isEmpty =>
      budget == null &&
      hunger == null &&
      protein == null &&
      style == null &&
      taste == null &&
      restrictions.isEmpty;

  /// Campos nulos e restrições vazias ficam de fora. A ausência é a seleção vazia.
  Map<String, Object?> toJson() {
    final selectedBudget = budget;
    final selectedHunger = hunger;
    final selectedProtein = protein;
    final selectedStyle = style;
    final selectedTaste = taste;
    return {
      if (selectedBudget != null) 'budget': selectedBudget.value,
      if (selectedHunger != null) 'hunger': selectedHunger.value,
      if (selectedProtein != null) 'protein': selectedProtein.value,
      if (selectedStyle != null) 'style': selectedStyle.value,
      if (selectedTaste != null) 'taste': selectedTaste.value,
      if (restrictions.isNotEmpty)
        'restrictions': [for (final restriction in restrictions) restriction.value],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecommendationSelection &&
        other.budget == budget &&
        other.hunger == hunger &&
        other.protein == protein &&
        other.style == style &&
        other.taste == taste &&
        _sameRestrictions(other.restrictions, restrictions);
  }

  @override
  int get hashCode =>
      Object.hash(budget, hunger, protein, style, taste, Object.hashAll(restrictions));

  @override
  String toString() =>
      'RecommendationSelection(${budget?.value}, ${hunger?.value}, ${protein?.value}, '
      '${style?.value}, ${taste?.value}, $restrictions)';
}

/// Preferências do formulário, separadas do carrinho e da intenção de pedido.
///
/// [current] é o que a próxima abertura da tela deve mostrar. [save] substitui
/// o documento inteiro. Gravações seguem a ordem em que foram pedidas; uma
/// escolha mais nova dispensa a escrita de uma anterior que ainda não começou.
abstract interface class RecommendationPreferencesStore {
  RecommendationSelection? get current;

  /// Sobe quando uma gravação nova é pedida. A falha não cria outro marco.
  int get epoch;

  Future<void> save(RecommendationSelection selection);
}

/// Nenhuma preferência foi gravada. Usado quando o diretório não abre.
///
/// [current] fica nulo e [save] falha. O formulário segue editável.
final class UnavailableRecommendationPreferencesStore implements RecommendationPreferencesStore {
  const UnavailableRecommendationPreferencesStore();

  @override
  RecommendationSelection? get current => null;

  @override
  int get epoch => 0;

  @override
  Future<void> save(RecommendationSelection selection) async {
    throw const RecommendationPreferencesStoreException(
      RecommendationPreferencesStoreProblem.unwritable,
    );
  }
}

/// Preferências só na memória. Testes usam o atraso e a falha da próxima gravação.
final class MemoryRecommendationPreferencesStore implements RecommendationPreferencesStore {
  MemoryRecommendationPreferencesStore({RecommendationSelection? initial}) {
    if (initial != null) _queue.restore(initial);
  }

  final _queue = _SaveQueue();
  Future<void> Function()? _delay;
  var _failNextSave = false;
  final completed = <RecommendationSelection>[];
  var _inFlight = 0;
  var maxInFlight = 0;

  /// A próxima [save] espera esta função antes de publicar a escolha.
  void delaySaves(Future<void> Function() delay) => _delay = delay;

  /// A próxima gravação falha e conserva a última que tinha dado certo.
  void failNextSave() => _failNextSave = true;

  @override
  RecommendationSelection? get current => _queue.current;

  @override
  int get epoch => _queue.epoch;

  @override
  Future<void> save(RecommendationSelection selection) => _queue.save(selection, _write);

  Future<void> _write(RecommendationSelection selection) async {
    _inFlight += 1;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      final delay = _delay;
      if (delay != null) await delay();
      if (_failNextSave) {
        _failNextSave = false;
        throw const RecommendationPreferencesStoreException(
          RecommendationPreferencesStoreProblem.unwritable,
        );
      }
      completed.add(selection);
    } finally {
      _inFlight -= 1;
    }
  }
}

/// Um JSON no diretório de suporte, fora do SQLite do carrinho.
///
/// [open] lê o arquivo antes de devolver a instância. Arquivo ausente, vazio
/// ou inválido vira seleção nula. Erro de leitura que não prova ausência lança
/// [RecommendationPreferencesStoreException].
final class FileRecommendationPreferencesStore implements RecommendationPreferencesStore {
  FileRecommendationPreferencesStore._(this._file);

  final File _file;
  final _queue = _SaveQueue();

  static Future<FileRecommendationPreferencesStore> open(File file) async {
    final store = FileRecommendationPreferencesStore._(file);
    await store._load();
    return store;
  }

  @override
  RecommendationSelection? get current => _queue.current;

  @override
  int get epoch => _queue.epoch;

  @override
  Future<void> save(RecommendationSelection selection) => _queue.save(selection, _write);

  Future<void> _load() async {
    try {
      _queue.restore(_selectionFromEncoded(await _file.readAsString()));
    } on FileSystemException catch (error) {
      if (_isMissing(error) || _isCorruptEncoding(error)) return;
      throw const RecommendationPreferencesStoreException(
        RecommendationPreferencesStoreProblem.unreadable,
      );
    }
  }

  Future<void> _write(RecommendationSelection selection) async {
    final encoded = jsonEncode(selection.toJson());
    final temp = File('${_file.path}.tmp');
    try {
      await _file.parent.create(recursive: true);
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(_file.path);
    } on FileSystemException {
      throw const RecommendationPreferencesStoreException(
        RecommendationPreferencesStoreProblem.unwritable,
      );
    }
  }
}

/// Abre `recommendation-preferences.json`. Diretório inacessível devolve
/// [UnavailableRecommendationPreferencesStore] para o formulário continuar.
Future<RecommendationPreferencesStore> openRecommendationPreferencesStore({
  Future<Directory> Function()? applicationSupportDirectory,
}) async {
  try {
    final support = await (applicationSupportDirectory ?? getApplicationSupportDirectory)();
    final directory = Directory(support.path);
    await directory.create(recursive: true);
    return await FileRecommendationPreferencesStore.open(
      File('${directory.path}/recommendation-preferences.json'),
    );
  } catch (error, stackTrace) {
    if (kDebugMode) {
      FlutterError.presentError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'recommendation preferences store',
          context: ErrorDescription('ao preparar as preferências da recomendação'),
        ),
      );
    }
    return const UnavailableRecommendationPreferencesStore();
  }
}

/// Fila de gravação. A escolha pedida por último fica em [current] na hora;
/// a escrita só corre depois da anterior. Se uma mais nova já foi pedida, a
/// anterior que ainda não escreveu é dispensada.
final class _SaveQueue {
  RecommendationSelection? current;
  RecommendationSelection? _durable;
  Future<void> _tail = Future<void>.value();
  var _revision = 0;

  /// Marco da última gravação pedida. O rollback de uma falha não muda.
  int get epoch => _revision;

  void restore(RecommendationSelection? selection) {
    current = selection;
    _durable = selection;
  }

  Future<void> save(
    RecommendationSelection selection,
    Future<void> Function(RecommendationSelection selection) write,
  ) {
    if (selection == current && selection == _durable) return Future<void>.value();
    final revision = ++_revision;
    current = selection;
    final result = _tail.then((_) => _commit(selection, revision, write));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _commit(
    RecommendationSelection selection,
    int revision,
    Future<void> Function(RecommendationSelection selection) write,
  ) async {
    if (revision != _revision) return;
    try {
      await write(selection);
    } catch (_) {
      if (revision == _revision) current = _durable;
      rethrow;
    }
    // A escrita terminou, então o arquivo agora é esta seleção, mesmo que uma
    // escolha mais nova já esteja em [current] e ainda não tenha sido gravada.
    _durable = selection;
  }
}

T? _match<T>(Object? raw, List<T> values, String Function(T value) read) {
  if (raw is! String) return null;
  for (final value in values) {
    if (read(value) == raw) return value;
  }
  return null;
}

List<DietaryRestriction> _restrictions(Object? raw) {
  if (raw is! List) return const [];
  final selected = <DietaryRestriction>{};
  for (final item in raw) {
    if (item is! String) continue;
    for (final restriction in DietaryRestriction.values) {
      if (restriction.value == item) selected.add(restriction);
    }
  }
  return _ordered(selected.toList());
}

List<DietaryRestriction> _ordered(List<DietaryRestriction> restrictions) {
  final selected = restrictions.toSet();
  return [
    for (final restriction in DietaryRestriction.values)
      if (selected.contains(restriction)) restriction,
  ];
}

bool _sameRestrictions(List<DietaryRestriction> left, List<DietaryRestriction> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

RecommendationSelection? _selectionFromEncoded(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Object) return null;
    final selection = RecommendationSelection.fromStoredJson(decoded);
    if (selection == null || selection.isEmpty) return null;
    return selection;
  } on FormatException {
    return null;
  }
}

bool _isCorruptEncoding(FileSystemException error) {
  return error.osError == null && error.message.toLowerCase().contains('utf-8');
}

bool _isMissing(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 2 || code == 3;
}
