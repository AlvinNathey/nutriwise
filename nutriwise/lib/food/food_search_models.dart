class FoodServingOption {
  final String label;
  final double quantity;
  final String unit;

  const FoodServingOption({
    required this.label,
    required this.quantity,
    required this.unit,
  });
}

class FoodSearchResult {
  final String id;
  final String name;
  final String subtitle;
  final double caloriesPer100g;
  final double carbsPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double defaultQuantity;
  final String quantityUnit;
  final String source;
  final String groupKey;
  final List<FoodServingOption> servingOptions;
  final int matchScore;

  const FoodSearchResult({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.caloriesPer100g,
    required this.carbsPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.defaultQuantity,
    required this.quantityUnit,
    required this.source,
    required this.groupKey,
    required this.servingOptions,
    required this.matchScore,
  });
}
