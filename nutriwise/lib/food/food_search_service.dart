import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nutriwise/food/kenyan_food_catalog.dart';
import 'package:nutriwise/food/food_search_models.dart';

export 'food_search_models.dart';

class FoodSearchService {
  FoodSearchService._();

  static const String _usdaApiKey = 'MplVWyn6crgaYXh8C4CdUKXmamwa06kR0fgM2XgG';

  // Unified search ranking (MyFitnessPal-like): exact/prefix first, then good partials.
  static Future<List<FoodSearchResult>> searchFoods(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final localResults = _searchKenyanFoods(trimmedQuery);
    final futures = await Future.wait([
      _searchUsda(trimmedQuery),
      _searchOpenFoodFacts(trimmedQuery),
    ]);

    final all = <FoodSearchResult>[
      ...localResults,
      ...futures[0],
      ...futures[1],
    ];

    final deduped = <String, FoodSearchResult>{};
    for (final item in all) {
      final key = _normalize(item.name);
      final existing = deduped[key];
      if (existing == null ||
          item.matchScore > existing.matchScore ||
          (item.matchScore == existing.matchScore &&
              _sourcePriority(item.source) < _sourcePriority(existing.source))) {
        deduped[key] = item;
      }
    }

    final results = deduped.values.toList()
      ..sort((a, b) {
        final byScore = b.matchScore.compareTo(a.matchScore);
        if (byScore != 0) return byScore;
        return _sourcePriority(a.source).compareTo(_sourcePriority(b.source));
      });

    return results.take(35).toList();
  }

  static List<FoodSearchResult> _searchKenyanFoods(String query) {
    final results = <FoodSearchResult>[];

    for (final entry in KenyanFoodCatalog.entries) {
      final score = _computeKenyanCatalogScore(
        query,
        entry.result.name,
        entry.result.subtitle,
        entry.aliases,
      );
      if (score <= 0) continue;

      results.add(
        FoodSearchResult(
          id: entry.result.id,
          name: entry.result.name,
          subtitle: entry.result.subtitle,
          caloriesPer100g: entry.result.caloriesPer100g,
          carbsPer100g: entry.result.carbsPer100g,
          proteinPer100g: entry.result.proteinPer100g,
          fatPer100g: entry.result.fatPer100g,
          defaultQuantity: entry.result.defaultQuantity,
          quantityUnit: entry.result.quantityUnit,
          source: entry.result.source,
          groupKey: entry.result.groupKey,
          servingOptions: entry.result.servingOptions,
          matchScore: score,
        ),
      );
    }

    results.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return results.take(20).toList();
  }

  static Future<List<FoodSearchResult>> _searchOpenFoodFacts(String query) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/cgi/search.pl'
        '?search_terms=${Uri.encodeQueryComponent(query)}'
        '&search_simple=1&action=process&json=1&page_size=20'
        '&fields=code,product_name,brands,categories,serving_quantity,serving_size,quantity,nutriments',
      );

      final response = await http.get(uri, headers: {'User-Agent': 'NutriWise/1.0'});
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final products = (data['products'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();

      final results = <FoodSearchResult>[];
      for (final product in products) {
        final name = (product['product_name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final nutriments = (product['nutriments'] as Map<String, dynamic>? ?? {});
        final calories = _parseNumber(
          nutriments['energy-kcal_100g'] ?? nutriments['energy_100g'],
        );
        final carbs = _parseNumber(nutriments['carbohydrates_100g']);
        final protein = _parseNumber(nutriments['proteins_100g']);
        final fat = _parseNumber(nutriments['fat_100g']);
        if (calories == null && carbs == null && protein == null && fat == null) {
          continue;
        }

        final quantity = _sanitizeQuantity(
          _parseNumber(product['serving_quantity']) ??
              _extractQuantity(product['serving_size']) ??
              _extractQuantity(product['quantity']),
        );
        final unit = _normalizeUnit(
          _extractUnit(product['serving_size']) ??
              _extractUnit(product['quantity']) ??
              'g',
        );
        final servingLabel = (product['serving_size'] ?? '').toString().trim();
        final brands = (product['brands'] ?? '').toString().trim();
        final subtitle = brands.isNotEmpty ? brands : 'Open Food Facts';

        results.add(
          FoodSearchResult(
            id: (product['code'] ?? name).toString(),
            name: name,
            subtitle: subtitle,
            caloriesPer100g: calories ?? 0,
            carbsPer100g: carbs ?? 0,
            proteinPer100g: protein ?? 0,
            fatPer100g: fat ?? 0,
            defaultQuantity: quantity,
            quantityUnit: unit,
            source: 'Open Food Facts',
            groupKey: 'general',
            servingOptions: _sanitizeServingOptions([
              if (servingLabel.isNotEmpty)
                FoodServingOption(label: servingLabel, quantity: quantity, unit: unit),
              FoodServingOption(label: '1 serving', quantity: quantity, unit: unit),
              FoodServingOption(label: '2 servings', quantity: quantity * 2, unit: unit),
              const FoodServingOption(label: '100 g', quantity: 100, unit: 'g'),
            ]),
            matchScore: _computeScore(query, name, subtitle),
          ),
        );
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  static Future<List<FoodSearchResult>> _searchUsda(String query) async {
    try {
      final uri = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/foods/search?api_key=$_usdaApiKey',
      );
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': query, 'pageSize': 20}),
      );
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body) as Map<String, dynamic>;
      final foods = (data['foods'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();

      final results = <FoodSearchResult>[];
      for (final food in foods) {
        final description = (food['description'] ?? '').toString().trim();
        if (description.isEmpty) continue;

        double calories = 0, carbs = 0, protein = 0, fat = 0;
        final nutrients = (food['foodNutrients'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>();
        for (final nutrient in nutrients) {
          final name = (nutrient['nutrientName'] ?? '').toString().toLowerCase();
          final value = _parseNumber(nutrient['value']) ?? 0;
          if (name.contains('energy')) calories = value;
          if (name.contains('carbohydrate')) carbs = value;
          if (name == 'protein') protein = value;
          if (name == 'total lipid (fat)' || name == 'fat') fat = value;
        }

        final servingSize = _sanitizeQuantity(_parseNumber(food['servingSize']));
        final servingUnit = _normalizeUnit((food['servingSizeUnit'] ?? 'g').toString());
        final subtitle = (food['brandOwner'] ?? food['dataType'] ?? 'USDA').toString();

        results.add(
          FoodSearchResult(
            id: (food['fdcId'] ?? description).toString(),
            name: _toTitleCase(description),
            subtitle: subtitle,
            caloriesPer100g: calories,
            carbsPer100g: carbs,
            proteinPer100g: protein,
            fatPer100g: fat,
            defaultQuantity: servingSize,
            quantityUnit: servingUnit,
            source: 'USDA',
            groupKey: 'general',
            servingOptions: const [
              FoodServingOption(label: '100 g', quantity: 100, unit: 'g'),
            ],
            matchScore: _computeScore(query, description, subtitle) + 3,
          ),
        );
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  static int _computeScore(String query, String name, String subtitle) {
    final q = _normalize(query);
    final n = _normalize(name);
    final s = _normalize(subtitle);
    if (n == q) return 120;
    if (n.startsWith(q)) return 106;
    if (n.contains(q)) return 92;
    if (q.split(' ').every((p) => n.contains(p))) return 86;
    if (s.contains(q)) return 74;
    return 60;
  }

  static int _sourcePriority(String source) {
    switch (source) {
      case 'Kenya FCT 2018':
        return -1;
      case 'USDA':
        return 0;
      case 'Open Food Facts':
        return 1;
      case 'Generic':
        return 2;
      default:
        return 3;
    }
  }

  static int _computeKenyanCatalogScore(
    String query,
    String name,
    String subtitle,
    List<String> aliases,
  ) {
    final q = _normalize(query);
    if (q.isEmpty) return 0;

    final candidates = <String>[name, subtitle, ...aliases];
    var bestScore = 0;

    for (final candidate in candidates) {
      final current = _computeCandidateScore(q, _normalize(candidate));
      if (current > bestScore) bestScore = current;
    }

    return bestScore;
  }

  static int _computeCandidateScore(String query, String candidate) {
    if (candidate.isEmpty) return 0;
    if (candidate == query) return 160;
    if (candidate.startsWith(query)) return 145;
    if (candidate.contains(query)) return 130;

    final queryParts = query.split(' ').where((part) => part.isNotEmpty).toList();
    if (queryParts.isEmpty) return 0;

    final allPartsMatch = queryParts.every(candidate.contains);
    if (allPartsMatch) return 118;

    final queryNoSpaces = query.replaceAll(' ', '');
    final candidateNoSpaces = candidate.replaceAll(' ', '');
    if (candidateNoSpaces.contains(queryNoSpaces)) return 110;

    return 0;
  }

  static double? _parseNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static double? _extractQuantity(dynamic value) {
    final raw = value?.toString().toLowerCase() ?? '';
    final match = RegExp(r'(\d+\.?\d*)\s*(g|ml)').firstMatch(raw);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static String? _extractUnit(dynamic value) {
    final raw = value?.toString().toLowerCase() ?? '';
    final match = RegExp(r'(\d+\.?\d*)\s*(g|ml)').firstMatch(raw);
    return match?.group(2);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _toTitleCase(String value) {
    return value
        .toLowerCase()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static double _sanitizeQuantity(double? value) {
    if (value == null || value.isNaN || value.isInfinite || value <= 0) return 100;
    return value.clamp(1, 5000).toDouble();
  }

  static String _normalizeUnit(String unit) {
    final v = unit.trim().toLowerCase();
    if (v.isEmpty) return 'g';
    if (v == 'grams' || v == 'gram') return 'g';
    if (v == 'milliliters' || v == 'milliliter') return 'ml';
    return v.length > 8 ? 'g' : v;
  }

  static List<FoodServingOption> _sanitizeServingOptions(
    List<FoodServingOption> options,
  ) {
    final deduped = <String, FoodServingOption>{};
    for (final option in options) {
      final qty = _sanitizeQuantity(option.quantity);
      final unit = _normalizeUnit(option.unit);
      final label = option.label.trim().isEmpty ? 'Serving' : option.label.trim();
      final key = '${label.toLowerCase()}|${qty.toStringAsFixed(2)}|$unit';
      deduped[key] = FoodServingOption(label: label, quantity: qty, unit: unit);
    }
    return deduped.values.toList();
  }
}
